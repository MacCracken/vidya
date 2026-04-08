# Vidya — Binary Formats in Python
#
# Compares binary executable formats across operating systems:
#   1. ELF (Linux/BSD) — header, magic, minimal binary construction
#   2. PE (Windows) — DOS stub, PE signature, COFF header
#   3. Mach-O (macOS) — magic, fat binaries, load commands
#   4. Builds a minimal ELF binary in Python (ehdr + phdr + code)
#   5. Verifies all magic numbers, field offsets, and sizes
#
# Every OS has its own binary format, but they solve the same problems:
#   - Identify the file type (magic number)
#   - Describe memory layout (segments/sections/load commands)
#   - Specify the entry point (where execution starts)

import struct

# ── Magic Numbers ────────────────────────────────────────────────────
# The first bytes of every binary identify the format.
# The OS kernel checks these before loading.

ELF_MAGIC = b'\x7fELF'                    # ELF: 4 bytes
PE_DOS_MAGIC = b'MZ'                       # PE: starts with DOS stub
PE_SIGNATURE = b'PE\x00\x00'              # PE: after DOS stub
MACHO_MAGIC_64 = 0xFEEDFACF               # Mach-O 64-bit (little-endian)
MACHO_MAGIC_32 = 0xFEEDFACE               # Mach-O 32-bit
MACHO_FAT_MAGIC = 0xCAFEBABE              # Universal binary (fat)

# ── ELF Constants ────────────────────────────────────────────────────

ELFCLASS64 = 2
ELFDATA2LSB = 1
ET_EXEC = 2
EM_X86_64 = 0x3E
PT_LOAD = 1
PF_X = 1
PF_W = 2
PF_R = 4

ELF64_EHDR_SIZE = 64
ELF64_PHDR_SIZE = 56


# ── Format Comparison ────────────────────────────────────────────────

def compare_formats():
    """Compare ELF, PE, and Mach-O binary formats."""

    formats = {
        "ELF": {
            "os": "Linux, BSD, Solaris",
            "magic": b'\x7fELF',
            "magic_size": 4,
            "header_size": 64,            # ELF64 header
            "segment_desc": "Program headers (PT_LOAD)",
            "section_desc": "Section headers (optional for execution)",
            "entry_field": "e_entry (offset 24, u64)",
            "min_overhead": 120,          # 64 ehdr + 56 phdr
        },
        "PE": {
            "os": "Windows",
            "magic": b'MZ',
            "magic_size": 2,
            "header_size": 64 + 24 + 112,  # DOS header + COFF + optional (PE32+)
            "segment_desc": "Section table (.text, .data, .rdata)",
            "section_desc": "Same as segments (no segment/section split)",
            "entry_field": "AddressOfEntryPoint (COFF optional header)",
            "min_overhead": 512,          # DOS stub + PE headers
        },
        "Mach-O": {
            "os": "macOS, iOS",
            "magic": struct.pack('<I', MACHO_MAGIC_64),
            "magic_size": 4,
            "header_size": 32,            # Mach-O 64-bit header
            "segment_desc": "Load commands (LC_SEGMENT_64)",
            "section_desc": "Sections within segments",
            "entry_field": "LC_MAIN (entry point offset)",
            "min_overhead": 200,          # header + load commands
        },
    }

    # Verify magic numbers are distinct
    magics = [f["magic"] for f in formats.values()]
    assert len(set(magics)) == 3, "all format magics must be unique"

    # ELF has the smallest minimum overhead
    assert formats["ELF"]["min_overhead"] < formats["PE"]["min_overhead"]
    assert formats["ELF"]["min_overhead"] < formats["Mach-O"]["min_overhead"]

    return formats


# ── ELF Header Construction ─────────────────────────────────────────

def build_elf64_header(entry, phoff, phnum):
    """Build a 64-byte ELF64 header."""
    e_ident = bytearray(16)
    e_ident[0:4] = ELF_MAGIC
    e_ident[4] = ELFCLASS64
    e_ident[5] = ELFDATA2LSB
    e_ident[6] = 1  # EV_CURRENT

    header = struct.pack(
        '<16sHHIQQQIHHHHHH',
        bytes(e_ident),
        ET_EXEC,            # e_type
        EM_X86_64,          # e_machine
        1,                  # e_version
        entry,              # e_entry
        phoff,              # e_phoff
        0,                  # e_shoff (no sections)
        0,                  # e_flags
        ELF64_EHDR_SIZE,    # e_ehsize
        ELF64_PHDR_SIZE,    # e_phentsize
        phnum,              # e_phnum
        64,                 # e_shentsize
        0,                  # e_shnum
        0,                  # e_shstrndx
    )
    return header


def build_program_header(p_type, p_flags, p_offset, p_vaddr, p_filesz,
                         p_memsz, p_align):
    """Build a 56-byte ELF64 program header."""
    return struct.pack(
        '<IIQQQQQQ',
        p_type,
        p_flags,
        p_offset,
        p_vaddr,
        p_vaddr,    # p_paddr = p_vaddr
        p_filesz,
        p_memsz,
        p_align,
    )


# ── Build a Minimal ELF Binary ──────────────────────────────────────
# The smallest valid Linux executable: ehdr + phdr + exit(0) code.
# No libc, no linker, no sections. Just headers and machine code.

def build_minimal_elf_binary():
    """Build a complete minimal ELF binary that exits with code 0."""
    base_addr = 0x400000
    code_offset = ELF64_EHDR_SIZE + ELF64_PHDR_SIZE  # 120

    # x86_64 machine code: exit(0)
    # xor edi, edi       — exit code 0 (2 bytes, shorter than mov)
    # mov eax, 60        — syscall number for exit (5 bytes)
    # syscall            — invoke kernel (2 bytes)
    code = bytes([
        0x31, 0xFF,                                  # xor edi, edi
        0xB8, 0x3C, 0x00, 0x00, 0x00,              # mov eax, 60
        0x0F, 0x05,                                  # syscall
    ])

    entry = base_addr + code_offset
    total_size = code_offset + len(code)

    ehdr = build_elf64_header(entry, ELF64_EHDR_SIZE, 1)
    phdr = build_program_header(
        PT_LOAD, PF_R | PF_X, 0, base_addr, total_size, total_size, 0x1000
    )

    binary = ehdr + phdr + code
    return binary, entry, total_size


# ── PE Format Internals ──────────────────────────────────────────────
# PE (Portable Executable) starts with a DOS stub for backward compat.
# The real PE header is at the offset stored at DOS offset 0x3C.

def verify_pe_structure():
    """Verify PE format constants and structure."""

    # DOS header magic
    assert PE_DOS_MAGIC == b'MZ', "PE starts with MZ (Mark Zbikowski)"

    # PE signature
    assert PE_SIGNATURE == b'PE\x00\x00', "PE signature is PE\\0\\0"

    # The DOS header is 64 bytes. At offset 0x3C (60), a u32 points
    # to the PE signature. Everything between is the DOS stub.
    pe_sig_offset_field = 0x3C
    assert pe_sig_offset_field == 60

    # COFF header (after PE signature): 20 bytes
    coff_header_size = 20

    # Optional header for PE32+: 112 bytes (PE32 = 96 bytes)
    pe32plus_optional_size = 112

    # Machine types
    IMAGE_FILE_MACHINE_AMD64 = 0x8664
    IMAGE_FILE_MACHINE_I386 = 0x14C
    IMAGE_FILE_MACHINE_ARM64 = 0xAA64

    assert IMAGE_FILE_MACHINE_AMD64 == 0x8664
    assert IMAGE_FILE_MACHINE_ARM64 == 0xAA64

    # Typical PE minimum: DOS stub (128) + PE sig (4) + COFF (20)
    # + optional (112) + 1 section header (40) = 304 bytes minimum
    min_pe_headers = 128 + 4 + coff_header_size + pe32plus_optional_size + 40
    assert min_pe_headers == 304

    return coff_header_size, pe32plus_optional_size


# ── Mach-O Format Internals ─────────────────────────────────────────
# Mach-O uses "load commands" instead of program headers.
# Each load command tells the kernel how to set up the process.

def verify_macho_structure():
    """Verify Mach-O format constants and structure."""

    # Mach-O magic numbers
    assert MACHO_MAGIC_64 == 0xFEEDFACF, "64-bit Mach-O magic"
    assert MACHO_MAGIC_32 == 0xFEEDFACE, "32-bit Mach-O magic"
    assert MACHO_FAT_MAGIC == 0xCAFEBABE, "fat/universal binary magic"

    # Mach-O 64-bit header: 32 bytes
    macho64_header_size = 32
    # Fields: magic(4) + cputype(4) + cpusubtype(4) + filetype(4)
    #       + ncmds(4) + sizeofcmds(4) + flags(4) + reserved(4)
    field_sum = 4 + 4 + 4 + 4 + 4 + 4 + 4 + 4
    assert field_sum == macho64_header_size

    # Load command types
    LC_SEGMENT_64 = 0x19     # map file content into address space
    LC_MAIN = 0x80000028     # entry point (replaces LC_UNIXTHREAD)
    LC_DYLD_INFO = 0x80000022  # dynamic linker info
    LC_SYMTAB = 0x02         # symbol table

    assert LC_SEGMENT_64 == 25
    assert LC_MAIN == 0x80000028

    # CPU types
    CPU_TYPE_X86_64 = 0x01000007
    CPU_TYPE_ARM64 = 0x0100000C

    assert CPU_TYPE_X86_64 == 16777223
    assert CPU_TYPE_ARM64 == 16777228

    return macho64_header_size


# ── Format Comparison: Segment Models ────────────────────────────────

def compare_segment_models():
    """Compare how each format describes memory layout."""

    # ELF: program headers describe segments (runtime view)
    #   PT_LOAD  — map file range to memory with permissions
    #   PT_INTERP — path to dynamic linker
    #   PT_DYNAMIC — dynamic linking info
    elf_segment_types = {
        "PT_LOAD": 1,
        "PT_DYNAMIC": 2,
        "PT_INTERP": 3,
        "PT_NOTE": 4,
        "PT_PHDR": 6,
    }

    # PE: section table (no segment/section duality)
    #   .text  — code (R+X)
    #   .data  — initialized data (R+W)
    #   .rdata — read-only data (R)
    #   .bss   — uninitialized data (R+W, no file space)
    pe_sections = [".text", ".data", ".rdata", ".bss", ".idata", ".reloc"]

    # Mach-O: load commands (each is a different command type)
    #   LC_SEGMENT_64 — map file to memory (like PT_LOAD)
    #   Segments contain sections (like ELF)
    #   __TEXT segment → __text, __stubs, __stub_helper sections
    #   __DATA segment → __data, __bss, __la_symbol_ptr sections
    macho_segments = {
        "__TEXT": ["__text", "__stubs", "__stub_helper", "__cstring"],
        "__DATA": ["__data", "__bss", "__la_symbol_ptr"],
        "__LINKEDIT": [],  # linker metadata (no sections)
    }

    # Key insight: ELF separates sections (linker) from segments (loader).
    # PE merges them — sections ARE the load units.
    # Mach-O has segments containing sections (hierarchical).
    assert len(elf_segment_types) == 5
    assert len(pe_sections) == 6
    assert len(macho_segments) == 3


# ── Static vs Dynamic Linking ────────────────────────────────────────

def compare_linking():
    """Compare static and dynamic linking across formats."""

    linking = {
        "ELF": {
            "static": "All code in one binary, no PT_DYNAMIC or PT_INTERP",
            "dynamic_loader": "/lib64/ld-linux-x86-64.so.2 (PT_INTERP)",
            "shared_libs": ".so files, loaded at runtime",
            "symbol_resolution": "GOT/PLT (lazy or eager)",
        },
        "PE": {
            "static": "All code in .exe, no imports",
            "dynamic_loader": "ntdll.dll (always loaded by kernel)",
            "shared_libs": ".dll files, loaded at runtime",
            "symbol_resolution": "Import Address Table (IAT)",
        },
        "Mach-O": {
            "static": "All code in binary (rare on macOS)",
            "dynamic_loader": "/usr/lib/dyld (LC_LOAD_DYLINKER)",
            "shared_libs": ".dylib files",
            "symbol_resolution": "lazy binding via dyld_stub_binder",
        },
    }

    # A static ELF has no PT_INTERP and no PT_DYNAMIC
    # A dynamic ELF has both
    assert len(linking) == 3

    return linking


def main():
    print("Binary Formats — cross-platform comparison:\n")

    # ── Magic numbers ──────────────────────────────────────────────────
    print("1. Magic numbers:")
    print(f"   ELF:    {ELF_MAGIC!r} ({' '.join(f'0x{b:02X}' for b in ELF_MAGIC)})")
    print(f"   PE:     {PE_DOS_MAGIC!r} (0x{PE_DOS_MAGIC[0]:02X} 0x{PE_DOS_MAGIC[1]:02X})")
    print(f"   PE sig: {PE_SIGNATURE!r}")
    print(f"   Mach-O: 0x{MACHO_MAGIC_64:08X} (64-bit)")
    print(f"   Fat:    0x{MACHO_FAT_MAGIC:08X} (universal)")

    assert ELF_MAGIC == b'\x7fELF'
    assert PE_DOS_MAGIC == b'MZ'
    assert MACHO_MAGIC_64 == 0xFEEDFACF

    # ── Format comparison ──────────────────────────────────────────────
    print("\n2. Format comparison:")
    formats = compare_formats()
    for name, info in formats.items():
        print(f"   {name}: {info['os']}")
        print(f"     Header:   {info['header_size']} bytes")
        print(f"     Segments: {info['segment_desc']}")
        print(f"     Min overhead: {info['min_overhead']} bytes")

    # ── Build minimal ELF ──────────────────────────────────────────────
    print("\n3. Minimal ELF binary (exit(0)):")
    binary, entry, total_size = build_minimal_elf_binary()

    # Verify magic
    assert binary[0:4] == ELF_MAGIC
    print(f"   Magic: verified ({binary[0:4]!r})")

    # Verify sizes
    assert len(binary) == total_size
    code_size = total_size - 120
    print(f"   Size: {total_size} bytes (120 headers + {code_size} code)")

    # Verify entry point
    e_entry = struct.unpack_from('<Q', binary, 24)[0]
    assert e_entry == entry
    print(f"   Entry: 0x{entry:X}")

    # Verify program header
    p_type = struct.unpack_from('<I', binary, 64)[0]
    assert p_type == PT_LOAD
    p_flags = struct.unpack_from('<I', binary, 68)[0]
    assert p_flags == (PF_R | PF_X)
    print(f"   Segment: PT_LOAD, flags=R+X")

    # Verify code location
    assert binary[120] == 0x31, "first code byte: xor edi,edi"
    assert binary[127] == 0x0F, "syscall prefix"
    assert binary[128] == 0x05, "syscall"
    print(f"   Code: xor edi,edi; mov eax,60; syscall")

    # ── PE structure ───────────────────────────────────────────────────
    print("\n4. PE (Windows) structure:")
    coff_size, opt_size = verify_pe_structure()
    print(f"   DOS stub: starts with 'MZ', PE offset at 0x3C")
    print(f"   COFF header: {coff_size} bytes")
    print(f"   Optional header (PE32+): {opt_size} bytes")
    print(f"   Section header: 40 bytes each")

    # ── Mach-O structure ───────────────────────────────────────────────
    print("\n5. Mach-O (macOS) structure:")
    macho_hdr = verify_macho_structure()
    print(f"   Header: {macho_hdr} bytes (64-bit)")
    print(f"   Magic: 0x{MACHO_MAGIC_64:08X}")
    print(f"   Uses load commands instead of program headers")
    print(f"   LC_SEGMENT_64 maps file to memory (like PT_LOAD)")

    # ── Segment models ─────────────────────────────────────────────────
    print("\n6. Segment models:")
    compare_segment_models()
    print("   ELF:    segments (loader) vs sections (linker) — dual view")
    print("   PE:     sections ARE the load units — no duality")
    print("   Mach-O: segments contain sections — hierarchical")

    # ── Linking comparison ─────────────────────────────────────────────
    print("\n7. Static vs dynamic linking:")
    linking = compare_linking()
    for fmt, info in linking.items():
        print(f"   {fmt}: {info['dynamic_loader']}")

    # ── Size comparison ────────────────────────────────────────────────
    print("\n8. Minimum binary sizes:")
    print(f"   {'Format':<12} {'Min overhead':>14} {'Typical hello':>14}")
    print(f"   {'------':<12} {'-------------':>14} {'-------------':>14}")
    print(f"   {'ELF':<12} {'120 B':>14} {'~200 B':>14}")
    print(f"   {'PE':<12} {'~512 B':>14} {'~4 KB':>14}")
    print(f"   {'Mach-O':<12} {'~200 B':>14} {'~16 KB':>14}")

    print("\nAll binary format examples passed.")


if __name__ == "__main__":
    main()
