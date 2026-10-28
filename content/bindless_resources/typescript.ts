// Vidya — Bindless Resources in TypeScript
//
// In-memory descriptor table — "one global table per frame" pattern.
//
// A handle is (generation << 8) | slot. Freeing a slot bumps its
// generation, so a handle kept past free() no longer matches and is
// rejected instead of silently reading whatever reuses the slot. A bare
// slot index cannot tell the two apart, and a double free would put the
// slot on the free list twice (two live allocations, one slot).

const TABLE_CAP = 64;
const IDX_BITS = 8;
const IDX_MASK = (1 << IDX_BITS) - 1;
// 24 generation bits sit above the slot in a 32-bit handle. The counter
// wraps after 2^24 frees of one slot; a handle that old would alias.
const GEN_MASK = 0xffffff;

class DescriptorTable {
  slots: BigUint64Array = new BigUint64Array(TABLE_CAP);
  freeLinks: Uint32Array = new Uint32Array(TABLE_CAP);
  gens: Uint32Array = new Uint32Array(TABLE_CAP);
  live: Uint8Array = new Uint8Array(TABLE_CAP); // 1 = handed out, 0 = free / never used
  nextId = 1;
  freeHead = 0;

  private handle(i: number): number {
    return ((this.gens[i] << IDX_BITS) | i) >>> 0;
  }

  // Slot index for a live, current-generation handle, else 0.
  private liveIndex(h: number): number {
    const i = h & IDX_MASK;
    if (i === 0 || i >= TABLE_CAP || !this.live[i]) return 0;
    // Stale: the slot was freed (and maybe reused) since h was issued.
    if (h >>> IDX_BITS !== this.gens[i]) return 0;
    return i;
  }

  alloc(desc: bigint): number {
    let id: number;
    if (this.freeHead !== 0) {
      id = this.freeHead;
      this.freeHead = this.freeLinks[id];
    } else {
      if (this.nextId >= TABLE_CAP) return 0;
      id = this.nextId++;
    }
    this.slots[id] = desc;
    this.live[id] = 1;
    return this.handle(id);
  }

  lookup(h: number): bigint {
    const i = this.liveIndex(h);
    return i === 0 ? 0n : this.slots[i];
  }

  update(h: number, desc: bigint): boolean {
    const i = this.liveIndex(h);
    if (i === 0) return false;
    this.slots[i] = desc;
    return true;
  }

  free(h: number): boolean {
    const i = this.liveIndex(h);
    // Null, stale or double free. A double free would link the slot to
    // itself and the next two allocs would hand out the SAME slot.
    if (i === 0) return false;
    this.live[i] = 0;
    this.gens[i] = (this.gens[i] + 1) & GEN_MASK;
    this.freeLinks[i] = this.freeHead;
    this.freeHead = i;
    this.slots[i] = 0n;
    return true;
  }
}

function eq<T>(got: T, want: T, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const t = new DescriptorTable();

  const id1 = t.alloc(0x1111111111111111n);
  const id2 = t.alloc(0x2222222222222222n);
  const id3 = t.alloc(0x3333333333333333n);
  eq(id1, 1, "id1");
  eq(id2, 2, "id2");
  eq(id3, 3, "id3");

  eq(t.lookup(0), 0n, "slot 0");

  eq(t.lookup(id1), 0x1111111111111111n, "lookup1");
  eq(t.lookup(id2), 0x2222222222222222n, "lookup2");
  eq(t.lookup(id3), 0x3333333333333333n, "lookup3");

  if (!t.update(id2, 0xAAAAAAAAAAAAAAAAn)) throw new Error("update");
  eq(t.lookup(id2), 0xAAAAAAAAAAAAAAAAn, "id2 new");
  eq(t.lookup(id1), 0x1111111111111111n, "id1 unchanged");
  eq(t.lookup(id3), 0x3333333333333333n, "id3 unchanged");

  eq(t.free(id2), true, "free");
  eq(t.free(id2), false, "double free rejected");
  eq(t.lookup(id2), 0n, "freed");
  const id4 = t.alloc(0x4444444444444444n);
  eq(id4 & IDX_MASK, id2 & IDX_MASK, "slot reused");
  eq(id4 !== id2, true, "...under a new generation");
  eq(t.lookup(id4), 0x4444444444444444n, "reused desc");
  eq(t.lookup(id2), 0n, "stale handle rejected");
  eq(t.update(id2, 0xbadn), false, "stale write rejected");
  eq(t.free(id2), false, "stale free rejected");
  eq(t.free(50), false, "never-allocated slot rejected");

  const t2 = new DescriptorTable();
  for (let i = 1; i < TABLE_CAP; i++) t2.alloc(BigInt(i));
  eq(t2.alloc(0xDEADBEEFn), 0, "exhausted");

  console.log("bindless_resources: 22/22 ok");
}

main();
