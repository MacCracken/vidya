// Vidya — Explicit GPU Synchronization in TypeScript
//
// Timeline semaphores — monotonic counters with signal/wait/wait_all.

class Timelines {
  compute = 0n;
  transfer = 0n;

  signal(sem: number, value: bigint): boolean {
    if (sem === 0) {
      if (value <= this.compute) return false;
      this.compute = value;
      return true;
    }
    if (sem === 1) {
      if (value <= this.transfer) return false;
      this.transfer = value;
      return true;
    }
    return false;
  }

  waitFor(sem: number, target: bigint): boolean {
    if (sem === 0) return this.compute >= target;
    if (sem === 1) return this.transfer >= target;
    return false;
  }

  waitAll(c: bigint, tr: bigint): boolean {
    return this.waitFor(0, c) && this.waitFor(1, tr);
  }
}

function ok(b: boolean, label: string): void {
  if (!b) throw new Error(label);
}

function nope(b: boolean, label: string): void {
  if (b) throw new Error(label);
}

function main(): void {
  const t = new Timelines();
  if (t.compute !== 0n || t.transfer !== 0n) throw new Error("init");
  ok(t.waitFor(0, 0n), "wait(0,0)");

  ok(t.signal(0, 5n), "signal 5");
  if (t.compute !== 5n) throw new Error("compute=5");

  ok(t.waitFor(0, 3n), "past");
  ok(t.waitFor(0, 5n), "current");
  nope(t.waitFor(0, 10n), "future");

  nope(t.signal(0, 3n), "regress 3");
  if (t.compute !== 5n) throw new Error("after regress");
  nope(t.signal(0, 5n), "regress 5");

  t.signal(1, 3n);
  if (t.transfer !== 3n) throw new Error("transfer=3");
  ok(t.waitAll(5n, 3n), "all 5,3");
  nope(t.waitAll(5n, 4n), "all 5,4");
  nope(t.waitAll(6n, 3n), "all 6,3");
  ok(t.waitAll(0n, 0n), "all 0,0");

  const t2 = new Timelines();
  for (let i = 1n; i <= 10n; i++) t2.signal(0, i);
  if (t2.compute !== 10n) throw new Error("monotonic");
  ok(t2.waitFor(0, 10n), "final");
  nope(t2.waitFor(0, 11n), "beyond");

  console.log("explicit_gpu_synchronization: 19/19 ok");
}

main();
