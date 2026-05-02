// Vidya — Write-Ahead Logging in Rust
//
// In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
// mutating the data store, then replay the durable prefix on recovery.
// Rust's `Vec<u8>` (sized via `vec![0u8; 6144]`) gives us a flat
// little-endian byte buffer; `i64::to_le_bytes` / `i64::from_le_bytes`
// make the load64/store64 primitives explicit. The 256-record cap and
// the OP_INVALID/SET/DEL constants match the cyrius reference byte-for-
// byte. No real fsync — `log_committed` snapshots the durable prefix.

#![allow(dead_code)]

const REC_SZ: usize = 24;
const LOG_CAP_BYTES: usize = 6144;
const OP_INVALID: i64 = 0;
const OP_SET: i64 = 1;
const OP_DEL: i64 = 2;
const STORE_KEYS: usize = 16;

struct Wal {
    log_buf: Vec<u8>,
    log_offset: usize,
    log_committed: usize,
    data_vals: [i64; STORE_KEYS],
    data_present: [u8; STORE_KEYS],
}

impl Wal {
    fn new() -> Self {
        Wal {
            log_buf: vec![0u8; LOG_CAP_BYTES],
            log_offset: 0,
            log_committed: 0,
            data_vals: [0; STORE_KEYS],
            data_present: [0; STORE_KEYS],
        }
    }

    fn log_reset(&mut self) {
        self.log_offset = 0;
        self.log_committed = 0;
    }

    fn store_clear(&mut self) {
        self.data_vals = [0; STORE_KEYS];
        self.data_present = [0; STORE_KEYS];
    }

    fn reset_all(&mut self) {
        self.log_reset();
        self.store_clear();
        // Wipe the buffer so leftover bytes from a previous test don't
        // ghost into a fresh replay.
        for b in self.log_buf.iter_mut() {
            *b = 0;
        }
    }

    fn store64(&mut self, off: usize, v: i64) {
        self.log_buf[off..off + 8].copy_from_slice(&v.to_le_bytes());
    }

    fn load64(&self, off: usize) -> i64 {
        let mut bytes = [0u8; 8];
        bytes.copy_from_slice(&self.log_buf[off..off + 8]);
        i64::from_le_bytes(bytes)
    }

    // Returns 1 on success, 0 if the buffer is full (matches cyrius).
    fn log_append(&mut self, op: i64, key: i64, val: i64) -> i64 {
        if self.log_offset + REC_SZ > LOG_CAP_BYTES {
            return 0;
        }
        let off = self.log_offset;
        self.store64(off, op);
        self.store64(off + 8, key);
        self.store64(off + 16, val);
        self.log_offset += REC_SZ;
        1
    }

    fn log_commit(&mut self) -> usize {
        // Real implementations call fsync(wal_fd) here; we model that
        // with an offset snapshot — every byte up to log_committed is
        // assumed durable.
        self.log_committed = self.log_offset;
        self.log_committed
    }

    fn store_set(&mut self, key: i64, val: i64) -> i64 {
        if key < 0 || key >= STORE_KEYS as i64 {
            return 0;
        }
        // WAL rule: log BEFORE data.
        if self.log_append(OP_SET, key, val) == 0 {
            return 0;
        }
        let k = key as usize;
        self.data_vals[k] = val;
        self.data_present[k] = 1;
        1
    }

    fn store_del(&mut self, key: i64) -> i64 {
        if key < 0 || key >= STORE_KEYS as i64 {
            return 0;
        }
        if self.log_append(OP_DEL, key, 0) == 0 {
            return 0;
        }
        let k = key as usize;
        self.data_vals[k] = 0;
        self.data_present[k] = 0;
        1
    }

    fn store_get(&self, key: i64) -> i64 {
        if key < 0 || key >= STORE_KEYS as i64 {
            return -1;
        }
        let k = key as usize;
        if self.data_present[k] == 0 {
            return -1;
        }
        self.data_vals[k]
    }

    fn replay(&mut self) -> i64 {
        self.store_clear();
        let mut pos = 0;
        let mut applied: i64 = 0;
        while pos < self.log_committed {
            let op = self.load64(pos);
            let key = self.load64(pos + 8);
            let val = self.load64(pos + 16);
            if op == OP_SET {
                let k = key as usize;
                self.data_vals[k] = val;
                self.data_present[k] = 1;
                applied += 1;
            } else if op == OP_DEL {
                let k = key as usize;
                self.data_vals[k] = 0;
                self.data_present[k] = 0;
                applied += 1;
            }
            pos += REC_SZ;
        }
        applied
    }
}

fn check(cond: bool, msg: &str) {
    if !cond {
        eprintln!("FAIL: {}", msg);
        std::process::exit(1);
    }
}

fn test_append_and_replay() {
    let mut w = Wal::new();
    w.reset_all();
    w.store_set(0, 100);
    w.store_set(1, 200);
    w.store_set(2, 300);
    w.log_commit();
    w.store_clear();
    let n = w.replay();
    check(n == 3, "replayed 3 records");
    check(w.store_get(0) == 100, "key 0 = 100");
    check(w.store_get(1) == 200, "key 1 = 200");
    check(w.store_get(2) == 300, "key 2 = 300");
}

fn test_log_before_data_invariant() {
    let mut w = Wal::new();
    w.reset_all();
    let ok = w.store_set(5, 42);
    check(ok == 1, "first set succeeds");
    check(w.load64(0) == OP_SET, "log[0].op = SET");
    check(w.load64(8) == 5, "log[0].key = 5");
    check(w.load64(16) == 42, "log[0].val = 42");
    check(w.store_get(5) == 42, "data has key 5 = 42");
    let _ = OP_INVALID;
}

fn test_uncommitted_writes_lost_on_crash() {
    let mut w = Wal::new();
    w.reset_all();
    w.store_set(0, 1);
    w.store_set(1, 2);
    w.log_commit();
    w.store_set(2, 3);
    w.store_set(3, 4);
    w.store_clear();
    let n = w.replay();
    check(n == 2, "only 2 committed records replayed");
    check(w.store_get(0) == 1, "committed key 0 survived");
    check(w.store_get(1) == 2, "committed key 1 survived");
    check(w.store_get(2) == -1, "uncommitted key 2 lost");
    check(w.store_get(3) == -1, "uncommitted key 3 lost");
}

fn test_delete_replays_correctly() {
    let mut w = Wal::new();
    w.reset_all();
    w.store_set(0, 100);
    w.store_set(1, 200);
    w.store_del(0);
    w.log_commit();
    w.store_clear();
    w.replay();
    check(w.store_get(0) == -1, "key 0 deleted");
    check(w.store_get(1) == 200, "key 1 = 200");
}

fn test_overwrite_uses_last_record() {
    let mut w = Wal::new();
    w.reset_all();
    w.store_set(7, 100);
    w.store_set(7, 200);
    w.store_set(7, 300);
    w.log_commit();
    w.store_clear();
    w.replay();
    check(w.store_get(7) == 300, "last write wins on replay");
}

fn test_sequential_offsets_monotonic() {
    let mut w = Wal::new();
    w.reset_all();
    let mut prev = w.log_offset;
    for i in 0..5 {
        w.store_set(i, i * 10);
        let now = w.log_offset;
        check(now > prev, "log offset advances monotonically");
        prev = now;
    }
}

fn test_log_capacity_limit() {
    let mut w = Wal::new();
    w.reset_all();
    let mut failures = 0;
    for i in 0..300 {
        let ok = w.store_set(0, i);
        if ok == 0 {
            failures += 1;
        }
    }
    check(failures > 0, "log capacity is bounded");
}

fn main() {
    test_append_and_replay();
    test_log_before_data_invariant();
    test_uncommitted_writes_lost_on_crash();
    test_delete_replays_correctly();
    test_overwrite_uses_last_record();
    test_sequential_offsets_monotonic();
    test_log_capacity_limit();
    println!("All write_ahead_logging examples passed.");
}
