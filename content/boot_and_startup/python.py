# Vidya — Boot and Startup in Python
#
# How a computer goes from power-on to running an OS. Since Python can't
# execute boot code, we model the key data structures and verify their
# layouts:
#   1. GDT entry (segment descriptor) — 8-byte packed format
#   2. IDT gate descriptor — interrupt vector routing
#   3. Multiboot header — bootloader handshake magic
#   4. Mode transition sequence — real -> protected -> long mode
#
# Every field offset, bit mask, and magic constant is verified with
# assertions. These are the same values you'd use in assembly.

import struct

# ── GDT Entry (Segment Descriptor) ───────────────────────────────────
#
# Each GDT entry is 8 bytes with a notoriously fragmented layout:
#
#   Bits 0-15:   Limit (low 16 bits)
#   Bits 16-31:  Base (low 16 bits)
#   Bits 32-39:  Base (mid 8 bits)
#   Bits 40-47:  Access byte
#   Bits 48-51:  Limit (high 4 bits)
#   Bits 52-55:  Flags (G, DB, L, reserved)
#   Bits 56-63:  Base (high 8 bits)
#
# In long mode, base and limit are ignored (flat model), but the
# access byte and flags still matter.

class GdtEntry:
    """An 8-byte segment descriptor for the Global Descriptor Table."""

    def __init__(self, base=0, limit=0, access=0, flags=0):
        self.base = base        # 32-bit base address
        self.limit = limit      # 20-bit segment limit
        self.access = access    # 8-bit access byte
        self.flags = flags      # 4-bit flags (G, DB, L, reserved)

    def pack(self):
        """Pack into 8 bytes matching hardware layout."""
        limit_lo = self.limit & 0xFFFF
        limit_hi = (self.limit >> 16) & 0x0F
        base_lo = self.base & 0xFFFF
        base_mid = (self.base >> 16) & 0xFF
        base_hi = (self.base >> 24) & 0xFF
        flags_limit = (self.flags << 4) | limit_hi

        return struct.pack('<HHBBBB',
            limit_lo,       # bytes 0-1: limit low
            base_lo,        # bytes 2-3: base low
            base_mid,       # byte 4: base mid
            self.access,    # byte 5: access byte
            flags_limit,    # byte 6: flags (high nibble) + limit high (low nibble)
            base_hi,        # byte 7: base high
        )

    @property
    def present(self):
        return bool(self.access & 0x80)

    @property
    def dpl(self):
        return (self.access >> 5) & 0x03

    @property
    def is_code(self):
        return bool(self.access & 0x08)

    @property
    def is_long_mode(self):
        return bool(self.flags & 0x02)

    def __repr__(self):
        if self.access == 0 and self.base == 0 and self.limit == 0:
            return "GDT[NULL]"
        kind = "CODE" if self.is_code else "DATA"
        mode = "64-bit" if self.is_long_mode else "32-bit"
        return f"GDT[{kind} ring{self.dpl} {mode}]"


def null_descriptor():
    """Entry 0 must always be null."""
    return GdtEntry(base=0, limit=0, access=0, flags=0)


def code64_descriptor(dpl=0):
    """64-bit code segment. L=1, DB=0. Access: P=1, S=1, E=1, R=1."""
    access = 0x80 | (dpl << 5) | 0x1A  # P + DPL + S + E + R
    flags = 0x0A  # G=1, L=1 (long mode), DB=0
    return GdtEntry(base=0, limit=0xFFFFF, access=access, flags=flags)


def data_descriptor(dpl=0):
    """Data segment (same for 32/64-bit). Access: P=1, S=1, W=1."""
    access = 0x80 | (dpl << 5) | 0x12  # P + DPL + S + W
    flags = 0x0C  # G=1, DB=1
    return GdtEntry(base=0, limit=0xFFFFF, access=access, flags=flags)


# ── IDT Gate Descriptor ───────────────────────────────────────────────
#
# Each IDT entry is 16 bytes in long mode:
#   Bytes 0-1:   Offset low (bits 0-15)
#   Bytes 2-3:   Segment selector
#   Byte  4:     IST (bits 0-2), reserved (bits 3-7)
#   Byte  5:     Type/attributes (P, DPL, gate type)
#   Bytes 6-7:   Offset mid (bits 16-31)
#   Bytes 8-11:  Offset high (bits 32-63)
#   Bytes 12-15: Reserved (must be zero)

class IdtGateDescriptor:
    """A 16-byte IDT gate descriptor for long mode."""

    # Gate types
    INTERRUPT_GATE = 0x0E  # clears IF (disables interrupts)
    TRAP_GATE = 0x0F       # does not clear IF

    def __init__(self, offset, selector, gate_type=0x0E, dpl=0, ist=0):
        self.offset = offset        # 64-bit handler address
        self.selector = selector    # code segment selector
        self.gate_type = gate_type  # interrupt (0xE) or trap (0xF)
        self.dpl = dpl              # descriptor privilege level
        self.ist = ist & 0x07       # interrupt stack table index

    def pack(self):
        """Pack into 16 bytes matching hardware layout."""
        offset_lo = self.offset & 0xFFFF
        offset_mid = (self.offset >> 16) & 0xFFFF
        offset_hi = (self.offset >> 32) & 0xFFFFFFFF
        type_attr = 0x80 | (self.dpl << 5) | self.gate_type  # P=1

        return struct.pack('<HHBBHII',
            offset_lo,     # bytes 0-1
            self.selector, # bytes 2-3
            self.ist,      # byte 4
            type_attr,     # byte 5
            offset_mid,    # bytes 6-7
            offset_hi,     # bytes 8-11
            0,             # bytes 12-15: reserved
        )

    def __repr__(self):
        kind = "INT" if self.gate_type == 0x0E else "TRAP"
        return f"IDT[{kind} sel=0x{self.selector:02X} offset=0x{self.offset:016X}]"


# ── Multiboot Header ─────────────────────────────────────────────────
#
# The Multiboot1 header tells the bootloader (GRUB) how to load the
# kernel. It must appear in the first 8KB of the kernel image.
#   Magic:    0x1BADB002
#   Flags:    requested features
#   Checksum: -(magic + flags) truncated to 32 bits
#
# The bootloader confirms by placing 0x2BADB002 in EAX at kernel entry.

MULTIBOOT1_MAGIC_REQUEST = 0x1BADB002
MULTIBOOT1_MAGIC_RESPONSE = 0x2BADB002
MULTIBOOT1_FLAG_ALIGN = 1 << 0    # align modules on page boundaries
MULTIBOOT1_FLAG_MEMINFO = 1 << 1  # provide memory map

class MultibootHeader:
    """Multiboot1 header — 12 bytes minimum."""

    def __init__(self, flags=0):
        self.magic = MULTIBOOT1_MAGIC_REQUEST
        self.flags = flags
        # Checksum: magic + flags + checksum must equal 0 (mod 2^32)
        self.checksum = (-(self.magic + self.flags)) & 0xFFFFFFFF

    def pack(self):
        return struct.pack('<III', self.magic, self.flags, self.checksum)

    def verify(self):
        """The sum of all three fields must be zero (mod 2^32)."""
        return (self.magic + self.flags + self.checksum) & 0xFFFFFFFF == 0


# ── Mode Transition Sequence ─────────────────────────────────────────
#
# x86 boot goes through three CPU modes:
#   Real mode (16-bit)     — BIOS/firmware runs here
#   Protected mode (32-bit) — GRUB delivers kernel here (Multiboot)
#   Long mode (64-bit)     — where the kernel actually runs

class CpuMode:
    REAL = "real_mode_16bit"
    PROTECTED = "protected_mode_32bit"
    LONG = "long_mode_64bit"

# CR0 bits
CR0_PE = 1 << 0   # Protection Enable — switches to protected mode
CR0_PG = 1 << 31  # Paging — required for long mode

# CR4 bits
CR4_PAE = 1 << 5  # Physical Address Extension — required for long mode

# EFER MSR (Model Specific Register 0xC0000080)
EFER_LME = 1 << 8   # Long Mode Enable
EFER_LMA = 1 << 10  # Long Mode Active (read-only, set by CPU)


def simulate_mode_transition():
    """Walk through the steps from protected mode to long mode."""
    cr0 = CR0_PE  # start in protected mode (PE already set by GRUB)
    cr4 = 0
    efer = 0
    mode = CpuMode.PROTECTED
    steps = []

    # Step 1: Enable PAE in CR4
    cr4 |= CR4_PAE
    steps.append(("Enable PAE (CR4.PAE=1)", cr0, cr4, efer))

    # Step 2: Load PML4 into CR3 (simulated — just note it)
    steps.append(("Load PML4 into CR3", cr0, cr4, efer))

    # Step 3: Enable Long Mode in EFER
    efer |= EFER_LME
    steps.append(("Set EFER.LME=1", cr0, cr4, efer))

    # Step 4: Enable paging (activates long mode)
    cr0 |= CR0_PG
    efer |= EFER_LMA  # CPU sets this automatically when PG + LME
    mode = CpuMode.LONG
    steps.append(("Enable paging (CR0.PG=1) — now in long mode", cr0, cr4, efer))

    return steps, mode


# ── Main ──────────────────────────────────────────────────────────────

def main():
    # ── Test GDT construction ──────────────────────────────────────
    null = null_descriptor()
    kernel_code = code64_descriptor(dpl=0)
    kernel_data = data_descriptor(dpl=0)
    user_code = code64_descriptor(dpl=3)
    user_data = data_descriptor(dpl=3)

    # Null descriptor must be all zeros
    assert null.pack() == b'\x00' * 8, "null descriptor must be 8 zero bytes"
    assert not null.present

    # Kernel code: present, ring 0, code, long mode
    assert kernel_code.present
    assert kernel_code.dpl == 0
    assert kernel_code.is_code
    assert kernel_code.is_long_mode
    assert len(kernel_code.pack()) == 8

    # Kernel data: present, ring 0, data, not long mode (DB=1)
    assert kernel_data.present
    assert kernel_data.dpl == 0
    assert not kernel_data.is_code

    # User code: ring 3
    assert user_code.dpl == 3
    assert user_code.is_code
    assert user_code.is_long_mode

    # User data: ring 3
    assert user_data.dpl == 3
    assert not user_data.is_code

    # Segment selectors: index * 8
    # 0x00 = null, 0x08 = kernel code, 0x10 = kernel data,
    # 0x18 = user code, 0x20 = user data
    gdt = [null, kernel_code, kernel_data, user_code, user_data]
    selectors = {name: idx * 8 for idx, name in enumerate([
        "null", "kernel_code", "kernel_data", "user_code", "user_data"
    ])}
    assert selectors["null"] == 0x00
    assert selectors["kernel_code"] == 0x08
    assert selectors["kernel_data"] == 0x10
    assert selectors["user_code"] == 0x18
    assert selectors["user_data"] == 0x20

    # Full GDT as byte array
    gdt_bytes = b''.join(entry.pack() for entry in gdt)
    assert len(gdt_bytes) == 5 * 8  # 40 bytes total

    print("GDT entries:")
    for i, entry in enumerate(gdt):
        print(f"  [0x{i*8:02X}] {entry}")

    # ── Test IDT gate descriptor ───────────────────────────────────
    # Example: divide-by-zero handler at address 0xFFFF800000001000
    handler_addr = 0xFFFF_8000_0000_1000
    div_zero = IdtGateDescriptor(
        offset=handler_addr,
        selector=0x08,  # kernel code segment
        gate_type=IdtGateDescriptor.INTERRUPT_GATE,
        dpl=0,
        ist=1,  # use IST 1 for stack switching
    )

    packed = div_zero.pack()
    assert len(packed) == 16, "IDT gate must be 16 bytes in long mode"

    # Verify the packed fields by unpacking
    offset_lo, sel, ist_byte, type_attr, offset_mid, offset_hi, reserved = \
        struct.unpack('<HHBBHII', packed)
    assert offset_lo == handler_addr & 0xFFFF
    assert sel == 0x08
    assert ist_byte == 1
    assert type_attr & 0x0F == 0x0E  # interrupt gate type
    assert type_attr & 0x80 == 0x80  # present bit
    assert offset_mid == (handler_addr >> 16) & 0xFFFF
    assert offset_hi == (handler_addr >> 32) & 0xFFFFFFFF
    assert reserved == 0

    # Reconstructed address must match original
    reconstructed = offset_lo | (offset_mid << 16) | (offset_hi << 32)
    assert reconstructed == handler_addr

    print(f"\nIDT gate: {div_zero}")
    print(f"  Reconstructed offset: 0x{reconstructed:016X}")

    # ── Test Multiboot header ──────────────────────────────────────
    flags = MULTIBOOT1_FLAG_ALIGN | MULTIBOOT1_FLAG_MEMINFO
    header = MultibootHeader(flags=flags)

    assert header.magic == 0x1BADB002
    assert header.verify(), "checksum must validate"
    assert len(header.pack()) == 12

    # Verify checksum math explicitly
    total = (header.magic + header.flags + header.checksum) & 0xFFFFFFFF
    assert total == 0, f"checksum failed: sum = 0x{total:08X}"

    # Response magic is what GRUB puts in EAX
    assert MULTIBOOT1_MAGIC_RESPONSE == 0x2BADB002

    print(f"\nMultiboot header:")
    print(f"  Magic:    0x{header.magic:08X}")
    print(f"  Flags:    0x{header.flags:08X} (ALIGN | MEMINFO)")
    print(f"  Checksum: 0x{header.checksum:08X}")
    print(f"  Response: 0x{MULTIBOOT1_MAGIC_RESPONSE:08X} (in EAX at entry)")

    # ── Test mode transition ───────────────────────────────────────
    steps, final_mode = simulate_mode_transition()

    assert final_mode == CpuMode.LONG

    # Verify CR0/CR4/EFER at the end
    _, final_cr0, final_cr4, final_efer = steps[-1]
    assert final_cr0 & CR0_PE, "PE must be set"
    assert final_cr0 & CR0_PG, "PG must be set for long mode"
    assert final_cr4 & CR4_PAE, "PAE must be set for long mode"
    assert final_efer & EFER_LME, "LME must be set"
    assert final_efer & EFER_LMA, "LMA must be set after PG+LME"

    # Verify control register bit positions
    assert CR0_PE == 0x0000_0001, "PE is bit 0 of CR0"
    assert CR0_PG == 0x8000_0000, "PG is bit 31 of CR0"
    assert CR4_PAE == 0x0000_0020, "PAE is bit 5 of CR4"

    print("\nMode transition (protected -> long mode):")
    for desc, cr0, cr4, efer in steps:
        print(f"  {desc}")
        print(f"    CR0=0x{cr0:08X} CR4=0x{cr4:08X} EFER=0x{efer:08X}")
    print(f"  Final mode: {final_mode}")

    print("\nAll boot and startup assertions passed.")


if __name__ == "__main__":
    main()
