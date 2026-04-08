// Vidya — Interrupt Handling in TypeScript
//
// Interrupts are the mechanism by which hardware and software signal
// the CPU to stop what it is doing and handle an event. The CPU looks
// up the handler in the IDT (Interrupt Descriptor Table), pushes a
// stack frame, and jumps to the handler. We model IDT gate descriptors
// with DataView, simulate PIC interrupt routing, build the x86_64
// exception table, and decode page fault error codes.

function main(): void {
    testIdtGateDescriptor();
    testExceptionTable();
    testErrorCodeDecoding();
    testPicSimulation();
    testInterruptDispatch();
    testInterruptStackFrame();

    console.log("All interrupt handling examples passed.");
}

// ── IDT Gate Descriptor (16 bytes, 64-bit mode) ─────────────────────

// An x86_64 IDT entry is 16 bytes. It encodes:
//   [0..2)   offset_low     handler address bits 0-15
//   [2..4)   selector       code segment selector (GDT index)
//   [4..5)   ist            interrupt stack table index (0-7)
//   [5..6)   type_attr      type (0xE=interrupt, 0xF=trap) + DPL + P
//   [6..8)   offset_mid     handler address bits 16-31
//   [8..12)  offset_high    handler address bits 32-63
//   [12..16) reserved       must be zero

const IDT_ENTRY_SIZE = 16;
const GATE_TYPE_INTERRUPT = 0x0E; // clears IF (disables interrupts)
const GATE_TYPE_TRAP      = 0x0F; // does NOT clear IF

class IdtGateDescriptor {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        this.buf = new ArrayBuffer(IDT_ENTRY_SIZE);
        this.view = new DataView(this.buf);
    }

    static interruptGate(handler: bigint, selector: number, ist: number, dpl: number): IdtGateDescriptor {
        const gate = new IdtGateDescriptor();
        const v = gate.view;

        v.setUint16(0, Number(handler & 0xFFFFn), true);
        v.setUint16(2, selector, true);
        v.setUint8(4, ist & 0x7);
        v.setUint8(5, 0x80 | ((dpl & 0x3) << 5) | GATE_TYPE_INTERRUPT);
        v.setUint16(6, Number((handler >> 16n) & 0xFFFFn), true);
        v.setUint32(8, Number((handler >> 32n) & 0xFFFF_FFFFn), true);
        v.setUint32(12, 0, true);

        return gate;
    }

    static trapGate(handler: bigint, selector: number, ist: number, dpl: number): IdtGateDescriptor {
        const gate = new IdtGateDescriptor();
        const v = gate.view;

        v.setUint16(0, Number(handler & 0xFFFFn), true);
        v.setUint16(2, selector, true);
        v.setUint8(4, ist & 0x7);
        v.setUint8(5, 0x80 | ((dpl & 0x3) << 5) | GATE_TYPE_TRAP);
        v.setUint16(6, Number((handler >> 16n) & 0xFFFFn), true);
        v.setUint32(8, Number((handler >> 32n) & 0xFFFF_FFFFn), true);
        v.setUint32(12, 0, true);

        return gate;
    }

    get handlerAddress(): bigint {
        const low  = BigInt(this.view.getUint16(0, true));
        const mid  = BigInt(this.view.getUint16(6, true));
        const high = BigInt(this.view.getUint32(8, true));
        return low | (mid << 16n) | (high << 32n);
    }

    get selector(): number  { return this.view.getUint16(2, true); }
    get ist(): number       { return this.view.getUint8(4) & 0x7; }
    get present(): boolean  { return (this.view.getUint8(5) & 0x80) !== 0; }
    get dpl(): number       { return (this.view.getUint8(5) >> 5) & 0x3; }
    get gateType(): number  { return this.view.getUint8(5) & 0x0F; }

    get isInterruptGate(): boolean { return this.gateType === GATE_TYPE_INTERRUPT; }
    get isTrapGate(): boolean      { return this.gateType === GATE_TYPE_TRAP; }
}

function testIdtGateDescriptor(): void {
    const handler = 0xFFFF_8000_0010_ABCDn;

    // Interrupt gate (clears IF)
    const intGate = IdtGateDescriptor.interruptGate(handler, 0x08, 1, 0);
    assert(intGate.handlerAddress === handler, "handler roundtrip");
    assert(intGate.selector === 0x08, "kernel CS");
    assert(intGate.ist === 1, "IST 1");
    assert(intGate.present, "present");
    assert(intGate.dpl === 0, "kernel only");
    assert(intGate.isInterruptGate, "interrupt gate type");

    // Trap gate (does NOT clear IF — interrupts stay enabled)
    const trapGate = IdtGateDescriptor.trapGate(0x40_0000n, 0x08, 0, 0);
    assert(trapGate.isTrapGate, "trap gate type");
    assert(!trapGate.isInterruptGate, "not interrupt gate");

    // User-callable gate (DPL=3, e.g., for breakpoint via int3)
    const userGate = IdtGateDescriptor.interruptGate(0x40_0000n, 0x08, 0, 3);
    assert(userGate.dpl === 3, "user-callable");

    // Verify size
    assert(intGate.buf.byteLength === 16, "IDT entry = 16 bytes");
}

// ── x86_64 Exception Table ──────────────────────────────────────────

// Vectors 0-31 are reserved for CPU exceptions. Each has a fixed
// vector number, a mnemonic, and specific behavior.

type ExceptionType = "fault" | "trap" | "abort" | "interrupt" | "fault/trap";

interface ExceptionInfo {
    vector: number;
    mnemonic: string;
    name: string;
    hasErrorCode: boolean;
    type: ExceptionType;
}

const EXCEPTIONS: ExceptionInfo[] = [
    { vector: 0,  mnemonic: "#DE", name: "Divide Error",           hasErrorCode: false, type: "fault" },
    { vector: 1,  mnemonic: "#DB", name: "Debug",                  hasErrorCode: false, type: "fault/trap" },
    { vector: 2,  mnemonic: "NMI", name: "Non-Maskable Interrupt", hasErrorCode: false, type: "interrupt" },
    { vector: 3,  mnemonic: "#BP", name: "Breakpoint",             hasErrorCode: false, type: "trap" },
    { vector: 4,  mnemonic: "#OF", name: "Overflow",               hasErrorCode: false, type: "trap" },
    { vector: 5,  mnemonic: "#BR", name: "Bound Range Exceeded",   hasErrorCode: false, type: "fault" },
    { vector: 6,  mnemonic: "#UD", name: "Invalid Opcode",         hasErrorCode: false, type: "fault" },
    { vector: 7,  mnemonic: "#NM", name: "Device Not Available",   hasErrorCode: false, type: "fault" },
    { vector: 8,  mnemonic: "#DF", name: "Double Fault",           hasErrorCode: true,  type: "abort" },
    { vector: 10, mnemonic: "#TS", name: "Invalid TSS",            hasErrorCode: true,  type: "fault" },
    { vector: 11, mnemonic: "#NP", name: "Segment Not Present",    hasErrorCode: true,  type: "fault" },
    { vector: 12, mnemonic: "#SS", name: "Stack-Segment Fault",    hasErrorCode: true,  type: "fault" },
    { vector: 13, mnemonic: "#GP", name: "General Protection",     hasErrorCode: true,  type: "fault" },
    { vector: 14, mnemonic: "#PF", name: "Page Fault",             hasErrorCode: true,  type: "fault" },
    { vector: 16, mnemonic: "#MF", name: "x87 FP Exception",       hasErrorCode: false, type: "fault" },
    { vector: 17, mnemonic: "#AC", name: "Alignment Check",        hasErrorCode: true,  type: "fault" },
    { vector: 18, mnemonic: "#MC", name: "Machine Check",          hasErrorCode: false, type: "abort" },
    { vector: 19, mnemonic: "#XM", name: "SIMD FP Exception",      hasErrorCode: false, type: "fault" },
    { vector: 20, mnemonic: "#VE", name: "Virtualization Exception", hasErrorCode: false, type: "fault" },
    { vector: 21, mnemonic: "#CP", name: "Control Protection",     hasErrorCode: true,  type: "fault" },
];

function testExceptionTable(): void {
    // Divide error is vector 0
    const de = EXCEPTIONS.find((e) => e.mnemonic === "#DE")!;
    assert(de.vector === 0, "divide error is vector 0");
    assert(!de.hasErrorCode, "#DE has no error code");
    assert(de.type === "fault", "#DE is a fault");

    // Page fault is vector 14 with error code
    const pf = EXCEPTIONS.find((e) => e.mnemonic === "#PF")!;
    assert(pf.vector === 14, "page fault is vector 14");
    assert(pf.hasErrorCode, "#PF has error code");

    // Double fault is an abort (unrecoverable)
    const df = EXCEPTIONS.find((e) => e.mnemonic === "#DF")!;
    assert(df.type === "abort", "#DF is an abort");
    assert(df.hasErrorCode, "#DF has error code (always 0)");

    // Breakpoint is a trap (RIP points to NEXT instruction)
    const bp = EXCEPTIONS.find((e) => e.mnemonic === "#BP")!;
    assert(bp.type === "trap", "#BP is a trap");

    // Fault vs trap distinction:
    // Fault: RIP points to faulting instruction (can restart)
    // Trap: RIP points to next instruction (for debugging)
    // Abort: CPU state is undefined (cannot recover)

    // Count exceptions with error codes
    const withError = EXCEPTIONS.filter((e) => e.hasErrorCode).length;
    assert(withError === 8, "8 exceptions push error codes");
}

// ── Error Code Decoding ─────────────────────────────────────────────

// Page fault error code (CR2 holds the faulting address):
//   Bit 0: P  — 0 = page not present, 1 = protection violation
//   Bit 1: W  — 0 = read, 1 = write
//   Bit 2: U  — 0 = kernel mode, 1 = user mode
//   Bit 3: R  — 1 = reserved bit set in PTE
//   Bit 4: I  — 1 = instruction fetch (NX violation)

interface PageFaultInfo {
    present: boolean;     // was page present? (protection vs not-present)
    write: boolean;       // was it a write access?
    user: boolean;        // from user mode?
    reservedBit: boolean; // reserved bit set in page table?
    instrFetch: boolean;  // instruction fetch (NX)?
}

function decodePageFaultError(code: number): PageFaultInfo {
    return {
        present:     (code & 0x01) !== 0,
        write:       (code & 0x02) !== 0,
        user:        (code & 0x04) !== 0,
        reservedBit: (code & 0x08) !== 0,
        instrFetch:  (code & 0x10) !== 0,
    };
}

function describePageFault(code: number): string {
    const info = decodePageFaultError(code);
    const parts: string[] = [];
    parts.push(info.present ? "protection violation" : "page not present");
    parts.push(info.write ? "write" : "read");
    parts.push(info.user ? "user mode" : "kernel mode");
    if (info.reservedBit) parts.push("reserved bit set");
    if (info.instrFetch) parts.push("instruction fetch");
    return parts.join(", ");
}

// General Protection Fault error code:
//   If non-zero: segment selector index that caused the fault
//   Bit 0: EXT — external event
//   Bit 1: IDT — selector is in IDT (not GDT/LDT)
//   Bit 2: TI  — 0 = GDT, 1 = LDT

function decodeGPErrorCode(code: number): { external: boolean; idt: boolean; table: string; index: number } {
    return {
        external: (code & 0x01) !== 0,
        idt:      (code & 0x02) !== 0,
        table:    (code & 0x02) !== 0 ? "IDT" : ((code & 0x04) !== 0 ? "LDT" : "GDT"),
        index:    (code >> 3) & 0x1FFF,
    };
}

function testErrorCodeDecoding(): void {
    // User-mode write to unmapped page: code = 0x6 (W=1, U=1)
    const write_unmapped = decodePageFaultError(0x6);
    assert(!write_unmapped.present, "page not present");
    assert(write_unmapped.write, "write access");
    assert(write_unmapped.user, "user mode");

    // Kernel read causing protection violation: code = 0x1 (P=1)
    const kern_prot = decodePageFaultError(0x1);
    assert(kern_prot.present, "protection violation");
    assert(!kern_prot.write, "read access");
    assert(!kern_prot.user, "kernel mode");

    // NX violation: code = 0x15 (P=1, U=1, I=1)
    const nx = decodePageFaultError(0x15);
    assert(nx.present, "NX: page was present");
    assert(nx.instrFetch, "NX: instruction fetch");
    assert(nx.user, "NX: user mode");

    // Description string
    const desc = describePageFault(0x6);
    assert(desc.includes("page not present"), "desc: not present");
    assert(desc.includes("write"), "desc: write");
    assert(desc.includes("user mode"), "desc: user");

    // GP fault error code
    const gp = decodeGPErrorCode(0x0);
    assert(gp.table === "GDT", "GP: GDT");
    assert(gp.index === 0, "GP: index 0 = null selector");
}

// ── PIC (Programmable Interrupt Controller) Simulation ──────────────

// The legacy 8259 PIC routes hardware interrupts to CPU vectors.
// Two PICs: master (IRQ 0-7) and slave (IRQ 8-15).
// Modern systems use APIC, but understanding the PIC is foundational.

class PicSimulator {
    private irr = 0;     // Interrupt Request Register
    private isr = 0;     // In-Service Register
    private imr = 0xFF;  // Interrupt Mask Register (all masked initially)
    private baseVector: number;
    eois = 0;

    constructor(baseVector: number) {
        this.baseVector = baseVector;
    }

    /** Unmask an IRQ line (enable it). */
    unmask(irq: number): void {
        this.imr &= ~(1 << irq);
    }

    /** Mask an IRQ line (disable it). */
    mask(irq: number): void {
        this.imr |= (1 << irq);
    }

    /** Raise an interrupt request. */
    raise(irq: number): void {
        this.irr |= (1 << irq);
    }

    /** Get the highest-priority pending interrupt (lowest IRQ number). */
    poll(): number | null {
        const pending = this.irr & ~this.imr;
        if (pending === 0) return null;

        // Find lowest set bit (highest priority)
        for (let i = 0; i < 8; i++) {
            if (pending & (1 << i)) {
                this.irr &= ~(1 << i);    // clear from IRR
                this.isr |= (1 << i);     // mark in-service
                return this.baseVector + i;
            }
        }
        return null;
    }

    /** Send End-Of-Interrupt. Must be called after handling. */
    eoi(irq: number): void {
        this.isr &= ~(1 << irq);
        this.eois++;
    }

    get pendingCount(): number {
        let count = 0;
        let pending = this.irr & ~this.imr;
        while (pending) {
            count += pending & 1;
            pending >>= 1;
        }
        return count;
    }
}

function testPicSimulation(): void {
    // Master PIC: IRQs 0-7 → vectors 32-39
    const pic = new PicSimulator(32);

    // Initially all IRQs are masked
    pic.raise(0); // timer
    assert(pic.poll() === null, "masked IRQ not delivered");

    // Unmask timer (IRQ 0) and keyboard (IRQ 1)
    pic.unmask(0);
    pic.unmask(1);

    // Raise timer interrupt
    pic.raise(0);
    const vec = pic.poll();
    assert(vec === 32, "timer = vector 32");

    // Must send EOI before the same IRQ can fire again
    pic.eoi(0);

    // Priority: lower IRQ number = higher priority
    pic.raise(1); // keyboard
    pic.raise(0); // timer (higher priority)
    const first = pic.poll();
    assert(first === 32, "timer wins over keyboard");
    pic.eoi(0);

    const second = pic.poll();
    assert(second === 33, "keyboard delivered after timer EOI");
    pic.eoi(1);

    assert(pic.eois === 3, "3 EOIs sent");
}

// ── Interrupt Dispatch Simulation ───────────────────────────────────

// When an interrupt fires, the CPU:
// 1. Looks up the IDT entry for the vector
// 2. Pushes SS, RSP, RFLAGS, CS, RIP onto the stack
// 3. If error code: pushes error code
// 4. If IST > 0: switches to IST stack
// 5. Clears IF (for interrupt gates) or not (for trap gates)
// 6. Jumps to the handler address

interface DispatchResult {
    vector: number;
    handler: bigint;
    stackSwitch: boolean;
    interruptsDisabled: boolean;
    errorCode: number | null;
    description: string;
}

class InterruptController {
    private gates = new Map<number, IdtGateDescriptor>();
    dispatches: DispatchResult[] = [];

    register(vector: number, gate: IdtGateDescriptor): void {
        this.gates.set(vector, gate);
    }

    dispatch(vector: number, errorCode: number | null): DispatchResult | null {
        const gate = this.gates.get(vector);
        if (!gate || !gate.present) return null;

        const exc = EXCEPTIONS.find((e) => e.vector === vector);
        const description = exc
            ? `${exc.mnemonic} ${exc.name}`
            : (vector >= 32 ? `IRQ ${vector - 32}` : `Vector ${vector}`);

        const result: DispatchResult = {
            vector,
            handler: gate.handlerAddress,
            stackSwitch: gate.ist > 0,
            interruptsDisabled: gate.isInterruptGate,
            errorCode,
            description,
        };

        this.dispatches.push(result);
        return result;
    }
}

function testInterruptDispatch(): void {
    const ic = new InterruptController();

    // Register handlers
    const baseAddr = 0xFFFF_8000_0010_0000n;
    for (const exc of EXCEPTIONS) {
        const handler = baseAddr + BigInt(exc.vector) * 0x100n;
        const ist = exc.mnemonic === "#DF" ? 1 : 0; // double fault gets IST
        ic.register(exc.vector, IdtGateDescriptor.interruptGate(handler, 0x08, ist, 0));
    }

    // Timer IRQ
    ic.register(32, IdtGateDescriptor.interruptGate(baseAddr + 0x2000n, 0x08, 0, 0));

    // Dispatch page fault
    const pf = ic.dispatch(14, 0x6)!;
    assert(pf.description.includes("#PF"), "page fault dispatched");
    assert(pf.errorCode === 0x6, "error code passed");
    assert(pf.interruptsDisabled, "interrupt gate disables IF");
    assert(!pf.stackSwitch, "PF uses normal stack");

    // Dispatch double fault (uses IST)
    const df = ic.dispatch(8, 0)!;
    assert(df.stackSwitch, "double fault switches stack");

    // Dispatch timer
    const timer = ic.dispatch(32, null)!;
    assert(timer.description === "IRQ 0", "timer is IRQ 0");
    assert(timer.errorCode === null, "IRQ has no error code");

    // Unregistered vector
    const unknown = ic.dispatch(100, null);
    assert(unknown === null, "unregistered returns null");

    assert(ic.dispatches.length === 3, "3 dispatches recorded");
}

// ── Interrupt Stack Frame ───────────────────────────────────────────

// When an interrupt fires, the CPU automatically pushes 5 values
// (plus error code for some exceptions). This is the interrupt
// stack frame that the handler receives.

interface InterruptFrame {
    rip: bigint;     // instruction pointer at interrupt
    cs: bigint;      // code segment
    rflags: bigint;  // flags register
    rsp: bigint;     // stack pointer at interrupt
    ss: bigint;      // stack segment
}

function buildFrame(rip: bigint, userMode: boolean): InterruptFrame {
    return {
        rip,
        cs: userMode ? 0x2Bn : 0x08n,
        rflags: 0x202n,  // IF set
        rsp: userMode ? 0x7FFF_F000n : 0xFFFF_C000_0001_0000n,
        ss: userMode ? 0x33n : 0x10n,
    };
}

function testInterruptStackFrame(): void {
    // User-mode interrupt (ring 3 → ring 0)
    const userFrame = buildFrame(0x40_1234n, true);
    assert(userFrame.cs === 0x2Bn, "user CS");
    assert(userFrame.ss === 0x33n, "user SS");
    // User→kernel causes stack switch (RSP loaded from TSS)

    // Kernel-mode interrupt (ring 0 → ring 0, no stack switch unless IST)
    const kernFrame = buildFrame(0xFFFF_8000_0005_0000n, false);
    assert(kernFrame.cs === 0x08n, "kernel CS");
    assert(kernFrame.ss === 0x10n, "kernel SS");

    // The frame is pushed in this order (top of stack first):
    //   SS → RSP → RFLAGS → CS → RIP [→ error code]
    // Handler accesses them as a struct.
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
