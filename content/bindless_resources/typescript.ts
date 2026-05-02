// Vidya — Bindless Resources in TypeScript
//
// In-memory descriptor table — "one global table per frame" pattern.

const TABLE_CAP = 64;

class DescriptorTable {
  slots: BigUint64Array = new BigUint64Array(TABLE_CAP);
  freeLinks: Uint32Array = new Uint32Array(TABLE_CAP);
  nextId = 1;
  freeHead = 0;

  alloc(desc: bigint): number {
    if (this.freeHead !== 0) {
      const id = this.freeHead;
      this.freeHead = this.freeLinks[id];
      this.slots[id] = desc;
      return id;
    }
    if (this.nextId >= TABLE_CAP) return 0;
    const id = this.nextId++;
    this.slots[id] = desc;
    return id;
  }

  lookup(id: number): bigint {
    if (id === 0 || id >= TABLE_CAP) return 0n;
    return this.slots[id];
  }

  update(id: number, desc: bigint): boolean {
    if (id === 0 || id >= TABLE_CAP) return false;
    this.slots[id] = desc;
    return true;
  }

  free(id: number): boolean {
    if (id === 0 || id >= TABLE_CAP) return false;
    this.freeLinks[id] = this.freeHead;
    this.freeHead = id;
    this.slots[id] = 0n;
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

  t.free(id2);
  eq(t.lookup(id2), 0n, "freed");
  const id4 = t.alloc(0x4444444444444444n);
  eq(id4, id2, "reused");
  eq(t.lookup(id4), 0x4444444444444444n, "reused desc");

  const t2 = new DescriptorTable();
  for (let i = 1; i < TABLE_CAP; i++) t2.alloc(BigInt(i));
  eq(t2.alloc(0xDEADBEEFn), 0, "exhausted");

  console.log("bindless_resources: 15/15 ok");
}

main();
