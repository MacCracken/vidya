# Interrupt Handling — Python Implementation
#
# Demonstrates x86_64 interrupt handling concepts:
#   1. IDT (Interrupt Descriptor Table) structure and entry encoding
#   2. Interrupt stack frame layout
#   3. Exception types and error codes
#   4. PIC 8259A cascade configuration
#   5. Interrupt dispatch simulation
#
# In a real kernel, IDT entries point to assembly stubs that save registers
# and call handlers. Here we simulate the mechanics.

from dataclasses import dataclass
from enum import Enum, auto
from typing import Optional

# ── IDT Entry (x86_64 Gate Descriptor) ────────────────────────────────────


class GateType(Enum):
    """x86_64 gate types in the IDT."""
    INTERRUPT = 0x0E  # clears IF — interrupts disabled during handler
    TRAP = 0x0F       # does NOT clear IF — interrupts remain enabled


@dataclass
class IdtEntry:
    """An x86_64 IDT entry is 16 bytes (128 bits).

    It encodes:
      - Handler address (split across 3 fields for historical reasons)
      - Code segment selector (which GDT entry to load into CS)
      - IST index (which stack to switch to, 0 = no switch)
      - Gate type (interrupt gate vs trap gate)
      - DPL (who can trigger via INT instruction: 0=kernel, 3=user)
      - Present bit (must be set or #GP on dispatch)
    """
    handler_addr: int = 0
    selector: int = 0
    ist: int = 0
    gate_type: GateType = GateType.INTERRUPT
    dpl: int = 0
    present: bool = False

    def type_attr_byte(self) -> int:
        """Encode the type_attr field as hardware expects it."""
        p = 0x80 if self.present else 0
        return p | ((self.dpl & 0x3) << 5) | self.gate_type.value

    def encode(self) -> tuple[int, int, int, int, int]:
        """Return the 5 hardware fields (offset_low, selector, ist+type, offset_mid, offset_high)."""
        return (
            self.handler_addr & 0xFFFF,
            self.selector,
            (self.ist & 0x7) | (self.type_attr_byte() << 8),
            (self.handler_addr >> 16) & 0xFFFF,
            (self.handler_addr >> 32) & 0xFFFFFFFF,
        )

    @classmethod
    def interrupt_gate(cls, handler: int, selector: int = 0x08,
                       ist: int = 0, dpl: int = 0) -> "IdtEntry":
        return cls(handler_addr=handler, selector=selector, ist=ist,
                   gate_type=GateType.INTERRUPT, dpl=dpl, present=True)


# ── Interrupt Descriptor Table ────────────────────────────────────────────

IDT_SIZE = 256

class Idt:
    """The IDT: 256 entries, loaded via LIDT instruction."""

    def __init__(self):
        self.entries: list[IdtEntry] = [IdtEntry() for _ in range(IDT_SIZE)]
        self.handlers_set = 0

    def set_handler(self, vector: int, entry: IdtEntry) -> None:
        assert 0 <= vector < IDT_SIZE
        self.entries[vector] = entry
        self.handlers_set += 1

    def get(self, vector: int) -> IdtEntry:
        return self.entries[vector]


# ── Interrupt Stack Frame ─────────────────────────────────────────────────

@dataclass
class InterruptFrame:
    """What the CPU pushes onto the stack when an interrupt fires.

    The CPU pushes these in order (top of stack = RIP):
      SS, RSP, RFLAGS, CS, RIP [, error_code]
    """
    rip: int
    cs: int
    rflags: int
    rsp: int
    ss: int

    def __str__(self) -> str:
        return (f"RIP=0x{self.rip:016X} CS=0x{self.cs:04X} "
                f"RFLAGS=0x{self.rflags:08X} RSP=0x{self.rsp:016X} SS=0x{self.ss:04X}")


# ── Exception Types ──────────────────────────────────────────────────────

class ExceptionType(Enum):
    FAULT = auto()       # restartable — RIP points to faulting instruction
    TRAP = auto()        # RIP points to NEXT instruction
    ABORT = auto()       # unrecoverable
    INTERRUPT = auto()   # externally triggered (NMI)
    FAULT_TRAP = auto()  # either, depending on cause (#DB)


@dataclass
class ExceptionInfo:
    vector: int
    name: str
    has_error_code: bool
    exc_type: ExceptionType


# All 18 architected x86_64 exceptions (vector 0-19, skipping reserved 9 and 15)
EXCEPTIONS: list[ExceptionInfo] = [
    ExceptionInfo(0,  "Divide Error (#DE)",          False, ExceptionType.FAULT),
    ExceptionInfo(1,  "Debug (#DB)",                 False, ExceptionType.FAULT_TRAP),
    ExceptionInfo(2,  "NMI",                         False, ExceptionType.INTERRUPT),
    ExceptionInfo(3,  "Breakpoint (#BP)",            False, ExceptionType.TRAP),
    ExceptionInfo(4,  "Overflow (#OF)",              False, ExceptionType.TRAP),
    ExceptionInfo(5,  "Bound Range (#BR)",           False, ExceptionType.FAULT),
    ExceptionInfo(6,  "Invalid Opcode (#UD)",        False, ExceptionType.FAULT),
    ExceptionInfo(7,  "Device Not Available (#NM)",  False, ExceptionType.FAULT),
    ExceptionInfo(8,  "Double Fault (#DF)",          True,  ExceptionType.ABORT),
    ExceptionInfo(10, "Invalid TSS (#TS)",           True,  ExceptionType.FAULT),
    ExceptionInfo(11, "Segment Not Present (#NP)",   True,  ExceptionType.FAULT),
    ExceptionInfo(12, "Stack Fault (#SS)",           True,  ExceptionType.FAULT),
    ExceptionInfo(13, "General Protection (#GP)",    True,  ExceptionType.FAULT),
    ExceptionInfo(14, "Page Fault (#PF)",            True,  ExceptionType.FAULT),
    ExceptionInfo(16, "x87 FP Exception (#MF)",      False, ExceptionType.FAULT),
    ExceptionInfo(17, "Alignment Check (#AC)",       True,  ExceptionType.FAULT),
    ExceptionInfo(18, "Machine Check (#MC)",         False, ExceptionType.ABORT),
    ExceptionInfo(19, "SIMD FP Exception (#XM)",     False, ExceptionType.FAULT),
]

EXCEPTION_BY_VECTOR: dict[int, ExceptionInfo] = {e.vector: e for e in EXCEPTIONS}


# ── Page Fault Error Code Decoding ────────────────────────────────────────

def decode_page_fault_error(error_code: int) -> str:
    """Decode the #PF error code bit field.

    Bit 0: 0=page not present, 1=protection violation
    Bit 1: 0=read, 1=write
    Bit 2: 0=kernel mode, 1=user mode
    Bit 3: 1=reserved bit set in PTE
    Bit 4: 1=instruction fetch (NX violation)
    """
    parts = []
    parts.append("protection violation" if error_code & 1 else "page not present")
    parts.append("write access" if error_code & 2 else "read access")
    parts.append("user mode" if error_code & 4 else "kernel mode")
    if error_code & 8:
        parts.append("reserved bit set")
    if error_code & 16:
        parts.append("instruction fetch")
    return ", ".join(parts)


# ── PIC 8259A Simulation ─────────────────────────────────────────────────

@dataclass
class Pic8259:
    """Intel 8259A Programmable Interrupt Controller.

    Two PICs in cascade: master (IRQ 0-7) and slave (IRQ 8-15).
    The slave is connected to master's IRQ 2 (cascade input).
    """
    base_vector: int      # remapped base (typically 0x20 for master, 0x28 for slave)
    mask: int             # IMR: bit set = IRQ masked (disabled)
    isr: int              # In-Service Register: currently being handled
    irr: int              # Interrupt Request Register: pending

    @classmethod
    def master(cls, base: int = 0x20) -> "Pic8259":
        return cls(base_vector=base, mask=0xFF, isr=0, irr=0)

    @classmethod
    def slave(cls, base: int = 0x28) -> "Pic8259":
        return cls(base_vector=base, mask=0xFF, isr=0, irr=0)

    def unmask(self, irq_line: int) -> None:
        """Enable an IRQ line (clear its mask bit)."""
        assert 0 <= irq_line < 8
        self.mask &= ~(1 << irq_line)

    def is_masked(self, irq_line: int) -> bool:
        return bool(self.mask & (1 << irq_line))

    def raise_irq(self, irq_line: int) -> None:
        """Signal an interrupt request on the given line."""
        self.irr |= (1 << irq_line)

    def acknowledge(self) -> Optional[int]:
        """Get highest-priority pending unmasked IRQ. Returns vector or None."""
        pending = self.irr & ~self.mask
        if pending == 0:
            return None
        # Highest priority = lowest bit number
        for i in range(8):
            if pending & (1 << i):
                self.irr &= ~(1 << i)    # clear request
                self.isr |= (1 << i)     # mark in-service
                return self.base_vector + i
        return None

    def end_of_interrupt(self, irq_line: int) -> None:
        """Send EOI — clear in-service bit."""
        self.isr &= ~(1 << irq_line)


# ── Interrupt Dispatch Simulation ─────────────────────────────────────────

def simulate_interrupt(idt: Idt, vector: int, frame: InterruptFrame,
                       error_code: Optional[int] = None) -> None:
    """Simulate what happens when an interrupt fires."""
    entry = idt.get(vector)
    exc_info = EXCEPTION_BY_VECTOR.get(vector)

    if exc_info:
        print(f"  Exception #{vector}: {exc_info.name} ({exc_info.exc_type.name.lower()})")
    elif vector >= 32:
        print(f"  IRQ {vector - 32} (vector {vector})")
    else:
        print(f"  Vector {vector}")

    print(f"    Frame: {frame}")

    if error_code is not None:
        detail = ""
        if vector == 14:
            detail = f" ({decode_page_fault_error(error_code)})"
        print(f"    Error code: 0x{error_code:X}{detail}")

    if entry.present:
        print(f"    Handler: 0x{entry.handler_addr:016X} sel=0x{entry.selector:04X} ist={entry.ist}")
        if entry.ist > 0:
            print(f"    Stack switch: IST[{entry.ist}]")
        print(f"    Action: save registers -> call handler -> send EOI -> IRETQ")
    else:
        print(f"    ERROR: no handler registered! Would cause #DF (double fault)")


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    print("Interrupt Handling — x86_64 IDT and exception mechanics:\n")

    # ── 1. Build the IDT ──────────────────────────────────────────────
    print("1. Building IDT (256 entries):")
    idt = Idt()

    for exc in EXCEPTIONS:
        handler_addr = 0xFFFF_8000_0010_0000 + (exc.vector * 0x100)
        ist = 1 if exc.vector == 8 else 0  # Double fault gets IST[1]
        idt.set_handler(exc.vector,
                        IdtEntry.interrupt_gate(handler_addr, selector=0x08, ist=ist))

    # Timer (IRQ 0 = vector 32) and keyboard (IRQ 1 = vector 33)
    idt.set_handler(32, IdtEntry.interrupt_gate(0xFFFF_8000_0020_0000))
    idt.set_handler(33, IdtEntry.interrupt_gate(0xFFFF_8000_0020_0100))

    print(f"   Registered {idt.handlers_set} handlers ({len(EXCEPTIONS)} exceptions + 2 IRQs)")
    pf_entry = idt.get(14)
    print(f"   IDT[14] #PF: handler=0x{pf_entry.handler_addr:016X} ist={pf_entry.ist}")
    df_entry = idt.get(8)
    print(f"   IDT[8]  #DF: handler=0x{df_entry.handler_addr:016X} ist={df_entry.ist} (IST[1])")
    print(f"   IDT[32] timer: handler=0x{idt.get(32).handler_addr:016X}")

    # Verify encoding
    assert pf_entry.present
    assert pf_entry.type_attr_byte() == 0x8E  # P=1, DPL=0, type=0xE
    assert df_entry.ist == 1

    # ── 2. Exception table ────────────────────────────────────────────
    print(f"\n2. x86_64 exception table:")
    print(f"   {'#':>3}  {'Name':<35} {'ErrC':>5} {'Type':<10}")
    print(f"   {'-' * 55}")
    for exc in EXCEPTIONS:
        err_str = "yes" if exc.has_error_code else "no"
        print(f"   {exc.vector:>3}  {exc.name:<35} {err_str:>5} {exc.exc_type.name.lower():<10}")

    # Verify error code expectations
    assert not EXCEPTION_BY_VECTOR[0].has_error_code   # #DE: no error code
    assert EXCEPTION_BY_VECTOR[14].has_error_code       # #PF: has error code
    assert EXCEPTION_BY_VECTOR[13].has_error_code       # #GP: has error code

    # ── 3. PIC 8259A cascade ──────────────────────────────────────────
    print(f"\n3. PIC 8259A cascade configuration:")
    master = Pic8259.master(base=0x20)
    slave = Pic8259.slave(base=0x28)

    # Unmask timer (IRQ 0), keyboard (IRQ 1), and cascade (IRQ 2)
    master.unmask(0)  # timer
    master.unmask(1)  # keyboard
    master.unmask(2)  # cascade to slave
    slave.unmask(0)   # IRQ 8 (RTC)

    print(f"   Master PIC: base=0x{master.base_vector:02X} mask=0x{master.mask:02X}")
    print(f"     IRQ 0 (timer):    {'unmasked' if not master.is_masked(0) else 'masked'}")
    print(f"     IRQ 1 (keyboard): {'unmasked' if not master.is_masked(1) else 'masked'}")
    print(f"     IRQ 2 (cascade):  {'unmasked' if not master.is_masked(2) else 'masked'}")
    print(f"   Slave PIC:  base=0x{slave.base_vector:02X} mask=0x{slave.mask:02X}")
    print(f"     IRQ 8 (RTC):      {'unmasked' if not slave.is_masked(0) else 'masked'}")

    # Simulate timer interrupt through PIC
    master.raise_irq(0)
    vector = master.acknowledge()
    assert vector == 0x20  # timer = IRQ 0 + base 0x20
    print(f"\n   Timer IRQ fired -> vector 0x{vector:02X} (IRQ {vector - master.base_vector})")
    master.end_of_interrupt(0)
    assert master.isr == 0  # ISR cleared after EOI

    # ── 4. Simulate interrupts ────────────────────────────────────────
    print(f"\n4. Simulating interrupt dispatch:")

    user_frame = InterruptFrame(
        rip=0x0000_0000_0040_1234, cs=0x2B, rflags=0x202,
        rsp=0x0000_7FFF_FFFF_F000, ss=0x33,
    )

    # Page fault: user-mode write to unmapped page
    print()
    simulate_interrupt(idt, 14, user_frame, error_code=0x6)

    # Timer interrupt in kernel mode
    print()
    kernel_frame = InterruptFrame(
        rip=0xFFFF_8000_0005_0000, cs=0x08, rflags=0x202,
        rsp=0xFFFF_C000_0001_0000, ss=0x10,
    )
    simulate_interrupt(idt, 32, kernel_frame)

    # General protection fault
    print()
    simulate_interrupt(idt, 13, user_frame, error_code=0x0)

    # ── 5. Page fault error code examples ─────────────────────────────
    print(f"\n5. Page fault error code decoding:")
    pf_codes = [
        (0x0, "kernel read, page not present"),
        (0x2, "kernel write, page not present"),
        (0x4, "user read, page not present"),
        (0x5, "user read, protection violation"),
        (0x6, "user write, page not present"),
        (0x7, "user write, protection violation"),
        (0x14, "user instruction fetch (NX)"),
    ]
    for code, expected_desc in pf_codes:
        decoded = decode_page_fault_error(code)
        print(f"   0x{code:02X} -> {decoded}")

    # Verify decoding
    assert "page not present" in decode_page_fault_error(0x0)
    assert "write access" in decode_page_fault_error(0x2)
    assert "user mode" in decode_page_fault_error(0x4)
    assert "instruction fetch" in decode_page_fault_error(0x14)

    print("\nAll assertions passed.")


if __name__ == "__main__":
    main()
