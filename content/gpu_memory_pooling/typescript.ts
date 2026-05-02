// Vidya — GPU Memory Pooling in TypeScript
//
// Bump allocator over a 1024-byte pool.

const POOL_SIZE = 1024;

class Pool {
  bump = 0;
  reset(): void { this.bump = 0; }
  used(): number { return this.bump; }
  free(): number { return POOL_SIZE - this.bump; }

  alloc(size: number): number {
    if (size === 0) return this.bump;
    if (this.bump + size > POOL_SIZE) return -1;
    const off = this.bump;
    this.bump += size;
    return off;
  }

  allocAligned(size: number, align: number): number {
    const mask = align - 1;
    const aligned = (this.bump + mask) & ~mask;
    if (aligned + size > POOL_SIZE) return -1;
    this.bump = aligned + size;
    return aligned;
  }
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const p = new Pool();
  eq(p.used(), 0, "init used");
  eq(p.free(), 1024, "init free");

  eq(p.alloc(100), 0, "alloc1");
  eq(p.used(), 100, "used1");

  eq(p.alloc(200), 100, "alloc2");
  eq(p.used(), 300, "used2");

  eq(p.alloc(1000), -1, "exhausted");
  eq(p.used(), 300, "used unchanged");

  p.reset();
  eq(p.used(), 0, "reset used");
  eq(p.free(), 1024, "reset free");
  eq(p.alloc(50), 0, "post reset");

  eq(p.allocAligned(32, 16), 64, "aligned 64");
  eq(p.used(), 96, "used 96");

  eq(p.alloc(0), 96, "noop");
  eq(p.used(), 96, "noop used");

  p.reset();
  for (let i = 0; i < 10; i++) p.alloc(8);
  eq(p.used(), 80, "10x8");

  console.log("gpu_memory_pooling: 16/16 ok");
}

main();
