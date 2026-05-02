// Vidya — Direct DRM GPU Compute in TypeScript
//
// In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

const BO_CAP = 32;
const VA_CAP = 32;

class Device {
  fd = 0;
  boSize = new BigUint64Array(BO_CAP);
  nextBO = 1;
  vaAddr = new BigUint64Array(VA_CAP);
  vaBO = new Uint32Array(VA_CAP);
  vaCount = 0;
  nextSeq = 1n;
  completedSeq = 0n;

  openRenderNode(): number { this.fd = 42; return this.fd; }

  gemCreate(size: bigint): number {
    if (this.nextBO >= BO_CAP) return 0;
    const h = this.nextBO++;
    this.boSize[h] = size;
    return h;
  }

  gemDestroy(handle: number): boolean {
    if (handle === 0 || handle >= BO_CAP) return false;
    if (this.boSize[handle] === 0n) return false;
    this.boSize[handle] = 0n;
    for (let i = 0; i < this.vaCount; i++) {
      if (this.vaBO[i] === handle) this.vaBO[i] = 0;
    }
    return true;
  }

  gemVaMap(handle: number, va: bigint): boolean {
    if (handle === 0 || handle >= BO_CAP) return false;
    if (this.boSize[handle] === 0n) return false;
    if (this.vaCount >= VA_CAP) return false;
    this.vaAddr[this.vaCount] = va;
    this.vaBO[this.vaCount] = handle;
    this.vaCount++;
    return true;
  }

  vaLookup(va: bigint): number {
    for (let i = 0; i < this.vaCount; i++) {
      if (this.vaAddr[i] === va && this.vaBO[i] !== 0) return this.vaBO[i];
    }
    return 0;
  }

  submit(handle: number): bigint {
    if (handle === 0 || handle >= BO_CAP) return 0n;
    if (this.boSize[handle] === 0n) return 0n;
    const seq = this.nextSeq++;
    this.completedSeq = seq;
    return seq;
  }

  syncobjWait(seq: bigint): boolean {
    return this.completedSeq >= seq;
  }
}

function eq<T>(got: T, want: T, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function ok(b: boolean, label: string): void {
  if (!b) throw new Error(label);
}

function main(): void {
  const d = new Device();

  if (d.openRenderNode() === 0) throw new Error("fd");

  const b1 = d.gemCreate(4096n);
  const b2 = d.gemCreate(8192n);
  const b3 = d.gemCreate(16384n);
  eq(b1, 1, "b1");
  eq(b2, 2, "b2");
  eq(b3, 3, "b3");

  ok(d.gemVaMap(b1, 0x1000n), "map b1");
  ok(d.gemVaMap(b2, 0x2000n), "map b2");

  eq(d.vaLookup(0x1000n), b1, "lookup b1");
  eq(d.vaLookup(0x2000n), b2, "lookup b2");
  eq(d.vaLookup(0x9000n), 0, "unmapped");

  ok(!d.gemVaMap(99, 0x3000n), "invalid handle");
  ok(!d.gemVaMap(0, 0x3000n), "handle 0");

  eq(d.submit(b1), 1n, "seq 1");
  eq(d.submit(b2), 2n, "seq 2");
  eq(d.submit(b3), 3n, "seq 3");

  ok(d.syncobjWait(1n), "wait 1");
  ok(d.syncobjWait(3n), "wait 3");
  ok(!d.syncobjWait(99n), "wait future");

  d.gemDestroy(b1);
  eq(d.vaLookup(0x1000n), 0, "destroyed");

  eq(d.submit(b1), 0n, "submit destroyed");
  eq(d.submit(b2), 4n, "next valid");

  console.log("direct_drm_gpu_compute: 20/20 ok");
}

main();
