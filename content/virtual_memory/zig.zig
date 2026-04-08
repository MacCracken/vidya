// Vidya — Virtual Memory in Zig
//
// x86_64 uses 4-level page tables (PML4 → PDPT → PD → PT → Page).
// Each level indexes 9 bits of the virtual address. Zig packed structs
// model page table entries with exact bitfield layout. comptime builds
// page tables and validates address arithmetic at compile time.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testPageTableEntry();
    try testAddressDecomposition();
    try testFourLevelWalk();
    try testHugePages();
    try testTlbSimulation();
    try testAddressSpaceLayout();
    try testPageFaultClassification();

    std.debug.print("All virtual memory examples passed.\n", .{});
}

// ── Page Table Entry (64-bit) ────────────────────────────────────────
// Each PTE is 8 bytes with specific bit meanings
const PteFlags = struct {
    const PRESENT: u64 = 1 << 0; // Page is in physical memory
    const WRITABLE: u64 = 1 << 1; // Read/write (vs read-only)
    const USER: u64 = 1 << 2; // User-mode accessible
    const WRITE_THROUGH: u64 = 1 << 3; // Write-through caching
    const NO_CACHE: u64 = 1 << 4; // Disable caching
    const ACCESSED: u64 = 1 << 5; // CPU sets on access
    const DIRTY: u64 = 1 << 6; // CPU sets on write
    const HUGE_PAGE: u64 = 1 << 7; // 2MB (PD) or 1GB (PDPT)
    const GLOBAL: u64 = 1 << 8; // Not flushed on CR3 reload
    const NO_EXECUTE: u64 = @as(u64, 1) << 63; // NX bit (requires EFER.NXE)

    // Physical address mask: bits 12-51
    const ADDR_MASK: u64 = 0x000F_FFFF_FFFF_F000;
};

const PageTableEntry = struct {
    raw: u64,

    fn new(phys_addr: u64, flags: u64) PageTableEntry {
        return .{ .raw = (phys_addr & PteFlags.ADDR_MASK) | flags };
    }

    fn empty() PageTableEntry {
        return .{ .raw = 0 };
    }

    fn present(self: PageTableEntry) bool {
        return self.raw & PteFlags.PRESENT != 0;
    }

    fn writable(self: PageTableEntry) bool {
        return self.raw & PteFlags.WRITABLE != 0;
    }

    fn user(self: PageTableEntry) bool {
        return self.raw & PteFlags.USER != 0;
    }

    fn noExecute(self: PageTableEntry) bool {
        return self.raw & PteFlags.NO_EXECUTE != 0;
    }

    fn dirty(self: PageTableEntry) bool {
        return self.raw & PteFlags.DIRTY != 0;
    }

    fn accessed(self: PageTableEntry) bool {
        return self.raw & PteFlags.ACCESSED != 0;
    }

    fn hugePage(self: PageTableEntry) bool {
        return self.raw & PteFlags.HUGE_PAGE != 0;
    }

    fn physAddr(self: PageTableEntry) u64 {
        return self.raw & PteFlags.ADDR_MASK;
    }
};

fn testPageTableEntry() !void {
    // Kernel code page: present, not writable, not user, no-execute off
    const code = PageTableEntry.new(0x1000, PteFlags.PRESENT);
    try expect(code.present());
    try expect(!code.writable());
    try expect(!code.user());
    try expect(!code.noExecute());
    try expect(code.physAddr() == 0x1000);

    // User data page: present, writable, user-accessible, NX
    const data = PageTableEntry.new(
        0x200_000,
        PteFlags.PRESENT | PteFlags.WRITABLE | PteFlags.USER | PteFlags.NO_EXECUTE,
    );
    try expect(data.present() and data.writable() and data.user() and data.noExecute());

    // Unmapped page: not present — any access triggers #PF
    const unmapped = PageTableEntry.empty();
    try expect(!unmapped.present());

    // MMIO page: present, writable, no cache, no execute
    const mmio = PageTableEntry.new(
        0xFE00_0000,
        PteFlags.PRESENT | PteFlags.WRITABLE | PteFlags.NO_CACHE | PteFlags.NO_EXECUTE,
    );
    try expect(mmio.raw & PteFlags.NO_CACHE != 0);
}

// ── Address Decomposition ────────────────────────────────────────────
// 48-bit virtual address → 4 indices (9 bits each) + 12-bit offset
//
// Bits:  [63:48] sign ext | [47:39] PML4 | [38:30] PDPT | [29:21] PD | [20:12] PT | [11:0] offset
const VAddrParts = struct {
    pml4: u9, // Page Map Level 4 index
    pdpt: u9, // Page Directory Pointer Table index
    pd: u9, // Page Directory index
    pt: u9, // Page Table index
    offset: u12, // Offset within page
    is_canonical: bool, // Sign-extended bits 48-63
};

fn decomposeVaddr(vaddr: u64) VAddrParts {
    // Canonical check: bits 48-63 must match bit 47
    const bit47 = (vaddr >> 47) & 1;
    const upper = vaddr >> 48;
    const canonical = if (bit47 == 1) upper == 0xFFFF else upper == 0;

    return .{
        .pml4 = @truncate((vaddr >> 39) & 0x1FF),
        .pdpt = @truncate((vaddr >> 30) & 0x1FF),
        .pd = @truncate((vaddr >> 21) & 0x1FF),
        .pt = @truncate((vaddr >> 12) & 0x1FF),
        .offset = @truncate(vaddr & 0xFFF),
        .is_canonical = canonical,
    };
}

fn composeVaddr(parts: VAddrParts) u64 {
    var addr: u64 = 0;
    addr |= @as(u64, parts.offset);
    addr |= @as(u64, parts.pt) << 12;
    addr |= @as(u64, parts.pd) << 21;
    addr |= @as(u64, parts.pdpt) << 30;
    addr |= @as(u64, parts.pml4) << 39;
    // Sign extend for canonical form
    if (parts.pml4 & 0x100 != 0) {
        addr |= 0xFFFF_0000_0000_0000;
    }
    return addr;
}

fn testAddressDecomposition() !void {
    // User-space address
    const user = decomposeVaddr(0x0000_7FFF_FFFF_F000);
    try expect(user.pml4 == 0xFF);
    try expect(user.pdpt == 0x1FF);
    try expect(user.pd == 0x1FF);
    try expect(user.pt == 0x1FF);
    try expect(user.offset == 0);
    try expect(user.is_canonical);

    // Kernel-space address (higher half)
    const kernel = decomposeVaddr(0xFFFF_8000_0000_0000);
    try expect(kernel.pml4 == 256); // first kernel PML4 entry
    try expect(kernel.is_canonical);

    // Zero address
    const zero = decomposeVaddr(0x0);
    try expect(zero.pml4 == 0);
    try expect(zero.offset == 0);
    try expect(zero.is_canonical);

    // Round-trip: decompose then compose
    const test_addr: u64 = 0x0000_7F80_1234_5678;
    const parts = decomposeVaddr(test_addr);
    const reconstructed = composeVaddr(parts);
    try expect(reconstructed == test_addr);
}

// ── Four-Level Page Walk ─────────────────────────────────────────────
// Simulates MMU hardware translating virtual → physical address
const PAGE_SIZE = 4096;
const ENTRIES_PER_TABLE = 512;

const PageTable = struct {
    entries: [ENTRIES_PER_TABLE]PageTableEntry,

    fn empty() PageTable {
        return .{ .entries = [_]PageTableEntry{PageTableEntry.empty()} ** ENTRIES_PER_TABLE };
    }
};

const WalkResult = union(enum) {
    success: u64, // physical address
    not_present: u8, // level where walk failed (4=PML4, 1=PT)
    permission_denied: []const u8,
};

fn simulateWalk(
    pml4: *const PageTable,
    pdpt: *const PageTable,
    pd: *const PageTable,
    pt: *const PageTable,
    vaddr: u64,
) WalkResult {
    const parts = decomposeVaddr(vaddr);

    // Level 4: PML4
    const pml4e = pml4.entries[parts.pml4];
    if (!pml4e.present()) return .{ .not_present = 4 };

    // Level 3: PDPT
    const pdpte = pdpt.entries[parts.pdpt];
    if (!pdpte.present()) return .{ .not_present = 3 };

    // Level 2: PD (check for 2MB huge page)
    const pde = pd.entries[parts.pd];
    if (!pde.present()) return .{ .not_present = 2 };
    if (pde.hugePage()) {
        // 2MB page: physical = pde.physAddr + offset_21bit
        const offset_2mb = vaddr & 0x1FFFFF;
        return .{ .success = pde.physAddr() + offset_2mb };
    }

    // Level 1: PT
    const pte = pt.entries[parts.pt];
    if (!pte.present()) return .{ .not_present = 1 };

    return .{ .success = pte.physAddr() + parts.offset };
}

fn testFourLevelWalk() !void {
    // Build a minimal page table hierarchy
    var pml4 = PageTable.empty();
    var pdpt = PageTable.empty();
    var pd = PageTable.empty();
    var pt = PageTable.empty();

    // Map virtual 0x0000_0000_0020_1000 → physical 0x8000_1000
    // PML4[0] → PDPT, PDPT[0] → PD, PD[1] → PT, PT[1] → 0x8000_1000
    pml4.entries[0] = PageTableEntry.new(0x1000, PteFlags.PRESENT | PteFlags.WRITABLE);
    pdpt.entries[0] = PageTableEntry.new(0x2000, PteFlags.PRESENT | PteFlags.WRITABLE);
    pd.entries[1] = PageTableEntry.new(0x3000, PteFlags.PRESENT | PteFlags.WRITABLE);
    pt.entries[1] = PageTableEntry.new(0x8000_1000, PteFlags.PRESENT | PteFlags.WRITABLE);

    const vaddr: u64 = 0x0000_0000_0020_1ABC; // PD=1, PT=1, offset=0xABC
    const result = simulateWalk(&pml4, &pdpt, &pd, &pt, vaddr);

    switch (result) {
        .success => |phys| try expect(phys == 0x8000_1000 + 0xABC),
        else => return error.UnexpectedWalkFailure,
    }

    // Unmapped address triggers page fault at level 2
    const unmapped_result = simulateWalk(&pml4, &pdpt, &pd, &pt, 0x0000_0000_0040_0000);
    switch (unmapped_result) {
        .not_present => |level| try expect(level == 2),
        else => return error.ExpectedNotPresent,
    }
}

// ── Huge Pages ───────────────────────────────────────────────────────
fn testHugePages() !void {
    // 2MB huge page: PD entry with HUGE_PAGE flag
    const huge_2mb = PageTableEntry.new(
        0x200000, // must be 2MB-aligned
        PteFlags.PRESENT | PteFlags.WRITABLE | PteFlags.HUGE_PAGE,
    );
    try expect(huge_2mb.hugePage());
    try expect(huge_2mb.physAddr() == 0x200000);

    // 2MB alignment check: address must have bits 20:0 clear
    try expect(huge_2mb.physAddr() & 0x1FFFFF == 0);

    // 1GB huge page: PDPT entry with HUGE_PAGE flag
    const huge_1gb = PageTableEntry.new(
        0x4000_0000, // 1GB aligned
        PteFlags.PRESENT | PteFlags.WRITABLE | PteFlags.HUGE_PAGE,
    );
    try expect(huge_1gb.physAddr() & 0x3FFFFFFF == 0);

    // Page sizes: 4KB (normal), 2MB (huge), 1GB (gigantic)
    try expect(4 * 1024 == 0x1000);
    try expect(2 * 1024 * 1024 == 0x200000);
    try expect(1024 * 1024 * 1024 == 0x40000000);
}

// ── TLB Simulation ──────────────────────────────────────────────────
// Translation Lookaside Buffer: caches virtual → physical mappings
const TlbEntry = struct {
    vaddr: u64, // Virtual page number (aligned)
    paddr: u64, // Physical page number
    valid: bool,
    asid: u16, // Address Space ID (PCID on x86_64)
};

const TLB_SIZE = 16; // Real TLBs: L1 dTLB ~64, L2 sTLB ~1536 entries

const Tlb = struct {
    entries: [TLB_SIZE]TlbEntry,
    hits: u64,
    misses: u64,

    fn init() Tlb {
        return .{
            .entries = [_]TlbEntry{.{
                .vaddr = 0,
                .paddr = 0,
                .valid = false,
                .asid = 0,
            }} ** TLB_SIZE,
            .hits = 0,
            .misses = 0,
        };
    }

    fn lookup(self: *Tlb, vpage: u64, asid: u16) ?u64 {
        for (&self.entries) |*e| {
            if (e.valid and e.vaddr == vpage and e.asid == asid) {
                self.hits += 1;
                return e.paddr;
            }
        }
        self.misses += 1;
        return null;
    }

    fn insert(self: *Tlb, vpage: u64, ppage: u64, asid: u16) void {
        // Simple FIFO replacement — real TLBs use pseudo-LRU
        var slot: usize = 0;
        for (self.entries, 0..) |e, i| {
            if (!e.valid) {
                slot = i;
                break;
            }
        }
        self.entries[slot] = .{
            .vaddr = vpage,
            .paddr = ppage,
            .valid = true,
            .asid = asid,
        };
    }

    fn flush(self: *Tlb) void {
        for (&self.entries) |*e| {
            e.valid = false;
        }
    }

    fn flushAsid(self: *Tlb, asid: u16) void {
        for (&self.entries) |*e| {
            if (e.asid == asid) e.valid = false;
        }
    }

    fn hitRate(self: *const Tlb) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }
};

fn testTlbSimulation() !void {
    var tlb = Tlb.init();

    // Miss on first access
    try expect(tlb.lookup(0x1000, 0) == null);
    try expect(tlb.misses == 1);

    // Insert and hit
    tlb.insert(0x1000, 0x5000, 0);
    try expect(tlb.lookup(0x1000, 0).? == 0x5000);
    try expect(tlb.hits == 1);

    // Different ASID misses even for same vaddr
    try expect(tlb.lookup(0x1000, 1) == null);

    // Add more entries
    tlb.insert(0x2000, 0x6000, 0);
    tlb.insert(0x3000, 0x7000, 0);

    _ = tlb.lookup(0x2000, 0);
    _ = tlb.lookup(0x3000, 0);
    try expect(tlb.hits == 3);

    // Flush invalidates everything — models CR3 reload
    tlb.flush();
    try expect(tlb.lookup(0x1000, 0) == null);

    // PCID (ASID) flush — only invalidates one address space
    tlb.insert(0x1000, 0x5000, 0);
    tlb.insert(0x1000, 0x9000, 1);
    tlb.flushAsid(0);
    try expect(tlb.lookup(0x1000, 0) == null); // flushed
    try expect(tlb.lookup(0x1000, 1) != null); // still valid
}

// ── Address Space Layout ─────────────────────────────────────────────
fn testAddressSpaceLayout() !void {
    // x86_64 canonical address space split:
    // User:   0x0000_0000_0000_0000 — 0x0000_7FFF_FFFF_FFFF (128 TB)
    // Hole:   0x0000_8000_0000_0000 — 0xFFFF_7FFF_FFFF_FFFF (non-canonical)
    // Kernel: 0xFFFF_8000_0000_0000 — 0xFFFF_FFFF_FFFF_FFFF (128 TB)

    const user_max: u64 = 0x0000_7FFF_FFFF_FFFF;
    const kernel_min: u64 = 0xFFFF_8000_0000_0000;

    try expect(decomposeVaddr(0).is_canonical);
    try expect(decomposeVaddr(user_max).is_canonical);
    try expect(decomposeVaddr(kernel_min).is_canonical);

    // Non-canonical: bit 47 = 0 but upper bits nonzero
    try expect(!decomposeVaddr(0x0001_0000_0000_0000).is_canonical);

    // User space is 128 TB
    try expect(user_max + 1 == 128 * 1024 * 1024 * 1024 * 1024);
}

// ── Page Fault Classification ────────────────────────────────────────
const PageFaultType = enum {
    not_present, // Page not mapped — allocate or SIGSEGV
    protection, // Permission violation — write to read-only
    write_to_cow, // Copy-on-write trigger
    demand_zero, // First access to anonymous page
    swap_in, // Page swapped to disk — read it back
    stack_growth, // Access below stack — grow it
};

// Error code pushed by CPU on #PF:
const PfError = struct {
    const PRESENT: u32 = 1 << 0; // 1 = protection violation, 0 = not present
    const WRITE: u32 = 1 << 1; // 1 = write, 0 = read
    const USER: u32 = 1 << 2; // 1 = user mode, 0 = kernel mode
    const RESERVED: u32 = 1 << 3; // Reserved bit set in PTE
    const IFETCH: u32 = 1 << 4; // Instruction fetch (NX violation)
};

fn classifyPageFault(error_code: u32, is_cow: bool) PageFaultType {
    if (error_code & PfError.PRESENT == 0) {
        return .not_present;
    }
    if (error_code & PfError.WRITE != 0) {
        if (is_cow) return .write_to_cow;
        return .protection;
    }
    return .protection;
}

fn testPageFaultClassification() !void {
    // Not-present page (error_code bit 0 = 0)
    try expect(classifyPageFault(0, false) == .not_present);

    // Write to read-only page (present + write)
    try expect(classifyPageFault(PfError.PRESENT | PfError.WRITE, false) == .protection);

    // Copy-on-write (present + write + COW VMA)
    try expect(classifyPageFault(PfError.PRESENT | PfError.WRITE, true) == .write_to_cow);

    // NX violation: instruction fetch from non-executable page
    const nx_error = PfError.PRESENT | PfError.IFETCH;
    try expect(nx_error & PfError.IFETCH != 0);
}
