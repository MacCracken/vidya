// Virtual Memory — Rust Implementation
//
// Demonstrates virtual memory concepts:
//   1. Page table structure simulation (4-level x86_64)
//   2. Address translation (virtual → physical)
//   3. Page fault handling and demand paging
//   4. TLB simulation with hit/miss tracking
//
// In a real kernel, these structures map directly to hardware.
// Here we simulate them to show the mechanics.

use std::collections::HashMap;

// ── Constants ─────────────────────────────────────────────────────────────

const PAGE_SIZE: u64 = 4096;           // 4 KB
const PAGE_SHIFT: u32 = 12;
const ENTRIES_PER_TABLE: usize = 512;  // 9 bits per level
const PTE_PRESENT: u64 = 1 << 0;
const PTE_WRITABLE: u64 = 1 << 1;
const PTE_USER: u64 = 1 << 2;
const PTE_ADDR_MASK: u64 = 0x000F_FFFF_FFFF_F000; // bits 12-51

// ── Page Table Entry ──────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy)]
struct Pte(u64);

impl Pte {
    fn empty() -> Self {
        Self(0)
    }

    fn new(phys_addr: u64, flags: u64) -> Self {
        Self((phys_addr & PTE_ADDR_MASK) | flags)
    }

    fn is_present(self) -> bool {
        self.0 & PTE_PRESENT != 0
    }

    fn address(self) -> u64 {
        self.0 & PTE_ADDR_MASK
    }

    fn flags(self) -> u64 {
        self.0 & 0xFFF
    }
}

// ── Page Table (one level) ────────────────────────────────────────────────

struct PageTable {
    entries: [Pte; ENTRIES_PER_TABLE],
}

impl PageTable {
    fn new() -> Self {
        Self {
            entries: [Pte::empty(); ENTRIES_PER_TABLE],
        }
    }
}

// ── Virtual Address decomposition ─────────────────────────────────────────

/// Extract the 4 page table indices and page offset from a 48-bit virtual address.
fn decompose_vaddr(vaddr: u64) -> (usize, usize, usize, usize, u64) {
    let offset = vaddr & 0xFFF;                   // bits 0-11
    let pt_idx = ((vaddr >> 12) & 0x1FF) as usize;  // bits 12-20
    let pd_idx = ((vaddr >> 21) & 0x1FF) as usize;  // bits 21-29
    let pdpt_idx = ((vaddr >> 30) & 0x1FF) as usize; // bits 30-38
    let pml4_idx = ((vaddr >> 39) & 0x1FF) as usize; // bits 39-47
    (pml4_idx, pdpt_idx, pd_idx, pt_idx, offset)
}

fn format_vaddr(vaddr: u64) -> String {
    let (pml4, pdpt, pd, pt, off) = decompose_vaddr(vaddr);
    format!(
        "PML4[{}] → PDPT[{}] → PD[{}] → PT[{}] + 0x{:03X}",
        pml4, pdpt, pd, pt, off
    )
}

// ── Physical Memory Allocator (simple bump) ───────────────────────────────

struct PhysAllocator {
    next_frame: u64,
    allocated: usize,
}

impl PhysAllocator {
    fn new(start: u64) -> Self {
        Self {
            next_frame: start,
            allocated: 0,
        }
    }

    fn alloc_frame(&mut self) -> u64 {
        let frame = self.next_frame;
        self.next_frame += PAGE_SIZE;
        self.allocated += 1;
        frame
    }
}

// ── TLB Simulation ────────────────────────────────────────────────────────

struct Tlb {
    entries: HashMap<u64, u64>, // virtual page → physical frame
    hits: u64,
    misses: u64,
    capacity: usize,
}

impl Tlb {
    fn new(capacity: usize) -> Self {
        Self {
            entries: HashMap::new(),
            hits: 0,
            misses: 0,
            capacity,
        }
    }

    fn lookup(&mut self, vpage: u64) -> Option<u64> {
        if let Some(&pframe) = self.entries.get(&vpage) {
            self.hits += 1;
            Some(pframe)
        } else {
            self.misses += 1;
            None
        }
    }

    fn insert(&mut self, vpage: u64, pframe: u64) {
        if self.entries.len() >= self.capacity {
            // Simple eviction: remove an arbitrary entry
            if let Some(&key) = self.entries.keys().next() {
                self.entries.remove(&key);
            }
        }
        self.entries.insert(vpage, pframe);
    }

    fn flush(&mut self) {
        self.entries.clear();
    }

    fn flush_page(&mut self, vpage: u64) {
        self.entries.remove(&vpage);
    }
}

// ── Memory Management Unit (simulation) ───────────────────────────────────

struct Mmu {
    /// Page tables stored by physical address
    page_tables: HashMap<u64, PageTable>,
    /// PML4 physical address (like CR3)
    cr3: u64,
    phys: PhysAllocator,
    tlb: Tlb,
    page_faults: u64,
}

impl Mmu {
    fn new() -> Self {
        let mut phys = PhysAllocator::new(0x1000); // start at 4KB (skip first page)
        let pml4_addr = phys.alloc_frame();
        let mut page_tables = HashMap::new();
        page_tables.insert(pml4_addr, PageTable::new());

        Self {
            page_tables,
            cr3: pml4_addr,
            phys,
            tlb: Tlb::new(64), // 64-entry TLB
            page_faults: 0,
        }
    }

    /// Map a virtual page to a physical frame.
    fn map_page(&mut self, vaddr: u64, phys_frame: u64, flags: u64) {
        let (pml4_idx, pdpt_idx, pd_idx, pt_idx, _) = decompose_vaddr(vaddr);

        // Walk/create page table levels
        let pdpt_addr = self.ensure_entry(self.cr3, pml4_idx, flags);
        let pd_addr = self.ensure_entry(pdpt_addr, pdpt_idx, flags);
        let pt_addr = self.ensure_entry(pd_addr, pd_idx, flags);

        // Set the final PTE
        let pt = self.page_tables.get_mut(&pt_addr).unwrap();
        pt.entries[pt_idx] = Pte::new(phys_frame, flags | PTE_PRESENT);

        // Invalidate TLB for this page
        self.tlb.flush_page(vaddr & !0xFFF);
    }

    /// Ensure a page table entry exists at the given level. Returns the address of the next-level table.
    fn ensure_entry(&mut self, table_addr: u64, index: usize, flags: u64) -> u64 {
        let table = self.page_tables.get(&table_addr).unwrap();
        let entry = table.entries[index];

        if entry.is_present() {
            entry.address()
        } else {
            let new_table_addr = self.phys.alloc_frame();
            self.page_tables.insert(new_table_addr, PageTable::new());
            let table = self.page_tables.get_mut(&table_addr).unwrap();
            table.entries[index] = Pte::new(new_table_addr, flags | PTE_PRESENT);
            new_table_addr
        }
    }

    /// Translate a virtual address to physical. Returns None on page fault.
    fn translate(&mut self, vaddr: u64) -> Option<u64> {
        let vpage = vaddr & !0xFFF;
        let offset = vaddr & 0xFFF;

        // Check TLB first
        if let Some(pframe) = self.tlb.lookup(vpage) {
            return Some(pframe | offset);
        }

        // Page table walk (4 levels)
        let (pml4_idx, pdpt_idx, pd_idx, pt_idx, _) = decompose_vaddr(vaddr);

        let pml4 = self.page_tables.get(&self.cr3)?;
        let pml4e = pml4.entries[pml4_idx];
        if !pml4e.is_present() {
            self.page_faults += 1;
            return None;
        }

        let pdpt = self.page_tables.get(&pml4e.address())?;
        let pdpte = pdpt.entries[pdpt_idx];
        if !pdpte.is_present() {
            self.page_faults += 1;
            return None;
        }

        let pd = self.page_tables.get(&pdpte.address())?;
        let pde = pd.entries[pd_idx];
        if !pde.is_present() {
            self.page_faults += 1;
            return None;
        }

        let pt = self.page_tables.get(&pde.address())?;
        let pte = pt.entries[pt_idx];
        if !pte.is_present() {
            self.page_faults += 1;
            return None;
        }

        let pframe = pte.address();
        self.tlb.insert(vpage, pframe);
        Some(pframe | offset)
    }
}

fn main() {
    println!("Virtual Memory — x86_64 page table simulation:\n");

    let mut mmu = Mmu::new();

    // ── Address decomposition ─────────────────────────────────────────
    println!("1. Virtual address decomposition (48-bit, 4 levels):");
    let addrs = [0x0000_0000_0040_0078u64, 0x0000_7FFF_FFFF_FFF0, 0xFFFF_8000_0000_0000];
    for addr in &addrs {
        println!("   0x{:016X} → {}", addr, format_vaddr(*addr));
    }

    // ── Page table mapping ────────────────────────────────────────────
    println!("\n2. Mapping virtual pages to physical frames:");
    let mappings = [
        (0x0040_0000u64, 0x0020_0000u64, "code segment"),
        (0x0040_1000, 0x0020_1000, "code page 2"),
        (0x0060_0000, 0x0030_0000, "data segment"),
        (0x7FFF_F000, 0x0010_0000, "stack top"),
    ];

    for (vaddr, paddr, label) in &mappings {
        mmu.map_page(*vaddr, *paddr, PTE_PRESENT | PTE_WRITABLE | PTE_USER);
        println!(
            "   mapped 0x{:08X} → 0x{:08X} ({})",
            vaddr, paddr, label
        );
    }
    println!(
        "   Page tables allocated: {} frames ({} KB)",
        mmu.phys.allocated,
        mmu.phys.allocated * 4
    );

    // ── Address translation ───────────────────────────────────────────
    println!("\n3. Address translation:");
    let test_addrs = [
        0x0040_0078u64, // code + offset
        0x0040_0078,    // same (TLB hit)
        0x0040_1234,    // code page 2
        0x0060_0100,    // data
        0x7FFF_F800,    // stack
        0x0050_0000,    // unmapped — page fault
    ];

    for addr in &test_addrs {
        match mmu.translate(*addr) {
            Some(phys) => {
                let hit = if mmu.tlb.hits > 0 { "" } else { "" };
                println!("   0x{:08X} → 0x{:08X}{}", addr, phys, hit);
            }
            None => {
                println!("   0x{:08X} → PAGE FAULT (not mapped)", addr);
            }
        }
    }

    println!(
        "\n4. TLB statistics: {} hits, {} misses ({:.0}% hit rate)",
        mmu.tlb.hits,
        mmu.tlb.misses,
        if mmu.tlb.hits + mmu.tlb.misses > 0 {
            mmu.tlb.hits as f64 / (mmu.tlb.hits + mmu.tlb.misses) as f64 * 100.0
        } else {
            0.0
        }
    );
    println!("   Page faults: {}", mmu.page_faults);
    println!("   Page table frames used: {}", mmu.phys.allocated);
}
