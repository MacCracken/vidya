# Vidya — Kernel Topics in Python
#
# Python isn't used for kernel development, but it's invaluable for
# kernel tooling: parsing page tables, decoding MMIO registers,
# analyzing interrupt logs, and simulating hardware behavior.
# Think of this as the kernel developer's Swiss Army knife.

import struct


def main():
    test_page_table_entry()
    test_virtual_address_decompose()
    test_mmio_register()
    test_interrupt_descriptor_table()
    test_abi_calling_convention()
    test_gdt_entry()
    test_elf_header_parsing()

    print("All kernel topics examples passed.")


# ── Page Table Entry ───────────────────────────────────────────────────
class PageTableEntry:
    PRESENT      = 1 << 0
    WRITABLE     = 1 << 1
    USER         = 1 << 2
    WRITE_THROUGH = 1 << 3
    NO_CACHE     = 1 << 4
    ACCESSED     = 1 << 5
    DIRTY        = 1 << 6
    HUGE_PAGE    = 1 << 7
    NO_EXECUTE   = 1 << 63
    ADDR_MASK    = 0x000F_FFFF_FFFF_F000

    def __init__(self, raw: int):
        self.raw = raw

    @classmethod
    def new(cls, phys_addr: int, flags: int) -> "PageTableEntry":
        assert phys_addr & ~cls.ADDR_MASK == 0, "address not 4KB aligned"
        return cls((phys_addr & cls.ADDR_MASK) | flags)

    @property
    def present(self) -> bool:
        return bool(self.raw & self.PRESENT)

    @property
    def writable(self) -> bool:
        return bool(self.raw & self.WRITABLE)

    @property
    def user(self) -> bool:
        return bool(self.raw & self.USER)

    @property
    def no_execute(self) -> bool:
        return bool(self.raw & self.NO_EXECUTE)

    @property
    def phys_addr(self) -> int:
        return self.raw & self.ADDR_MASK

    def __repr__(self) -> str:
        flags = ""
        flags += "P" if self.present else "-"
        flags += "W" if self.writable else "R"
        flags += "U" if self.user else "S"
        flags += "NX" if self.no_execute else "X"
        return f"PTE(addr=0x{self.phys_addr:012x}, {flags})"


def test_page_table_entry():
    code = PageTableEntry.new(0x1000, PageTableEntry.PRESENT)
    assert code.present
    assert not code.writable
    assert code.phys_addr == 0x1000

    data = PageTableEntry.new(
        0x200_000,
        PageTableEntry.PRESENT | PageTableEntry.WRITABLE | PageTableEntry.USER | PageTableEntry.NO_EXECUTE,
    )
    assert data.present and data.writable and data.user and data.no_execute
    assert data.phys_addr == 0x200_000

    unmapped = PageTableEntry(0)
    assert not unmapped.present


# ── Virtual Address Decomposition ──────────────────────────────────────
def decompose_vaddr(vaddr: int) -> dict:
    return {
        "pml4":   (vaddr >> 39) & 0x1FF,
        "pdpt":   (vaddr >> 30) & 0x1FF,
        "pd":     (vaddr >> 21) & 0x1FF,
        "pt":     (vaddr >> 12) & 0x1FF,
        "offset": vaddr & 0xFFF,
    }


def test_virtual_address_decompose():
    parts = decompose_vaddr(0x0000_7FFF_FFFF_F000)
    assert parts["pml4"] == 0xFF
    assert parts["pdpt"] == 0x1FF
    assert parts["pd"] == 0x1FF
    assert parts["pt"] == 0x1FF
    assert parts["offset"] == 0

    # Kernel address
    parts = decompose_vaddr(0xFFFF_8000_0000_0000)
    assert parts["pml4"] == 256


# ── MMIO Register ──────────────────────────────────────────────────────
class MmioRegister:
    def __init__(self, name: str, width: int = 32):
        self.name = name
        self.width = width
        self._value = 0

    def read(self) -> int:
        return self._value

    def write(self, val: int) -> None:
        self._value = val & ((1 << self.width) - 1)

    def set_bits(self, mask: int) -> None:
        self.write(self.read() | mask)

    def clear_bits(self, mask: int) -> None:
        self.write(self.read() & ~mask)

    def bit(self, n: int) -> bool:
        return bool(self.read() & (1 << n))


def test_mmio_register():
    ctrl = MmioRegister("UART_CTRL")
    ctrl.set_bits(0b11)  # enable TX and RX
    assert ctrl.read() == 0b11
    assert ctrl.bit(0) and ctrl.bit(1)

    ctrl.clear_bits(0b10)  # disable RX
    assert ctrl.read() == 0b01
    assert ctrl.bit(0) and not ctrl.bit(1)


# ── Interrupt Descriptor Table ─────────────────────────────────────────
class IdtEntry:
    def __init__(self, vector: int, name: str, handler, ist: int = 0):
        self.vector = vector
        self.name = name
        self.handler = handler
        self.ist = ist


class Idt:
    def __init__(self):
        self.entries: dict[int, IdtEntry] = {}

    def register(self, vector: int, name: str, handler, ist: int = 0):
        self.entries[vector] = IdtEntry(vector, name, handler, ist)

    def dispatch(self, vector: int) -> str | None:
        entry = self.entries.get(vector)
        if entry is None:
            return None
        return entry.handler(vector)


def test_interrupt_descriptor_table():
    idt = Idt()
    idt.register(0, "Divide Error", lambda v: "handled: #DE")
    idt.register(8, "Double Fault", lambda v: "handled: #DF", ist=1)
    idt.register(14, "Page Fault", lambda v: "handled: #PF")
    idt.register(32, "Timer", lambda v: "handled: timer")

    assert idt.dispatch(0) == "handled: #DE"
    assert idt.dispatch(14) == "handled: #PF"
    assert idt.dispatch(32) == "handled: timer"
    assert idt.dispatch(255) is None
    assert idt.entries[8].ist > 0, "double fault needs IST"


# ── ABI / Calling Convention ──────────────────────────────────────────
SYSV_INT_REGS = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
SYSCALL_REGS = ["rax", "rdi", "rsi", "rdx", "r10", "r8", "r9"]


def test_abi_calling_convention():
    # SysV AMD64: first 6 integer args in registers
    assert SYSV_INT_REGS[0] == "rdi"
    assert SYSV_INT_REGS[5] == "r9"
    assert len(SYSV_INT_REGS) == 6

    # Linux syscall: number in rax, args in rdi/rsi/rdx/r10/r8/r9
    # Note: r10 replaces rcx (clobbered by syscall instruction)
    assert SYSCALL_REGS[0] == "rax"  # syscall number
    assert SYSCALL_REGS[4] == "r10"  # NOT rcx

    # AArch64 AAPCS: x0-x7 for args, x8 for syscall number
    aarch64_regs = ["x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7"]
    assert len(aarch64_regs) == 8  # more register args than x86_64


# ── GDT Entry ──────────────────────────────────────────────────────────
def decode_gdt_entry(raw: int) -> dict:
    return {
        "present":   bool((raw >> 47) & 1),
        "dpl":       (raw >> 45) & 0x3,
        "long_mode": bool((raw >> 53) & 1),
        "raw":       raw,
    }


def test_gdt_entry():
    null = decode_gdt_entry(0)
    assert not null["present"]

    kernel_code = decode_gdt_entry(0x00AF_9A00_0000_FFFF)
    assert kernel_code["present"]
    assert kernel_code["dpl"] == 0
    assert kernel_code["long_mode"]

    kernel_data = decode_gdt_entry(0x00CF_9200_0000_FFFF)
    assert kernel_data["present"]
    assert kernel_data["dpl"] == 0


# ── ELF Header Parsing ────────────────────────────────────────────────
def parse_elf_ident(data: bytes) -> dict | None:
    if len(data) < 16 or data[:4] != b"\x7fELF":
        return None
    classes = {1: "ELF32", 2: "ELF64"}
    endians = {1: "little", 2: "big"}
    return {
        "magic":   data[:4],
        "class":   classes.get(data[4], "unknown"),
        "endian":  endians.get(data[5], "unknown"),
        "version": data[6],
        "os_abi":  data[7],
    }


def test_elf_header_parsing():
    # Minimal ELF64 little-endian header
    elf_header = b"\x7fELF\x02\x01\x01\x00" + b"\x00" * 8
    info = parse_elf_ident(elf_header)
    assert info is not None
    assert info["class"] == "ELF64"
    assert info["endian"] == "little"
    assert info["version"] == 1

    # Not an ELF
    assert parse_elf_ident(b"not elf") is None
    assert parse_elf_ident(b"") is None


if __name__ == "__main__":
    main()
