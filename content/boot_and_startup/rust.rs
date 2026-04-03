// Boot and Startup — Rust Implementation
//
// Demonstrates the boot process concepts that are normally done in assembly
// and early kernel code. Since we can't actually boot from this program,
// we simulate the key data structures and initialization sequence:
//   1. GDT (Global Descriptor Table) construction
//   2. Page table setup for identity mapping + higher-half kernel
//   3. Memory map parsing (Multiboot2-style)
//   4. Boot sequence simulation showing the transition from
//      32-bit protected mode → 64-bit long mode
//
// In a real kernel, steps 1-2 are assembly. Step 3 is early Rust.

use std::fmt;

// ── GDT (Global Descriptor Table) ────────────────────────────────────────

/// A GDT entry (segment descriptor) is 8 bytes.
/// In long mode, most fields are ignored, but the entry must exist.
#[derive(Debug, Clone, Copy)]
struct GdtEntry(u64);

impl GdtEntry {
    const fn null() -> Self {
        Self(0)
    }

    /// Create a code segment descriptor.
    /// In long mode: only L bit (long mode), DPL, and P bit matter.
    const fn code_segment(dpl: u8) -> Self {
        let mut entry: u64 = 0;
        // Limit (ignored in long mode, set to 0xFFFFF for compatibility)
        entry |= 0x000F_0000_0000_FFFF;
        // Access byte: P=1, DPL, S=1 (code/data), E=1 (executable), RW=1 (readable)
        let access = 0x80 | ((dpl as u64 & 0x3) << 5) | 0x1A; // P + DPL + S + E + R
        entry |= access << 40;
        // Flags: G=1 (4KB granularity), L=1 (long mode)
        entry |= 0x00A0_0000_0000_0000; // G=1, L=1
        Self(entry)
    }

    /// Create a data segment descriptor.
    const fn data_segment(dpl: u8) -> Self {
        let mut entry: u64 = 0;
        entry |= 0x000F_0000_0000_FFFF; // limit
        let access = 0x80 | ((dpl as u64 & 0x3) << 5) | 0x12; // P + DPL + S + W
        entry |= access << 40;
        entry |= 0x00C0_0000_0000_0000; // G=1, DB=1 (32-bit compat)
        Self(entry)
    }

    fn present(&self) -> bool {
        (self.0 >> 47) & 1 != 0
    }

    fn dpl(&self) -> u8 {
        ((self.0 >> 45) & 0x3) as u8
    }

    fn is_code(&self) -> bool {
        (self.0 >> 43) & 1 != 0
    }

    fn is_long_mode(&self) -> bool {
        (self.0 >> 53) & 1 != 0
    }
}

impl fmt::Display for GdtEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.0 == 0 {
            return write!(f, "NULL");
        }
        let kind = if self.is_code() { "CODE" } else { "DATA" };
        let ring = self.dpl();
        let mode = if self.is_long_mode() { "64-bit" } else { "32-bit" };
        write!(f, "{} ring{} {} [0x{:016X}]", kind, ring, mode, self.0)
    }
}

struct Gdt {
    entries: Vec<GdtEntry>,
}

impl Gdt {
    fn new() -> Self {
        Self {
            entries: vec![GdtEntry::null()], // entry 0 is always null
        }
    }

    fn add(&mut self, entry: GdtEntry) -> u16 {
        let index = self.entries.len();
        self.entries.push(entry);
        (index * 8) as u16 // selector = index * 8
    }
}

// ── Page Table Simulation ─────────────────────────────────────────────────

const PAGE_SIZE: u64 = 4096;
const HUGE_PAGE: u64 = 2 * 1024 * 1024; // 2MB

struct BootPageTables {
    /// Mappings: vaddr → paddr, size
    mappings: Vec<(u64, u64, u64, &'static str)>,
}

impl BootPageTables {
    fn new() -> Self {
        Self {
            mappings: Vec::new(),
        }
    }

    fn identity_map_range(&mut self, start: u64, size: u64, label: &'static str) {
        self.mappings.push((start, start, size, label));
    }

    fn map_higher_half(&mut self, vaddr: u64, paddr: u64, size: u64, label: &'static str) {
        self.mappings.push((vaddr, paddr, size, label));
    }
}

// ── Memory Map (Multiboot2-style) ─────────────────────────────────────────

#[derive(Debug, Clone, Copy)]
enum MemoryType {
    Usable,
    Reserved,
    AcpiReclaimable,
    AcpiNvs,
    BadMemory,
    Firmware,
}

impl fmt::Display for MemoryType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MemoryType::Usable => write!(f, "Usable RAM"),
            MemoryType::Reserved => write!(f, "Reserved"),
            MemoryType::AcpiReclaimable => write!(f, "ACPI Reclaimable"),
            MemoryType::AcpiNvs => write!(f, "ACPI NVS"),
            MemoryType::BadMemory => write!(f, "Bad Memory"),
            MemoryType::Firmware => write!(f, "Firmware"),
        }
    }
}

struct MemoryMapEntry {
    base: u64,
    length: u64,
    mem_type: MemoryType,
}

impl fmt::Display for MemoryMapEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "0x{:012X} - 0x{:012X} ({:>8} KB) {}",
            self.base,
            self.base + self.length,
            self.length / 1024,
            self.mem_type
        )
    }
}

// ── Boot Sequence Simulation ──────────────────────────────────────────────

fn simulate_boot() {
    println!("Boot Sequence — 32-bit protected mode to 64-bit long mode:\n");

    // ── Step 1: Parse memory map ──────────────────────────────────────
    println!("Step 1: Parse firmware memory map");
    let memory_map = vec![
        MemoryMapEntry { base: 0x000000, length: 0x80000, mem_type: MemoryType::Usable },           // 0-512KB
        MemoryMapEntry { base: 0x080000, length: 0x20000, mem_type: MemoryType::Reserved },          // 512-640KB (VGA, etc.)
        MemoryMapEntry { base: 0x100000, length: 0x3FF00000, mem_type: MemoryType::Usable },         // 1MB-1GB
        MemoryMapEntry { base: 0x40000000, length: 0x10000, mem_type: MemoryType::AcpiReclaimable }, // ACPI tables
        MemoryMapEntry { base: 0xFEC00000, length: 0x1000, mem_type: MemoryType::Reserved },         // IOAPIC MMIO
        MemoryMapEntry { base: 0xFEE00000, length: 0x1000, mem_type: MemoryType::Reserved },         // LAPIC MMIO
    ];

    let mut usable_ram = 0u64;
    for entry in &memory_map {
        println!("  {}", entry);
        if matches!(entry.mem_type, MemoryType::Usable) {
            usable_ram += entry.length;
        }
    }
    println!("  Total usable: {} MB\n", usable_ram / (1024 * 1024));

    // ── Step 2: Build GDT ─────────────────────────────────────────────
    println!("Step 2: Build GDT");
    let mut gdt = Gdt::new();
    let kernel_cs = gdt.add(GdtEntry::code_segment(0));
    let kernel_ds = gdt.add(GdtEntry::data_segment(0));
    let user_cs = gdt.add(GdtEntry::code_segment(3));
    let user_ds = gdt.add(GdtEntry::data_segment(3));

    println!("  GDT entries:");
    for (i, entry) in gdt.entries.iter().enumerate() {
        println!("    [{:02X}] {}", i * 8, entry);
    }
    println!("  Kernel CS: 0x{:02X}, DS: 0x{:02X}", kernel_cs, kernel_ds);
    println!("  User CS: 0x{:02X}, DS: 0x{:02X}\n", user_cs, user_ds);

    // ── Step 3: Set up page tables ────────────────────────────────────
    println!("Step 3: Set up boot page tables (2MB huge pages)");
    let mut pages = BootPageTables::new();

    // Identity map first 4MB (contains boot code)
    pages.identity_map_range(0, 4 * 1024 * 1024, "boot code (identity)");
    // Higher-half mapping for kernel
    let kernel_vaddr: u64 = 0xFFFF_8000_0000_0000;
    pages.map_higher_half(kernel_vaddr, 0x100000, 2 * 1024 * 1024, "kernel text");
    pages.map_higher_half(kernel_vaddr + HUGE_PAGE, 0x300000, 2 * 1024 * 1024, "kernel data");

    println!("  Page table mappings:");
    for (vaddr, paddr, size, label) in &pages.mappings {
        println!("    0x{:016X} → 0x{:012X} ({:>4} KB) {}",
            vaddr, paddr, size / 1024, label);
    }
    println!();

    // ── Step 4: Transition to long mode ───────────────────────────────
    println!("Step 4: Transition to 64-bit long mode");
    let steps = [
        ("1. Disable interrupts", "cli"),
        ("2. Load GDT", "lgdt [gdt_descriptor]"),
        ("3. Enable PAE", "mov eax, cr4; or eax, (1<<5); mov cr4, eax"),
        ("4. Load PML4 into CR3", "mov eax, pml4_phys_addr; mov cr3, eax"),
        ("5. Set EFER.LME", "mov ecx, 0xC0000080; rdmsr; or eax, (1<<8); wrmsr"),
        ("6. Enable paging", "mov eax, cr0; or eax, (1<<31); mov cr0, eax"),
        ("7. Far jump to 64-bit", "jmp 0x08:long_mode_entry  ; CS=kernel_cs"),
    ];

    for (desc, asm) in &steps {
        println!("  {:<35} {}", desc, asm);
    }
    println!();

    // ── Step 5: Early kernel init ─────────────────────────────────────
    println!("Step 5: Early kernel init (now in 64-bit mode)");
    let init_steps = [
        "1. Set RSP to boot stack top (in .bss)",
        "2. Zero .bss section (__bss_start to __bss_end)",
        "3. Remap PIC (IRQs to vectors 32-47) or disable PIC + init APIC",
        "4. Build IDT (exception handlers 0-31 + IRQ handlers)",
        "5. Load IDT (lidt)",
        "6. Enable interrupts (sti)",
        "7. Initialize physical memory allocator (from memory map)",
        "8. Set up kernel heap allocator",
        "9. Initialize serial port for debug output",
        "10. Call kernel_main(boot_info)",
    ];

    for step in &init_steps {
        println!("  {}", step);
    }

    // ── Summary ───────────────────────────────────────────────────────
    println!("\nBoot complete: firmware → bootloader → 32-bit stub → long mode → kernel_main");
}

fn main() {
    simulate_boot();
}
