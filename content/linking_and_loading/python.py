# Vidya — Linking and Loading in Python
#
# Demonstrates linker concepts by building a simplified linker model:
#   - Object files with symbol tables, sections, and relocations
#   - Symbol resolution: matching references to definitions
#   - Section merging: combining .text and .data from multiple objects
#   - Relocation patching: absolute and PC-relative address fixups
#   - GOT/PLT lazy binding model (conceptual)
#   - Static vs dynamic linking tradeoffs
#
# This is what happens when ld combines .o files into an executable.
# Every symbol reference must resolve to exactly one definition.
# Every relocation must be patched with a computed address.

from enum import Enum, auto


# ── Relocation Types ─────────────────────────────────────────────────
# These mirror the x86_64 ELF relocation types from the ABI spec.

class RelocType(Enum):
    ABS64 = auto()   # R_X86_64_64: absolute 64-bit address
    ABS32 = auto()   # R_X86_64_32S: absolute 32-bit (sign-extended)
    PC32 = auto()    # R_X86_64_PC32: PC-relative 32-bit


# ── Object File Model ────────────────────────────────────────────────

class Section:
    """A section in an object file (.text, .data, .bss)."""
    __slots__ = ("name", "data", "base_addr")

    def __init__(self, name, data):
        self.name = name
        self.data = bytearray(data)
        self.base_addr = None  # filled in by linker layout


class Symbol:
    """A symbol: either a definition (with section+offset) or a reference."""
    __slots__ = ("name", "section", "offset", "is_defined", "resolved_addr")

    def __init__(self, name, section=None, offset=None, is_defined=False):
        self.name = name
        self.section = section
        self.offset = offset
        self.is_defined = is_defined
        self.resolved_addr = None


class Relocation:
    """Patch instruction at (section, offset) with symbol's address."""
    __slots__ = ("section", "offset", "symbol", "reloc_type", "addend")

    def __init__(self, section, offset, symbol, reloc_type, addend=0):
        self.section = section
        self.offset = offset
        self.symbol = symbol
        self.reloc_type = reloc_type
        self.addend = addend


class ObjectFile:
    """A simplified .o file: sections + symbol table + relocation table."""

    def __init__(self, name, sections, symbols, relocations):
        self.name = name
        self.sections = sections
        self.symbols = symbols
        self.relocations = relocations


# ── Linker ───────────────────────────────────────────────────────────

class Linker:
    """
    Two-pass linker:
      Pass 1: Collect symbols from all objects, detect duplicates/undefined
      Pass 2: Layout sections, resolve addresses, apply relocations
    """

    def __init__(self, base_addr):
        self.base_addr = base_addr
        self.objects = []
        self.global_symbols = {}  # name -> (obj_name, section, offset, addr)
        self.placements = []      # (obj_name, sec_name, base_addr, size)

    def add_object(self, obj):
        self.objects.append(obj)

    def collect_symbols(self):
        """Pass 1: Build global symbol table, check for duplicates and undefined refs."""
        for obj in self.objects:
            for sym in obj.symbols:
                if sym.is_defined:
                    if sym.name in self.global_symbols:
                        other = self.global_symbols[sym.name]["defined_in"]
                        raise LinkError(
                            f"duplicate symbol '{sym.name}' "
                            f"(defined in {other} and {obj.name})"
                        )
                    self.global_symbols[sym.name] = {
                        "defined_in": obj.name,
                        "section": sym.section,
                        "offset": sym.offset,
                        "addr": None,
                    }

        # Check for undefined references
        for obj in self.objects:
            for sym in obj.symbols:
                if not sym.is_defined and sym.name not in self.global_symbols:
                    raise LinkError(
                        f"undefined reference to '{sym.name}' in {obj.name}"
                    )

    def layout_sections(self):
        """Place sections contiguously in memory, grouped by section name."""
        addr = self.base_addr

        # All .text first, then all .data (standard linker order)
        for sec_name in [".text", ".data"]:
            for obj in self.objects:
                for sec in obj.sections:
                    if sec.name == sec_name:
                        self.placements.append(
                            (obj.name, sec.name, addr, len(sec.data))
                        )
                        addr += len(sec.data)

        # Resolve symbol addresses: base of section + symbol offset
        for gsym in self.global_symbols.values():
            for obj_name, sec_name, base, _ in self.placements:
                if obj_name == gsym["defined_in"] and sec_name == gsym["section"]:
                    gsym["addr"] = base + gsym["offset"]

    def apply_relocations(self):
        """Pass 2: Patch code bytes with resolved addresses."""
        # Build output by concatenating sections in layout order
        output = bytearray()
        for obj_name, sec_name, _, _ in self.placements:
            obj = next(o for o in self.objects if o.name == obj_name)
            sec = next(s for s in obj.sections if s.name == sec_name)
            output.extend(sec.data)

        # Apply each relocation
        for obj in self.objects:
            for reloc in obj.relocations:
                # Find section base in output
                placement = next(
                    (on, sn, base, sz) for on, sn, base, sz in self.placements
                    if on == obj.name and sn == reloc.section
                )
                sec_base = placement[2]

                # Symbol's resolved address
                sym_info = self.global_symbols.get(reloc.symbol)
                if sym_info is None or sym_info["addr"] is None:
                    raise LinkError(f"unresolved symbol '{reloc.symbol}'")
                sym_addr = sym_info["addr"]

                # File offset in output buffer
                file_offset = (sec_base - self.base_addr) + reloc.offset

                if reloc.reloc_type == RelocType.ABS64:
                    value = sym_addr + reloc.addend
                    output[file_offset:file_offset + 8] = \
                        value.to_bytes(8, "little", signed=True)

                elif reloc.reloc_type == RelocType.ABS32:
                    value = sym_addr + reloc.addend
                    output[file_offset:file_offset + 4] = \
                        (value & 0xFFFFFFFF).to_bytes(4, "little")

                elif reloc.reloc_type == RelocType.PC32:
                    # PC-relative: target - (patch_address + 4)
                    patch_addr = sec_base + reloc.offset
                    value = sym_addr + reloc.addend - (patch_addr + 4)
                    output[file_offset:file_offset + 4] = \
                        value.to_bytes(4, "little", signed=True)

        return output

    def link(self):
        """Run both passes and return the linked binary."""
        self.collect_symbols()
        self.layout_sections()
        return self.apply_relocations()


class LinkError(Exception):
    pass


# ── GOT/PLT Model ───────────────────────────────────────────────────
# In dynamic linking, calls to shared library functions go through:
#   PLT (Procedure Linkage Table) — stub code that jumps through GOT
#   GOT (Global Offset Table) — table of function pointers
#
# Lazy binding: GOT initially points to PLT resolver.
# First call: PLT → GOT → resolver → real function (patches GOT entry).
# Subsequent calls: PLT → GOT → real function (direct, no resolver).

class GotPlt:
    """Simplified GOT/PLT model for dynamic linking."""

    def __init__(self):
        self.got = {}   # symbol -> resolved address (or None for lazy)
        self.plt = {}   # symbol -> PLT stub index
        self.resolver_calls = 0

    def add_import(self, symbol):
        """Register a dynamic symbol (initially unresolved)."""
        idx = len(self.plt)
        self.plt[symbol] = idx
        self.got[symbol] = None  # lazy: not yet resolved

    def resolve(self, symbol, addr):
        """Simulate the dynamic linker resolving a symbol."""
        self.got[symbol] = addr

    def call_through_plt(self, symbol, real_addr):
        """
        Simulate calling a function through PLT/GOT.
        Returns the target address the call reaches.
        """
        got_entry = self.got.get(symbol)

        if got_entry is not None:
            # Already resolved — fast path (GOT has real address)
            return got_entry

        # Lazy binding: first call triggers resolver
        self.resolver_calls += 1
        self.got[symbol] = real_addr  # resolver patches GOT
        return real_addr


# ── Tests ────────────────────────────────────────────────────────────

def main():
    print("Linking and Loading — symbol resolution and relocation:\n")

    # ── Test 1: Basic linking ──────────────────────────────────────
    print("1. Two-pass linking: main.o + math.o")

    main_obj = ObjectFile(
        name="main.o",
        sections=[Section(".text", [
            # mov rdi, 10
            0x48, 0xC7, 0xC7, 0x0A, 0x00, 0x00, 0x00,
            # mov rsi, 32
            0x48, 0xC7, 0xC6, 0x20, 0x00, 0x00, 0x00,
            # call add_numbers (rel32 placeholder)
            0xE8, 0x00, 0x00, 0x00, 0x00,
            # mov [GLOBAL_BASE], rax (abs32 placeholder)
            0x48, 0x89, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00,
            # ret
            0xC3,
        ])],
        symbols=[
            Symbol("main", ".text", 0, is_defined=True),
            Symbol("add_numbers"),        # undefined reference
            Symbol("GLOBAL_BASE"),        # undefined reference
        ],
        relocations=[
            Relocation(".text", 15, "add_numbers", RelocType.PC32),
            Relocation(".text", 23, "GLOBAL_BASE", RelocType.ABS32),
        ],
    )

    math_obj = ObjectFile(
        name="math.o",
        sections=[
            Section(".text", [
                # lea rax, [rdi + rsi]; ret
                0x48, 0x8D, 0x04, 0x37, 0xC3,
            ]),
            Section(".data", [0x00] * 8),  # GLOBAL_BASE: 8 zero bytes
        ],
        symbols=[
            Symbol("add_numbers", ".text", 0, is_defined=True),
            Symbol("GLOBAL_BASE", ".data", 0, is_defined=True),
        ],
        relocations=[],
    )

    base_addr = 0x400000
    linker = Linker(base_addr)
    linker.add_object(main_obj)
    linker.add_object(math_obj)
    output = linker.link()

    # Verify the binary was produced
    # main.o .text = 28 bytes, math.o .text = 5 bytes, math.o .data = 8 bytes
    assert len(output) == 28 + 5 + 8, f"expected 41 bytes, got {len(output)}"
    print(f"   Linked binary: {len(output)} bytes")

    # Verify CALL relocation (PC-relative)
    call_offset = 15
    patched_rel32 = int.from_bytes(output[call_offset:call_offset + 4], "little", signed=True)
    call_site = base_addr + call_offset + 4  # PC after CALL
    target = call_site + patched_rel32
    assert target == base_addr + 28, \
        f"CALL should target 0x{base_addr + 28:X}, got 0x{target:X}"
    print(f"   CALL rel32 = {patched_rel32} -> target 0x{target:X}")

    # Verify ABS32 relocation
    abs_offset = 23
    patched_abs32 = int.from_bytes(output[abs_offset:abs_offset + 4], "little")
    expected_data_addr = base_addr + 28 + 5  # after both .text sections
    assert patched_abs32 == expected_data_addr, \
        f"ABS32 should be 0x{expected_data_addr:X}, got 0x{patched_abs32:X}"
    print(f"   GLOBAL_BASE = 0x{patched_abs32:X}")

    # ── Test 2: Symbol resolution errors ───────────────────────────
    print("\n2. Link errors: duplicate and undefined symbols")

    # Duplicate symbol
    dup_obj1 = ObjectFile("a.o", [Section(".text", [0xC3])],
                          [Symbol("foo", ".text", 0, is_defined=True)], [])
    dup_obj2 = ObjectFile("b.o", [Section(".text", [0xC3])],
                          [Symbol("foo", ".text", 0, is_defined=True)], [])
    dup_linker = Linker(0x400000)
    dup_linker.add_object(dup_obj1)
    dup_linker.add_object(dup_obj2)
    try:
        dup_linker.link()
        assert False, "should have raised LinkError for duplicate"
    except LinkError as e:
        assert "duplicate" in str(e)
        print(f"   Caught: {e}")

    # Undefined symbol
    undef_obj = ObjectFile("c.o", [Section(".text", [0xC3])],
                           [Symbol("nonexistent")], [])
    undef_linker = Linker(0x400000)
    undef_linker.add_object(undef_obj)
    try:
        undef_linker.link()
        assert False, "should have raised LinkError for undefined"
    except LinkError as e:
        assert "undefined" in str(e)
        print(f"   Caught: {e}")

    # ── Test 3: Section merging ────────────────────────────────────
    print("\n3. Section merging: .text then .data")

    obj_a = ObjectFile("a.o",
                       [Section(".text", [0x90] * 10), Section(".data", [0x01] * 4)],
                       [Symbol("a_func", ".text", 0, is_defined=True)], [])
    obj_b = ObjectFile("b.o",
                       [Section(".text", [0xCC] * 6), Section(".data", [0x02] * 8)],
                       [Symbol("b_func", ".text", 0, is_defined=True)], [])

    merge_linker = Linker(0x400000)
    merge_linker.add_object(obj_a)
    merge_linker.add_object(obj_b)
    merge_linker.collect_symbols()
    merge_linker.layout_sections()

    # .text sections first, then .data sections
    assert merge_linker.placements[0] == ("a.o", ".text", 0x400000, 10)
    assert merge_linker.placements[1] == ("b.o", ".text", 0x40000A, 6)
    assert merge_linker.placements[2] == ("a.o", ".data", 0x400010, 4)
    assert merge_linker.placements[3] == ("b.o", ".data", 0x400014, 8)
    print(f"   Layout: {len(merge_linker.placements)} sections placed")
    for obj_name, sec_name, base, size in merge_linker.placements:
        print(f"     {obj_name}:{sec_name} at 0x{base:X} ({size} bytes)")

    # Verify symbols resolved to correct addresses
    assert merge_linker.global_symbols["a_func"]["addr"] == 0x400000
    assert merge_linker.global_symbols["b_func"]["addr"] == 0x40000A
    print(f"   a_func = 0x{merge_linker.global_symbols['a_func']['addr']:X}")
    print(f"   b_func = 0x{merge_linker.global_symbols['b_func']['addr']:X}")

    # ── Test 4: GOT/PLT lazy binding ──────────────────────────────
    print("\n4. GOT/PLT lazy binding:")

    got_plt = GotPlt()
    got_plt.add_import("printf")
    got_plt.add_import("malloc")

    # First call: triggers resolver (lazy binding)
    printf_addr = 0x7FFFF7A00000
    result1 = got_plt.call_through_plt("printf", printf_addr)
    assert result1 == printf_addr
    assert got_plt.resolver_calls == 1
    print(f"   First call to printf: resolver invoked, GOT patched -> 0x{result1:X}")

    # Second call: GOT already patched (fast path)
    result2 = got_plt.call_through_plt("printf", printf_addr)
    assert result2 == printf_addr
    assert got_plt.resolver_calls == 1  # resolver NOT called again
    print(f"   Second call to printf: direct through GOT -> 0x{result2:X}")

    # Different symbol: triggers resolver again
    malloc_addr = 0x7FFFF7A80000
    result3 = got_plt.call_through_plt("malloc", malloc_addr)
    assert result3 == malloc_addr
    assert got_plt.resolver_calls == 2
    print(f"   First call to malloc: resolver invoked -> 0x{result3:X}")
    print(f"   Total resolver calls: {got_plt.resolver_calls}")

    # ── Test 5: Static vs dynamic linking comparison ───────────────
    print("\n5. Static vs dynamic linking tradeoffs:")

    static_props = {
        "self_contained": True,     # no runtime dependencies
        "larger_binary": True,      # includes all library code
        "faster_startup": True,     # no dynamic loader overhead
        "no_symbol_interposition": True,  # calls are direct
        "security_updates_require_relink": True,
    }
    dynamic_props = {
        "shared_memory": True,      # multiple processes share .so in RAM
        "smaller_binary": True,     # only references, not code
        "symbol_interposition": True,  # LD_PRELOAD works
        "runtime_dependency": True,    # needs .so at runtime
        "plt_overhead": True,          # indirect calls through GOT/PLT
    }

    assert static_props["self_contained"] is True
    assert dynamic_props["shared_memory"] is True
    assert static_props["faster_startup"] is True
    assert dynamic_props["plt_overhead"] is True
    print("   Static: self-contained, larger binary, faster startup")
    print("   Dynamic: shared memory, smaller binary, PLT overhead")

    # ── Test 6: Relocation type semantics ─────────────────────────
    print("\n6. Relocation type formulas:")

    # R_X86_64_64:   S + A (absolute 64-bit)
    # R_X86_64_32S:  S + A (truncated to 32-bit, sign-extended check)
    # R_X86_64_PC32: S + A - P (PC-relative, P = patch address)

    sym_addr = 0x401000
    addend = 0
    patch_addr = 0x400100

    abs64 = sym_addr + addend
    assert abs64 == 0x401000, "ABS64 = S + A"

    pc32 = sym_addr + addend - (patch_addr + 4)  # P includes +4 for instruction size
    assert pc32 == 0xEFC, "PC32 = S + A - (P + 4)"
    print(f"   ABS64: S(0x{sym_addr:X}) + A({addend}) = 0x{abs64:X}")
    print(f"   PC32:  S(0x{sym_addr:X}) + A({addend}) - P(0x{patch_addr + 4:X}) = 0x{pc32:X}")

    print("\nAll linking and loading examples passed.")


if __name__ == "__main__":
    main()
