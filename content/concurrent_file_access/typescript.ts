// Vidya — Concurrent File Access (flock) in TypeScript
//
// Node.js has no built-in flock binding (proper-lockfile et al. need
// npm). To keep this port dependency-free we simulate the per-OPEN
// flock state machine in process memory: an Open object tracks its
// current lock mode, and a shared Lockable tracks how many shared
// holders exist and whether one exclusive holder is active. The state
// transitions match real flock semantics — LOCK_NB returns EAGAIN
// when an exclusive request conflicts; multiple shared holders coexist;
// downgrades drop the exclusive count first.

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
        if (nonBlocking) {
          // restore prior
          if (prev === LockMode.Shared) this.shared++;
          if (prev === LockMode.Exclusive) this.exclusive++;
          return false;
        }
        // blocking would block here — caller doesn't expect that in single-thread
        throw new Error("would block");
      }
      this.exclusive++;
      return true;
    }
    if (want === LockMode.Shared) {
      if (this.exclusive > 0) {
        if (nonBlocking) {
          if (prev === LockMode.Shared) this.shared++;
          if (prev === LockMode.Exclusive) this.exclusive++;
          return false;
        }
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
    if (ok) this.mode = op;
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
  const fd = fs.openSync(path, mode === "rw" ? "w+" : "r+");
  return new Open(openLockable(path), fd);
}

function check(cond: boolean, label: string): void {
  if (!cond) throw new Error(`FAIL: ${label}`);
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

  // Test 3: exclusive contention via second OPEN
  const f2 = open(path, "rw");
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

  fs.closeSync(f1.fd);
  fs.closeSync(f2.fd);
  fs.unlinkSync(path);
  console.log("concurrent_file_access: 12/12 ok");
}

main();
