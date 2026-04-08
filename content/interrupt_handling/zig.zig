// Vidya — Interrupt Handling in Zig
//
// Interrupts are the CPU's event mechanism: hardware signals (IRQs),
// software traps (syscalls), and exceptions (page faults). The IDT
// maps interrupt vectors to handlers. Zig packed structs model the
// 16-byte IDT gate descriptors exactly. PIC 8259A manages hardware
// IRQ routing before APIC.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testIdtGateDescriptor();
    try testExceptionTable();
    try testPic8259A();
    try testInterruptPriority();
    try testInterruptStackTable();
    try testApicBasics();
    try testIrqRouting();

    std.debug.print("All interrupt handling examples passed.\n", .{});
}

// ── IDT Gate Descriptor (16 bytes) ──────────────────────────────────
// In 64-bit mode, each IDT entry is 16 bytes. The handler address is
// split across three fields (a quirk inherited from 286/386 design).
const IdtGateDescriptor = packed struct {
    offset_low: u16, // Handler address bits 0-15
    selector: u16, // Code segment selector (GDT index)
    ist: u3, // Interrupt Stack Table (0 = none, 1-7 = IST)
    reserved0: u5, // Must be zero
    gate_type: u4, // 0xE = interrupt gate, 0xF = trap gate
    zero: u1, // Must be zero
    dpl: u2, // Descriptor Privilege Level
    present: u1, // Segment present
    offset_mid: u16, // Handler address bits 16-31
    offset_high: u32, // Handler address bits 32-63
    reserved1: u32, // Must be zero
};

const GateType = struct {
    // Interrupt gate: clears IF (disables further interrupts)
    const INTERRUPT: u4 = 0xE;
    // Trap gate: does NOT clear IF (interrupts stay enabled)
    const TRAP: u4 = 0xF;
};

fn makeIdtGate(handler: u64, selector: u16, ist: u3, gate_type: u4, dpl: u2) IdtGateDescriptor {
    return .{
        .offset_low = @truncate(handler),
        .selector = selector,
        .ist = ist,
        .reserved0 = 0,
        .gate_type = gate_type,
        .zero = 0,
        .dpl = dpl,
        .present = 1,
        .offset_mid = @truncate(handler >> 16),
        .offset_high = @truncate(handler >> 32),
        .reserved1 = 0,
    };
}

fn gateHandlerAddr(gate: IdtGateDescriptor) u64 {
    return @as(u64, gate.offset_low) |
        (@as(u64, gate.offset_mid) << 16) |
        (@as(u64, gate.offset_high) << 32);
}

fn testIdtGateDescriptor() !void {
    // 16 bytes exactly per the Intel manual
    comptime {
        std.debug.assert(@sizeOf(IdtGateDescriptor) == 16);
    }

    // Kernel interrupt handler at a higher-half address
    const handler: u64 = 0xFFFF_8000_0010_ABCD;
    const gate = makeIdtGate(handler, 0x08, 0, GateType.INTERRUPT, 0);

    try expect(gate.present == 1);
    try expect(gate.gate_type == GateType.INTERRUPT);
    try expect(gate.dpl == 0); // kernel only
    try expect(gate.selector == 0x08); // kernel code segment
    try expect(gate.ist == 0); // no IST

    // Reconstruct the handler address from the three split fields
    try expect(gateHandlerAddr(gate) == handler);

    // Trap gate for syscall — DPL 3 so user mode can invoke
    const syscall_gate = makeIdtGate(handler, 0x08, 0, GateType.TRAP, 3);
    try expect(syscall_gate.gate_type == GateType.TRAP);
    try expect(syscall_gate.dpl == 3); // user-accessible

    // Not-present gate — CPU generates #GP if invoked
    var absent = makeIdtGate(0, 0x08, 0, GateType.INTERRUPT, 0);
    absent.present = 0;
    try expect(absent.present == 0);
}

// ── IDTR (IDT Register) ─────────────────────────────────────────────
// IDTR is 10 bytes on hardware (2-byte limit + 8-byte base).
// Neither packed nor extern struct gives exactly 10 bytes in Zig,
// so we model it as a plain struct with an encode method.
const IdtDescriptor = struct {
    limit: u16, // Size of IDT - 1
    base: u64, // Linear address of IDT
};

// ── Exception Table ──────────────────────────────────────────────────
// x86_64 reserves vectors 0-31 for CPU exceptions
const Exception = struct {
    vector: u8,
    mnemonic: []const u8,
    name: []const u8,
    has_error_code: bool,
    class: ExceptionClass,
};

const ExceptionClass = enum {
    fault, // Re-executes the instruction (e.g., #PF)
    trap, // Continues after the instruction (e.g., #DB)
    abort, // Unrecoverable (e.g., #DF, #MC)
};

fn testExceptionTable() !void {
    const exceptions = [_]Exception{
        .{ .vector = 0, .mnemonic = "#DE", .name = "Divide Error", .has_error_code = false, .class = .fault },
        .{ .vector = 1, .mnemonic = "#DB", .name = "Debug", .has_error_code = false, .class = .trap },
        .{ .vector = 3, .mnemonic = "#BP", .name = "Breakpoint", .has_error_code = false, .class = .trap },
        .{ .vector = 6, .mnemonic = "#UD", .name = "Invalid Opcode", .has_error_code = false, .class = .fault },
        .{ .vector = 8, .mnemonic = "#DF", .name = "Double Fault", .has_error_code = true, .class = .abort },
        .{ .vector = 13, .mnemonic = "#GP", .name = "General Protection", .has_error_code = true, .class = .fault },
        .{ .vector = 14, .mnemonic = "#PF", .name = "Page Fault", .has_error_code = true, .class = .fault },
        .{ .vector = 18, .mnemonic = "#MC", .name = "Machine Check", .has_error_code = false, .class = .abort },
    };

    // Verify key exception properties
    try expect(exceptions[0].vector == 0); // #DE is always vector 0
    try expect(exceptions[6].vector == 14); // #PF is vector 14

    // Page fault pushes an error code; divide error does not
    try expect(exceptions[6].has_error_code); // #PF
    try expect(!exceptions[0].has_error_code); // #DE

    // Double fault is an abort — unrecoverable
    try expect(exceptions[4].class == .abort);

    // Page fault is a fault — instruction will be re-executed after handling
    try expect(exceptions[6].class == .fault);

    // Breakpoint is a trap — continues at next instruction
    try expect(exceptions[2].class == .trap);

    // Vectors 0-31 reserved for exceptions; 32-255 for user-defined
    for (exceptions) |e| {
        try expect(e.vector < 32);
    }
}

// ── PIC 8259A Simulation ─────────────────────────────────────────────
// The 8259A PIC routes hardware IRQs to CPU interrupt vectors.
// Two PICs cascaded: master (IRQ 0-7) and slave (IRQ 8-15).
const Pic8259A = struct {
    offset: u8, // Base interrupt vector
    mask: u8, // Interrupt mask register (1 = masked/disabled)
    isr: u8, // In-Service Register (currently being handled)
    irr: u8, // Interrupt Request Register (pending)

    fn init(offset: u8) Pic8259A {
        return .{
            .offset = offset,
            .mask = 0xFF, // All masked initially
            .isr = 0,
            .irr = 0,
        };
    }

    fn enableIrq(self: *Pic8259A, irq: u3) void {
        self.mask &= ~(@as(u8, 1) << irq);
    }

    fn disableIrq(self: *Pic8259A, irq: u3) void {
        self.mask |= @as(u8, 1) << irq;
    }

    fn isEnabled(self: *const Pic8259A, irq: u3) bool {
        return self.mask & (@as(u8, 1) << irq) == 0;
    }

    fn raiseIrq(self: *Pic8259A, irq: u3) void {
        self.irr |= @as(u8, 1) << irq;
    }

    fn acknowledgeIrq(self: *Pic8259A, irq: u3) ?u8 {
        const bit = @as(u8, 1) << irq;
        if (self.irr & bit != 0 and self.mask & bit == 0) {
            self.irr &= ~bit;
            self.isr |= bit;
            return self.offset + irq;
        }
        return null;
    }

    fn endOfInterrupt(self: *Pic8259A, irq: u3) void {
        self.isr &= ~(@as(u8, 1) << irq);
    }
};

fn testPic8259A() !void {
    // Master PIC: IRQ 0-7 mapped to vectors 32-39
    var master = Pic8259A.init(32);
    try expect(master.mask == 0xFF); // all masked

    // Enable timer (IRQ 0) and keyboard (IRQ 1)
    master.enableIrq(0);
    master.enableIrq(1);
    try expect(master.isEnabled(0));
    try expect(master.isEnabled(1));
    try expect(!master.isEnabled(2)); // still masked

    // Timer fires
    master.raiseIrq(0);
    try expect(master.irr & 1 != 0);

    // Acknowledge → returns vector 32
    const vector = master.acknowledgeIrq(0);
    try expect(vector.? == 32);
    try expect(master.isr & 1 != 0); // now in-service
    try expect(master.irr & 1 == 0); // request cleared

    // End of interrupt
    master.endOfInterrupt(0);
    try expect(master.isr == 0);

    // Masked IRQ is not acknowledged
    master.raiseIrq(2); // IRQ 2 is masked
    try expect(master.acknowledgeIrq(2) == null);

    // Slave PIC: IRQ 8-15 mapped to vectors 40-47
    var slave = Pic8259A.init(40);
    slave.enableIrq(0); // IRQ 8 (RTC)
    slave.raiseIrq(0);
    try expect(slave.acknowledgeIrq(0).? == 40);
}

// ── Interrupt Priority ───────────────────────────────────────────────
const InterruptPriority = enum(u8) {
    nmi = 0, // Non-maskable — highest priority
    machine_check = 1,
    double_fault = 2,
    exception = 3, // CPU exceptions (#PF, #GP, etc.)
    hardware_high = 4, // Timer, IPI
    hardware_low = 5, // Disk, network
    software = 6, // Syscalls, INT instruction
};

fn testInterruptPriority() !void {
    // NMI cannot be masked — always handled
    try expect(@intFromEnum(InterruptPriority.nmi) < @intFromEnum(InterruptPriority.exception));

    // Hardware interrupts have higher priority than software
    try expect(@intFromEnum(InterruptPriority.hardware_high) < @intFromEnum(InterruptPriority.software));

    // Exceptions are between NMI and hardware IRQs
    try expect(@intFromEnum(InterruptPriority.exception) < @intFromEnum(InterruptPriority.hardware_high));
}

// ── Interrupt Stack Table (IST) ──────────────────────────────────────
// IST provides known-good stacks for critical exceptions.
// Without IST, a stack overflow causes a double fault that also fails.
const IstEntry = struct {
    index: u3, // 1-7 (0 means no IST)
    purpose: []const u8,
    stack_size: usize,
};

fn testInterruptStackTable() !void {
    const ist_config = [_]IstEntry{
        .{ .index = 1, .purpose = "Double Fault", .stack_size = 4096 },
        .{ .index = 2, .purpose = "NMI", .stack_size = 4096 },
        .{ .index = 3, .purpose = "Machine Check", .stack_size = 4096 },
        .{ .index = 4, .purpose = "Debug", .stack_size = 4096 },
    };

    try expect(ist_config.len == 4);

    // Double fault MUST use IST — otherwise a stack overflow
    // that causes #DF would fail again because the stack is bad
    try expect(ist_config[0].index == 1);
    try expect(std.mem.eql(u8, ist_config[0].purpose, "Double Fault"));

    // IST indices 1-7 are valid; 0 means "use current stack"
    for (ist_config) |entry| {
        try expect(entry.index >= 1 and entry.index <= 7);
    }
}

// ── APIC Basics ──────────────────────────────────────────────────────
// Modern systems use APIC (Advanced PIC) instead of 8259A
const ApicRegister = struct {
    const ID: u32 = 0x020; // Local APIC ID
    const VERSION: u32 = 0x030;
    const TPR: u32 = 0x080; // Task Priority Register
    const EOI: u32 = 0x0B0; // End Of Interrupt
    const SVR: u32 = 0x0F0; // Spurious Vector Register
    const ICR_LOW: u32 = 0x300; // Interrupt Command Register
    const ICR_HIGH: u32 = 0x310;
    const TIMER_LVT: u32 = 0x320; // Timer Local Vector Table
    const TIMER_INIT: u32 = 0x380; // Timer Initial Count
    const TIMER_CURRENT: u32 = 0x390; // Timer Current Count
    const TIMER_DIVIDE: u32 = 0x3E0; // Timer Divide Config
};

fn testApicBasics() !void {
    // APIC is memory-mapped at 0xFEE0_0000 (default)
    const APIC_BASE: u64 = 0xFEE0_0000;

    // SVR bit 8 enables the APIC
    const SVR_ENABLE: u32 = 1 << 8;
    const svr_value = SVR_ENABLE | 0xFF; // spurious vector 0xFF
    try expect(svr_value & SVR_ENABLE != 0);

    // APIC replaces PIC: supports per-CPU interrupts, IPI
    try expect(APIC_BASE > 0);

    // Key advantage: each CPU has its own local APIC
    // IPI (Inter-Processor Interrupt) via ICR register
    try expect(ApicRegister.ICR_LOW == 0x300);
}

// ── IRQ Routing ──────────────────────────────────────────────────────
const IrqAssignment = struct {
    irq: u8,
    device: []const u8,
    vector: u8, // CPU interrupt vector
};

fn testIrqRouting() !void {
    // Classic PC IRQ assignments (PIC mode)
    const irqs = [_]IrqAssignment{
        .{ .irq = 0, .device = "PIT Timer", .vector = 32 },
        .{ .irq = 1, .device = "Keyboard", .vector = 33 },
        .{ .irq = 2, .device = "Cascade (to slave PIC)", .vector = 34 },
        .{ .irq = 4, .device = "COM1 (Serial)", .vector = 36 },
        .{ .irq = 6, .device = "Floppy Disk", .vector = 38 },
        .{ .irq = 8, .device = "RTC", .vector = 40 },
        .{ .irq = 12, .device = "PS/2 Mouse", .vector = 44 },
        .{ .irq = 14, .device = "Primary ATA", .vector = 46 },
    };

    // Timer is always IRQ 0 → vector 32
    try expect(irqs[0].vector == 32);
    try expect(std.mem.eql(u8, irqs[0].device, "PIT Timer"));

    // IRQ 2 is cascade — slave PIC connects here
    try expect(irqs[2].irq == 2);

    // All hardware IRQs map to vectors 32+ (0-31 reserved for exceptions)
    for (irqs) |irq| {
        try expect(irq.vector >= 32);
    }
}
