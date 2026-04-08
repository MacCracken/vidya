// Vidya — Allocators in TypeScript
//
// Simulates three fundamental memory allocation strategies using
// ArrayBuffer and DataView — the same byte-level manipulation that
// real allocators perform on raw memory.
//
//   1. Bump Allocator: fastest possible allocation. A pointer advances
//      forward; no individual frees. Reset deallocates everything at once.
//      Used for arenas (compiler AST nodes, per-frame game data).
//
//   2. Slab Allocator: pre-partitions memory into fixed-size slots.
//      O(1) alloc and free via a free list. Zero fragmentation for
//      same-size objects. Used in kernels (struct caches) and pools.
//
//   3. Bitmap Allocator: tracks free/used blocks with a bit vector.
//      Scans bits to find free blocks. Used for page frame allocation
//      in kernels and block allocation in filesystems.
//
// TypeScript idioms: ArrayBuffer for raw memory, DataView for typed
// access, classes with generics, explicit alignment handling.

// ── Bump Allocator ───────────────────────────────────────────────────
// Allocation = increment a pointer. Free = reset everything.
// Fastest allocator possible. No per-object free.

class BumpAllocator {
    private buffer: ArrayBuffer;
    private view: DataView;
    private offset: number = 0;
    private readonly capacity: number;
    private allocCount: number = 0;

    constructor(sizeBytes: number) {
        this.buffer = new ArrayBuffer(sizeBytes);
        this.view = new DataView(this.buffer);
        this.capacity = sizeBytes;
    }

    // Allocate `size` bytes with given alignment. Returns offset or null.
    alloc(size: number, align: number = 8): number | null {
        // Align the current offset upward
        const aligned = (this.offset + align - 1) & ~(align - 1);
        if (aligned + size > this.capacity) return null;

        this.offset = aligned + size;
        this.allocCount++;
        return aligned;
    }

    // Write a 32-bit value at an offset
    writeU32(offset: number, value: number): void {
        this.view.setUint32(offset, value, true); // little-endian
    }

    // Read a 32-bit value at an offset
    readU32(offset: number): number {
        return this.view.getUint32(offset, true);
    }

    // Reset the allocator — all allocations invalidated
    reset(): void {
        this.offset = 0;
        this.allocCount = 0;
    }

    used(): number { return this.offset; }
    remaining(): number { return this.capacity - this.offset; }
    count(): number { return this.allocCount; }
}

// ── Slab Allocator ───────────────────────────────────────────────────
// Fixed-size slots with a free list. O(1) alloc and free.
// Each free slot stores the index of the next free slot (intrusive list).

class SlabAllocator {
    private buffer: ArrayBuffer;
    private view: DataView;
    private readonly slotSize: number;
    private readonly slotCount: number;
    private freeHead: number; // index of first free slot (-1 = full)
    private allocatedCount: number = 0;

    constructor(slotSize: number, slotCount: number) {
        // Slot must be at least 4 bytes (to store the free list pointer)
        this.slotSize = Math.max(slotSize, 4);
        this.slotCount = slotCount;
        this.buffer = new ArrayBuffer(this.slotSize * slotCount);
        this.view = new DataView(this.buffer);

        // Initialize free list: each slot points to the next
        for (let i = 0; i < slotCount - 1; i++) {
            this.view.setInt32(i * this.slotSize, i + 1, true);
        }
        // Last slot: -1 (end of list)
        this.view.setInt32((slotCount - 1) * this.slotSize, -1, true);
        this.freeHead = 0;
    }

    // Allocate one slot. Returns slot index or null if full.
    alloc(): number | null {
        if (this.freeHead === -1) return null;

        const slot = this.freeHead;
        // Follow the free list to the next free slot
        this.freeHead = this.view.getInt32(slot * this.slotSize, true);
        this.allocatedCount++;
        return slot;
    }

    // Free a slot. Returns it to the free list head.
    free(slot: number): void {
        if (slot < 0 || slot >= this.slotCount) {
            throw new Error(`invalid slot index: ${slot}`);
        }
        // Point this slot to current head, make it the new head
        this.view.setInt32(slot * this.slotSize, this.freeHead, true);
        this.freeHead = slot;
        this.allocatedCount--;
    }

    // Write data into a slot
    writeSlot(slot: number, offset: number, value: number): void {
        this.view.setUint32(slot * this.slotSize + offset, value, true);
    }

    // Read data from a slot
    readSlot(slot: number, offset: number): number {
        return this.view.getUint32(slot * this.slotSize + offset, true);
    }

    allocated(): number { return this.allocatedCount; }
    available(): number { return this.slotCount - this.allocatedCount; }
}

// ── Bitmap Allocator ─────────────────────────────────────────────────
// Tracks block usage with a bit vector. Bit 0 = free, bit 1 = used.
// Scans for free bits to allocate. Used for page frames and disk blocks.

class BitmapAllocator {
    private bitmap: Uint32Array; // 32 blocks per word
    private readonly totalBlocks: number;
    private readonly blockSize: number;
    private freeCount: number;

    constructor(totalBlocks: number, blockSize: number) {
        this.totalBlocks = totalBlocks;
        this.blockSize = blockSize;
        this.freeCount = totalBlocks;
        // Round up to cover all blocks
        const words = Math.ceil(totalBlocks / 32);
        this.bitmap = new Uint32Array(words);
        // All bits zero = all blocks free
    }

    // Allocate a single block. Returns block index or null.
    alloc(): number | null {
        for (let word = 0; word < this.bitmap.length; word++) {
            if (this.bitmap[word] === 0xffffffff) continue; // all used

            // Find first zero bit
            for (let bit = 0; bit < 32; bit++) {
                const blockIdx = word * 32 + bit;
                if (blockIdx >= this.totalBlocks) return null;

                if ((this.bitmap[word] & (1 << bit)) === 0) {
                    this.bitmap[word] |= (1 << bit); // mark used
                    this.freeCount--;
                    return blockIdx;
                }
            }
        }
        return null;
    }

    // Allocate a contiguous range of n blocks. Returns start index or null.
    allocContiguous(n: number): number | null {
        let runStart = -1;
        let runLen = 0;

        for (let i = 0; i < this.totalBlocks; i++) {
            if (this.isBlockFree(i)) {
                if (runLen === 0) runStart = i;
                runLen++;
                if (runLen === n) {
                    // Mark all blocks in the run as used
                    for (let j = runStart; j < runStart + n; j++) {
                        this.markUsed(j);
                    }
                    return runStart;
                }
            } else {
                runLen = 0;
            }
        }
        return null;
    }

    // Free a block
    free(block: number): void {
        if (block < 0 || block >= this.totalBlocks) {
            throw new Error(`invalid block: ${block}`);
        }
        const word = Math.floor(block / 32);
        const bit = block % 32;
        if ((this.bitmap[word] & (1 << bit)) === 0) {
            throw new Error(`double free: block ${block}`);
        }
        this.bitmap[word] &= ~(1 << bit);
        this.freeCount++;
    }

    // Free a contiguous range
    freeRange(start: number, count: number): void {
        for (let i = start; i < start + count; i++) {
            this.free(i);
        }
    }

    private isBlockFree(block: number): boolean {
        const word = Math.floor(block / 32);
        const bit = block % 32;
        return (this.bitmap[word] & (1 << bit)) === 0;
    }

    private markUsed(block: number): void {
        const word = Math.floor(block / 32);
        const bit = block % 32;
        this.bitmap[word] |= (1 << bit);
        this.freeCount--;
    }

    getFreeCount(): number { return this.freeCount; }
    getUsedCount(): number { return this.totalBlocks - this.freeCount; }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testBumpBasic(): void {
    const bump = new BumpAllocator(256);

    const a = bump.alloc(16);
    const b = bump.alloc(32);
    const c = bump.alloc(8);

    assert(a !== null, "first alloc succeeds");
    assert(b !== null, "second alloc succeeds");
    assert(c !== null, "third alloc succeeds");

    // Allocations should not overlap
    assert(a === 0, "first alloc at 0");
    assert(b! >= 16, "second alloc after first");
    assert(c! >= b! + 32, "third alloc after second");
    assert(bump.count() === 3, "three allocations");
}

function testBumpAlignment(): void {
    const bump = new BumpAllocator(256);

    // Allocate 3 bytes, then require 8-byte alignment
    bump.alloc(3, 1);
    const aligned = bump.alloc(16, 8);

    assert(aligned !== null, "aligned alloc succeeds");
    assert(aligned! % 8 === 0, `should be 8-byte aligned, got offset ${aligned}`);
}

function testBumpReadWrite(): void {
    const bump = new BumpAllocator(256);
    const offset = bump.alloc(8)!;

    bump.writeU32(offset, 0xdeadbeef);
    assert(bump.readU32(offset) === 0xdeadbeef, "read back written value");
}

function testBumpExhaustion(): void {
    const bump = new BumpAllocator(32);

    const a = bump.alloc(16);
    const b = bump.alloc(16);
    const c = bump.alloc(1); // should fail

    assert(a !== null, "first fits");
    assert(b !== null, "second fits");
    assert(c === null, "third should fail — no space");
}

function testBumpReset(): void {
    const bump = new BumpAllocator(64);

    bump.alloc(64);
    assert(bump.remaining() === 0, "full after large alloc");

    bump.reset();
    assert(bump.remaining() === 64, "full capacity after reset");
    assert(bump.count() === 0, "count reset to 0");

    const a = bump.alloc(32);
    assert(a !== null, "can allocate after reset");
}

function testSlabBasic(): void {
    const slab = new SlabAllocator(16, 4);

    const s0 = slab.alloc();
    const s1 = slab.alloc();
    const s2 = slab.alloc();
    const s3 = slab.alloc();
    const s4 = slab.alloc(); // should fail

    assert(s0 === 0, "first slot is 0");
    assert(s1 === 1, "second slot is 1");
    assert(s2 === 2, "third slot is 2");
    assert(s3 === 3, "fourth slot is 3");
    assert(s4 === null, "fifth should fail — slab full");
    assert(slab.allocated() === 4, "all 4 allocated");
}

function testSlabFreeReuse(): void {
    const slab = new SlabAllocator(16, 4);

    const s0 = slab.alloc()!;
    const s1 = slab.alloc()!;
    slab.free(s0); // free slot 0

    const reused = slab.alloc();
    assert(reused === s0, "freed slot is reused");
    assert(slab.allocated() === 2, "two allocated after free + realloc");
}

function testSlabReadWrite(): void {
    const slab = new SlabAllocator(16, 4);
    const slot = slab.alloc()!;

    slab.writeSlot(slot, 0, 42);
    slab.writeSlot(slot, 4, 99);

    assert(slab.readSlot(slot, 0) === 42, "read first field");
    assert(slab.readSlot(slot, 4) === 99, "read second field");
}

function testBitmapBasic(): void {
    const bm = new BitmapAllocator(64, 4096);

    assert(bm.getFreeCount() === 64, "all free initially");

    const b0 = bm.alloc();
    const b1 = bm.alloc();

    assert(b0 === 0, "first block is 0");
    assert(b1 === 1, "second block is 1");
    assert(bm.getUsedCount() === 2, "two used");
}

function testBitmapFree(): void {
    const bm = new BitmapAllocator(32, 4096);

    const blocks: number[] = [];
    for (let i = 0; i < 10; i++) {
        blocks.push(bm.alloc()!);
    }

    assert(bm.getUsedCount() === 10, "10 used");

    bm.free(blocks[5]);
    assert(bm.getUsedCount() === 9, "9 after free");
    assert(bm.getFreeCount() === 23, "23 free after free");

    // Re-allocate should get the freed block
    const reused = bm.alloc();
    assert(reused === 5, "freed block 5 is reused");
}

function testBitmapContiguous(): void {
    const bm = new BitmapAllocator(64, 4096);

    // Allocate some blocks to fragment
    bm.alloc(); // 0
    bm.alloc(); // 1
    bm.alloc(); // 2

    // Allocate contiguous range
    const start = bm.allocContiguous(4);
    assert(start === 3, `contiguous 4 blocks starting at 3, got ${start}`);
    assert(bm.getUsedCount() === 7, "7 used total");

    // Free the range
    bm.freeRange(start!, 4);
    assert(bm.getUsedCount() === 3, "back to 3 after freeing range");
}

function testBitmapExhaustion(): void {
    const bm = new BitmapAllocator(8, 4096);

    for (let i = 0; i < 8; i++) {
        assert(bm.alloc() !== null, `block ${i} allocates`);
    }

    assert(bm.alloc() === null, "9th alloc should fail");
    assert(bm.getFreeCount() === 0, "no free blocks");
}

function testBitmapDoubleFree(): void {
    const bm = new BitmapAllocator(16, 4096);
    const b = bm.alloc()!;
    bm.free(b);

    let caught = false;
    try {
        bm.free(b);
    } catch (e) {
        caught = (e as Error).message.includes("double free");
    }
    assert(caught, "double free should throw");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testBumpBasic();
    testBumpAlignment();
    testBumpReadWrite();
    testBumpExhaustion();
    testBumpReset();
    testSlabBasic();
    testSlabFreeReuse();
    testSlabReadWrite();
    testBitmapBasic();
    testBitmapFree();
    testBitmapContiguous();
    testBitmapExhaustion();
    testBitmapDoubleFree();

    console.log("All allocators tests passed.");
}

main();
