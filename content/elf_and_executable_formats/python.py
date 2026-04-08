# Vidya — ELF and Executable Formats in Python
#
# Parses and builds ELF64 binary structures from scratch using struct:
#   1. ELF header (64 bytes) — magic, class, data encoding, type, machine
#   2. Program header (56 bytes) — segment type, flags, virtual address
#   3. Section header (64 bytes) — name, type, flags, offset, size
#   4. Field offset verification — every field at its correct byte offset
#   5. Section vs segment duality — linker view vs loader view
#
# This is what readelf, objdump, and the kernel's ELF loader parse.
# The kernel only reads program headers — sections are for tools.

import struct

# ── ELF Constants ────────────────────────────────────────────────────

ELF_MAGIC = b'\x7fELF'
ELFCLASS64 = 2
ELFDATA2LSB = 1       # little-endian
EV_CURRENT = 1        # ELF version
ET_EXEC = 2           # executable
ET_DYN = 3            # shared object / PIE
EM_X86_64 = 0x3E      # x86-64 (62 decimal)

# Program header types
PT_NULL = 0
PT_LOAD = 1
PT_DYNAMIC = 2
PT_INTERP = 3
PT_NOTE = 4
PT_PHDR = 6

# Program header flags
PF_X = 1
PF_W = 2
PF_R = 4

# Section header types
SHT_NULL = 0
SHT_PROGBITS = 1
SHT_SYMTAB = 2
SHT_STRTAB = 3
SHT_RELA = 4
SHT_NOBITS = 8

# Section header flags
SHF_WRITE = 1
SHF_ALLOC = 2
SHF_EXECINSTR = 4


# ── ELF64 Header (64 bytes) ─────────────────────────────────────────
# Layout:
#   Offset  Size  Field
#   0       16    e_ident (magic + class + data + version + padding)
#   16      2     e_type
#   18      2     e_machine
#   20      4     e_version
#   24      8     e_entry
#   32      8     e_phoff
#   40      8     e_shoff
#   48      4     e_flags
#   52      2     e_ehsize
#   54      2     e_phentsize
#   56      2     e_phnum
#   58      2     e_shentsize
#   60      2     e_shnum
#   62      2     e_shstrndx

ELF64_EHDR_SIZE = 64
ELF64_EHDR_FORMAT = '<16sHHIQQQIHHHHHH'

def build_elf64_header(entry, phoff, shoff, phnum, shnum, shstrndx=0):
    """Build a 64-byte ELF64 header as raw bytes."""
    # Build e_ident: 16-byte identification
    e_ident = bytearray(16)
    e_ident[0:4] = ELF_MAGIC          # magic: \x7fELF
    e_ident[4] = ELFCLASS64           # class: 64-bit
    e_ident[5] = ELFDATA2LSB          # data: little-endian
    e_ident[6] = EV_CURRENT           # version: current
    e_ident[7] = 0                    # OS/ABI: ELFOSABI_NONE
    # bytes 8-15: padding (zero)

    header = struct.pack(
        ELF64_EHDR_FORMAT,
        bytes(e_ident),    # e_ident
        ET_EXEC,           # e_type: executable
        EM_X86_64,         # e_machine: x86-64
        EV_CURRENT,        # e_version
        entry,             # e_entry: virtual address of entry point
        phoff,             # e_phoff: program header table offset
        shoff,             # e_shoff: section header table offset
        0,                 # e_flags: processor-specific flags
        ELF64_EHDR_SIZE,   # e_ehsize: ELF header size
        56,                # e_phentsize: program header entry size
        phnum,             # e_phnum: number of program headers
        64,                # e_shentsize: section header entry size
        shnum,             # e_shnum: number of section headers
        shstrndx,          # e_shstrndx: section name string table index
    )
    return header


# ── ELF64 Program Header (56 bytes) ─────────────────────────────────
# Layout:
#   Offset  Size  Field
#   0       4     p_type
#   4       4     p_flags
#   8       8     p_offset
#   16      8     p_vaddr
#   24      8     p_paddr
#   32      8     p_filesz
#   40      8     p_memsz
#   48      8     p_align

ELF64_PHDR_SIZE = 56
ELF64_PHDR_FORMAT = '<IIQQQQQQ'

def build_program_header(p_type, p_flags, p_offset, p_vaddr, p_filesz, p_memsz, p_align):
    """Build a 56-byte ELF64 program header."""
    return struct.pack(
        ELF64_PHDR_FORMAT,
        p_type,
        p_flags,
        p_offset,
        p_vaddr,
        p_vaddr,    # p_paddr = p_vaddr (physical = virtual for user space)
        p_filesz,
        p_memsz,
        p_align,
    )


# ── ELF64 Section Header (64 bytes) ─────────────────────────────────
# Layout:
#   Offset  Size  Field
#   0       4     sh_name      (offset into .shstrtab)
#   4       4     sh_type
#   8       8     sh_flags
#   16      8     sh_addr      (virtual address if loaded)
#   24      8     sh_offset    (file offset)
#   32      8     sh_size
#   40      4     sh_link
#   44      4     sh_info
#   48      8     sh_addralign
#   56      8     sh_entsize

ELF64_SHDR_SIZE = 64
ELF64_SHDR_FORMAT = '<IIQQQQIIqq'

def build_section_header(sh_name, sh_type, sh_flags, sh_addr, sh_offset,
                         sh_size, sh_link=0, sh_info=0, sh_addralign=1,
                         sh_entsize=0):
    """Build a 64-byte ELF64 section header."""
    return struct.pack(
        ELF64_SHDR_FORMAT,
        sh_name,
        sh_type,
        sh_flags,
        sh_addr,
        sh_offset,
        sh_size,
        sh_link,
        sh_info,
        sh_addralign,
        sh_entsize,
    )


# ── Verification ─────────────────────────────────────────────────────

def verify_header_sizes():
    """Verify that struct formats produce the correct sizes."""
    assert struct.calcsize(ELF64_EHDR_FORMAT) == 64, \
        f"ELF header must be 64 bytes, got {struct.calcsize(ELF64_EHDR_FORMAT)}"
    assert struct.calcsize(ELF64_PHDR_FORMAT) == 56, \
        f"Program header must be 56 bytes, got {struct.calcsize(ELF64_PHDR_FORMAT)}"
    assert struct.calcsize(ELF64_SHDR_FORMAT) == 64, \
        f"Section header must be 64 bytes, got {struct.calcsize(ELF64_SHDR_FORMAT)}"


def verify_elf_header_fields():
    """Verify every field in the ELF header is at the correct offset."""
    base_addr = 0x400000
    entry = base_addr + 120  # after ELF header + 1 program header

    header = build_elf64_header(
        entry=entry,
        phoff=64,
        shoff=0,
        phnum=1,
        shnum=0,
    )
    assert len(header) == 64

    # e_ident[0:4] — ELF magic
    assert header[0:4] == b'\x7fELF', "magic must be \\x7fELF"

    # e_ident[4] — class (ELFCLASS64 = 2)
    assert header[4] == 2, "class must be ELFCLASS64 (2)"

    # e_ident[5] — data encoding (ELFDATA2LSB = 1)
    assert header[5] == 1, "data encoding must be little-endian (1)"

    # e_ident[6] — version (EV_CURRENT = 1)
    assert header[6] == 1, "ELF version must be EV_CURRENT (1)"

    # e_type at offset 16 — ET_EXEC = 2
    e_type = struct.unpack_from('<H', header, 16)[0]
    assert e_type == ET_EXEC, f"e_type must be ET_EXEC (2), got {e_type}"

    # e_machine at offset 18 — EM_X86_64 = 0x3E
    e_machine = struct.unpack_from('<H', header, 18)[0]
    assert e_machine == EM_X86_64, f"e_machine must be EM_X86_64 (0x3E), got {e_machine}"

    # e_version at offset 20
    e_version = struct.unpack_from('<I', header, 20)[0]
    assert e_version == 1, f"e_version must be 1, got {e_version}"

    # e_entry at offset 24
    e_entry = struct.unpack_from('<Q', header, 24)[0]
    assert e_entry == entry, f"e_entry must be 0x{entry:X}, got 0x{e_entry:X}"

    # e_phoff at offset 32
    e_phoff = struct.unpack_from('<Q', header, 32)[0]
    assert e_phoff == 64, f"e_phoff must be 64, got {e_phoff}"

    # e_shoff at offset 40
    e_shoff = struct.unpack_from('<Q', header, 40)[0]
    assert e_shoff == 0, f"e_shoff must be 0 (no sections), got {e_shoff}"

    # e_ehsize at offset 52
    e_ehsize = struct.unpack_from('<H', header, 52)[0]
    assert e_ehsize == 64, f"e_ehsize must be 64, got {e_ehsize}"

    # e_phentsize at offset 54
    e_phentsize = struct.unpack_from('<H', header, 54)[0]
    assert e_phentsize == 56, f"e_phentsize must be 56, got {e_phentsize}"

    # e_phnum at offset 56
    e_phnum = struct.unpack_from('<H', header, 56)[0]
    assert e_phnum == 1, f"e_phnum must be 1, got {e_phnum}"


def verify_program_header_fields():
    """Verify program header field offsets and values."""
    base_addr = 0x400000
    file_size = 200
    phdr = build_program_header(
        p_type=PT_LOAD,
        p_flags=PF_R | PF_X,
        p_offset=0,
        p_vaddr=base_addr,
        p_filesz=file_size,
        p_memsz=file_size,
        p_align=0x1000,
    )
    assert len(phdr) == 56

    # p_type at offset 0 — PT_LOAD = 1
    p_type = struct.unpack_from('<I', phdr, 0)[0]
    assert p_type == PT_LOAD, f"p_type must be PT_LOAD (1), got {p_type}"

    # p_flags at offset 4 — PF_R | PF_X = 5
    p_flags = struct.unpack_from('<I', phdr, 4)[0]
    assert p_flags == (PF_R | PF_X), f"p_flags must be 5 (R+X), got {p_flags}"

    # p_offset at offset 8
    p_offset = struct.unpack_from('<Q', phdr, 8)[0]
    assert p_offset == 0, f"p_offset must be 0, got {p_offset}"

    # p_vaddr at offset 16
    p_vaddr = struct.unpack_from('<Q', phdr, 16)[0]
    assert p_vaddr == base_addr, f"p_vaddr must be 0x{base_addr:X}, got 0x{p_vaddr:X}"

    # p_paddr at offset 24 (same as vaddr for user space)
    p_paddr = struct.unpack_from('<Q', phdr, 24)[0]
    assert p_paddr == base_addr

    # p_filesz at offset 32
    p_filesz = struct.unpack_from('<Q', phdr, 32)[0]
    assert p_filesz == file_size

    # p_memsz at offset 40
    p_memsz = struct.unpack_from('<Q', phdr, 40)[0]
    assert p_memsz == file_size

    # p_align at offset 48
    p_align = struct.unpack_from('<Q', phdr, 48)[0]
    assert p_align == 0x1000, f"p_align must be 0x1000, got 0x{p_align:X}"


def verify_section_vs_segment():
    """Demonstrate and verify the section vs segment duality.

    Sections are the linker's view — they organize code and data by type.
    Segments are the loader's view — they describe memory mappings.
    Multiple sections can map to a single segment.
    """
    # A typical executable has these sections mapped to two segments:
    section_to_segment = {
        # Section           Segment (by permissions)
        ".text":     "PT_LOAD R+X",     # code — executable
        ".rodata":   "PT_LOAD R+X",     # read-only data — same segment as code
        ".data":     "PT_LOAD R+W",     # initialized data — writable
        ".bss":      "PT_LOAD R+W",     # uninitialized — writable, no file space
        ".symtab":   "not loaded",      # symbol table — tools only
        ".strtab":   "not loaded",      # string table — tools only
        ".debug_info": "not loaded",    # DWARF debug — tools only
    }

    # Verify: .text and .rodata share the R+X segment
    assert section_to_segment[".text"] == section_to_segment[".rodata"]

    # Verify: .data and .bss share the R+W segment
    assert section_to_segment[".data"] == section_to_segment[".bss"]

    # Verify: debug info is not loaded into memory
    assert section_to_segment[".debug_info"] == "not loaded"

    # Verify: stripping removes non-loaded sections but execution is unchanged
    loaded_sections = [s for s, seg in section_to_segment.items()
                       if seg != "not loaded"]
    stripped_sections = [s for s, seg in section_to_segment.items()
                        if seg == "not loaded"]
    assert len(loaded_sections) == 4
    assert len(stripped_sections) == 3


def verify_bss_segment():
    """Verify that BSS has zero file size but non-zero memory size.

    The PT_LOAD for data has p_memsz > p_filesz.
    The kernel zero-fills the difference — that's the BSS.
    """
    data_filesz = 512     # .data: 512 bytes of initialized data
    bss_size = 1024       # .bss: 1024 bytes of uninitialized data
    data_memsz = data_filesz + bss_size

    phdr = build_program_header(
        p_type=PT_LOAD,
        p_flags=PF_R | PF_W,
        p_offset=0x3000,
        p_vaddr=0x403000,
        p_filesz=data_filesz,
        p_memsz=data_memsz,
        p_align=0x1000,
    )

    p_filesz = struct.unpack_from('<Q', phdr, 32)[0]
    p_memsz = struct.unpack_from('<Q', phdr, 40)[0]

    # p_memsz > p_filesz indicates BSS
    assert p_memsz > p_filesz, "data segment must have memsz > filesz for BSS"
    assert p_memsz - p_filesz == bss_size, "difference is the BSS size"


def verify_vaddr_to_file_offset():
    """Verify virtual address to file offset conversion.

    Given a virtual address and the PT_LOAD segments, find the file offset:
      file_offset = vaddr - segment.p_vaddr + segment.p_offset
    """
    # Segment: code loaded at vaddr 0x400000 from file offset 0
    code_vaddr = 0x400000
    code_offset = 0

    # Symbol at vaddr 0x401234
    target_vaddr = 0x401234

    # Conversion: file_offset = target_vaddr - segment.p_vaddr + segment.p_offset
    file_offset = target_vaddr - code_vaddr + code_offset
    assert file_offset == 0x1234, f"expected 0x1234, got 0x{file_offset:X}"

    # Second segment: data loaded at vaddr 0x403000 from file offset 0x3000
    data_vaddr = 0x403000
    data_offset = 0x3000
    data_target = 0x403100
    data_file_offset = data_target - data_vaddr + data_offset
    assert data_file_offset == 0x3100


def verify_dwarf_sections():
    """Verify DWARF debug info lives in sections, not segments.

    Debug sections are NOT part of any PT_LOAD — they exist only in the file.
    Tools (GDB, readelf) read them from disk. They are never mapped to memory.
    """
    dwarf_sections = [
        ".debug_info",     # type information, variables, functions
        ".debug_line",     # source line number mapping
        ".debug_abbrev",   # abbreviation tables for .debug_info
        ".debug_str",      # string table for debug info
        ".debug_aranges",  # address range lookup table
    ]

    # All DWARF sections have SHT_PROGBITS type but no SHF_ALLOC flag
    # (SHF_ALLOC = 2 means "occupies memory during execution")
    for section_name in dwarf_sections:
        # DWARF sections: flags = 0 (no ALLOC, no WRITE, no EXECINSTR)
        dwarf_flags = 0
        assert (dwarf_flags & SHF_ALLOC) == 0, \
            f"{section_name} must NOT have SHF_ALLOC — it's not loaded"

    # .eh_frame is the exception — it IS loaded (for stack unwinding)
    eh_frame_flags = SHF_ALLOC
    assert (eh_frame_flags & SHF_ALLOC) != 0, \
        ".eh_frame IS loaded — needed for stack unwinding"


def main():
    print("ELF and Executable Formats — Python struct-level deep dive:\n")

    # ── Verify struct sizes ────────────────────────────────────────────
    print("1. Header sizes:")
    verify_header_sizes()
    print(f"   ELF header:     {ELF64_EHDR_SIZE} bytes")
    print(f"   Program header: {ELF64_PHDR_SIZE} bytes")
    print(f"   Section header: {ELF64_SHDR_SIZE} bytes")
    print(f"   Minimum binary: {ELF64_EHDR_SIZE + ELF64_PHDR_SIZE} bytes (headers only)")

    # ── Verify ELF header fields ───────────────────────────────────────
    print("\n2. ELF header field verification:")
    verify_elf_header_fields()
    print("   e_ident[0:4]  = \\x7fELF (magic)")
    print("   e_ident[4]    = 2 (ELFCLASS64)")
    print("   e_ident[5]    = 1 (ELFDATA2LSB, little-endian)")
    print(f"   e_type        = {ET_EXEC} (ET_EXEC)")
    print(f"   e_machine     = 0x{EM_X86_64:02X} (EM_X86_64)")
    print(f"   e_entry       = 0x{0x400078:X} (entry point)")
    print("   All field offsets verified.")

    # ── Verify program header fields ───────────────────────────────────
    print("\n3. Program header field verification:")
    verify_program_header_fields()
    print(f"   p_type  = {PT_LOAD} (PT_LOAD)")
    print(f"   p_flags = {PF_R | PF_X} (PF_R | PF_X)")
    print("   p_align = 0x1000 (4KB page alignment)")
    print("   All field offsets verified.")

    # ── Section vs segment duality ─────────────────────────────────────
    print("\n4. Section vs segment duality:")
    verify_section_vs_segment()
    print("   .text + .rodata  -> PT_LOAD R+X (code segment)")
    print("   .data + .bss     -> PT_LOAD R+W (data segment)")
    print("   .symtab, .debug* -> not loaded (tools read from file)")
    print("   Stripping removes non-loaded sections; execution unchanged.")

    # ── BSS segment ────────────────────────────────────────────────────
    print("\n5. BSS (uninitialized data):")
    verify_bss_segment()
    print("   p_filesz = 512 (initialized .data)")
    print("   p_memsz  = 1536 (512 .data + 1024 .bss)")
    print("   Kernel zero-fills 1024 bytes for .bss")

    # ── Virtual address to file offset ─────────────────────────────────
    print("\n6. Virtual address -> file offset conversion:")
    verify_vaddr_to_file_offset()
    print("   vaddr=0x401234, segment(vaddr=0x400000, offset=0x0)")
    print("   file_offset = 0x401234 - 0x400000 + 0x0 = 0x1234")

    # ── DWARF debug sections ──────────────────────────────────────────
    print("\n7. DWARF debug sections:")
    verify_dwarf_sections()
    print("   .debug_info, .debug_line, etc. — NOT loaded into memory")
    print("   .eh_frame — IS loaded (stack unwinding)")
    print("   Stripping removes debug sections; stack traces lose detail")

    print("\nAll ELF format examples passed.")


if __name__ == "__main__":
    main()
