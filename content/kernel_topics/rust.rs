// Vidya — Kernel Topics in Rust
//
// Rust is increasingly used for kernel development (Linux, Redox,
// AGNOS). Its type system can encode hardware invariants: volatile
// MMIO wrappers, bitfield page table entries, type-safe interrupt
// tables. No runtime, no allocator required — #![no_std] all the way.

use std::fmt;

fn main() {
    test_page_table_entry();
    test_mmio_register();
    test_interrupt_descriptor_table();
    test_abi_calling_convention();
    test_physical_virtual_address();
    test_gdt_entry();

    println!("All kernel topics examples passed.");
}

// ── Page Table Entry (x86_64 4-level paging) ──────────────────────────
// A PTE is a 64-bit value with flags in bits 0-11 and physical address
// in bits 12-51 (52-bit physical address space, 4KB aligned).

#[derive(Clone, Copy)]
struct PageTableEntry(u64);

impl PageTableEntry {
    const PRESENT: u64 = 1 << 0;
    const WRITABLE: u64 = 1 << 1;
    const USER: u64 = 1 << 2;
    const WRITE_THROUGH: u64 = 1 << 3;
    const NO_CACHE: u64 = 1 << 4;
    const ACCESSED: u64 = 1 << 5;
    const DIRTY: u64 = 1 << 6;
    const HUGE_PAGE: u64 = 1 << 7;
    const NO_EXECUTE: u64 = 1 << 63;

    const ADDR_MASK: u64 = 0x000F_FFFF_FFFF_F000; // bits 12-51

    fn new(phys_addr: u64, flags: u64) -> Self {
        assert_eq!(phys_addr & !Self::ADDR_MASK, 0, "address not 4KB aligned");
        Self((phys_addr & Self::ADDR_MASK) | flags)
    }

    fn is_present(self) -> bool {
        self.0 & Self::PRESENT != 0
    }
    fn is_writable(self) -> bool {
        self.0 & Self::WRITABLE != 0
    }
    fn is_user(self) -> bool {
        self.0 & Self::USER != 0
    }
    fn is_huge(self) -> bool {
        self.0 & Self::HUGE_PAGE != 0
    }
    fn is_no_execute(self) -> bool {
        self.0 & Self::NO_EXECUTE != 0
    }
    fn phys_addr(self) -> u64 {
        self.0 & Self::ADDR_MASK
    }
}

impl fmt::Debug for PageTableEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PTE(addr=0x{:012x}, {}{}{}{})",
            self.phys_addr(),
            if self.is_present() { "P" } else { "-" },
            if self.is_writable() { "W" } else { "R" },
            if self.is_user() { "U" } else { "S" },
            if self.is_no_execute() { "NX" } else { "X" },
        )
    }
}

fn test_page_table_entry() {
    // Kernel code page: present, read-only, supervisor, executable
    let code_pte = PageTableEntry::new(0x1000, PageTableEntry::PRESENT);
    assert!(code_pte.is_present());
    assert!(!code_pte.is_writable());
    assert!(!code_pte.is_user());
    assert_eq!(code_pte.phys_addr(), 0x1000);

    // User data page: present, writable, user, no-execute
    let data_pte = PageTableEntry::new(
        0x200_000,
        PageTableEntry::PRESENT | PageTableEntry::WRITABLE | PageTableEntry::USER | PageTableEntry::NO_EXECUTE,
    );
    assert!(data_pte.is_present());
    assert!(data_pte.is_writable());
    assert!(data_pte.is_user());
    assert!(data_pte.is_no_execute());
    assert_eq!(data_pte.phys_addr(), 0x200_000);

    // Not present — accessing this would cause a page fault
    let unmapped = PageTableEntry(0);
    assert!(!unmapped.is_present());

    // Cache control flags
    let uncacheable = PageTableEntry::new(
        0x3000,
        PageTableEntry::PRESENT | PageTableEntry::NO_CACHE | PageTableEntry::WRITE_THROUGH,
    );
    assert_eq!(uncacheable.0 & PageTableEntry::NO_CACHE, PageTableEntry::NO_CACHE);
    assert_eq!(uncacheable.0 & PageTableEntry::WRITE_THROUGH, PageTableEntry::WRITE_THROUGH);

    // Accessed/dirty tracking
    let accessed = PageTableEntry(PageTableEntry::PRESENT | PageTableEntry::ACCESSED | PageTableEntry::DIRTY);
    assert_eq!(accessed.0 & PageTableEntry::ACCESSED, PageTableEntry::ACCESSED);
    assert_eq!(accessed.0 & PageTableEntry::DIRTY, PageTableEntry::DIRTY);

    // 2MB huge page
    let huge = PageTableEntry::new(
        0x20_0000, // 2MB aligned
        PageTableEntry::PRESENT | PageTableEntry::HUGE_PAGE | PageTableEntry::WRITABLE,
    );
    assert!(huge.is_huge());
}

// ── MMIO Register (volatile access) ──────────────────────────────────
// In a real kernel, these would use volatile reads/writes to prevent
// compiler optimization. Here we simulate the register model.

struct MmioRegister {
    value: u32,
    name: &'static str,
}

impl MmioRegister {
    fn new(name: &'static str) -> Self {
        Self { value: 0, name }
    }

    /// Volatile write — in a real kernel: core::ptr::write_volatile
    fn write(&mut self, val: u32) {
        // Simulate side effect: hardware register write
        self.value = val;
    }

    /// Volatile read — in a real kernel: core::ptr::read_volatile
    fn read(&self) -> u32 {
        self.value
    }

    /// Read-modify-write: set specific bits
    fn set_bits(&mut self, mask: u32) {
        let val = self.read();
        self.write(val | mask);
    }

    /// Read-modify-write: clear specific bits
    fn clear_bits(&mut self, mask: u32) {
        let val = self.read();
        self.write(val & !mask);
    }
}

impl fmt::Debug for MmioRegister {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}=0x{:08x}", self.name, self.value)
    }
}

fn test_mmio_register() {
    // UART-like control register
    let mut ctrl = MmioRegister::new("UART_CTRL");
    assert_eq!(ctrl.read(), 0);

    // Enable TX (bit 0) and RX (bit 1)
    ctrl.set_bits(0b11);
    assert_eq!(ctrl.read(), 0b11);

    // Disable RX, keep TX
    ctrl.clear_bits(0b10);
    assert_eq!(ctrl.read(), 0b01);

    // Status register: write to acknowledge interrupt
    let mut status = MmioRegister::new("UART_STATUS");
    status.write(0xFF); // all bits set (pending interrupts)
    assert_eq!(status.read(), 0xFF);
    status.write(0x01); // write-1-to-clear: ack bit 0
    assert_eq!(status.read(), 0x01);
}

// ── Interrupt Descriptor Table (IDT) ──────────────────────────────────
// x86_64 IDT has 256 entries. Each maps an interrupt vector to a handler.

type InterruptHandler = fn(vector: u8) -> &'static str;

struct IdtEntry {
    vector: u8,
    handler: InterruptHandler,
    name: &'static str,
    ist: u8, // Interrupt Stack Table index (0 = no IST)
}

struct Idt {
    entries: Vec<IdtEntry>,
}

impl Idt {
    fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    fn register(&mut self, vector: u8, name: &'static str, ist: u8, handler: InterruptHandler) {
        self.entries.push(IdtEntry {
            vector,
            handler,
            name,
            ist,
        });
    }

    fn dispatch(&self, vector: u8) -> Option<&'static str> {
        self.entries
            .iter()
            .find(|e| e.vector == vector)
            .map(|e| (e.handler)(e.vector))
    }
}

fn test_interrupt_descriptor_table() {
    let mut idt = Idt::new();

    // Standard x86_64 exceptions
    idt.register(0, "Divide Error", 0, |_| "handled: #DE");
    idt.register(8, "Double Fault", 1, |_| "handled: #DF"); // IST 1 for safety
    idt.register(13, "General Protection", 0, |_| "handled: #GP");
    idt.register(14, "Page Fault", 0, |_| "handled: #PF");
    idt.register(32, "Timer", 0, |_| "handled: timer tick");

    assert_eq!(idt.dispatch(0), Some("handled: #DE"));
    assert_eq!(idt.dispatch(8), Some("handled: #DF"));
    assert_eq!(idt.dispatch(14), Some("handled: #PF"));
    assert_eq!(idt.dispatch(32), Some("handled: timer tick"));
    assert_eq!(idt.dispatch(255), None); // unregistered

    // Double fault must use IST (separate stack)
    let df = idt.entries.iter().find(|e| e.vector == 8).unwrap();
    assert!(df.ist > 0, "double fault must use IST");
    assert_eq!(df.name, "Double Fault");
}

// ── ABI / Calling Convention ──────────────────────────────────────────
// Simulating the System V AMD64 ABI register allocation

struct SysVCall {
    // Integer arguments: rdi, rsi, rdx, rcx, r8, r9
    int_args: Vec<u64>,
    // Return value in rax (and rdx for 128-bit returns)
    ret_val: u64,
}

impl SysVCall {
    fn new() -> Self {
        Self {
            int_args: Vec::new(),
            ret_val: 0,
        }
    }

    fn arg(mut self, val: u64) -> Self {
        assert!(
            self.int_args.len() < 6,
            "SysV ABI: max 6 integer register args"
        );
        self.int_args.push(val);
        self
    }

    fn register_for_arg(index: usize) -> &'static str {
        match index {
            0 => "rdi",
            1 => "rsi",
            2 => "rdx",
            3 => "rcx",
            4 => "r8",
            5 => "r9",
            _ => "stack",
        }
    }

    fn execute(mut self, f: fn(&[u64]) -> u64) -> u64 {
        self.ret_val = f(&self.int_args);
        self.ret_val
    }
}

fn test_abi_calling_convention() {
    // Simulate: add(a, b) → a + b
    let result = SysVCall::new().arg(42).arg(58).execute(|args| args[0] + args[1]);
    assert_eq!(result, 100);

    // Verify register allocation
    assert_eq!(SysVCall::register_for_arg(0), "rdi");
    assert_eq!(SysVCall::register_for_arg(1), "rsi");
    assert_eq!(SysVCall::register_for_arg(2), "rdx");
    assert_eq!(SysVCall::register_for_arg(5), "r9");
    assert_eq!(SysVCall::register_for_arg(6), "stack");

    // Linux syscall ABI: syscall number in rax, args in rdi/rsi/rdx/r10/r8/r9
    // Note: r10 replaces rcx (which is clobbered by syscall instruction)
    let syscall_regs = ["rax", "rdi", "rsi", "rdx", "r10", "r8", "r9"];
    assert_eq!(syscall_regs[0], "rax"); // syscall number
    assert_eq!(syscall_regs.len(), 7);  // number + 6 args
}

// ── Physical / Virtual Address Translation ────────────────────────────
// 4-level paging: virtual address bits [47:39]=PML4, [38:30]=PDPT,
// [29:21]=PD, [20:12]=PT, [11:0]=offset

fn decompose_virtual_addr(vaddr: u64) -> (u16, u16, u16, u16, u16) {
    let pml4 = ((vaddr >> 39) & 0x1FF) as u16;
    let pdpt = ((vaddr >> 30) & 0x1FF) as u16;
    let pd = ((vaddr >> 21) & 0x1FF) as u16;
    let pt = ((vaddr >> 12) & 0x1FF) as u16;
    let offset = (vaddr & 0xFFF) as u16;
    (pml4, pdpt, pd, pt, offset)
}

fn compose_physical_addr(page_frame: u64, offset: u16) -> u64 {
    (page_frame << 12) | offset as u64
}

fn test_physical_virtual_address() {
    // Decompose 0x00007FFF_FFFFF000 (typical user-space high address)
    let vaddr: u64 = 0x0000_7FFF_FFFF_F000;
    let (pml4, pdpt, pd, pt, offset) = decompose_virtual_addr(vaddr);
    assert_eq!(pml4, 0xFF);   // PML4 index 255
    assert_eq!(pdpt, 0x1FF);  // PDPT index 511
    assert_eq!(pd, 0x1FF);    // PD index 511
    assert_eq!(pt, 0x1FF);    // PT index 511
    assert_eq!(offset, 0);    // page-aligned

    // Compose: page frame 0x1234 + offset 0x567
    let paddr = compose_physical_addr(0x1234, 0x567);
    assert_eq!(paddr, 0x1234_567);

    // Kernel addresses have sign-extension (bits 48-63 = 1)
    let kernel_addr: u64 = 0xFFFF_8000_0000_0000;
    let (kpml4, _, _, _, _) = decompose_virtual_addr(kernel_addr);
    assert_eq!(kpml4, 256); // kernel half starts at PML4 index 256
}

// ── GDT Entry (x86_64 segment descriptor) ─────────────────────────────
#[derive(Clone, Copy)]
struct GdtEntry(u64);

impl GdtEntry {
    fn null() -> Self {
        Self(0)
    }

    fn kernel_code() -> Self {
        // Long mode code segment: L=1, D=0, P=1, S=1, Type=Execute/Read
        // Flags: G=1, L=1, P=1, DPL=0, S=1, Type=0xA (Execute/Read)
        Self(0x00AF_9A00_0000_FFFF)
    }

    fn kernel_data() -> Self {
        // Long mode data segment: P=1, S=1, Type=Read/Write
        Self(0x00CF_9200_0000_FFFF)
    }

    fn is_present(self) -> bool {
        (self.0 >> 47) & 1 == 1
    }

    fn dpl(self) -> u8 {
        ((self.0 >> 45) & 0x3) as u8
    }

    fn is_long_mode(self) -> bool {
        (self.0 >> 53) & 1 == 1
    }
}

fn test_gdt_entry() {
    let null = GdtEntry::null();
    assert!(!null.is_present());

    let code = GdtEntry::kernel_code();
    assert!(code.is_present());
    assert_eq!(code.dpl(), 0); // ring 0
    assert!(code.is_long_mode());

    let data = GdtEntry::kernel_data();
    assert!(data.is_present());
    assert_eq!(data.dpl(), 0);

    // A minimal GDT needs: null, kernel code, kernel data
    let gdt = [GdtEntry::null(), GdtEntry::kernel_code(), GdtEntry::kernel_data()];
    assert_eq!(gdt.len(), 3);
    assert!(!gdt[0].is_present()); // null descriptor
    assert!(gdt[1].is_present());  // code
    assert!(gdt[2].is_present());  // data
}
