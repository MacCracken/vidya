// Vidya — Concurrent File Access (flock) in TypeScript
//
// Node.js has no built-in flock binding (proper-lockfile et al. need
// npm). To keep this port dependency-free we simulate the per-OPEN
// flock state machine in process memory: an Open object tracks its
// current lock mode, and a shared Lockable tracks how many shared
// holders exist and whether one exclusive holder is active. The state
// transitions match real flock semantics — LOCK_NB returns EAGAIN
// when an exclusive request conflicts; multiple shared holders coexist;
// a conversion (SH↔EX) drops the old lock first and is NOT atomic, so on
// Linux a conversion that fails with EAGAIN leaves the open holding no
// lock at all (flock(2); fs/locks.c flock_lock_inode).

import * as fs from "fs";

enum LockMode {
  None,
  Shared,
  Exclusive,
}

class Lockable {
  shared = 0;
  exclusive = 0;

  acquire(prev: LockMode, want: LockMode, nonBlocking: boolean): boolean {
    // Release prior holding first
    if (prev === LockMode.Shared) this.shared--;
    if (prev === LockMode.Exclusive) this.exclusive--;

    if (want === LockMode.Exclusive) {
      if (this.shared > 0 || this.exclusive > 0) {
        // The prior lock is already gone and is NOT restored (Linux semantics)
        if (nonBlocking) return false;
        // blocking would block here — caller doesn't expect that in single-thread
        throw new Error("would block");
      }
      this.exclusive++;
      return true;
    }
    if (want === LockMode.Shared) {
      if (this.exclusive > 0) {
        if (nonBlocking) return false;
        throw new Error("would block");
      }
      this.shared++;
      return true;
    }
    return true; // LockMode.None = unlock; nothing more to do
  }
}

class Open {
  mode: LockMode = LockMode.None;
  constructor(public lockable: Lockable, public fd: number) {}

  flock(op: LockMode, nonBlocking: boolean): boolean {
    const ok = this.lockable.acquire(this.mode, op, nonBlocking);
    this.mode = ok ? op : LockMode.None; // failed conversion: old lock dropped
    return ok;
  }
}

const LOCKS = new Map<string, Lockable>();
function openLockable(path: string): Lockable {
  let l = LOCKS.get(path);
  if (!l) { l = new Lockable(); LOCKS.set(path, l); }
  return l;
}

function open(path: string, mode: string): Open {
  // O_RDWR|O_CREAT, never "w+": "w+" adds O_TRUNC, and truncation is not
  // stopped by an advisory lock — a second open would wipe data another
  // open is holding LOCK_EX over.
  const rw = fs.constants.O_RDWR | fs.constants.O_CREAT;
  const fd = fs.openSync(path, mode === "rw" ? rw : "r+");
  return new Open(openLockable(path), fd);
}

let checks = 0;
function check(cond: boolean, label: string): void {
  if (!cond) throw new Error(`FAIL: ${label}`);
  checks++;
}

function main(): void {
  const path = "/tmp/vidya_cfa_ts.bin";
  try { fs.unlinkSync(path); } catch {}

  // Test 1: exclusive write
  const f1 = open(path, "rw");
  check(f1.flock(LockMode.Exclusive, true), "fd1 LOCK_EX");

  const val = 0xDEADBEEF12345678n;
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(val, 0);
  fs.writeSync(f1.fd, buf, 0, 8, 0);
  check(f1.flock(LockMode.None, true), "fd1 LOCK_UN after write");

  // Test 2: shared read with roundtrip
  check(f1.flock(LockMode.Shared, true), "fd1 LOCK_SH");
  const rb = Buffer.alloc(8);
  fs.readSync(f1.fd, rb, 0, 8, 0);
  const got = rb.readBigUInt64LE(0);
  check(got === val, "data roundtrip");
  f1.flock(LockMode.None, true);

  // Test 3: exclusive contention via second OPEN (which must not truncate)
  const f2 = open(path, "rw");
  check(fs.fstatSync(f1.fd).size === 8, "second open keeps fd1's data");
  check(f1.flock(LockMode.Exclusive, true), "fd1 re-acquires LOCK_EX");
  check(!f2.flock(LockMode.Exclusive, true), "fd2 LOCK_NB blocked");

  // Test 4: release fd1, fd2 acquires
  f1.flock(LockMode.None, true);
  check(f2.flock(LockMode.Exclusive, true), "fd2 acquires after fd1 releases");
  f2.flock(LockMode.None, true);

  // Test 5: shared locks coexist
  check(f1.flock(LockMode.Shared, true), "fd1 LOCK_SH non-blocking");
  check(f2.flock(LockMode.Shared, true), "fd2 LOCK_SH non-blocking coexists");
  f1.flock(LockMode.None, true);
  f2.flock(LockMode.None, true);

  // Test 6: a failed non-blocking upgrade loses the shared lock (not atomic)
  const f3 = open(path, "rw");
  check(f1.flock(LockMode.Shared, true) && f2.flock(LockMode.Shared, true), "fd1+fd2 LOCK_SH");
  check(!f1.flock(LockMode.Exclusive, true), "fd1 SH→EX LOCK_NB fails (fd2 holds SH)");
  check(f1.mode === LockMode.None, "fd1's shared lock was dropped by the failed upgrade");
  f2.flock(LockMode.None, true);
  check(f3.flock(LockMode.Exclusive, true), "fd3 LOCK_EX: nobody holds the file");
  f3.flock(LockMode.None, true);
  fs.closeSync(f3.fd);

  fs.closeSync(f1.fd);
  fs.closeSync(f2.fd);
  fs.unlinkSync(path);
  console.log(`concurrent_file_access: ${checks}/${checks} ok`);
}

main();
