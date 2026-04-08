// Vidya — Binary Formats in TypeScript
//
// Executable file formats tell the OS how to load a program into memory.
// Every format starts with a magic number so the loader knows what it is.
// Here we model ELF64, PE, and Mach-O headers, build a complete ELF64
// header with DataView for byte-level control, and compare formats.

function main(): void {
    testMagicNumbers();
    testElf64HeaderConstruction();
    testPeHeaderModel();
    testMachOHeaderModel();
    testFormatComparison();
    testEndianness();

    console.log("All binary formats examples passed.");
}

// ── Magic Numbers ────────────────────────────────────────────────────

// Every executable format starts with a recognizable byte sequence.
// The kernel/loader reads these first bytes to decide how to proceed.

const ELF_MAGIC = new Uint8Array([0x7F, 0x45, 0x4C, 0x46]); // \x7FELF
const PE_MAGIC = new Uint8Array([0x4D, 0x5A]);               // MZ (DOS stub)
const MACHO_MAGIC_64 = 0xFEEDFACF;                           // Mach-O 64-bit
const MACHO_MAGIC_32 = 0xFEEDFACE;                           // Mach-O 32-bit

function detectFormat(data: Uint8Array): string {
    if (data.length < 4) return "unknown (too short)";

    // ELF: \x7FELF
    if (data[0] === 0x7F && data[1] === 0x45 && data[2] === 0x4C && data[3] === 0x46) {
        return "ELF";
    }

    // PE/COFF: starts with MZ (DOS stub)
    if (data[0] === 0x4D && data[1] === 0x5A) {
        return "PE (MZ)";
    }

    // Mach-O: 0xFEEDFACF (64-bit) or 0xFEEDFACE (32-bit)
    const dv = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const magic32be = dv.getUint32(0, false);
    if (magic32be === MACHO_MAGIC_64) return "Mach-O 64-bit";
    if (magic32be === MACHO_MAGIC_32) return "Mach-O 32-bit";

    return "unknown";
}

function testMagicNumbers(): void {
    // ELF detection
    const elfData = new Uint8Array([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0]);
    assert(detectFormat(elfData) === "ELF", "detect ELF");

    // PE detection
    const peData = new Uint8Array([0x4D, 0x5A, 0x90, 0x00]);
    assert(detectFormat(peData) === "PE (MZ)", "detect PE");

    // Mach-O 64-bit detection
    const machoData = new Uint8Array([0xFE, 0xED, 0xFA, 0xCF]);
    assert(detectFormat(machoData) === "Mach-O 64-bit", "detect Mach-O 64");

    // Unknown format
    const unknown = new Uint8Array([0x00, 0x00, 0x00, 0x00]);
    assert(detectFormat(unknown) === "unknown", "detect unknown");

    // Too short
    assert(detectFormat(new Uint8Array([0x7F])) === "unknown (too short)", "too short");
}

// ── ELF64 Header (64 bytes) ─────────────────────────────────────────

// ELF header layout for 64-bit:
//   Offset  Size  Field
//   0x00    16    e_ident (magic + class + endian + version + padding)
//   0x10    2     e_type (ET_EXEC=2, ET_DYN=3)
//   0x12    2     e_machine (EM_X86_64=0x3E)
//   0x14    4     e_version
//   0x18    8     e_entry (entry point virtual address)
//   0x20    8     e_phoff (program header table offset)
//   0x28    8     e_shoff (section header table offset)
//   0x30    4     e_flags
//   0x34    2     e_ehsize (this header's size = 64)
//   0x36    2     e_phentsize (program header entry size = 56)
//   0x38    2     e_phnum (number of program headers)
//   0x3A    2     e_shentsize (section header entry size = 64)
//   0x3C    2     e_shnum (number of section headers)
//   0x3E    2     e_shstrndx (section name string table index)

const ELF_HDR_SIZE = 64;
const PHDR_SIZE = 56;

class Elf64Header {
    readonly buffer: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        this.buffer = new ArrayBuffer(ELF_HDR_SIZE);
        this.view = new DataView(this.buffer);
    }

    /** Build a minimal ELF64 executable header. */
    static executable(entry: bigint, phnum: number): Elf64Header {
        const hdr = new Elf64Header();
        const v = hdr.view;

        // e_ident[0..4]: magic number
        v.setUint8(0, 0x7F);
        v.setUint8(1, 0x45); // 'E'
        v.setUint8(2, 0x4C); // 'L'
        v.setUint8(3, 0x46); // 'F'
        // e_ident[4]: class = ELFCLASS64
        v.setUint8(4, 2);
        // e_ident[5]: data = ELFDATA2LSB (little-endian)
        v.setUint8(5, 1);
        // e_ident[6]: version = EV_CURRENT
        v.setUint8(6, 1);
        // e_ident[7]: OS/ABI = ELFOSABI_NONE
        v.setUint8(7, 0);
        // e_ident[8..16]: padding (already zero)

        // e_type = ET_EXEC (2)
        v.setUint16(0x10, 2, true);
        // e_machine = EM_X86_64 (0x3E)
        v.setUint16(0x12, 0x3E, true);
        // e_version = 1
        v.setUint32(0x14, 1, true);
        // e_entry (8 bytes, little-endian)
        v.setBigUint64(0x18, entry, true);
        // e_phoff = 64 (immediately after header)
        v.setBigUint64(0x20, BigInt(ELF_HDR_SIZE), true);
        // e_shoff = 0 (no section headers in minimal binary)
        v.setBigUint64(0x28, 0n, true);
        // e_flags = 0
        v.setUint32(0x30, 0, true);
        // e_ehsize = 64
        v.setUint16(0x34, ELF_HDR_SIZE, true);
        // e_phentsize = 56
        v.setUint16(0x36, PHDR_SIZE, true);
        // e_phnum
        v.setUint16(0x38, phnum, true);
        // e_shentsize = 64
        v.setUint16(0x3A, 64, true);
        // e_shnum = 0
        v.setUint16(0x3C, 0, true);
        // e_shstrndx = 0
        v.setUint16(0x3E, 0, true);

        return hdr;
    }

    // Accessors read back from the raw buffer — proves byte layout is correct
    get magic(): Uint8Array {
        return new Uint8Array(this.buffer, 0, 4);
    }

    get elfClass(): number { return this.view.getUint8(4); }
    get dataEncoding(): number { return this.view.getUint8(5); }
    get type(): number { return this.view.getUint16(0x10, true); }
    get machine(): number { return this.view.getUint16(0x12, true); }
    get entry(): bigint { return this.view.getBigUint64(0x18, true); }
    get phoff(): bigint { return this.view.getBigUint64(0x20, true); }
    get ehsize(): number { return this.view.getUint16(0x34, true); }
    get phentsize(): number { return this.view.getUint16(0x36, true); }
    get phnum(): number { return this.view.getUint16(0x38, true); }
}

function testElf64HeaderConstruction(): void {
    const entry = 0x40_0078n;
    const hdr = Elf64Header.executable(entry, 1);

    // Verify magic bytes
    const magic = hdr.magic;
    assert(magic[0] === 0x7F && magic[1] === 0x45, "elf magic");
    assert(magic[2] === 0x4C && magic[3] === 0x46, "elf magic cont");

    // Verify header fields
    assert(hdr.elfClass === 2, "ELFCLASS64");
    assert(hdr.dataEncoding === 1, "little-endian");
    assert(hdr.type === 2, "ET_EXEC");
    assert(hdr.machine === 0x3E, "EM_X86_64");
    assert(hdr.entry === entry, "entry point");
    assert(hdr.phoff === 64n, "phoff after header");
    assert(hdr.ehsize === 64, "header size");
    assert(hdr.phentsize === 56, "phdr entry size");
    assert(hdr.phnum === 1, "one program header");

    // Total binary overhead: 64 (ehdr) + 56 (phdr) = 120 bytes
    assert(ELF_HDR_SIZE + PHDR_SIZE === 120, "minimal overhead");
}

// ── PE Header Model ─────────────────────────────────────────────────

// PE (Portable Executable) is used on Windows. The file starts with a
// DOS stub (MZ header), then a PE signature, then COFF header + optional header.

interface PeHeaderInfo {
    dosSignature: string;
    peOffset: number;
    peSignature: string;
    machine: number;
    numberOfSections: number;
    imageBase: bigint;
    entryPoint: number;
}

function buildPeModel(): PeHeaderInfo {
    // In a real PE file, the DOS header at offset 0x3C points to the PE signature.
    // We model the key fields for comparison with ELF.
    return {
        dosSignature: "MZ",
        peOffset: 0x80,              // typical offset to PE\0\0
        peSignature: "PE\\0\\0",
        machine: 0x8664,             // IMAGE_FILE_MACHINE_AMD64
        numberOfSections: 3,         // .text, .rdata, .data
        imageBase: 0x0040_0000n,     // default for executables
        entryPoint: 0x1000,          // RVA of entry point
    };
}

function testPeHeaderModel(): void {
    const pe = buildPeModel();
    assert(pe.dosSignature === "MZ", "PE starts with MZ");
    assert(pe.machine === 0x8664, "PE AMD64 machine");
    assert(pe.imageBase === 0x0040_0000n, "PE default image base");
    assert(pe.entryPoint > 0, "PE entry point set");
}

// ── Mach-O Header Model ─────────────────────────────────────────────

// Mach-O is used on macOS/iOS. It uses a different approach: load commands
// instead of program/section headers.

interface MachOHeaderInfo {
    magic: number;
    cpuType: number;
    cpuSubtype: number;
    fileType: number;      // MH_EXECUTE=2
    numLoadCommands: number;
    sizeOfLoadCommands: number;
}

function buildMachOModel(): MachOHeaderInfo {
    return {
        magic: MACHO_MAGIC_64,
        cpuType: 0x0100_0007,     // CPU_TYPE_X86_64
        cpuSubtype: 3,            // CPU_SUBTYPE_X86_ALL
        fileType: 2,              // MH_EXECUTE
        numLoadCommands: 4,       // LC_SEGMENT_64, LC_MAIN, etc.
        sizeOfLoadCommands: 392,
    };
}

function testMachOHeaderModel(): void {
    const mach = buildMachOModel();
    assert(mach.magic === MACHO_MAGIC_64, "Mach-O 64-bit magic");
    assert(mach.fileType === 2, "MH_EXECUTE");
    assert(mach.numLoadCommands > 0, "has load commands");
}

// ── Format Comparison ───────────────────────────────────────────────

// Key differences between executable formats:
//
// Feature          ELF               PE                Mach-O
// ─────────────────────────────────────────────────────────────────
// Platforms        Linux, BSD, etc.  Windows           macOS, iOS
// Magic            \x7FELF           MZ                0xFEEDFACF
// Header size      64 bytes (64-bit) DOS+COFF+Optional 32 bytes (64-bit)
// Segments         Program headers   Sections          Load commands
// Dynamic linking  .dynamic + .got   Import table      LC_LOAD_DYLIB
// Entry point      e_entry           AddressOfEntry    LC_MAIN

interface FormatInfo {
    name: string;
    magic: string;
    headerSize: number;
    segmentConcept: string;
    platforms: string[];
}

function getFormatInfos(): FormatInfo[] {
    return [
        {
            name: "ELF",
            magic: "\\x7FELF",
            headerSize: 64,
            segmentConcept: "program headers (phdr)",
            platforms: ["Linux", "FreeBSD", "Solaris"],
        },
        {
            name: "PE",
            magic: "MZ",
            headerSize: 248, // DOS + COFF + optional header (PE32+)
            segmentConcept: "sections (.text, .data, .rdata)",
            platforms: ["Windows"],
        },
        {
            name: "Mach-O",
            magic: "0xFEEDFACF",
            headerSize: 32,
            segmentConcept: "load commands (LC_SEGMENT_64)",
            platforms: ["macOS", "iOS"],
        },
    ];
}

function testFormatComparison(): void {
    const formats = getFormatInfos();
    assert(formats.length === 3, "three major formats");

    const elf = formats.find((f) => f.name === "ELF")!;
    assert(elf.headerSize === 64, "ELF header 64 bytes");
    assert(elf.platforms.includes("Linux"), "ELF on Linux");

    const pe = formats.find((f) => f.name === "PE")!;
    assert(pe.platforms.includes("Windows"), "PE on Windows");

    // ELF is the simplest header, Mach-O is even smaller at the top level
    const macho = formats.find((f) => f.name === "Mach-O")!;
    assert(macho.headerSize < elf.headerSize, "Mach-O header smaller");
}

// ── Endianness with DataView ────────────────────────────────────────

// DataView lets you read/write with explicit endianness — critical for
// binary format work. ELF and PE are typically little-endian on x86.

function testEndianness(): void {
    const buf = new ArrayBuffer(8);
    const dv = new DataView(buf);

    // Write 0x0102 as little-endian: stored as [0x02, 0x01]
    dv.setUint16(0, 0x0102, true);
    const bytes = new Uint8Array(buf);
    assert(bytes[0] === 0x02, "LE byte 0");
    assert(bytes[1] === 0x01, "LE byte 1");

    // Read it back as big-endian: gets 0x0201
    const asBE = dv.getUint16(0, false);
    assert(asBE === 0x0201, "BE readback swapped");

    // 64-bit values with BigInt — needed for addresses
    dv.setBigUint64(0, 0x0040_0000n, true);
    assert(dv.getBigUint64(0, true) === 0x0040_0000n, "64-bit roundtrip");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
