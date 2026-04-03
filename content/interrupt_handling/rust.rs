// Interrupt Handling — Rust Implementation
//
// Demonstrates x86_64 interrupt handling concepts:
//   1. IDT (Interrupt Descriptor Table) structure and entry encoding
//   2. Interrupt stack frame layout
//   3. Exception types and error codes
//   4. A simulation of interrupt dispatch and handling
//
// In a real kernel, IDT entries point to assembly stubs that save registers
// and call Rust handlers. Here we simulate the mechanics.

use std::fmt;

// ── IDT Entry (x86_64 Gate Descriptor) ────────────────────────────────────

/// An x86_64 IDT entry is 16 bytes (128 bits).
/// It describes where to jump when an interrupt fires.
#[derive(Debug, Clone, Copy)]
struct IdtEntry {
    offset_low: u16,    // handler address bits 0-15
    selector: u16,      // code segment selector (GDT)
    ist: u8,            // interrupt stack table index (0 = no switch)
    type_attr: u8,      // gate type + DPL + present bit
    offset_mid: u16,    // handler address bits 16-31
    offset_high: u32,   // handler address bits 32-63
    _reserved: u32,
}

impl IdtEntry {
    const fn empty() -> Self {
        Self {
            offset_low: 0,
            selector: 0,
            ist: 0,
            type_attr: 0,
            offset_mid: 0,
            offset_high: 0,
            _reserved: 0,
        }
    }

    /// Create an interrupt gate entry.
    ///
    /// - `handler`: virtual address of the ISR
    /// - `selector`: code segment selector (typically 0x08 for kernel CS)
    /// - `ist`: IST index (0 = don't switch stack, 1-7 = use IST[n])
    /// - `dpl`: descriptor privilege level (0 = kernel only, 3 = user callable)
    fn interrupt_gate(handler: u64, selector: u16, ist: u8, dpl: u8) -> Self {
        Self {
            offset_low: handler as u16,
            selector,
            ist: ist & 0x7,
            // Type: 0xE = 64-bit interrupt gate, P=1, DPL in bits 5-6
            type_attr: 0x80 | ((dpl & 0x3) << 5) | 0x0E,
            offset_mid: (handler >> 16) as u16,
            offset_high: (handler >> 32) as u32,
            _reserved: 0,
        }
    }

    fn handler_address(&self) -> u64 {
        (self.offset_low as u64)
            | ((self.offset_mid as u64) << 16)
            | ((self.offset_high as u64) << 32)
    }

    fn is_present(&self) -> bool {
        self.type_attr & 0x80 != 0
    }
}

impl fmt::Display for IdtEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.is_present() {
            write!(
                f,
                "handler=0x{:016X} sel=0x{:04X} ist={} type=0x{:02X}",
                self.handler_address(),
                self.selector,
                self.ist,
                self.type_attr
            )
        } else {
            write!(f, "(not present)")
        }
    }
}

// ── Interrupt Descriptor Table ────────────────────────────────────────────

const IDT_SIZE: usize = 256;

struct Idt {
    entries: [IdtEntry; IDT_SIZE],
}

impl Idt {
    fn new() -> Self {
        Self {
            entries: [IdtEntry::empty(); IDT_SIZE],
        }
    }

    fn set_handler(&mut self, vector: u8, entry: IdtEntry) {
        self.entries[vector as usize] = entry;
    }
}

// ── Interrupt Stack Frame ─────────────────────────────────────────────────

/// What the CPU pushes onto the stack when an interrupt fires.
#[derive(Debug)]
struct InterruptFrame {
    rip: u64,       // instruction pointer at time of interrupt
    cs: u64,        // code segment
    rflags: u64,    // flags register
    rsp: u64,       // stack pointer at time of interrupt
    ss: u64,        // stack segment
}

impl fmt::Display for InterruptFrame {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "RIP=0x{:016X} CS=0x{:04X} RFLAGS=0x{:08X} RSP=0x{:016X} SS=0x{:04X}",
            self.rip, self.cs, self.rflags, self.rsp, self.ss
        )
    }
}

// ── Exception Information ─────────────────────────────────────────────────

#[derive(Debug, Clone, Copy)]
struct ExceptionInfo {
    vector: u8,
    name: &'static str,
    has_error_code: bool,
    exception_type: ExceptionType,
}

#[derive(Debug, Clone, Copy)]
enum ExceptionType {
    Fault,      // restartable — RIP points to the faulting instruction
    Trap,       // RIP points to the NEXT instruction
    Abort,      // unrecoverable
    Interrupt,  // externally triggered (NMI)
    FaultTrap,  // either fault or trap depending on cause (#DB)
}

impl fmt::Display for ExceptionType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ExceptionType::Fault => write!(f, "fault"),
            ExceptionType::Trap => write!(f, "trap"),
            ExceptionType::Abort => write!(f, "abort"),
            ExceptionType::Interrupt => write!(f, "interrupt"),
            ExceptionType::FaultTrap => write!(f, "fault/trap"),
        }
    }
}

const EXCEPTIONS: &[ExceptionInfo] = &[
    ExceptionInfo { vector: 0,  name: "Divide Error (#DE)",             has_error_code: false, exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 1,  name: "Debug (#DB)",                    has_error_code: false, exception_type: ExceptionType::FaultTrap },
    ExceptionInfo { vector: 2,  name: "NMI",                           has_error_code: false, exception_type: ExceptionType::Interrupt },
    ExceptionInfo { vector: 3,  name: "Breakpoint (#BP)",              has_error_code: false, exception_type: ExceptionType::Trap },
    ExceptionInfo { vector: 4,  name: "Overflow (#OF)",                has_error_code: false, exception_type: ExceptionType::Trap },
    ExceptionInfo { vector: 5,  name: "Bound Range (#BR)",             has_error_code: false, exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 6,  name: "Invalid Opcode (#UD)",          has_error_code: false, exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 7,  name: "Device Not Available (#NM)",    has_error_code: false, exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 8,  name: "Double Fault (#DF)",            has_error_code: true,  exception_type: ExceptionType::Abort },
    ExceptionInfo { vector: 10, name: "Invalid TSS (#TS)",             has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 11, name: "Segment Not Present (#NP)",     has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 12, name: "Stack Fault (#SS)",             has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 13, name: "General Protection (#GP)",      has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 14, name: "Page Fault (#PF)",              has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 16, name: "x87 FP Exception (#MF)",       has_error_code: false, exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 17, name: "Alignment Check (#AC)",         has_error_code: true,  exception_type: ExceptionType::Fault },
    ExceptionInfo { vector: 18, name: "Machine Check (#MC)",           has_error_code: false, exception_type: ExceptionType::Abort },
    ExceptionInfo { vector: 19, name: "SIMD FP Exception (#XM)",      has_error_code: false, exception_type: ExceptionType::Fault },
];

// ── Page Fault Error Code Decoding ────────────────────────────────────────

fn decode_page_fault_error(error_code: u64) -> String {
    let mut parts = Vec::new();
    if error_code & 1 != 0 {
        parts.push("protection violation");
    } else {
        parts.push("page not present");
    }
    if error_code & 2 != 0 {
        parts.push("write access");
    } else {
        parts.push("read access");
    }
    if error_code & 4 != 0 {
        parts.push("user mode");
    } else {
        parts.push("kernel mode");
    }
    if error_code & 8 != 0 {
        parts.push("reserved bit set");
    }
    if error_code & 16 != 0 {
        parts.push("instruction fetch");
    }
    parts.join(", ")
}

// ── Interrupt Dispatch Simulation ─────────────────────────────────────────

fn simulate_interrupt(idt: &Idt, vector: u8, frame: &InterruptFrame, error_code: Option<u64>) {
    let entry = &idt.entries[vector as usize];
    let exc_info = EXCEPTIONS.iter().find(|e| e.vector == vector);

    if let Some(info) = exc_info {
        println!("  Exception #{}: {} ({})", vector, info.name, info.exception_type);
    } else if vector >= 32 {
        println!("  IRQ {} (vector {})", vector - 32, vector);
    } else {
        println!("  Vector {}", vector);
    }

    println!("    Frame: {}", frame);

    if let Some(code) = error_code {
        print!("    Error code: 0x{:X}", code);
        if vector == 14 {
            print!(" ({})", decode_page_fault_error(code));
        }
        println!();
    }

    if entry.is_present() {
        println!("    Handler: {}", entry);
        if entry.ist > 0 {
            println!("    Stack switch: IST[{}]", entry.ist);
        }
        println!("    Action: save registers → call handler → send EOI → IRETQ");
    } else {
        println!("    ERROR: no handler registered! Would cause #DF (double fault)");
    }
}

fn main() {
    println!("Interrupt Handling — x86_64 IDT and exception mechanics:\n");

    // ── Build the IDT ─────────────────────────────────────────────────
    println!("1. Building IDT (256 entries):");
    let mut idt = Idt::new();

    // Register exception handlers
    for exc in EXCEPTIONS {
        let handler_addr = 0xFFFF_8000_0010_0000u64 + (exc.vector as u64 * 0x100);
        let ist = if exc.vector == 8 { 1 } else { 0 }; // Double fault gets IST[1]
        idt.set_handler(
            exc.vector,
            IdtEntry::interrupt_gate(handler_addr, 0x08, ist, 0),
        );
    }

    // Register timer interrupt (IRQ 0 = vector 32)
    idt.set_handler(32, IdtEntry::interrupt_gate(0xFFFF_8000_0020_0000, 0x08, 0, 0));
    // Keyboard (IRQ 1 = vector 33)
    idt.set_handler(33, IdtEntry::interrupt_gate(0xFFFF_8000_0020_0100, 0x08, 0, 0));

    println!("   Registered {} exception handlers + 2 IRQ handlers", EXCEPTIONS.len());
    println!("   IDT entry for #PF: {}", idt.entries[14]);
    println!("   IDT entry for #DF: {} (IST[1])", idt.entries[8]);
    println!("   IDT entry for timer: {}", idt.entries[32]);

    // ── Exception table ───────────────────────────────────────────────
    println!("\n2. x86_64 exception table:");
    println!("   {:>3}  {:<35} {:>5} {:<6}", "#", "Name", "ErrC", "Type");
    println!("   {}", "-".repeat(55));
    for exc in EXCEPTIONS {
        println!(
            "   {:>3}  {:<35} {:>5} {:<6}",
            exc.vector,
            exc.name,
            if exc.has_error_code { "yes" } else { "no" },
            format!("{}", exc.exception_type),
        );
    }

    // ── Simulate interrupts ───────────────────────────────────────────
    println!("\n3. Simulating interrupt dispatch:");

    let user_frame = InterruptFrame {
        rip: 0x0000_0000_0040_1234,
        cs: 0x2B,    // user code segment
        rflags: 0x202, // IF set
        rsp: 0x0000_7FFF_FFFF_F000,
        ss: 0x33,    // user stack segment
    };

    // Page fault: user-mode write to unmapped page
    println!();
    simulate_interrupt(&idt, 14, &user_frame, Some(0x6)); // write + user mode

    // Timer interrupt
    println!();
    let kernel_frame = InterruptFrame {
        rip: 0xFFFF_8000_0005_0000,
        cs: 0x08,
        rflags: 0x202,
        rsp: 0xFFFF_C000_0001_0000,
        ss: 0x10,
    };
    simulate_interrupt(&idt, 32, &kernel_frame, None);

    // General protection fault
    println!();
    simulate_interrupt(&idt, 13, &user_frame, Some(0x0));

    // Unregistered vector (would cause double fault)
    println!();
    simulate_interrupt(&idt, 50, &kernel_frame, None);

    println!("\n4. Key implementation rules:");
    println!("   - Compile kernel with -mno-red-zone (handlers clobber red zone)");
    println!("   - Double fault handler MUST use IST (needs guaranteed-good stack)");
    println!("   - Push dummy error code for exceptions that don't push one");
    println!("   - Send EOI to LAPIC after handling hardware interrupts");
    println!("   - IRETQ (not RET) to return from interrupt handlers");
}
