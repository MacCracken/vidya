// Vidya — Write-Ahead Logging in TypeScript
//
// In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
// mutating the data store, then replay the durable prefix on recovery.
// Records hold 64-bit values, so JavaScript's `number` (53-bit safe)
// won't do — we back the buffer with `Uint8Array` and read/write
// 64-bit fields through a `DataView` (`getBigInt64`/`setBigInt64`).
// The 256-record cap and the OP_INVALID/SET/DEL constants match the
// cyrius reference. No real fsync — `logCommitted` snapshots the
// durable prefix.

const REC_SZ = 24;
const LOG_CAP_BYTES = 6144;
const OP_INVALID = 0n;
const OP_SET = 1n;
const OP_DEL = 2n;
const STORE_KEYS = 16;

class Wal {
  logBuf: Uint8Array;
  view: DataView;
  logOffset: number = 0;
  logCommitted: number = 0;
  dataVals: BigInt64Array = new BigInt64Array(STORE_KEYS);
  dataPresent: Uint8Array = new Uint8Array(STORE_KEYS);

  constructor() {
    this.logBuf = new Uint8Array(LOG_CAP_BYTES);
    this.view = new DataView(this.logBuf.buffer);
  }

  logReset(): void {
    this.logOffset = 0;
    this.logCommitted = 0;
  }

  storeClear(): void {
    this.dataVals.fill(0n);
    this.dataPresent.fill(0);
  }

  resetAll(): void {
    this.logReset();
    this.storeClear();
    // Wipe the buffer so leftover bytes from a prior test don't ghost
    // into a fresh replay.
    this.logBuf.fill(0);
  }

  store64(off: number, v: bigint): void {
    // Little-endian — `true` flag — to match cyrius's byte order.
    this.view.setBigInt64(off, v, true);
  }

  load64(off: number): bigint {
    return this.view.getBigInt64(off, true);
  }

  // Returns 1 on success, 0 if the buffer is full — matches cyrius.
  logAppend(op: bigint, key: bigint, val: bigint): number {
    if (this.logOffset + REC_SZ > LOG_CAP_BYTES) return 0;
    const off = this.logOffset;
    this.store64(off + 0, op);
    this.store64(off + 8, key);
    this.store64(off + 16, val);
    this.logOffset += REC_SZ;
    return 1;
  }

  logCommit(): number {
    // Real implementations call fsync(walFd); we model durability with
    // an offset snapshot.
    this.logCommitted = this.logOffset;
    return this.logCommitted;
  }

  storeSet(key: number, val: bigint): number {
    if (key < 0 || key >= STORE_KEYS) return 0;
    // WAL rule: log BEFORE data.
    if (this.logAppend(OP_SET, BigInt(key), val) === 0) return 0;
    this.dataVals[key] = val;
    this.dataPresent[key] = 1;
    return 1;
  }

  storeDel(key: number): number {
    if (key < 0 || key >= STORE_KEYS) return 0;
    if (this.logAppend(OP_DEL, BigInt(key), 0n) === 0) return 0;
    this.dataVals[key] = 0n;
    this.dataPresent[key] = 0;
    return 1;
  }

  storeGet(key: number): bigint {
    if (key < 0 || key >= STORE_KEYS) return -1n;
    if (this.dataPresent[key] === 0) return -1n;
    return this.dataVals[key];
  }

  replay(): number {
    this.storeClear();
    let pos = 0;
    let applied = 0;
    while (pos < this.logCommitted) {
      const op = this.load64(pos + 0);
      const key = this.load64(pos + 8);
      const val = this.load64(pos + 16);
      const k = Number(key);
      if (op === OP_SET) {
        this.dataVals[k] = val;
        this.dataPresent[k] = 1;
        applied++;
      } else if (op === OP_DEL) {
        this.dataVals[k] = 0n;
        this.dataPresent[k] = 0;
        applied++;
      }
      pos += REC_SZ;
    }
    return applied;
  }
}

function check(cond: boolean, msg: string): void {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
}

// test_append_and_replay
{
  const w = new Wal();
  w.resetAll();
  w.storeSet(0, 100n);
  w.storeSet(1, 200n);
  w.storeSet(2, 300n);
  w.logCommit();
  w.storeClear();
  const n = w.replay();
  check(n === 3, "replayed 3 records");
  check(w.storeGet(0) === 100n, "key 0 = 100");
  check(w.storeGet(1) === 200n, "key 1 = 200");
  check(w.storeGet(2) === 300n, "key 2 = 300");
}

// test_log_before_data_invariant
{
  const w = new Wal();
  w.resetAll();
  const ok = w.storeSet(5, 42n);
  check(ok === 1, "first set succeeds");
  check(w.load64(0) === OP_SET, "log[0].op = SET");
  check(w.load64(8) === 5n, "log[0].key = 5");
  check(w.load64(16) === 42n, "log[0].val = 42");
  check(w.storeGet(5) === 42n, "data has key 5 = 42");
}

// test_uncommitted_writes_lost_on_crash
{
  const w = new Wal();
  w.resetAll();
  w.storeSet(0, 1n);
  w.storeSet(1, 2n);
  w.logCommit();
  w.storeSet(2, 3n);
  w.storeSet(3, 4n);
  w.storeClear();
  const n = w.replay();
  check(n === 2, "only 2 committed records replayed");
  check(w.storeGet(0) === 1n, "committed key 0 survived");
  check(w.storeGet(1) === 2n, "committed key 1 survived");
  check(w.storeGet(2) === -1n, "uncommitted key 2 lost");
  check(w.storeGet(3) === -1n, "uncommitted key 3 lost");
}

// test_delete_replays_correctly
{
  const w = new Wal();
  w.resetAll();
  w.storeSet(0, 100n);
  w.storeSet(1, 200n);
  w.storeDel(0);
  w.logCommit();
  w.storeClear();
  w.replay();
  check(w.storeGet(0) === -1n, "key 0 deleted");
  check(w.storeGet(1) === 200n, "key 1 = 200");
}

// test_overwrite_uses_last_record
{
  const w = new Wal();
  w.resetAll();
  w.storeSet(7, 100n);
  w.storeSet(7, 200n);
  w.storeSet(7, 300n);
  w.logCommit();
  w.storeClear();
  w.replay();
  check(w.storeGet(7) === 300n, "last write wins on replay");
}

// test_sequential_offsets_monotonic
{
  const w = new Wal();
  w.resetAll();
  let prev = w.logOffset;
  for (let i = 0; i < 5; i++) {
    w.storeSet(i, BigInt(i * 10));
    const now = w.logOffset;
    check(now > prev, "log offset advances monotonically");
    prev = now;
  }
}

// test_log_capacity_limit
{
  const w = new Wal();
  w.resetAll();
  let failures = 0;
  for (let i = 0; i < 300; i++) {
    const ok = w.storeSet(0, BigInt(i));
    if (ok === 0) failures++;
  }
  check(failures > 0, "log capacity is bounded");
}

// OP_INVALID is exported by spec; reference it so the lint doesn't bite.
void OP_INVALID;

console.log("All write_ahead_logging examples passed.");
