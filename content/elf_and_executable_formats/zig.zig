// Vidya — ELF and Executable Formats in Zig
//
// The ELF format has a duality: sections (for linkers) and segments
// (for loaders). Zig packed structs map exactly to the on-disk
// structures — Ehdr (64 bytes), Phdr (56 bytes), Shdr (64 bytes).
// comptime validates all sizes at compile time.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testElf64Ehdr();
    try testElf64Phdr();
    try testElf64Shdr();
    try testSectionSegmentDuality();
    try testElfTypes();
    try testSymbolTableEntry();
    try testRelocationEntry();

    std.debug.print("All ELF and executable formats examples passed.\n", .{});
}

// ── ELF64 Ehdr (64 bytes) ───────────────────────────────────────────
const Elf64Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

// ── ELF64 Phdr (56 bytes) ───────────────────────────────────────────
// Program headers define segments — the loader's view of the binary
const Elf64Phdr = extern struct {
    p_type: u32, // PT_LOAD, PT_DYNAMIC, etc.
    p_flags: u32, // PF_R | PF_W | PF_X
    p_offset: u64, // Offset in file
    p_vaddr: u64, // Virtual address in memory
    p_paddr: u64, // Physical address (usually ignored)
    p_filesz: u64, // Size in file
    p_memsz: u64, // Size in memory (>= filesz for .bss)
    p_align: u64, // Alignment
};

// ── ELF64 Shdr (64 bytes) ───────────────────────────────────────────
// Section headers define sections — the linker's view
const Elf64Shdr = extern struct {
    sh_name: u32, // Offset into .shstrtab
    sh_type: u32, // SHT_PROGBITS, SHT_SYMTAB, etc.
    sh_flags: u64, // SHF_WRITE | SHF_ALLOC | SHF_EXECINSTR
    sh_addr: u64, // Virtual address if loaded
    sh_offset: u64, // File offset
    sh_size: u64, // Section size
    sh_link: u32, // Section index link
    sh_info: u32, // Extra info
    sh_addralign: u64, // Alignment
    sh_entsize: u64, // Entry size for fixed-size sections
};

// ── Constants ────────────────────────────────────────────────────────
const ET = struct {
    const NONE: u16 = 0;
    const REL: u16 = 1; // Relocatable
    const EXEC: u16 = 2; // Executable
    const DYN: u16 = 3; // Shared object / PIE
    const CORE: u16 = 4; // Core dump
};

const PT = struct {
    const NULL: u32 = 0;
    const LOAD: u32 = 1; // Loadable segment
    const DYNAMIC: u32 = 2; // Dynamic linking info
    const INTERP: u32 = 3; // Program interpreter path
    const NOTE: u32 = 4; // Auxiliary info
    const PHDR: u32 = 6; // Program header table itself
    const TLS: u32 = 7; // Thread-local storage
    const GNU_STACK: u32 = 0x6474E551;
    const GNU_RELRO: u32 = 0x6474E552;
};

const PF = struct {
    const X: u32 = 1; // Execute
    const W: u32 = 2; // Write
    const R: u32 = 4; // Read
};

const SHT = struct {
    const NULL: u32 = 0;
    const PROGBITS: u32 = 1; // .text, .data, .rodata
    const SYMTAB: u32 = 2; // Symbol table
    const STRTAB: u32 = 3; // String table
    const RELA: u32 = 4; // Relocations with addend
    const HASH: u32 = 5; // Symbol hash table
    const DYNAMIC: u32 = 6; // Dynamic linking
    const NOTE: u32 = 7;
    const NOBITS: u32 = 8; // .bss — no file space
    const DYNSYM: u32 = 11;
};

const SHF = struct {
    const WRITE: u64 = 1;
    const ALLOC: u64 = 2;
    const EXECINSTR: u64 = 4;
};

const EM = struct {
    const X86_64: u16 = 0x3E;
    const AARCH64: u16 = 0xB7;
    const RISCV: u16 = 0xF3;
};

fn testElf64Ehdr() !void {
    // Size must be exactly 64 bytes per the ELF spec
    comptime {
        std.debug.assert(@sizeOf(Elf64Ehdr) == 64);
    }

    var ident = [_]u8{0} ** 16;
    ident[0] = 0x7F;
    ident[1] = 'E';
    ident[2] = 'L';
    ident[3] = 'F';
    ident[4] = 2; // ELFCLASS64
    ident[5] = 1; // ELFDATA2LSB
    ident[6] = 1; // EV_CURRENT

    const hdr = Elf64Ehdr{
        .e_ident = ident,
        .e_type = ET.DYN, // PIE executable
        .e_machine = EM.X86_64,
        .e_version = 1,
        .e_entry = 0x1000,
        .e_phoff = @sizeOf(Elf64Ehdr),
        .e_shoff = 0x2000,
        .e_flags = 0,
        .e_ehsize = @sizeOf(Elf64Ehdr),
        .e_phentsize = @sizeOf(Elf64Phdr),
        .e_phnum = 4,
        .e_shentsize = @sizeOf(Elf64Shdr),
        .e_shnum = 10,
        .e_shstrndx = 9,
    };

    try expect(hdr.e_type == ET.DYN);
    try expect(hdr.e_ehsize == 64);
    try expect(hdr.e_phentsize == 56);
    try expect(hdr.e_shentsize == 64);
    try expect(hdr.e_phoff == 64); // right after Ehdr
}

fn testElf64Phdr() !void {
    // Program header: exactly 56 bytes
    comptime {
        std.debug.assert(@sizeOf(Elf64Phdr) == 56);
    }

    // .text segment: readable + executable, loaded into memory
    const text_seg = Elf64Phdr{
        .p_type = PT.LOAD,
        .p_flags = PF.R | PF.X,
        .p_offset = 0x1000,
        .p_vaddr = 0x401000,
        .p_paddr = 0x401000,
        .p_filesz = 0x500,
        .p_memsz = 0x500,
        .p_align = 0x1000, // page-aligned
    };

    try expect(text_seg.p_type == PT.LOAD);
    try expect(text_seg.p_flags & PF.X != 0); // executable
    try expect(text_seg.p_flags & PF.W == 0); // not writable (W^X)
    try expect(text_seg.p_filesz == text_seg.p_memsz); // .text has no BSS

    // .data + .bss segment: memsz > filesz (BSS is zero-initialized)
    const data_seg = Elf64Phdr{
        .p_type = PT.LOAD,
        .p_flags = PF.R | PF.W,
        .p_offset = 0x2000,
        .p_vaddr = 0x402000,
        .p_paddr = 0x402000,
        .p_filesz = 0x100, // .data only
        .p_memsz = 0x500, // .data + .bss
        .p_align = 0x1000,
    };

    // BSS takes no file space but occupies memory
    try expect(data_seg.p_memsz > data_seg.p_filesz);
    try expect(data_seg.p_flags & PF.W != 0); // writable
    try expect(data_seg.p_flags & PF.X == 0); // not executable
}

fn testElf64Shdr() !void {
    // Section header: exactly 64 bytes
    comptime {
        std.debug.assert(@sizeOf(Elf64Shdr) == 64);
    }

    // .text section: code
    const text_shdr = Elf64Shdr{
        .sh_name = 0x1B,
        .sh_type = SHT.PROGBITS,
        .sh_flags = SHF.ALLOC | SHF.EXECINSTR,
        .sh_addr = 0x401000,
        .sh_offset = 0x1000,
        .sh_size = 0x500,
        .sh_link = 0,
        .sh_info = 0,
        .sh_addralign = 16,
        .sh_entsize = 0,
    };

    try expect(text_shdr.sh_type == SHT.PROGBITS);
    try expect(text_shdr.sh_flags & SHF.EXECINSTR != 0);

    // .bss section: NOBITS — occupies memory, not file
    const bss_shdr = Elf64Shdr{
        .sh_name = 0x27,
        .sh_type = SHT.NOBITS,
        .sh_flags = SHF.ALLOC | SHF.WRITE,
        .sh_addr = 0x402100,
        .sh_offset = 0x2100,
        .sh_size = 0x400,
        .sh_link = 0,
        .sh_info = 0,
        .sh_addralign = 32,
        .sh_entsize = 0,
    };

    try expect(bss_shdr.sh_type == SHT.NOBITS);
    try expect(bss_shdr.sh_flags & SHF.WRITE != 0);
}

// ── Section vs Segment Duality ───────────────────────────────────────
// Sections are the linker's view; segments are the loader's view.
// Multiple sections can be packed into one segment.
const SectionMapping = struct {
    section_name: []const u8,
    section_type: u32,
    segment_type: u32,
    segment_flags: u32,
};

fn testSectionSegmentDuality() !void {
    // Common section-to-segment mappings:
    const mappings = [_]SectionMapping{
        // .text → LOAD segment (R+X)
        .{ .section_name = ".text", .section_type = SHT.PROGBITS, .segment_type = PT.LOAD, .segment_flags = PF.R | PF.X },
        // .rodata → same LOAD segment as .text (R only, but often combined)
        .{ .section_name = ".rodata", .section_type = SHT.PROGBITS, .segment_type = PT.LOAD, .segment_flags = PF.R },
        // .data → LOAD segment (R+W)
        .{ .section_name = ".data", .section_type = SHT.PROGBITS, .segment_type = PT.LOAD, .segment_flags = PF.R | PF.W },
        // .bss → same LOAD segment as .data (R+W, NOBITS)
        .{ .section_name = ".bss", .section_type = SHT.NOBITS, .segment_type = PT.LOAD, .segment_flags = PF.R | PF.W },
        // .dynamic → DYNAMIC segment
        .{ .section_name = ".dynamic", .section_type = SHT.DYNAMIC, .segment_type = PT.DYNAMIC, .segment_flags = PF.R | PF.W },
    };

    // .text and .rodata can share a segment (both readable, .text also executable)
    try expect(mappings[0].segment_type == mappings[1].segment_type);
    try expect(mappings[0].segment_type == PT.LOAD);

    // .data and .bss share a segment (both R+W)
    try expect(mappings[2].segment_flags == mappings[3].segment_flags);

    // .bss has NOBITS — it takes file space via the section, but the
    // loader allocates memory from p_memsz - p_filesz
    try expect(mappings[3].section_type == SHT.NOBITS);

    // Stripped binaries lose sections but keep segments — still runnable
    // The kernel only needs PT_LOAD segments to execute the binary
    try expect(mappings[0].segment_type == PT.LOAD);
}

// ── ELF Type Classification ─────────────────────────────────────────
fn testElfTypes() !void {
    // ET_REL: .o files — relocatable, not yet linked
    // ET_EXEC: static executable — fixed addresses
    // ET_DYN: shared library or PIE — position-independent
    // ET_CORE: core dump — process memory snapshot

    const types = [_]struct { t: u16, name: []const u8 }{
        .{ .t = ET.NONE, .name = "none" },
        .{ .t = ET.REL, .name = "relocatable" },
        .{ .t = ET.EXEC, .name = "executable" },
        .{ .t = ET.DYN, .name = "shared/PIE" },
        .{ .t = ET.CORE, .name = "core dump" },
    };

    try expect(types.len == 5);
    try expect(types[2].t == ET.EXEC);
    try expect(types[3].t == ET.DYN);

    // Modern Linux: almost all executables are ET_DYN (PIE)
    // ET_EXEC is legacy — no ASLR possible with fixed addresses
    try expect(ET.DYN == 3);
}

// ── Symbol Table Entry ───────────────────────────────────────────────
const Elf64Sym = extern struct {
    st_name: u32, // Offset into string table
    st_info: u8, // Type (low 4) + Binding (high 4)
    st_other: u8, // Visibility
    st_shndx: u16, // Section index
    st_value: u64, // Symbol value (address)
    st_size: u64, // Symbol size
};

const STB = struct {
    const LOCAL: u8 = 0;
    const GLOBAL: u8 = 1;
    const WEAK: u8 = 2;
};

const STT = struct {
    const NOTYPE: u8 = 0;
    const FUNC: u8 = 2;
    const OBJECT: u8 = 1;
    const SECTION: u8 = 3;
};

fn stInfo(binding: u8, sym_type: u8) u8 {
    return (binding << 4) | (sym_type & 0xF);
}

fn testSymbolTableEntry() !void {
    comptime {
        std.debug.assert(@sizeOf(Elf64Sym) == 24);
    }

    const sym = Elf64Sym{
        .st_name = 0x10,
        .st_info = stInfo(STB.GLOBAL, STT.FUNC),
        .st_other = 0, // STV_DEFAULT
        .st_shndx = 1, // .text section
        .st_value = 0x401000,
        .st_size = 64,
    };

    // Extract binding and type from st_info
    try expect((sym.st_info >> 4) == STB.GLOBAL);
    try expect((sym.st_info & 0xF) == STT.FUNC);
    try expect(sym.st_size == 64);
}

// ── Relocation Entry ─────────────────────────────────────────────────
const Elf64Rela = extern struct {
    r_offset: u64, // Where to apply the relocation
    r_info: u64, // Symbol index + type
    r_addend: i64, // Addend for the relocation
};

fn testRelocationEntry() !void {
    comptime {
        std.debug.assert(@sizeOf(Elf64Rela) == 24);
    }

    const R_X86_64_64: u32 = 1; // Direct 64-bit
    const R_X86_64_PC32: u32 = 2; // PC-relative 32-bit
    const sym_index: u64 = 5;

    const rela = Elf64Rela{
        .r_offset = 0x401020,
        .r_info = (sym_index << 32) | R_X86_64_64,
        .r_addend = 0,
    };

    // Extract symbol index and type from r_info
    try expect((rela.r_info >> 32) == sym_index);
    try expect(@as(u32, @truncate(rela.r_info)) == R_X86_64_64);

    const pc_rel = Elf64Rela{
        .r_offset = 0x401030,
        .r_info = (sym_index << 32) | R_X86_64_PC32,
        .r_addend = -4, // common for call instructions
    };

    try expect(@as(u32, @truncate(pc_rel.r_info)) == R_X86_64_PC32);
    try expect(pc_rel.r_addend == -4);
}
