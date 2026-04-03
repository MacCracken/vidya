// Binary Formats — Rust Implementation
//
// Generates a minimal static ELF64 binary from scratch.
// No linker, no libc, no external tools.
// The resulting binary prints "ELF!" and exits.
//
// Structure: 64-byte ELF header + 56-byte program header + machine code
// Total overhead: 120 bytes. The rest is your code.

use std::io::Write;

const BASE_ADDR: u64 = 0x400000;
const ELF_HDR_SIZE: u64 = 64;
const PHDR_SIZE: u64 = 56;
const CODE_OFFSET: u64 = ELF_HDR_SIZE + PHDR_SIZE;

fn main() {
    // x86_64 machine code: write "ELF!\n" to stdout, then exit(0)
    let code: Vec<u8> = vec![
        // mov rax, 1 (write syscall)
        0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00,
        // mov rdi, 1 (stdout)
        0x48, 0xC7, 0xC7, 0x01, 0x00, 0x00, 0x00,
        // lea rsi, [rip+msg] — point to message after this code
        0x48, 0x8D, 0x35, 0x0E, 0x00, 0x00, 0x00,
        // mov rdx, 5 (length)
        0x48, 0xC7, 0xC2, 0x05, 0x00, 0x00, 0x00,
        // syscall
        0x0F, 0x05,
        // mov rax, 60 (exit)
        0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
        // xor rdi, rdi (exit code 0)
        0x48, 0x31, 0xFF,
        // syscall
        0x0F, 0x05,
        // "ELF!\n"
        b'E', b'L', b'F', b'!', b'\n',
    ];

    let entry_point = BASE_ADDR + CODE_OFFSET;
    let file_size = CODE_OFFSET as usize + code.len();

    let mut elf = Vec::with_capacity(file_size);

    // ── ELF Header (64 bytes) ──
    elf.extend_from_slice(&[0x7F, b'E', b'L', b'F']); // magic
    elf.push(2);                                         // ELFCLASS64
    elf.push(1);                                         // little-endian
    elf.push(1);                                         // ELF version
    elf.push(0);                                         // OS/ABI
    elf.extend_from_slice(&[0; 8]);                      // padding
    elf.extend_from_slice(&2u16.to_le_bytes());          // ET_EXEC
    elf.extend_from_slice(&0x3Eu16.to_le_bytes());       // EM_X86_64
    elf.extend_from_slice(&1u32.to_le_bytes());          // version
    elf.extend_from_slice(&entry_point.to_le_bytes());   // entry
    elf.extend_from_slice(&ELF_HDR_SIZE.to_le_bytes());  // phoff
    elf.extend_from_slice(&0u64.to_le_bytes());          // shoff (none)
    elf.extend_from_slice(&0u32.to_le_bytes());          // flags
    elf.extend_from_slice(&64u16.to_le_bytes());         // ehsize
    elf.extend_from_slice(&56u16.to_le_bytes());         // phentsize
    elf.extend_from_slice(&1u16.to_le_bytes());          // phnum
    elf.extend_from_slice(&64u16.to_le_bytes());         // shentsize
    elf.extend_from_slice(&0u16.to_le_bytes());          // shnum
    elf.extend_from_slice(&0u16.to_le_bytes());          // shstrndx
    assert_eq!(elf.len(), 64);

    // ── Program Header (56 bytes) ──
    elf.extend_from_slice(&1u32.to_le_bytes());          // PT_LOAD
    elf.extend_from_slice(&5u32.to_le_bytes());          // PF_R | PF_X
    elf.extend_from_slice(&0u64.to_le_bytes());          // offset
    elf.extend_from_slice(&BASE_ADDR.to_le_bytes());     // vaddr
    elf.extend_from_slice(&BASE_ADDR.to_le_bytes());     // paddr
    elf.extend_from_slice(&(file_size as u64).to_le_bytes()); // filesz
    elf.extend_from_slice(&(file_size as u64).to_le_bytes()); // memsz
    elf.extend_from_slice(&0x1000u64.to_le_bytes());     // align
    assert_eq!(elf.len(), 120);

    // ── Code ──
    elf.extend_from_slice(&code);

    // Write to file
    let mut f = std::fs::File::create("/tmp/vidya_elf_demo").unwrap();
    f.write_all(&elf).unwrap();

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions("/tmp/vidya_elf_demo",
            std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    println!("Generated ELF binary: /tmp/vidya_elf_demo ({} bytes)", elf.len());
    println!("  Header: 64 bytes (ELF) + 56 bytes (program header) = 120 bytes overhead");
    println!("  Code: {} bytes", code.len());
    println!("  Entry point: 0x{:X}", entry_point);
    println!("Run it: /tmp/vidya_elf_demo");
}
