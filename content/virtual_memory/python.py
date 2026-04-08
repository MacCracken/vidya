# Virtual Memory — Python Implementation
#
# Demonstrates virtual memory concepts:
#   1. Page table structure simulation (4-level x86_64)
#   2. Address translation (virtual -> physical)
#   3. Page fault handling and demand paging
#   4. TLB simulation with hit/miss tracking
#
# In a real kernel, these structures map directly to hardware.
# Here we simulate them to show the mechanics.

# ── Constants ─────────────────────────────────────────────────────────────

PAGE_SIZE = 4096          # 4 KB
PAGE_SHIFT = 12
ENTRIES_PER_TABLE = 512   # 9 bits per level
PTE_PRESENT = 1 << 0
PTE_WRITABLE = 1 << 1
PTE_USER = 1 << 2
PTE_ADDR_MASK = 0x000F_FFFF_FFFF_F000  # bits 12-51


# ── Page Table Entry ──────────────────────────────────────────────────────

class Pte:
    """A single page table entry (64 bits on x86_64).

    Encodes a physical address in bits 12-51 and flags in bits 0-11.
    """

    def __init__(self, value: int = 0):
        self.value = value

    @classmethod
    def new(cls, phys_addr: int, flags: int) -> "Pte":
        return cls((phys_addr & PTE_ADDR_MASK) | flags)

    def is_present(self) -> bool:
        return bool(self.value & PTE_PRESENT)

    def address(self) -> int:
        return self.value & PTE_ADDR_MASK

    def flags(self) -> int:
        return self.value & 0xFFF

    def __repr__(self) -> str:
        if self.is_present():
            return f"Pte(addr=0x{self.address():X}, flags=0x{self.flags():03X})"
        return "Pte(empty)"


# ── Page Table (one level) ────────────────────────────────────────────────

class PageTable:
    """One level of a 4-level page table. Contains 512 entries."""

    def __init__(self):
        self.entries: list[Pte] = [Pte() for _ in range(ENTRIES_PER_TABLE)]


# ── Virtual Address Decomposition ─────────────────────────────────────────

def decompose_vaddr(vaddr: int) -> tuple[int, int, int, int, int]:
    """Extract the 4 page table indices and page offset from a 48-bit virtual address.

    x86_64 canonical 48-bit virtual address layout:
      [63:48] sign extension (must match bit 47)
      [47:39] PML4 index    (9 bits, 512 entries)
      [38:30] PDPT index    (9 bits, 512 entries)
      [29:21] PD index      (9 bits, 512 entries)
      [20:12] PT index      (9 bits, 512 entries)
      [11:0]  page offset   (12 bits, 4096 bytes)
    """
    offset = vaddr & 0xFFF
    pt_idx = (vaddr >> 12) & 0x1FF
    pd_idx = (vaddr >> 21) & 0x1FF
    pdpt_idx = (vaddr >> 30) & 0x1FF
    pml4_idx = (vaddr >> 39) & 0x1FF
    return (pml4_idx, pdpt_idx, pd_idx, pt_idx, offset)


def format_vaddr(vaddr: int) -> str:
    pml4, pdpt, pd, pt, off = decompose_vaddr(vaddr)
    return f"PML4[{pml4}] -> PDPT[{pdpt}] -> PD[{pd}] -> PT[{pt}] + 0x{off:03X}"


# ── Physical Memory Allocator (simple bump) ───────────────────────────────

class PhysAllocator:
    """Bump allocator for physical page frames.

    Real kernels use buddy allocators or free lists. This shows the simplest
    possible frame allocator: hand out the next frame and never reclaim.
    """

    def __init__(self, start: int):
        self.next_frame = start
        self.allocated = 0

    def alloc_frame(self) -> int:
        frame = self.next_frame
        self.next_frame += PAGE_SIZE
        self.allocated += 1
        return frame


# ── TLB Simulation ────────────────────────────────────────────────────────

class Tlb:
    """Translation Lookaside Buffer — caches virtual-to-physical mappings.

    A real TLB is hardware (CAM). This simulates the lookup/eviction behavior.
    Without a TLB, every memory access would require a 4-level page walk.
    """

    def __init__(self, capacity: int):
        self.entries: dict[int, int] = {}  # virtual page -> physical frame
        self.hits = 0
        self.misses = 0
        self.capacity = capacity

    def lookup(self, vpage: int) -> int | None:
        if vpage in self.entries:
            self.hits += 1
            return self.entries[vpage]
        self.misses += 1
        return None

    def insert(self, vpage: int, pframe: int) -> None:
        if len(self.entries) >= self.capacity:
            # Evict first entry (simulates random/LRU eviction)
            first_key = next(iter(self.entries))
            del self.entries[first_key]
        self.entries[vpage] = pframe

    def flush(self) -> None:
        """Full TLB flush — done on CR3 write (context switch)."""
        self.entries.clear()

    def flush_page(self, vpage: int) -> None:
        """Single-page invalidation — INVLPG instruction on x86_64."""
        self.entries.pop(vpage, None)


# ── Memory Management Unit (simulation) ───────────────────────────────────

class Mmu:
    """Simulates the x86_64 MMU: 4-level page tables, TLB, and address translation.

    CR3 holds the physical address of PML4 (the root page table).
    On every memory access, the MMU:
      1. Checks the TLB for a cached translation
      2. On miss, walks 4 levels of page tables
      3. Caches the result in the TLB
      4. Raises a page fault if any level is not present
    """

    def __init__(self):
        self.phys = PhysAllocator(0x1000)  # skip first page (null guard)
        self.cr3 = self.phys.alloc_frame()
        self.page_tables: dict[int, PageTable] = {self.cr3: PageTable()}
        self.tlb = Tlb(capacity=64)
        self.page_faults = 0

    def map_page(self, vaddr: int, phys_frame: int, flags: int) -> None:
        """Map a virtual page to a physical frame through 4 levels of page tables."""
        pml4_idx, pdpt_idx, pd_idx, pt_idx, _ = decompose_vaddr(vaddr)

        # Walk/create intermediate table levels
        pdpt_addr = self._ensure_entry(self.cr3, pml4_idx, flags)
        pd_addr = self._ensure_entry(pdpt_addr, pdpt_idx, flags)
        pt_addr = self._ensure_entry(pd_addr, pd_idx, flags)

        # Set the final PTE
        pt = self.page_tables[pt_addr]
        pt.entries[pt_idx] = Pte.new(phys_frame, flags | PTE_PRESENT)

        # Invalidate TLB for this page (INVLPG equivalent)
        self.tlb.flush_page(vaddr & ~0xFFF)

    def _ensure_entry(self, table_addr: int, index: int, flags: int) -> int:
        """Ensure an intermediate page table exists. Allocate one if needed."""
        entry = self.page_tables[table_addr].entries[index]
        if entry.is_present():
            return entry.address()
        # Allocate a new page table
        new_addr = self.phys.alloc_frame()
        self.page_tables[new_addr] = PageTable()
        self.page_tables[table_addr].entries[index] = Pte.new(
            new_addr, flags | PTE_PRESENT
        )
        return new_addr

    def translate(self, vaddr: int) -> int | None:
        """Translate virtual address to physical. Returns None on page fault."""
        vpage = vaddr & ~0xFFF
        offset = vaddr & 0xFFF

        # Step 1: TLB lookup (fast path)
        cached = self.tlb.lookup(vpage)
        if cached is not None:
            return cached | offset

        # Step 2: 4-level page table walk (slow path)
        pml4_idx, pdpt_idx, pd_idx, pt_idx, _ = decompose_vaddr(vaddr)

        levels = [
            (self.cr3, pml4_idx),
            (None, pdpt_idx),  # filled in as we walk
            (None, pd_idx),
            (None, pt_idx),
        ]

        current_addr = self.cr3
        for i, (_, idx) in enumerate(levels):
            table = self.page_tables.get(current_addr)
            if table is None:
                self.page_faults += 1
                return None
            entry = table.entries[idx]
            if not entry.is_present():
                self.page_faults += 1
                return None
            current_addr = entry.address()

        # current_addr is now the physical frame address
        self.tlb.insert(vpage, current_addr)
        return current_addr | offset


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    print("Virtual Memory — x86_64 page table simulation:\n")

    mmu = Mmu()

    # ── Address decomposition ─────────────────────────────────────────
    print("1. Virtual address decomposition (48-bit, 4 levels):")
    addrs = [0x0000_0000_0040_0078, 0x0000_7FFF_FFFF_FFF0, 0xFFFF_8000_0000_0000]
    for addr in addrs:
        print(f"   0x{addr:016X} -> {format_vaddr(addr)}")

    # Verify decomposition
    pml4, pdpt, pd, pt, off = decompose_vaddr(0x0000_0000_0040_0078)
    assert pml4 == 0 and pdpt == 0 and pd == 2 and pt == 0 and off == 0x078
    assert (pml4 << 39 | pdpt << 30 | pd << 21 | pt << 12 | off) == 0x0040_0078

    # ── Page table mapping ────────────────────────────────────────────
    print("\n2. Mapping virtual pages to physical frames:")
    mappings = [
        (0x0040_0000, 0x0020_0000, "code segment"),
        (0x0040_1000, 0x0020_1000, "code page 2"),
        (0x0060_0000, 0x0030_0000, "data segment"),
        (0x7FFF_F000, 0x0010_0000, "stack top"),
    ]

    flags = PTE_PRESENT | PTE_WRITABLE | PTE_USER
    for vaddr, paddr, label in mappings:
        mmu.map_page(vaddr, paddr, flags)
        print(f"   mapped 0x{vaddr:08X} -> 0x{paddr:08X} ({label})")

    print(f"   Page tables allocated: {mmu.phys.allocated} frames ({mmu.phys.allocated * 4} KB)")

    # ── Address translation ───────────────────────────────────────────
    print("\n3. Address translation:")
    test_addrs = [
        (0x0040_0078, "code + offset"),
        (0x0040_0078, "same — TLB hit"),
        (0x0040_1234, "code page 2"),
        (0x0060_0100, "data"),
        (0x7FFF_F800, "stack"),
        (0x0050_0000, "unmapped"),
    ]

    for addr, desc in test_addrs:
        phys = mmu.translate(addr)
        if phys is not None:
            print(f"   0x{addr:08X} -> 0x{phys:08X} ({desc})")
        else:
            print(f"   0x{addr:08X} -> PAGE FAULT ({desc})")

    # Verify translations
    assert mmu.translate(0x0040_0078) == 0x0020_0078  # offset preserved
    assert mmu.translate(0x0060_0100) == 0x0030_0100
    assert mmu.translate(0x0050_0000) is None          # unmapped

    # ── TLB statistics ────────────────────────────────────────────────
    total = mmu.tlb.hits + mmu.tlb.misses
    hit_rate = (mmu.tlb.hits / total * 100) if total > 0 else 0
    print(f"\n4. TLB statistics: {mmu.tlb.hits} hits, {mmu.tlb.misses} misses ({hit_rate:.0f}% hit rate)")
    print(f"   Page faults: {mmu.page_faults}")
    print(f"   Page table frames used: {mmu.phys.allocated}")

    assert mmu.tlb.hits > 0, "should have at least one TLB hit"
    assert mmu.page_faults >= 1, "unmapped address should cause page fault"
    print("\nAll assertions passed.")


if __name__ == "__main__":
    main()
