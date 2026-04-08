// Vidya — ELF and Executable Formats in TypeScript
//
// ELF (Executable and Linkable Format) is the standard binary format
// on Linux, BSD, and most Unix systems. This file models the three
// core ELF64 structures — header, program header, section header —
// using DataView for byte-accurate layout and verifies field offsets.

function main(): void {
    testElf64Header();
    testProgramHeader();
    testSectionHeader();
    testElf64Serialization();
    testSegmentPermissions();
    testSectionTypes();
    testStringTable();

    console.log("All ELF and executable formats examples passed.");
}

// ── ELF Constants ───────────────────────────────────────────────────

// File types
const ET_NONE = 0;
const ET_REL  = 1;  // relocatable (.o)
const ET_EXEC = 2;  // executable
const ET_DYN  = 3;  // shared object (.so) or PIE executable
const ET_CORE = 4;  // core dump

// Machine types
const EM_X86_64 = 0x3E;   // 62
const EM_AARCH64 = 0xB7;  // 183
const EM_RISCV = 0xF3;    // 243

// Program header types
const PT_NULL    = 0;
const PT_LOAD    = 1;  // loadable segment
const PT_DYNAMIC = 2;  // dynamic linking info
const PT_INTERP  = 3;  // path to interpreter
const PT_NOTE    = 4;  // auxiliary information
const PT_PHDR    = 6;  // program header table itself

// Program header flags
const PF_X = 1;  // executable
const PF_W = 2;  // writable
const PF_R = 4;  // readable

// Section header types
const SHT_NULL     = 0;
const SHT_PROGBITS = 1;   // program data (.text, .data)
const SHT_SYMTAB   = 2;   // symbol table
const SHT_STRTAB   = 3;   // string table
const SHT_RELA     = 4;   // relocation entries with addend
const SHT_NOBITS   = 8;   // .bss (no file data, zeroed in memory)
const SHT_DYNSYM   = 11;  // dynamic symbol table

// Section header flags
const SHF_WRITE     = 0x1;
const SHF_ALLOC     = 0x2;
const SHF_EXECINSTR = 0x4;

// ── ELF64 Header (64 bytes) ────────────────────────────────────────

// Layout with byte offsets:
//   [0x00..0x10)  e_ident     16 bytes  (magic, class, endian, version, ABI, pad)
//   [0x10..0x12)  e_type       2 bytes
//   [0x12..0x14)  e_machine    2 bytes
//   [0x14..0x18)  e_version    4 bytes
//   [0x18..0x20)  e_entry      8 bytes  (entry point address)
//   [0x20..0x28)  e_phoff      8 bytes  (program header table offset)
//   [0x28..0x30)  e_shoff      8 bytes  (section header table offset)
//   [0x30..0x34)  e_flags      4 bytes
//   [0x34..0x36)  e_ehsize     2 bytes  (this header's size = 64)
//   [0x36..0x38)  e_phentsize  2 bytes  (program header entry size = 56)
//   [0x38..0x3A)  e_phnum      2 bytes
//   [0x3A..0x3C)  e_shentsize  2 bytes  (section header entry size = 64)
//   [0x3C..0x3E)  e_shnum      2 bytes
//   [0x3E..0x40)  e_shstrndx   2 bytes  (section name string table index)
//   Total: 0x40 = 64 bytes

const EHDR_SIZE = 64;

class Elf64Ehdr {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor(buf?: ArrayBuffer) {
        this.buf = buf ?? new ArrayBuffer(EHDR_SIZE);
        this.view = new DataView(this.buf, 0, EHDR_SIZE);
    }

    static build(opts: {
        type: number;
        machine: number;
        entry: bigint;
        phnum: number;
        shnum: number;
        shstrndx: number;
    }): Elf64Ehdr {
        const hdr = new Elf64Ehdr();
        const v = hdr.view;

        // e_ident
        v.setUint8(0, 0x7F);
        v.setUint8(1, 0x45); // E
        v.setUint8(2, 0x4C); // L
        v.setUint8(3, 0x46); // F
        v.setUint8(4, 2);    // ELFCLASS64
        v.setUint8(5, 1);    // ELFDATA2LSB
        v.setUint8(6, 1);    // EV_CURRENT
        v.setUint8(7, 0);    // ELFOSABI_NONE

        v.setUint16(0x10, opts.type, true);
        v.setUint16(0x12, opts.machine, true);
        v.setUint32(0x14, 1, true); // version
        v.setBigUint64(0x18, opts.entry, true);
        v.setBigUint64(0x20, BigInt(EHDR_SIZE), true); // phoff
        // shoff: right after program headers
        const shoff = BigInt(EHDR_SIZE + PHDR_SIZE * opts.phnum);
        v.setBigUint64(0x28, shoff, true);
        v.setUint32(0x30, 0, true); // flags
        v.setUint16(0x34, EHDR_SIZE, true);
        v.setUint16(0x36, PHDR_SIZE, true);
        v.setUint16(0x38, opts.phnum, true);
        v.setUint16(0x3A, SHDR_SIZE, true);
        v.setUint16(0x3C, opts.shnum, true);
        v.setUint16(0x3E, opts.shstrndx, true);

        return hdr;
    }

    // Field accessors — read from raw bytes to verify layout
    get elfClass(): number    { return this.view.getUint8(4); }
    get dataEnc(): number     { return this.view.getUint8(5); }
    get type(): number        { return this.view.getUint16(0x10, true); }
    get machine(): number     { return this.view.getUint16(0x12, true); }
    get entry(): bigint       { return this.view.getBigUint64(0x18, true); }
    get phoff(): bigint       { return this.view.getBigUint64(0x20, true); }
    get shoff(): bigint       { return this.view.getBigUint64(0x28, true); }
    get ehsize(): number      { return this.view.getUint16(0x34, true); }
    get phentsize(): number   { return this.view.getUint16(0x36, true); }
    get phnum(): number       { return this.view.getUint16(0x38, true); }
    get shentsize(): number   { return this.view.getUint16(0x3A, true); }
    get shnum(): number       { return this.view.getUint16(0x3C, true); }
    get shstrndx(): number    { return this.view.getUint16(0x3E, true); }
}

function testElf64Header(): void {
    const hdr = Elf64Ehdr.build({
        type: ET_EXEC,
        machine: EM_X86_64,
        entry: 0x40_1000n,
        phnum: 2,
        shnum: 5,
        shstrndx: 4,
    });

    // Verify sizes match spec
    assert(hdr.ehsize === 64, "ELF header = 64 bytes");
    assert(hdr.phentsize === 56, "phdr entry = 56 bytes");
    assert(hdr.shentsize === 64, "shdr entry = 64 bytes");

    // Verify field values
    assert(hdr.elfClass === 2, "ELFCLASS64");
    assert(hdr.dataEnc === 1, "little-endian");
    assert(hdr.type === ET_EXEC, "ET_EXEC");
    assert(hdr.machine === EM_X86_64, "EM_X86_64");
    assert(hdr.entry === 0x40_1000n, "entry point");
    assert(hdr.phnum === 2, "two program headers");
    assert(hdr.shnum === 5, "five section headers");
    assert(hdr.shstrndx === 4, "shstrndx = 4");

    // phoff should be immediately after ehdr
    assert(hdr.phoff === 64n, "phoff follows ehdr");
    // shoff should be after ehdr + phdrs
    assert(hdr.shoff === BigInt(64 + 56 * 2), "shoff follows phdrs");
}

// ── Program Header (56 bytes) ───────────────────────────────────────

// Layout:
//   [0x00..0x04)  p_type     4 bytes
//   [0x04..0x08)  p_flags    4 bytes  (permissions: R/W/X)
//   [0x08..0x10)  p_offset   8 bytes  (file offset)
//   [0x10..0x18)  p_vaddr    8 bytes  (virtual address)
//   [0x18..0x20)  p_paddr    8 bytes  (physical address, usually = vaddr)
//   [0x20..0x28)  p_filesz   8 bytes  (size in file)
//   [0x28..0x30)  p_memsz    8 bytes  (size in memory, >= filesz for .bss)
//   [0x30..0x38)  p_align    8 bytes  (alignment, must be power of 2)
//   Total: 0x38 = 56 bytes

const PHDR_SIZE = 56;

class Elf64Phdr {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        this.buf = new ArrayBuffer(PHDR_SIZE);
        this.view = new DataView(this.buf);
    }

    static load(type_: number, flags: number, offset: bigint,
                vaddr: bigint, filesz: bigint, memsz: bigint,
                align: bigint): Elf64Phdr {
        const ph = new Elf64Phdr();
        const v = ph.view;
        v.setUint32(0x00, type_, true);
        v.setUint32(0x04, flags, true);
        v.setBigUint64(0x08, offset, true);
        v.setBigUint64(0x10, vaddr, true);
        v.setBigUint64(0x18, vaddr, true);  // paddr = vaddr
        v.setBigUint64(0x20, filesz, true);
        v.setBigUint64(0x28, memsz, true);
        v.setBigUint64(0x30, align, true);
        return ph;
    }

    get type(): number    { return this.view.getUint32(0x00, true); }
    get flags(): number   { return this.view.getUint32(0x04, true); }
    get offset(): bigint  { return this.view.getBigUint64(0x08, true); }
    get vaddr(): bigint   { return this.view.getBigUint64(0x10, true); }
    get paddr(): bigint   { return this.view.getBigUint64(0x18, true); }
    get filesz(): bigint  { return this.view.getBigUint64(0x20, true); }
    get memsz(): bigint   { return this.view.getBigUint64(0x28, true); }
    get align(): bigint   { return this.view.getBigUint64(0x30, true); }

    flagsString(): string {
        let s = "";
        s += (this.flags & PF_R) ? "R" : "-";
        s += (this.flags & PF_W) ? "W" : "-";
        s += (this.flags & PF_X) ? "X" : "-";
        return s;
    }
}

function testProgramHeader(): void {
    // Code segment: readable + executable, not writable
    const text = Elf64Phdr.load(
        PT_LOAD, PF_R | PF_X,
        0n, 0x40_0000n,
        0x1000n, 0x1000n,
        0x1000n,
    );

    assert(text.type === PT_LOAD, "PT_LOAD");
    assert(text.flagsString() === "R-X", "code is R-X");
    assert(text.vaddr === 0x40_0000n, "code vaddr");
    assert(text.filesz === text.memsz, "code: filesz == memsz");

    // Data segment with .bss: memsz > filesz (zero-filled portion)
    const data = Elf64Phdr.load(
        PT_LOAD, PF_R | PF_W,
        0x1000n, 0x60_0000n,
        0x200n, 0x1000n, // memsz > filesz: .bss is zeroed
        0x1000n,
    );

    assert(data.flagsString() === "RW-", "data is RW-");
    assert(data.memsz > data.filesz, "bss: memsz > filesz");

    // Verify structure size
    assert(PHDR_SIZE === 56, "phdr is 56 bytes");
}

// ── Section Header (64 bytes) ───────────────────────────────────────

// Layout:
//   [0x00..0x04)  sh_name       4 bytes  (offset into .shstrtab)
//   [0x04..0x08)  sh_type       4 bytes
//   [0x08..0x10)  sh_flags      8 bytes
//   [0x10..0x18)  sh_addr       8 bytes  (virtual address if loaded)
//   [0x18..0x20)  sh_offset     8 bytes  (file offset)
//   [0x20..0x28)  sh_size       8 bytes
//   [0x28..0x2C)  sh_link       4 bytes
//   [0x2C..0x30)  sh_info       4 bytes
//   [0x30..0x38)  sh_addralign  8 bytes
//   [0x38..0x40)  sh_entsize    8 bytes  (for tables: entry size)
//   Total: 0x40 = 64 bytes

const SHDR_SIZE = 64;

class Elf64Shdr {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        this.buf = new ArrayBuffer(SHDR_SIZE);
        this.view = new DataView(this.buf);
    }

    static build(opts: {
        name: number;
        type: number;
        flags: bigint;
        addr: bigint;
        offset: bigint;
        size: bigint;
        addralign: bigint;
        entsize?: bigint;
    }): Elf64Shdr {
        const sh = new Elf64Shdr();
        const v = sh.view;
        v.setUint32(0x00, opts.name, true);
        v.setUint32(0x04, opts.type, true);
        v.setBigUint64(0x08, opts.flags, true);
        v.setBigUint64(0x10, opts.addr, true);
        v.setBigUint64(0x18, opts.offset, true);
        v.setBigUint64(0x20, opts.size, true);
        v.setUint32(0x28, 0, true);  // link
        v.setUint32(0x2C, 0, true);  // info
        v.setBigUint64(0x30, opts.addralign, true);
        v.setBigUint64(0x38, opts.entsize ?? 0n, true);
        return sh;
    }

    get name(): number      { return this.view.getUint32(0x00, true); }
    get type(): number      { return this.view.getUint32(0x04, true); }
    get flags(): bigint     { return this.view.getBigUint64(0x08, true); }
    get addr(): bigint      { return this.view.getBigUint64(0x10, true); }
    get offset(): bigint    { return this.view.getBigUint64(0x18, true); }
    get size(): bigint      { return this.view.getBigUint64(0x20, true); }
    get addralign(): bigint { return this.view.getBigUint64(0x30, true); }
    get entsize(): bigint   { return this.view.getBigUint64(0x38, true); }
}

function testSectionHeader(): void {
    // .text section
    const text = Elf64Shdr.build({
        name: 1,
        type: SHT_PROGBITS,
        flags: BigInt(SHF_ALLOC | SHF_EXECINSTR),
        addr: 0x40_1000n,
        offset: 0x1000n,
        size: 0x500n,
        addralign: 16n,
    });

    assert(text.type === SHT_PROGBITS, "text is PROGBITS");
    assert(text.flags === BigInt(SHF_ALLOC | SHF_EXECINSTR), "text is AX");
    assert(text.size === 0x500n, "text size");

    // .bss section: SHT_NOBITS means no file data
    const bss = Elf64Shdr.build({
        name: 7,
        type: SHT_NOBITS,
        flags: BigInt(SHF_ALLOC | SHF_WRITE),
        addr: 0x60_2000n,
        offset: 0x2000n,
        size: 0x1000n,
        addralign: 32n,
    });

    assert(bss.type === SHT_NOBITS, "bss is NOBITS");
    assert(bss.flags === BigInt(SHF_ALLOC | SHF_WRITE), "bss is WA");

    // Verify structure size
    assert(SHDR_SIZE === 64, "shdr is 64 bytes");
}

// ── Full ELF Serialization ──────────────────────────────────────────

function testElf64Serialization(): void {
    // Build a complete ELF with header + 1 phdr, verify total byte count
    const hdr = Elf64Ehdr.build({
        type: ET_EXEC,
        machine: EM_X86_64,
        entry: 0x40_0078n,
        phnum: 1,
        shnum: 0,
        shstrndx: 0,
    });

    const phdr = Elf64Phdr.load(
        PT_LOAD, PF_R | PF_X,
        0n, 0x40_0000n,
        0x100n, 0x100n,
        0x1000n,
    );

    // Combine into a single buffer
    const total = EHDR_SIZE + PHDR_SIZE;
    const combined = new Uint8Array(total);
    combined.set(new Uint8Array(hdr.buf), 0);
    combined.set(new Uint8Array(phdr.buf), EHDR_SIZE);

    assert(combined.length === 120, "ehdr + phdr = 120 bytes");

    // Verify magic at the start
    assert(combined[0] === 0x7F, "magic[0]");
    assert(combined[1] === 0x45, "magic[1]");

    // Verify phdr starts at offset 64
    const phdrView = new DataView(combined.buffer, EHDR_SIZE, PHDR_SIZE);
    assert(phdrView.getUint32(0, true) === PT_LOAD, "phdr type at offset 64");
}

// ── Segment Permissions ─────────────────────────────────────────────

// W^X (Write XOR Execute) is a security principle:
// A memory page should NEVER be both writable and executable.
// This prevents code injection attacks.

function testSegmentPermissions(): void {
    const segments: Array<{ name: string; flags: number }> = [
        { name: ".text",   flags: PF_R | PF_X },       // code: read + execute
        { name: ".rodata", flags: PF_R },               // constants: read only
        { name: ".data",   flags: PF_R | PF_W },        // globals: read + write
        { name: ".bss",    flags: PF_R | PF_W },        // zero-init: read + write
    ];

    for (const seg of segments) {
        // W^X check: writable AND executable is a security violation
        const wxViolation = (seg.flags & PF_W) !== 0 && (seg.flags & PF_X) !== 0;
        assert(!wxViolation, `${seg.name} must not be W+X`);
    }

    // .text is executable but not writable
    assert((segments[0].flags & PF_X) !== 0, ".text is executable");
    assert((segments[0].flags & PF_W) === 0, ".text is not writable");

    // .data is writable but not executable
    assert((segments[2].flags & PF_W) !== 0, ".data is writable");
    assert((segments[2].flags & PF_X) === 0, ".data is not executable");
}

// ── Section Types ───────────────────────────────────────────────────

function sectionTypeName(type_: number): string {
    const names: Record<number, string> = {
        [SHT_NULL]:     "NULL",
        [SHT_PROGBITS]: "PROGBITS",
        [SHT_SYMTAB]:   "SYMTAB",
        [SHT_STRTAB]:   "STRTAB",
        [SHT_RELA]:     "RELA",
        [SHT_NOBITS]:   "NOBITS",
        [SHT_DYNSYM]:   "DYNSYM",
    };
    return names[type_] ?? `UNKNOWN(${type_})`;
}

function testSectionTypes(): void {
    assert(sectionTypeName(SHT_PROGBITS) === "PROGBITS", "progbits name");
    assert(sectionTypeName(SHT_NOBITS) === "NOBITS", "nobits name");
    assert(sectionTypeName(SHT_SYMTAB) === "SYMTAB", "symtab name");
    assert(sectionTypeName(999) === "UNKNOWN(999)", "unknown type");
}

// ── String Table ────────────────────────────────────────────────────

// ELF string tables are sequences of null-terminated strings.
// Section names, symbol names — all stored this way.
// An index into the table is just a byte offset.

class StringTable {
    private data: number[] = [0]; // starts with a null byte (index 0 = empty string)

    /** Add a string, return its offset in the table. */
    add(s: string): number {
        const offset = this.data.length;
        for (let i = 0; i < s.length; i++) {
            this.data.push(s.charCodeAt(i));
        }
        this.data.push(0); // null terminator
        return offset;
    }

    /** Look up a string by offset. */
    get(offset: number): string {
        let end = offset;
        while (end < this.data.length && this.data[end] !== 0) {
            end++;
        }
        return String.fromCharCode(...this.data.slice(offset, end));
    }

    get size(): number { return this.data.length; }
}

function testStringTable(): void {
    const strtab = new StringTable();

    const textIdx = strtab.add(".text");
    const dataIdx = strtab.add(".data");
    const bssIdx = strtab.add(".bss");

    assert(strtab.get(0) === "", "index 0 is empty string");
    assert(strtab.get(textIdx) === ".text", "lookup .text");
    assert(strtab.get(dataIdx) === ".data", "lookup .data");
    assert(strtab.get(bssIdx) === ".bss", "lookup .bss");

    // Offsets are sequential: 0, 1, 1+6=7, 7+6=13
    assert(textIdx === 1, ".text at offset 1");
    assert(dataIdx === 7, ".data at offset 7");
    assert(bssIdx === 13, ".bss at offset 13");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
