// Vidya — Binary Formats in Zig
//
// Binary executable formats (ELF, PE, Mach-O) begin with magic numbers
// that identify the format. Zig's packed structs map exactly to on-disk
// headers — no padding, no surprises. comptime validates sizes and
// builds tables at compile time.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testMagicNumbers();
    try testElf64Header();
    try testPeSignature();
    try testMachOHeader();
    try testFormatDetection();
    try testEndianness();

    std.debug.print("All binary formats examples passed.\n", .{});
}

// ── Magic Numbers ────────────────────────────────────────────────────
// Every binary format starts with a signature for identification
const Magic = struct {
    const ELF = [_]u8{ 0x7F, 'E', 'L', 'F' };
    const PE_DOS = [_]u8{ 'M', 'Z' }; // DOS MZ header
    const PE_SIG = [_]u8{ 'P', 'E', 0, 0 }; // PE\0\0 after e_lfanew
    const MACHO_64 = [_]u8{ 0xFE, 0xED, 0xFA, 0xCF }; // big-endian
    const MACHO_64_LE = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE }; // little-endian (most common)
    const MACHO_FAT = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE }; // universal binary
};

fn testMagicNumbers() !void {
    // ELF magic: 0x7F followed by "ELF"
    try expect(Magic.ELF[0] == 0x7F);
    try expect(Magic.ELF[1] == 'E');
    try expect(Magic.ELF[2] == 'L');
    try expect(Magic.ELF[3] == 'F');

    // PE starts with DOS stub "MZ"
    try expect(Magic.PE_DOS[0] == 'M');
    try expect(Magic.PE_DOS[1] == 'Z');

    // Mach-O magic differs by endianness
    try expect(Magic.MACHO_64[0] == 0xFE);
    try expect(Magic.MACHO_64_LE[0] == 0xCF);

    // Fat binary magic is 0xCAFEBABE (also Java class files!)
    try expect(Magic.MACHO_FAT[0] == 0xCA);
}

// ── ELF64 Header ─────────────────────────────────────────────────────
// Packed struct maps exactly to the on-disk layout (64 bytes)
const Elf64Ehdr = extern struct {
    e_ident: [16]u8, // Magic + class + data + version + OS/ABI + padding
    e_type: u16, // ET_EXEC, ET_DYN, etc.
    e_machine: u16, // EM_X86_64 = 0x3E
    e_version: u32, // EV_CURRENT = 1
    e_entry: u64, // Entry point virtual address
    e_phoff: u64, // Program header table offset
    e_shoff: u64, // Section header table offset
    e_flags: u32, // Processor-specific flags
    e_ehsize: u16, // ELF header size
    e_phentsize: u16, // Program header entry size
    e_phnum: u16, // Number of program headers
    e_shentsize: u16, // Section header entry size
    e_shnum: u16, // Number of section headers
    e_shstrndx: u16, // Section name string table index
};

// ELF constants
const ElfConst = struct {
    const ELFCLASS64: u8 = 2;
    const ELFDATA2LSB: u8 = 1; // little-endian
    const ET_EXEC: u16 = 2;
    const ET_DYN: u16 = 3; // shared object / PIE
    const EM_X86_64: u16 = 0x3E;
    const EM_AARCH64: u16 = 0xB7;
    const EV_CURRENT: u32 = 1;
};

fn buildMinimalElf64Header() Elf64Ehdr {
    var ident = [_]u8{0} ** 16;
    ident[0] = 0x7F;
    ident[1] = 'E';
    ident[2] = 'L';
    ident[3] = 'F';
    ident[4] = ElfConst.ELFCLASS64; // 64-bit
    ident[5] = ElfConst.ELFDATA2LSB; // little-endian
    ident[6] = 1; // ELF version

    return .{
        .e_ident = ident,
        .e_type = ElfConst.ET_EXEC,
        .e_machine = ElfConst.EM_X86_64,
        .e_version = ElfConst.EV_CURRENT,
        .e_entry = 0x400000, // typical Linux entry
        .e_phoff = @sizeOf(Elf64Ehdr), // immediately after header
        .e_shoff = 0,
        .e_flags = 0,
        .e_ehsize = @sizeOf(Elf64Ehdr),
        .e_phentsize = 56, // sizeof(Elf64_Phdr)
        .e_phnum = 1,
        .e_shentsize = 64, // sizeof(Elf64_Shdr)
        .e_shnum = 0,
        .e_shstrndx = 0,
    };
}

fn testElf64Header() !void {
    // Packed struct size must match the spec exactly
    comptime {
        std.debug.assert(@sizeOf(Elf64Ehdr) == 64);
    }

    const hdr = buildMinimalElf64Header();

    // Verify magic
    try expect(hdr.e_ident[0] == 0x7F);
    try expect(hdr.e_ident[1] == 'E');
    try expect(hdr.e_ident[4] == ElfConst.ELFCLASS64);

    // Verify fields
    try expect(hdr.e_type == ElfConst.ET_EXEC);
    try expect(hdr.e_machine == ElfConst.EM_X86_64);
    try expect(hdr.e_entry == 0x400000);
    try expect(hdr.e_ehsize == 64);

    // Program headers start right after the ELF header
    try expect(hdr.e_phoff == 64);
}

// ── PE Signature and COFF Header ─────────────────────────────────────
const PeCoffHeader = extern struct {
    machine: u16, // 0x8664 = AMD64
    number_of_sections: u16,
    time_date_stamp: u32,
    pointer_to_symbol_table: u32,
    number_of_symbols: u32,
    size_of_optional_header: u16,
    characteristics: u16,
};

const PeConst = struct {
    const IMAGE_FILE_MACHINE_AMD64: u16 = 0x8664;
    const IMAGE_FILE_MACHINE_ARM64: u16 = 0xAA64;
    const IMAGE_FILE_EXECUTABLE_IMAGE: u16 = 0x0002;
    const IMAGE_FILE_LARGE_ADDRESS_AWARE: u16 = 0x0020;
};

fn testPeSignature() !void {
    comptime {
        std.debug.assert(@sizeOf(PeCoffHeader) == 20);
    }

    const coff = PeCoffHeader{
        .machine = PeConst.IMAGE_FILE_MACHINE_AMD64,
        .number_of_sections = 3, // .text, .data, .rdata typical
        .time_date_stamp = 0,
        .pointer_to_symbol_table = 0,
        .number_of_symbols = 0,
        .size_of_optional_header = 240, // PE32+ optional header
        .characteristics = PeConst.IMAGE_FILE_EXECUTABLE_IMAGE | PeConst.IMAGE_FILE_LARGE_ADDRESS_AWARE,
    };

    try expect(coff.machine == 0x8664);
    try expect(coff.number_of_sections == 3);
    try expect(coff.characteristics & PeConst.IMAGE_FILE_EXECUTABLE_IMAGE != 0);
}

// ── Mach-O Header ────────────────────────────────────────────────────
const MachHeader64 = extern struct {
    magic: u32, // 0xFEEDFACF
    cputype: u32, // CPU_TYPE_X86_64 = 0x01000007
    cpusubtype: u32,
    filetype: u32, // MH_EXECUTE = 2
    ncmds: u32, // number of load commands
    sizeofcmds: u32,
    flags: u32,
    reserved: u32, // 64-bit only
};

const MachConst = struct {
    const MH_MAGIC_64: u32 = 0xFEEDFACF;
    const CPU_TYPE_X86_64: u32 = 0x01000007;
    const CPU_TYPE_ARM64: u32 = 0x0100000C;
    const MH_EXECUTE: u32 = 2;
    const MH_DYLIB: u32 = 6;
    const MH_PIE: u32 = 0x00200000;
};

fn testMachOHeader() !void {
    comptime {
        std.debug.assert(@sizeOf(MachHeader64) == 32);
    }

    const hdr = MachHeader64{
        .magic = MachConst.MH_MAGIC_64,
        .cputype = MachConst.CPU_TYPE_ARM64,
        .cpusubtype = 0,
        .filetype = MachConst.MH_EXECUTE,
        .ncmds = 16,
        .sizeofcmds = 1024,
        .flags = MachConst.MH_PIE,
        .reserved = 0,
    };

    try expect(hdr.magic == 0xFEEDFACF);
    try expect(hdr.cputype == MachConst.CPU_TYPE_ARM64);
    try expect(hdr.filetype == MachConst.MH_EXECUTE);
    try expect(hdr.flags & MachConst.MH_PIE != 0);
}

// ── Format Detection ─────────────────────────────────────────────────
// Detect binary format from the first few bytes
const BinaryFormat = enum { elf, pe, macho, macho_fat, unknown };

fn detectFormat(bytes: []const u8) BinaryFormat {
    if (bytes.len < 4) return .unknown;

    // ELF: 7F 45 4C 46
    if (bytes[0] == 0x7F and bytes[1] == 'E' and bytes[2] == 'L' and bytes[3] == 'F')
        return .elf;

    // PE: starts with MZ DOS stub
    if (bytes[0] == 'M' and bytes[1] == 'Z')
        return .pe;

    // Mach-O 64-bit (little-endian, most common)
    if (bytes[0] == 0xCF and bytes[1] == 0xFA and bytes[2] == 0xED and bytes[3] == 0xFE)
        return .macho;

    // Mach-O 64-bit (big-endian)
    if (bytes[0] == 0xFE and bytes[1] == 0xED and bytes[2] == 0xFA and bytes[3] == 0xCF)
        return .macho;

    // Fat/Universal binary
    if (bytes[0] == 0xCA and bytes[1] == 0xFE and bytes[2] == 0xBA and bytes[3] == 0xBE)
        return .macho_fat;

    return .unknown;
}

fn testFormatDetection() !void {
    const elf_bytes = [_]u8{ 0x7F, 'E', 'L', 'F', 0x02, 0x01 };
    try expect(detectFormat(&elf_bytes) == .elf);

    const pe_bytes = [_]u8{ 'M', 'Z', 0x90, 0x00 };
    try expect(detectFormat(&pe_bytes) == .pe);

    const macho_bytes = [_]u8{ 0xCF, 0xFA, 0xED, 0xFE };
    try expect(detectFormat(&macho_bytes) == .macho);

    const fat_bytes = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE };
    try expect(detectFormat(&fat_bytes) == .macho_fat);

    const garbage = [_]u8{ 0x00, 0x00 };
    try expect(detectFormat(&garbage) == .unknown);
}

// ── Endianness ───────────────────────────────────────────────────────
// ELF encodes endianness in e_ident[5]; PE is always LE; Mach-O magic
// indicates endianness by byte order
fn testEndianness() !void {
    // ELF: e_ident[5] tells us endianness
    const hdr = buildMinimalElf64Header();
    try expect(hdr.e_ident[5] == ElfConst.ELFDATA2LSB);

    // Little-endian: least significant byte first
    // 0x0102 stored as [0x02, 0x01] in memory
    const val: u16 = 0x0102;
    const bytes = std.mem.toBytes(val);
    if (@import("builtin").target.cpu.arch.endian() == .little) {
        try expect(bytes[0] == 0x02);
        try expect(bytes[1] == 0x01);
    }
}
