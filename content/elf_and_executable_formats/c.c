// Vidya — ELF and Executable Formats in C
//
// Defines ELF64 structures and builds/verifies a minimal ELF binary:
//   1. ELF64 header struct (64 bytes, packed)
//   2. Program header struct (56 bytes) — segment/runtime view
//   3. Section header struct (64 bytes) — section/link-time view
//   4. Minimal ELF construction — just ehdr + phdr + machine code
//   5. Section-to-segment mapping — multiple sections in one segment
//
// The kernel reads program headers. The linker reads section headers.
// A stripped binary has no section headers — it still runs.

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── ELF Constants ───────────────────────────────────────────────────

#define EI_NIDENT     16
#define ELFCLASS64     2
#define ELFDATA2LSB    1
#define EV_CURRENT     1
#define ET_EXEC        2
#define EM_X86_64     62   // 0x3E

#define PT_NULL        0
#define PT_LOAD        1
#define PT_DYNAMIC     2
#define PT_INTERP      3
#define PT_NOTE        4

#define PF_X           1
#define PF_W           2
#define PF_R           4

#define SHT_NULL       0
#define SHT_PROGBITS   1
#define SHT_SYMTAB     2
#define SHT_STRTAB     3
#define SHT_NOBITS     8

#define SHF_WRITE      1
#define SHF_ALLOC      2
#define SHF_EXECINSTR  4

// ── ELF64 Header (64 bytes) ────────────────────────────────────────

typedef struct __attribute__((packed)) {
    uint8_t  e_ident[EI_NIDENT];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint64_t e_entry;
    uint64_t e_phoff;
    uint64_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} Elf64_Ehdr;

// ── ELF64 Program Header (56 bytes) ────────────────────────────────

typedef struct __attribute__((packed)) {
    uint32_t p_type;
    uint32_t p_flags;
    uint64_t p_offset;
    uint64_t p_vaddr;
    uint64_t p_paddr;
    uint64_t p_filesz;
    uint64_t p_memsz;
    uint64_t p_align;
} Elf64_Phdr;

// ── ELF64 Section Header (64 bytes) ────────────────────────────────

typedef struct __attribute__((packed)) {
    uint32_t sh_name;       // offset into .shstrtab
    uint32_t sh_type;
    uint64_t sh_flags;
    uint64_t sh_addr;       // virtual address if loaded
    uint64_t sh_offset;     // file offset
    uint64_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint64_t sh_addralign;
    uint64_t sh_entsize;
} Elf64_Shdr;

// ── ELF64 Symbol Table Entry (24 bytes) ─────────────────────────────

typedef struct __attribute__((packed)) {
    uint32_t st_name;
    uint8_t  st_info;
    uint8_t  st_other;
    uint16_t st_shndx;
    uint64_t st_value;
    uint64_t st_size;
} Elf64_Sym;

// ── Verify struct sizes ─────────────────────────────────────────────
// The ELF spec defines exact sizes. If the compiler adds padding,
// the binary format is wrong.

static void test_struct_sizes(void) {
    assert(sizeof(Elf64_Ehdr) == 64);
    assert(sizeof(Elf64_Phdr) == 56);
    assert(sizeof(Elf64_Shdr) == 64);
    assert(sizeof(Elf64_Sym)  == 24);
}

// ── Verify field offsets ────────────────────────────────────────────
// Every field must be at its ELF-specified offset.

static void test_field_offsets(void) {
    // ELF header offsets
    assert(offsetof(Elf64_Ehdr, e_ident)     == 0);
    assert(offsetof(Elf64_Ehdr, e_type)      == 16);
    assert(offsetof(Elf64_Ehdr, e_machine)   == 18);
    assert(offsetof(Elf64_Ehdr, e_version)   == 20);
    assert(offsetof(Elf64_Ehdr, e_entry)     == 24);
    assert(offsetof(Elf64_Ehdr, e_phoff)     == 32);
    assert(offsetof(Elf64_Ehdr, e_shoff)     == 40);
    assert(offsetof(Elf64_Ehdr, e_flags)     == 48);
    assert(offsetof(Elf64_Ehdr, e_ehsize)    == 52);
    assert(offsetof(Elf64_Ehdr, e_phentsize) == 54);
    assert(offsetof(Elf64_Ehdr, e_phnum)     == 56);
    assert(offsetof(Elf64_Ehdr, e_shentsize) == 58);
    assert(offsetof(Elf64_Ehdr, e_shnum)     == 60);
    assert(offsetof(Elf64_Ehdr, e_shstrndx)  == 62);

    // Program header offsets
    assert(offsetof(Elf64_Phdr, p_type)   == 0);
    assert(offsetof(Elf64_Phdr, p_flags)  == 4);
    assert(offsetof(Elf64_Phdr, p_offset) == 8);
    assert(offsetof(Elf64_Phdr, p_vaddr)  == 16);
    assert(offsetof(Elf64_Phdr, p_paddr)  == 24);
    assert(offsetof(Elf64_Phdr, p_filesz) == 32);
    assert(offsetof(Elf64_Phdr, p_memsz)  == 40);
    assert(offsetof(Elf64_Phdr, p_align)  == 48);

    // Section header offsets
    assert(offsetof(Elf64_Shdr, sh_name)      == 0);
    assert(offsetof(Elf64_Shdr, sh_type)      == 4);
    assert(offsetof(Elf64_Shdr, sh_flags)     == 8);
    assert(offsetof(Elf64_Shdr, sh_addr)      == 16);
    assert(offsetof(Elf64_Shdr, sh_offset)    == 24);
    assert(offsetof(Elf64_Shdr, sh_size)      == 32);
    assert(offsetof(Elf64_Shdr, sh_link)      == 40);
    assert(offsetof(Elf64_Shdr, sh_info)      == 44);
    assert(offsetof(Elf64_Shdr, sh_addralign) == 48);
    assert(offsetof(Elf64_Shdr, sh_entsize)   == 56);

    // Symbol table entry offsets
    assert(offsetof(Elf64_Sym, st_name)  == 0);
    assert(offsetof(Elf64_Sym, st_info)  == 4);
    assert(offsetof(Elf64_Sym, st_other) == 5);
    assert(offsetof(Elf64_Sym, st_shndx) == 6);
    assert(offsetof(Elf64_Sym, st_value) == 8);
    assert(offsetof(Elf64_Sym, st_size)  == 16);
}

// ── Build and verify a minimal ELF header ───────────────────────────

static Elf64_Ehdr make_minimal_ehdr(uint64_t entry, uint16_t phnum) {
    Elf64_Ehdr ehdr;
    memset(&ehdr, 0, sizeof(ehdr));

    // e_ident: magic + class + encoding + version
    ehdr.e_ident[0] = 0x7F;
    ehdr.e_ident[1] = 'E';
    ehdr.e_ident[2] = 'L';
    ehdr.e_ident[3] = 'F';
    ehdr.e_ident[4] = ELFCLASS64;
    ehdr.e_ident[5] = ELFDATA2LSB;
    ehdr.e_ident[6] = EV_CURRENT;
    // bytes 7-15: zero (OS/ABI + padding)

    ehdr.e_type      = ET_EXEC;
    ehdr.e_machine   = EM_X86_64;
    ehdr.e_version   = EV_CURRENT;
    ehdr.e_entry     = entry;
    ehdr.e_phoff     = sizeof(Elf64_Ehdr);  // program headers immediately after
    ehdr.e_shoff     = 0;                    // no section headers
    ehdr.e_flags     = 0;
    ehdr.e_ehsize    = sizeof(Elf64_Ehdr);
    ehdr.e_phentsize = sizeof(Elf64_Phdr);
    ehdr.e_phnum     = phnum;
    ehdr.e_shentsize = sizeof(Elf64_Shdr);
    ehdr.e_shnum     = 0;
    ehdr.e_shstrndx  = 0;

    return ehdr;
}

static void test_minimal_elf_header(void) {
    uint64_t base = 0x400000;
    uint64_t entry = base + 64 + 56;  // after ehdr + 1 phdr

    Elf64_Ehdr ehdr = make_minimal_ehdr(entry, 1);

    // Verify magic
    assert(ehdr.e_ident[0] == 0x7F);
    assert(ehdr.e_ident[1] == 'E');
    assert(ehdr.e_ident[2] == 'L');
    assert(ehdr.e_ident[3] == 'F');

    // Verify class and encoding
    assert(ehdr.e_ident[4] == ELFCLASS64);
    assert(ehdr.e_ident[5] == ELFDATA2LSB);

    // Verify type and machine
    assert(ehdr.e_type == ET_EXEC);
    assert(ehdr.e_machine == EM_X86_64);

    // Verify entry point is within the loadable range
    assert(ehdr.e_entry == entry);
    assert(ehdr.e_entry > base);

    // Verify program header location
    assert(ehdr.e_phoff == 64);
    assert(ehdr.e_phentsize == 56);
    assert(ehdr.e_phnum == 1);
}

// ── Build a PT_LOAD program header ──────────────────────────────────

static Elf64_Phdr make_load_phdr(uint64_t vaddr, uint64_t filesz,
                                  uint64_t memsz, uint32_t flags) {
    Elf64_Phdr phdr;
    memset(&phdr, 0, sizeof(phdr));

    phdr.p_type   = PT_LOAD;
    phdr.p_flags  = flags;
    phdr.p_offset = 0;
    phdr.p_vaddr  = vaddr;
    phdr.p_paddr  = vaddr;
    phdr.p_filesz = filesz;
    phdr.p_memsz  = memsz;
    phdr.p_align  = 0x1000;

    return phdr;
}

// ── Section vs segment duality ──────────────────────────────────────
// Sections are the LINKER'S view — organize by type (.text, .data, .bss)
// Segments are the LOADER'S view — organize by permissions (R+X, R+W)
//
// Multiple sections map to a single segment:
//   Segment 1 (R+X): .text, .rodata
//   Segment 2 (R+W): .data, .bss
//   Not loaded:       .symtab, .strtab, .debug_*

typedef struct {
    const char *name;
    uint32_t    sh_type;
    uint64_t    sh_flags;
    uint64_t    sh_addr;
    uint64_t    sh_offset;
    uint64_t    sh_size;
    int         segment_index;  // -1 = not loaded
} SectionInfo;

static void test_section_segment_mapping(void) {
    // Typical section layout in a simple executable
    SectionInfo sections[] = {
        // Segment 0: code (R+X)
        {".text",      SHT_PROGBITS, SHF_ALLOC | SHF_EXECINSTR,
                       0x401000, 0x1000, 4096, 0},
        {".rodata",    SHT_PROGBITS, SHF_ALLOC,
                       0x402000, 0x2000, 256,  0},

        // Segment 1: data (R+W)
        {".data",      SHT_PROGBITS, SHF_ALLOC | SHF_WRITE,
                       0x403000, 0x3000, 512,  1},
        {".bss",       SHT_NOBITS,   SHF_ALLOC | SHF_WRITE,
                       0x403200, 0x3200, 1024, 1},

        // Not loaded — linker and tools only
        {".symtab",    SHT_SYMTAB, 0, 0, 0x3200, 384,  -1},
        {".strtab",    SHT_STRTAB, 0, 0, 0x3380, 128,  -1},
        {".shstrtab",  SHT_STRTAB, 0, 0, 0x3400, 64,   -1},
    };
    int num_sections = sizeof(sections) / sizeof(sections[0]);

    // Verify loaded sections have SHF_ALLOC
    for (int i = 0; i < num_sections; i++) {
        if (sections[i].segment_index >= 0) {
            assert((sections[i].sh_flags & SHF_ALLOC) != 0);
        } else {
            assert((sections[i].sh_flags & SHF_ALLOC) == 0);
        }
    }

    // Verify .bss is SHT_NOBITS — takes no space in the file
    assert(sections[3].sh_type == SHT_NOBITS);
    // But has a non-zero size in memory
    assert(sections[3].sh_size > 0);

    // Count sections by segment
    int seg0_count = 0, seg1_count = 0, unloaded_count = 0;
    for (int i = 0; i < num_sections; i++) {
        if (sections[i].segment_index == 0) seg0_count++;
        else if (sections[i].segment_index == 1) seg1_count++;
        else unloaded_count++;
    }
    assert(seg0_count == 2);      // .text + .rodata
    assert(seg1_count == 2);      // .data + .bss
    assert(unloaded_count == 3);  // .symtab + .strtab + .shstrtab
}

// ── Build a minimal ELF binary in memory ────────────────────────────
// Structure: 64-byte ELF header + 56-byte program header + machine code
// Total overhead: 120 bytes. The rest is your program.

static void test_build_minimal_elf(void) {
    uint64_t base_addr = 0x400000;
    uint64_t code_offset = sizeof(Elf64_Ehdr) + sizeof(Elf64_Phdr);

    // Machine code: mov rdi, 42; mov rax, 60; syscall (exit(42))
    uint8_t code[] = {
        0x48, 0xC7, 0xC7, 0x2A, 0x00, 0x00, 0x00,  // mov rdi, 42
        0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,  // mov rax, 60 (exit)
        0x0F, 0x05,                                   // syscall
    };
    size_t code_size = sizeof(code);
    uint64_t total_size = code_offset + code_size;
    uint64_t entry = base_addr + code_offset;

    // Build header
    Elf64_Ehdr ehdr = make_minimal_ehdr(entry, 1);

    // Build program header
    Elf64_Phdr phdr = make_load_phdr(base_addr, total_size, total_size,
                                      PF_R | PF_X);

    // Assemble the binary
    uint8_t binary[256];
    memset(binary, 0, sizeof(binary));
    memcpy(binary, &ehdr, sizeof(ehdr));
    memcpy(binary + sizeof(ehdr), &phdr, sizeof(phdr));
    memcpy(binary + code_offset, code, code_size);

    // Verify the binary
    assert(total_size == 64 + 56 + 16);  // 136 bytes

    // Verify ELF magic at start
    assert(binary[0] == 0x7F);
    assert(binary[1] == 'E');
    assert(binary[2] == 'L');
    assert(binary[3] == 'F');

    // Verify entry point
    uint64_t *entry_ptr = (uint64_t *)(binary + 24);
    assert(*entry_ptr == entry);

    // Verify program header type at offset 64
    uint32_t *pt_ptr = (uint32_t *)(binary + 64);
    assert(*pt_ptr == PT_LOAD);

    // Verify code starts at offset 120
    assert(binary[120] == 0x48);  // REX.W prefix of first instruction
}

// ── BSS and memsz vs filesz ─────────────────────────────────────────
// p_memsz > p_filesz means the kernel zero-fills the difference (BSS).
// p_memsz < p_filesz is INVALID — kernel rejects it.

static void test_bss_memsz(void) {
    // Data segment with BSS
    Elf64_Phdr data_phdr = make_load_phdr(
        0x403000,  // vaddr
        512,       // filesz: .data section (initialized)
        1536,      // memsz: .data (512) + .bss (1024)
        PF_R | PF_W
    );

    assert(data_phdr.p_memsz > data_phdr.p_filesz);
    uint64_t bss_size = data_phdr.p_memsz - data_phdr.p_filesz;
    assert(bss_size == 1024);

    // Code segment: memsz == filesz (no BSS in code)
    Elf64_Phdr code_phdr = make_load_phdr(
        0x400000,
        8192,
        8192,
        PF_R | PF_X
    );
    assert(code_phdr.p_memsz == code_phdr.p_filesz);
}

// ── Virtual address to file offset conversion ───────────────────────
// file_offset = vaddr - segment.p_vaddr + segment.p_offset
// This is what GDB does to read code from the binary file.

static void test_vaddr_to_offset(void) {
    Elf64_Phdr segments[2] = {
        // Code segment
        {PT_LOAD, PF_R | PF_X, 0, 0x400000, 0x400000, 8192, 8192, 0x1000},
        // Data segment
        {PT_LOAD, PF_R | PF_W, 0x3000, 0x403000, 0x403000, 512, 1536, 0x1000},
    };

    // Find file offset for vaddr 0x401234
    uint64_t target = 0x401234;
    int found = 0;
    for (int i = 0; i < 2; i++) {
        if (target >= segments[i].p_vaddr &&
            target < segments[i].p_vaddr + segments[i].p_memsz) {
            uint64_t file_off = target - segments[i].p_vaddr + segments[i].p_offset;
            assert(file_off == 0x1234);
            found = 1;
            break;
        }
    }
    assert(found);

    // Find file offset for vaddr 0x403100 (in data segment)
    target = 0x403100;
    found = 0;
    for (int i = 0; i < 2; i++) {
        if (target >= segments[i].p_vaddr &&
            target < segments[i].p_vaddr + segments[i].p_memsz) {
            uint64_t file_off = target - segments[i].p_vaddr + segments[i].p_offset;
            assert(file_off == 0x3100);
            found = 1;
            break;
        }
    }
    assert(found);
}

// ── Symbol table structure ──────────────────────────────────────────
// Symbols map names to addresses. The st_info byte encodes
// binding (local/global/weak) in the upper 4 bits and
// type (notype/object/func/section/file) in the lower 4 bits.

#define STB_LOCAL   0
#define STB_GLOBAL  1
#define STB_WEAK    2

#define STT_NOTYPE  0
#define STT_OBJECT  1
#define STT_FUNC    2

#define ELF64_ST_INFO(bind, type) (((bind) << 4) + ((type) & 0xF))
#define ELF64_ST_BIND(info)       ((info) >> 4)
#define ELF64_ST_TYPE(info)       ((info) & 0xF)

static void test_symbol_info(void) {
    // A global function symbol
    uint8_t info = ELF64_ST_INFO(STB_GLOBAL, STT_FUNC);
    assert(ELF64_ST_BIND(info) == STB_GLOBAL);
    assert(ELF64_ST_TYPE(info) == STT_FUNC);

    // A local data object
    info = ELF64_ST_INFO(STB_LOCAL, STT_OBJECT);
    assert(ELF64_ST_BIND(info) == STB_LOCAL);
    assert(ELF64_ST_TYPE(info) == STT_OBJECT);

    // Symbol entry size is always 24 bytes
    assert(sizeof(Elf64_Sym) == 24);
}

int main(void) {
    printf("ELF and Executable Formats — C struct-level deep dive:\n\n");

    // ── Struct sizes ──────────────────────────────────────────────────
    printf("1. Struct sizes (packed):\n");
    test_struct_sizes();
    printf("   Elf64_Ehdr: %zu bytes\n", sizeof(Elf64_Ehdr));
    printf("   Elf64_Phdr: %zu bytes\n", sizeof(Elf64_Phdr));
    printf("   Elf64_Shdr: %zu bytes\n", sizeof(Elf64_Shdr));
    printf("   Elf64_Sym:  %zu bytes\n", sizeof(Elf64_Sym));

    // ── Field offsets ─────────────────────────────────────────────────
    printf("\n2. Field offset verification:\n");
    test_field_offsets();
    printf("   ELF header:     14 fields, all offsets verified\n");
    printf("   Program header:  8 fields, all offsets verified\n");
    printf("   Section header: 10 fields, all offsets verified\n");
    printf("   Symbol entry:    6 fields, all offsets verified\n");

    // ── Minimal ELF header ────────────────────────────────────────────
    printf("\n3. Minimal ELF header:\n");
    test_minimal_elf_header();
    printf("   Magic: \\x7fELF\n");
    printf("   Class: ELFCLASS64 (2)\n");
    printf("   Machine: EM_X86_64 (0x3E)\n");
    printf("   Entry: 0x400078 (BASE + 64 + 56)\n");

    // ── Section vs segment mapping ────────────────────────────────────
    printf("\n4. Section vs segment mapping:\n");
    test_section_segment_mapping();
    printf("   PT_LOAD R+X: .text, .rodata (2 sections)\n");
    printf("   PT_LOAD R+W: .data, .bss   (2 sections)\n");
    printf("   Not loaded:  .symtab, .strtab, .shstrtab (3 sections)\n");

    // ── Build minimal binary ──────────────────────────────────────────
    printf("\n5. Minimal ELF binary (exit(42)):\n");
    test_build_minimal_elf();
    printf("   Size: 136 bytes (64 ehdr + 56 phdr + 16 code)\n");
    printf("   No sections, no symbols, no string tables\n");

    // ── BSS and memsz ─────────────────────────────────────────────────
    printf("\n6. BSS segment (memsz > filesz):\n");
    test_bss_memsz();
    printf("   filesz=512 (.data), memsz=1536 (.data+.bss)\n");
    printf("   Kernel zero-fills 1024 bytes for .bss\n");

    // ── Virtual address to file offset ────────────────────────────────
    printf("\n7. Virtual address -> file offset:\n");
    test_vaddr_to_offset();
    printf("   0x401234 -> offset 0x1234 (in code segment)\n");
    printf("   0x403100 -> offset 0x3100 (in data segment)\n");

    // ── Symbol table ──────────────────────────────────────────────────
    printf("\n8. Symbol table encoding:\n");
    test_symbol_info();
    printf("   st_info = (bind << 4) | type\n");
    printf("   GLOBAL+FUNC = 0x%02X\n", ELF64_ST_INFO(STB_GLOBAL, STT_FUNC));
    printf("   LOCAL+OBJECT = 0x%02X\n", ELF64_ST_INFO(STB_LOCAL, STT_OBJECT));

    printf("\nAll ELF format examples passed.\n");
    return 0;
}
