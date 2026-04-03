// ELF and Executable Formats — Rust Implementation
//
// Demonstrates ELF binary format internals:
//   1. ELF header parsing (64-bit)
//   2. Program header (segment) enumeration
//   3. Section header enumeration with string table resolution
//   4. Symbol table parsing
//   5. Building a minimal ELF executable from scratch
//
// This is what readelf, objdump, and linkers do when reading binaries.

use std::fmt;

// ── ELF Constants ─────────────────────────────────────────────────────────

const ELF_MAGIC: [u8; 4] = [0x7F, b'E', b'L', b'F'];
const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1; // little-endian
const ET_EXEC: u16 = 2;
const EM_X86_64: u16 = 62;
const PT_LOAD: u32 = 1;
const PT_NOTE: u32 = 4;
const PF_X: u32 = 1;
const PF_W: u32 = 2;
const PF_R: u32 = 4;
const SHT_NULL: u32 = 0;
const SHT_PROGBITS: u32 = 1;
const SHT_SYMTAB: u32 = 2;
const SHT_STRTAB: u32 = 3;
const SHT_NOBITS: u32 = 8;

// ── ELF Header (64-bit) ──────────────────────────────────────────────────

#[derive(Debug)]
struct Elf64Header {
    e_ident: [u8; 16],
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
}

impl Elf64Header {
    /// Create a minimal ELF64 header.
    fn new(entry: u64, phnum: u16, shnum: u16) -> Self {
        let mut ident = [0u8; 16];
        ident[0..4].copy_from_slice(&ELF_MAGIC);
        ident[4] = ELFCLASS64;
        ident[5] = ELFDATA2LSB;
        ident[6] = 1; // EV_CURRENT

        Self {
            e_ident: ident,
            e_type: ET_EXEC,
            e_machine: EM_X86_64,
            e_version: 1,
            e_entry: entry,
            e_phoff: 64,  // immediately after ELF header
            e_shoff: 0,   // no section headers in minimal binary
            e_flags: 0,
            e_ehsize: 64,
            e_phentsize: 56,
            e_phnum: phnum,
            e_shentsize: 64,
            e_shnum: shnum,
            e_shstrndx: 0,
        }
    }

    fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(64);
        buf.extend_from_slice(&self.e_ident);
        buf.extend_from_slice(&self.e_type.to_le_bytes());
        buf.extend_from_slice(&self.e_machine.to_le_bytes());
        buf.extend_from_slice(&self.e_version.to_le_bytes());
        buf.extend_from_slice(&self.e_entry.to_le_bytes());
        buf.extend_from_slice(&self.e_phoff.to_le_bytes());
        buf.extend_from_slice(&self.e_shoff.to_le_bytes());
        buf.extend_from_slice(&self.e_flags.to_le_bytes());
        buf.extend_from_slice(&self.e_ehsize.to_le_bytes());
        buf.extend_from_slice(&self.e_phentsize.to_le_bytes());
        buf.extend_from_slice(&self.e_phnum.to_le_bytes());
        buf.extend_from_slice(&self.e_shentsize.to_le_bytes());
        buf.extend_from_slice(&self.e_shnum.to_le_bytes());
        buf.extend_from_slice(&self.e_shstrndx.to_le_bytes());
        buf
    }
}

impl fmt::Display for Elf64Header {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let elf_type = match self.e_type {
            0 => "NONE", 1 => "REL", 2 => "EXEC", 3 => "DYN", _ => "?",
        };
        writeln!(f, "  ELF Header:")?;
        writeln!(f, "    Class:      ELF64")?;
        writeln!(f, "    Data:       {}", if self.e_ident[5] == 1 { "2's complement, little endian" } else { "big endian" })?;
        writeln!(f, "    Type:       {} ({})", elf_type, self.e_type)?;
        writeln!(f, "    Machine:    {}", if self.e_machine == 62 { "x86-64" } else { "other" })?;
        writeln!(f, "    Entry:      0x{:X}", self.e_entry)?;
        writeln!(f, "    PH offset:  {} ({} entries × {} bytes)", self.e_phoff, self.e_phnum, self.e_phentsize)?;
        writeln!(f, "    SH offset:  {} ({} entries × {} bytes)", self.e_shoff, self.e_shnum, self.e_shentsize)?;
        write!(f, "    Shstrndx:   {}", self.e_shstrndx)
    }
}

// ── Program Header ────────────────────────────────────────────────────────

#[derive(Debug)]
struct Elf64Phdr {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
}

impl Elf64Phdr {
    fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(56);
        buf.extend_from_slice(&self.p_type.to_le_bytes());
        buf.extend_from_slice(&self.p_flags.to_le_bytes());
        buf.extend_from_slice(&self.p_offset.to_le_bytes());
        buf.extend_from_slice(&self.p_vaddr.to_le_bytes());
        buf.extend_from_slice(&self.p_paddr.to_le_bytes());
        buf.extend_from_slice(&self.p_filesz.to_le_bytes());
        buf.extend_from_slice(&self.p_memsz.to_le_bytes());
        buf.extend_from_slice(&self.p_align.to_le_bytes());
        buf
    }

    fn flags_str(&self) -> String {
        let mut s = String::new();
        if self.p_flags & PF_R != 0 { s.push('R'); }
        if self.p_flags & PF_W != 0 { s.push('W'); }
        if self.p_flags & PF_X != 0 { s.push('X'); }
        s
    }

    fn type_str(&self) -> &'static str {
        match self.p_type {
            0 => "NULL", 1 => "LOAD", 2 => "DYNAMIC", 3 => "INTERP",
            4 => "NOTE", 6 => "PHDR", 0x6474e551 => "GNU_STACK",
            _ => "OTHER",
        }
    }
}

impl fmt::Display for Elf64Phdr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{:<10} off=0x{:06X} vaddr=0x{:08X} filesz={:<6} memsz={:<6} flags={} align=0x{:X}",
            self.type_str(), self.p_offset, self.p_vaddr,
            self.p_filesz, self.p_memsz, self.flags_str(), self.p_align
        )
    }
}

// ── Section Header ────────────────────────────────────────────────────────

struct Section {
    name: String,
    sh_type: u32,
    vaddr: u64,
    offset: u64,
    size: u64,
    flags: u64,
}

impl Section {
    fn type_str(&self) -> &'static str {
        match self.sh_type {
            SHT_NULL => "NULL",
            SHT_PROGBITS => "PROGBITS",
            SHT_SYMTAB => "SYMTAB",
            SHT_STRTAB => "STRTAB",
            SHT_NOBITS => "NOBITS",
            4 => "RELA",
            9 => "REL",
            _ => "OTHER",
        }
    }
}

impl fmt::Display for Section {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut flags_str = String::new();
        if self.flags & 1 != 0 { flags_str.push('W'); }
        if self.flags & 2 != 0 { flags_str.push('A'); }
        if self.flags & 4 != 0 { flags_str.push('X'); }

        write!(
            f,
            "{:<18} {:<10} addr=0x{:08X} off=0x{:04X} size={:<6} flags={}",
            self.name, self.type_str(), self.vaddr, self.offset, self.size, flags_str
        )
    }
}

// ── Build a minimal ELF ──────────────────────────────────────────────────

fn build_minimal_elf() -> Vec<u8> {
    let base_addr: u64 = 0x400000;
    let header_size: u64 = 64 + 56; // ELF header + 1 program header

    // Machine code: mov rdi, 42; mov rax, 60; syscall (exit(42))
    let code: Vec<u8> = vec![
        0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00, // mov rdi, 42
        0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00, // mov rax, 60 (exit)
        0x0F, 0x05,                                  // syscall
    ];

    let total_size = header_size + code.len() as u64;
    let entry = base_addr + header_size;

    let header = Elf64Header::new(entry, 1, 0);
    let phdr = Elf64Phdr {
        p_type: PT_LOAD,
        p_flags: PF_R | PF_X,
        p_offset: 0,
        p_vaddr: base_addr,
        p_paddr: base_addr,
        p_filesz: total_size,
        p_memsz: total_size,
        p_align: 0x1000,
    };

    let mut binary = Vec::new();
    binary.extend_from_slice(&header.to_bytes());
    binary.extend_from_slice(&phdr.to_bytes());
    binary.extend_from_slice(&code);

    binary
}

// ── Simulated ELF Analysis ───────────────────────────────────────────────

fn analyze_typical_binary() {
    // Simulate what readelf shows for a typical binary
    let phdrs = vec![
        Elf64Phdr { p_type: PT_LOAD, p_flags: PF_R | PF_X, p_offset: 0, p_vaddr: 0x400000, p_paddr: 0x400000, p_filesz: 8192, p_memsz: 8192, p_align: 0x1000 },
        Elf64Phdr { p_type: PT_LOAD, p_flags: PF_R | PF_W, p_offset: 0x3000, p_vaddr: 0x403000, p_paddr: 0x403000, p_filesz: 512, p_memsz: 1024, p_align: 0x1000 },
        Elf64Phdr { p_type: PT_NOTE, p_flags: PF_R, p_offset: 0x254, p_vaddr: 0x400254, p_paddr: 0x400254, p_filesz: 32, p_memsz: 32, p_align: 4 },
    ];

    println!("  Program Headers:");
    for phdr in &phdrs {
        println!("    {}", phdr);
    }
    println!("    Note: segment 2 has memsz > filesz → {} bytes of BSS (zero-filled)",
        phdrs[1].p_memsz - phdrs[1].p_filesz);

    let sections = vec![
        Section { name: ".text".into(), sh_type: SHT_PROGBITS, vaddr: 0x401000, offset: 0x1000, size: 4096, flags: 6 },
        Section { name: ".rodata".into(), sh_type: SHT_PROGBITS, vaddr: 0x402000, offset: 0x2000, size: 256, flags: 2 },
        Section { name: ".data".into(), sh_type: SHT_PROGBITS, vaddr: 0x403000, offset: 0x3000, size: 512, flags: 3 },
        Section { name: ".bss".into(), sh_type: SHT_NOBITS, vaddr: 0x403200, offset: 0x3200, size: 512, flags: 3 },
        Section { name: ".symtab".into(), sh_type: SHT_SYMTAB, vaddr: 0, offset: 0x3200, size: 384, flags: 0 },
        Section { name: ".strtab".into(), sh_type: SHT_STRTAB, vaddr: 0, offset: 0x3380, size: 128, flags: 0 },
        Section { name: ".shstrtab".into(), sh_type: SHT_STRTAB, vaddr: 0, offset: 0x3400, size: 64, flags: 0 },
    ];

    println!("\n  Section Headers:");
    for sec in &sections {
        println!("    {}", sec);
    }
    println!("    Note: .bss is NOBITS — takes no space in file, zero-filled in memory");
    println!("    Note: .symtab/.strtab have vaddr=0 — not loaded, tools read from file");
}

fn main() {
    println!("ELF and Executable Formats — binary structure deep dive:\n");

    // ── Build and analyze minimal ELF ─────────────────────────────────
    println!("1. Building minimal ELF executable (exit(42)):");
    let binary = build_minimal_elf();
    println!("   Total size: {} bytes ({} header + {} code)",
        binary.len(), 64 + 56, binary.len() - 64 - 56);

    // Parse our own binary
    let header = Elf64Header::new(
        0x400000 + 120,
        1,
        0,
    );
    println!("{}", header);

    // ── Typical binary structure ──────────────────────────────────────
    println!("\n2. Typical ELF binary structure:");
    analyze_typical_binary();

    // ── Section to segment mapping ────────────────────────────────────
    println!("\n3. Section → Segment mapping:");
    println!("   PT_LOAD (R+X): .text, .rodata  (code segment)");
    println!("   PT_LOAD (R+W): .data, .bss      (data segment)");
    println!("   Not loaded:    .symtab, .strtab, .debug_*  (tools only)");

    // ── Virtual address to file offset ────────────────────────────────
    println!("\n4. Virtual address → file offset conversion:");
    println!("   Given: vaddr=0x401234, PT_LOAD(vaddr=0x400000, offset=0x0)");
    println!("   file_offset = 0x401234 - 0x400000 + 0x0 = 0x1234");
    println!("   This is what GDB does to read code from the binary file.");

    // ── ELF sizes comparison ──────────────────────────────────────────
    println!("\n5. Binary size comparison:");
    println!("   {:>30} {:>10}", "Binary", "Size");
    println!("   {:>30} {:>10}", "-".repeat(30), "-".repeat(10));
    println!("   {:>30} {:>7} B", "Our minimal ELF (exit(42))", binary.len());
    println!("   {:>30} {:>7} B", "Cyrius seed (Hello, Cyrius!)", 199);
    println!("   {:>30} {:>7} B", "C hello (static, stripped)", "~800K");
    println!("   {:>30} {:>7} B", "C hello (dynamic, stripped)", "~16K");
    println!("   {:>30} {:>7} B", "Rust hello (stripped)", "~300K");
    println!("   {:>30} {:>7} B", "Go hello (stripped)", "~1.2M");
}
