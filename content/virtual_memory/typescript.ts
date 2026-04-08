// Vidya — Virtual Memory in TypeScript
//
// Virtual memory gives each process its own address space, mapped to
// physical memory through page tables. x86_64 uses 4-level paging:
// PML4 → PDPT → PD → PT → physical frame + offset.
// We simulate the full walk, model page table entries with bitfields,
// and build a TLB cache with Map.

function main(): void {
    testPageTableEntry();
    testAddressDecomposition();
    testPageTableWalk();
    testTlbCache();
    testDemandPaging();
    testPermissionChecks();

    console.log("All virtual memory examples passed.");
}

// ── Constants ───────────────────────────────────────────────────────

const PAGE_SIZE = 4096;            // 4 KB
const PAGE_SHIFT = 12;
const ENTRIES_PER_TABLE = 512;     // 9 bits per level
const ADDR_MASK = 0x000F_FFFF_FFFF_F000n; // bits 12-51: physical frame address

// Page table entry flags (bit positions)
const PTE_PRESENT    = 1n << 0n;   // P: page is mapped
const PTE_WRITABLE   = 1n << 1n;   // R/W: writable
const PTE_USER       = 1n << 2n;   // U/S: accessible from ring 3
const PTE_WRITETHROUGH = 1n << 3n; // PWT: write-through caching
const PTE_NOCACHE    = 1n << 4n;   // PCD: disable cache
const PTE_ACCESSED   = 1n << 5n;   // A: has been read
const PTE_DIRTY      = 1n << 6n;   // D: has been written
const PTE_HUGE       = 1n << 7n;   // PS: 2MB/1GB huge page
const PTE_GLOBAL     = 1n << 8n;   // G: don't flush from TLB on CR3 switch
const PTE_NO_EXECUTE = 1n << 63n;  // NX: no-execute (requires EFER.NXE)

// ── Page Table Entry ────────────────────────────────────────────────

class PageTableEntry {
    constructor(public raw: bigint) {}

    static empty(): PageTableEntry {
        return new PageTableEntry(0n);
    }

    static create(physAddr: bigint, flags: bigint): PageTableEntry {
        if ((physAddr & 0xFFFn) !== 0n) {
            throw new Error(`address 0x${physAddr.toString(16)} not 4KB aligned`);
        }
        return new PageTableEntry((physAddr & ADDR_MASK) | flags);
    }

    get present(): boolean    { return (this.raw & PTE_PRESENT) !== 0n; }
    get writable(): boolean   { return (this.raw & PTE_WRITABLE) !== 0n; }
    get user(): boolean       { return (this.raw & PTE_USER) !== 0n; }
    get accessed(): boolean   { return (this.raw & PTE_ACCESSED) !== 0n; }
    get dirty(): boolean      { return (this.raw & PTE_DIRTY) !== 0n; }
    get huge(): boolean       { return (this.raw & PTE_HUGE) !== 0n; }
    get global(): boolean     { return (this.raw & PTE_GLOBAL) !== 0n; }
    get noExecute(): boolean  { return (this.raw & PTE_NO_EXECUTE) !== 0n; }
    get physAddr(): bigint    { return this.raw & ADDR_MASK; }

    setAccessed(): void  { this.raw |= PTE_ACCESSED; }
    setDirty(): void     { this.raw |= PTE_DIRTY; }

    flagsString(): string {
        let s = "";
        s += this.present   ? "P" : "-";
        s += this.writable  ? "W" : "R";
        s += this.user      ? "U" : "S";
        s += this.accessed  ? "A" : "-";
        s += this.dirty     ? "D" : "-";
        s += this.noExecute ? "NX" : "--";
        return s;
    }
}

function testPageTableEntry(): void {
    // Code page: present, not writable, not user, no-execute disabled
    const code = PageTableEntry.create(0x20_0000n, PTE_PRESENT);
    assert(code.present, "code present");
    assert(!code.writable, "code read-only");
    assert(!code.user, "code supervisor");
    assert(code.physAddr === 0x20_0000n, "code phys addr");

    // Data page: present, writable, user, no-execute
    const data = PageTableEntry.create(
        0x30_0000n,
        PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NO_EXECUTE,
    );
    assert(data.writable, "data writable");
    assert(data.user, "data user");
    assert(data.noExecute, "data NX");

    // Accessed/dirty tracking (set by hardware on real CPUs)
    const page = PageTableEntry.create(0x40_0000n, PTE_PRESENT | PTE_WRITABLE);
    assert(!page.accessed, "initially not accessed");
    page.setAccessed();
    assert(page.accessed, "now accessed");
    page.setDirty();
    assert(page.dirty, "now dirty");

    // Unmapped page
    const empty = PageTableEntry.empty();
    assert(!empty.present, "empty not present");

    // Alignment check
    let threw = false;
    try { PageTableEntry.create(0x123n, PTE_PRESENT); } catch { threw = true; }
    assert(threw, "unaligned rejected");
}

// ── Virtual Address Decomposition ───────────────────────────────────

// A 48-bit virtual address is split into 4 page table indices + offset:
//   [47:39] PML4 index   (9 bits, 512 entries)
//   [38:30] PDPT index   (9 bits)
//   [29:21] PD index     (9 bits)
//   [20:12] PT index     (9 bits)
//   [11:0]  Page offset  (12 bits, 4096 bytes)

interface VAddrParts {
    pml4: number;
    pdpt: number;
    pd: number;
    pt: number;
    offset: number;
}

function decompose(vaddr: bigint): VAddrParts {
    return {
        pml4:   Number((vaddr >> 39n) & 0x1FFn),
        pdpt:   Number((vaddr >> 30n) & 0x1FFn),
        pd:     Number((vaddr >> 21n) & 0x1FFn),
        pt:     Number((vaddr >> 12n) & 0x1FFn),
        offset: Number(vaddr & 0xFFFn),
    };
}

function testAddressDecomposition(): void {
    // Address 0x0040_0078: low memory
    const low = decompose(0x0040_0078n);
    assert(low.pml4 === 0, "low pml4 = 0");
    assert(low.offset === 0x78, "low offset = 0x78");

    // Address near top of user space: 0x7FFF_FFFF_F000
    const top = decompose(0x7FFF_FFFF_F000n);
    assert(top.pml4 === 0xFF, "top pml4 = 255");
    assert(top.pdpt === 0x1FF, "top pdpt = 511");
    assert(top.pd === 0x1FF, "top pd = 511");
    assert(top.pt === 0x1FF, "top pt = 511");
    assert(top.offset === 0, "top offset = 0");

    // Kernel address (higher half): 0xFFFF_8000_0000_0000
    const kernel = decompose(0xFFFF_8000_0000_0000n);
    assert(kernel.pml4 === 256, "kernel pml4 = 256");
    // (Higher-half kernel starts at PML4[256])
}

// ── Page Table Walk Simulation ──────────────────────────────────────

// Simulates the 4-level page table walk that the MMU performs
// on every memory access (when not cached in the TLB).

class PageTable {
    entries: PageTableEntry[];

    constructor() {
        this.entries = Array.from({ length: ENTRIES_PER_TABLE }, () =>
            PageTableEntry.empty()
        );
    }
}

class PhysAllocator {
    private nextFrame: bigint;
    allocated = 0;

    constructor(start: bigint) {
        this.nextFrame = start;
    }

    allocFrame(): bigint {
        const frame = this.nextFrame;
        this.nextFrame += BigInt(PAGE_SIZE);
        this.allocated++;
        return frame;
    }
}

class MMU {
    private tables = new Map<bigint, PageTable>();
    private cr3: bigint;
    private phys: PhysAllocator;
    pageFaults = 0;

    constructor() {
        this.phys = new PhysAllocator(0x1000n);
        this.cr3 = this.phys.allocFrame();
        this.tables.set(this.cr3, new PageTable());
    }

    /** Map a virtual page to a physical frame. */
    mapPage(vaddr: bigint, physFrame: bigint, flags: bigint): void {
        const { pml4, pdpt, pd, pt } = decompose(vaddr);

        const pdptAddr = this.ensureEntry(this.cr3, pml4, flags);
        const pdAddr   = this.ensureEntry(pdptAddr, pdpt, flags);
        const ptAddr   = this.ensureEntry(pdAddr, pd, flags);

        const table = this.tables.get(ptAddr)!;
        table.entries[pt] = PageTableEntry.create(physFrame, flags | PTE_PRESENT);
    }

    private ensureEntry(tableAddr: bigint, index: number, flags: bigint): bigint {
        const table = this.tables.get(tableAddr)!;
        const entry = table.entries[index];

        if (entry.present) {
            return entry.physAddr;
        }

        const newAddr = this.phys.allocFrame();
        this.tables.set(newAddr, new PageTable());
        table.entries[index] = PageTableEntry.create(newAddr, flags | PTE_PRESENT);
        return newAddr;
    }

    /** Translate virtual address to physical. Returns null on page fault. */
    translate(vaddr: bigint): bigint | null {
        const { pml4, pdpt, pd, pt, offset } = decompose(vaddr);

        const pml4Table = this.tables.get(this.cr3);
        if (!pml4Table) return this.fault();

        const pml4e = pml4Table.entries[pml4];
        if (!pml4e.present) return this.fault();

        const pdptTable = this.tables.get(pml4e.physAddr);
        if (!pdptTable) return this.fault();

        const pdpte = pdptTable.entries[pdpt];
        if (!pdpte.present) return this.fault();

        const pdTable = this.tables.get(pdpte.physAddr);
        if (!pdTable) return this.fault();

        const pde = pdTable.entries[pd];
        if (!pde.present) return this.fault();

        const ptTable = this.tables.get(pde.physAddr);
        if (!ptTable) return this.fault();

        const pte = ptTable.entries[pt];
        if (!pte.present) return this.fault();

        return pte.physAddr | BigInt(offset);
    }

    private fault(): null {
        this.pageFaults++;
        return null;
    }

    get framesAllocated(): number { return this.phys.allocated; }
}

function testPageTableWalk(): void {
    const mmu = new MMU();

    // Map some pages
    const flags = PTE_PRESENT | PTE_WRITABLE | PTE_USER;
    mmu.mapPage(0x40_0000n, 0x20_0000n, flags); // code
    mmu.mapPage(0x40_1000n, 0x20_1000n, flags); // code page 2
    mmu.mapPage(0x60_0000n, 0x30_0000n, flags); // data

    // Translate mapped addresses
    const phys1 = mmu.translate(0x40_0078n);
    assert(phys1 === 0x20_0078n, "translate code+offset");

    const phys2 = mmu.translate(0x40_1234n);
    assert(phys2 === 0x20_1234n, "translate code page 2");

    const phys3 = mmu.translate(0x60_0100n);
    assert(phys3 === 0x30_0100n, "translate data");

    // Unmapped address causes page fault
    const unmapped = mmu.translate(0x50_0000n);
    assert(unmapped === null, "unmapped = page fault");
    assert(mmu.pageFaults === 1, "one page fault");

    // Page tables share intermediate levels (code pages share PML4/PDPT/PD)
    // Only the PT level differs for adjacent pages in the same 2MB range
}

// ── TLB Cache ───────────────────────────────────────────────────────

// The TLB (Translation Lookaside Buffer) caches recent virtual→physical
// translations. A TLB hit avoids the expensive 4-level page table walk.

class TlbCache {
    private entries = new Map<bigint, bigint>(); // virtual page → physical frame
    hits = 0;
    misses = 0;

    constructor(private capacity: number) {}

    lookup(vpage: bigint): bigint | null {
        const frame = this.entries.get(vpage);
        if (frame !== undefined) {
            this.hits++;
            return frame;
        }
        this.misses++;
        return null;
    }

    insert(vpage: bigint, pframe: bigint): void {
        if (this.entries.size >= this.capacity) {
            // Evict oldest entry (first key in Map iteration order)
            const firstKey = this.entries.keys().next().value!;
            this.entries.delete(firstKey);
        }
        this.entries.set(vpage, pframe);
    }

    /** Flush entire TLB (happens on CR3 write / context switch). */
    flush(): void {
        this.entries.clear();
    }

    /** Flush a single page (INVLPG instruction). */
    flushPage(vpage: bigint): void {
        this.entries.delete(vpage);
    }

    get hitRate(): number {
        const total = this.hits + this.misses;
        return total > 0 ? this.hits / total : 0;
    }

    get size(): number { return this.entries.size; }
}

function testTlbCache(): void {
    const tlb = new TlbCache(4); // tiny TLB for testing

    // Miss on first access
    assert(tlb.lookup(0x40_0000n) === null, "first access misses");

    // Insert and hit
    tlb.insert(0x40_0000n, 0x20_0000n);
    assert(tlb.lookup(0x40_0000n) === 0x20_0000n, "cached hit");
    assert(tlb.hits === 1, "one hit");
    assert(tlb.misses === 1, "one miss");

    // Fill to capacity
    tlb.insert(0x40_1000n, 0x20_1000n);
    tlb.insert(0x40_2000n, 0x20_2000n);
    tlb.insert(0x40_3000n, 0x20_3000n);
    assert(tlb.size === 4, "TLB full");

    // Adding one more evicts the oldest
    tlb.insert(0x40_4000n, 0x20_4000n);
    assert(tlb.size === 4, "still 4 after eviction");
    assert(tlb.lookup(0x40_0000n) === null, "evicted entry misses");

    // Flush entire TLB (context switch)
    tlb.flush();
    assert(tlb.size === 0, "flushed");

    // INVLPG: flush single page (after munmap or page table update)
    tlb.insert(0x50_0000n, 0x10_0000n);
    tlb.insert(0x50_1000n, 0x10_1000n);
    tlb.flushPage(0x50_0000n);
    assert(tlb.lookup(0x50_0000n) === null, "flushed page misses");
    assert(tlb.lookup(0x50_1000n) === 0x10_1000n, "other page still cached");
}

// ── Demand Paging Simulation ────────────────────────────────────────

// In demand paging, pages are only mapped when first accessed.
// A page fault triggers the OS to allocate a frame and map the page.

class DemandPagingMMU {
    private mmu = new MMU();
    private phys = new PhysAllocator(0x100_0000n);
    private mappedPages = new Set<bigint>();
    faultsHandled = 0;

    access(vaddr: bigint): bigint {
        const result = this.mmu.translate(vaddr);
        if (result !== null) return result;

        // Page fault! Allocate a frame and map the page.
        const vpage = vaddr & ~0xFFFn;
        const frame = this.phys.allocFrame();
        this.mmu.mapPage(vpage, frame, PTE_PRESENT | PTE_WRITABLE | PTE_USER);
        this.mappedPages.add(vpage);
        this.faultsHandled++;

        return this.mmu.translate(vaddr)!;
    }

    get pageCount(): number { return this.mappedPages.size; }
}

function testDemandPaging(): void {
    const dmmu = new DemandPagingMMU();

    // First access triggers a fault and allocation
    const phys1 = dmmu.access(0x40_0100n);
    assert(phys1 !== null, "demand-mapped");
    assert(dmmu.faultsHandled === 1, "one fault handled");

    // Second access to same page does NOT fault
    const phys2 = dmmu.access(0x40_0200n);
    assert(dmmu.faultsHandled === 1, "same page, no new fault");

    // Access to a different page triggers another fault
    dmmu.access(0x40_1000n);
    assert(dmmu.faultsHandled === 2, "new page faults");

    // Multiple pages
    dmmu.access(0x40_2000n);
    dmmu.access(0x40_3000n);
    assert(dmmu.pageCount === 4, "4 pages mapped on demand");
}

// ── Permission Checks ───────────────────────────────────────────────

// The MMU enforces permissions: user code cannot access supervisor pages,
// writes to read-only pages fault, and execution of NX pages faults.

type AccessType = "read" | "write" | "execute";

function checkPermission(
    pte: PageTableEntry,
    access: AccessType,
    userMode: boolean,
): { allowed: boolean; reason?: string } {
    if (!pte.present) {
        return { allowed: false, reason: "page not present" };
    }

    if (userMode && !pte.user) {
        return { allowed: false, reason: "supervisor page accessed from user mode" };
    }

    if (access === "write" && !pte.writable) {
        return { allowed: false, reason: "write to read-only page" };
    }

    if (access === "execute" && pte.noExecute) {
        return { allowed: false, reason: "execute on NX page" };
    }

    return { allowed: true };
}

function testPermissionChecks(): void {
    // Kernel code page: present, not user, not writable, executable
    const kcode = PageTableEntry.create(0x10_0000n, PTE_PRESENT);
    assert(checkPermission(kcode, "read", false).allowed, "kernel read kernel page");
    assert(!checkPermission(kcode, "read", true).allowed, "user cannot read kernel page");

    // User data page: present, writable, user, NX
    const udata = PageTableEntry.create(
        0x20_0000n,
        PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NO_EXECUTE,
    );
    assert(checkPermission(udata, "read", true).allowed, "user read data");
    assert(checkPermission(udata, "write", true).allowed, "user write data");
    assert(!checkPermission(udata, "execute", true).allowed, "cannot execute NX page");

    // Read-only user page (e.g., .rodata)
    const rodata = PageTableEntry.create(0x30_0000n, PTE_PRESENT | PTE_USER);
    assert(checkPermission(rodata, "read", true).allowed, "user read rodata");
    assert(!checkPermission(rodata, "write", true).allowed, "cannot write rodata");

    // Not present
    const empty = PageTableEntry.empty();
    assert(!checkPermission(empty, "read", false).allowed, "not present faults");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
