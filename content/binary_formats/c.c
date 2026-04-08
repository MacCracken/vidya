// Vidya — Binary Formats in C
//
// Builds a minimal ELF binary in memory and verifies every field.
// Demonstrates the difference between static and dynamic linking:
//   1. Minimal ELF: just ehdr + phdr + machine code (static, no libc)
//   2. Static linking: one PT_LOAD, no PT_INTERP, no PT_DYNAMIC
//   3. Dynamic linking: PT_INTERP (loader path) + PT_DYNAMIC (symbol info)
//   4. Header field size and offset verification
//
// The kernel's ELF loader reads only program headers.
// Section headers are for the linker and tools — not needed to run.

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
#define EM_X86_64     62

#define PT_NULL        0
#define PT_LOAD        1
#define PT_DYNAMIC     2
#define PT_INTERP      3
#define PT_NOTE        4
#define PT_PHDR        6

#define PF_X           1
#define PF_W           2
#define PF_R           4

// ── ELF64 Structures (packed) ───────────────────────────────────────

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

// ── Verify struct sizes ─────────────────────────────────────────────

static void test_struct_sizes(void) {
    assert(sizeof(Elf64_Ehdr) == 64);
    assert(sizeof(Elf64_Phdr) == 56);

    // Field sizes within ELF header
    assert(sizeof(((Elf64_Ehdr *)0)->e_ident) == 16);
    assert(sizeof(((Elf64_Ehdr *)0)->e_type) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_machine) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_version) == 4);
    assert(sizeof(((Elf64_Ehdr *)0)->e_entry) == 8);
    assert(sizeof(((Elf64_Ehdr *)0)->e_phoff) == 8);
    assert(sizeof(((Elf64_Ehdr *)0)->e_shoff) == 8);
    assert(sizeof(((Elf64_Ehdr *)0)->e_flags) == 4);
    assert(sizeof(((Elf64_Ehdr *)0)->e_ehsize) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_phentsize) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_phnum) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_shentsize) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_shnum) == 2);
    assert(sizeof(((Elf64_Ehdr *)0)->e_shstrndx) == 2);

    // Field sizes within program header
    assert(sizeof(((Elf64_Phdr *)0)->p_type) == 4);
    assert(sizeof(((Elf64_Phdr *)0)->p_flags) == 4);
    assert(sizeof(((Elf64_Phdr *)0)->p_offset) == 8);
    assert(sizeof(((Elf64_Phdr *)0)->p_vaddr) == 8);
    assert(sizeof(((Elf64_Phdr *)0)->p_paddr) == 8);
    assert(sizeof(((Elf64_Phdr *)0)->p_filesz) == 8);
    assert(sizeof(((Elf64_Phdr *)0)->p_memsz) == 8);
    assert(sizeof(((Elf64_Phdr *)0)->p_align) == 8);
}

// ── Verify field offsets ────────────────────────────────────────────

static void test_field_offsets(void) {
    // ELF header field offsets — must match the ELF spec exactly
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

    // Program header field offsets
    assert(offsetof(Elf64_Phdr, p_type)   == 0);
    assert(offsetof(Elf64_Phdr, p_flags)  == 4);
    assert(offsetof(Elf64_Phdr, p_offset) == 8);
    assert(offsetof(Elf64_Phdr, p_vaddr)  == 16);
    assert(offsetof(Elf64_Phdr, p_paddr)  == 24);
    assert(offsetof(Elf64_Phdr, p_filesz) == 32);
    assert(offsetof(Elf64_Phdr, p_memsz)  == 40);
    assert(offsetof(Elf64_Phdr, p_align)  == 48);
}

// ── Build Minimal ELF in Memory ─────────────────────────────────────
// Structure: 64 bytes ELF header + 56 bytes program header + code
// This is a static binary — no libc, no dynamic linker.

static void build_minimal_elf(uint8_t *out, size_t *out_size) {
    uint64_t base_addr = 0x400000;
    size_t code_offset = sizeof(Elf64_Ehdr) + sizeof(Elf64_Phdr);

    // Machine code: exit(0)
    // xor edi, edi    (2 bytes) — exit code 0
    // mov eax, 60     (5 bytes) — syscall number
    // syscall          (2 bytes) — invoke kernel
    uint8_t code[] = {
        0x31, 0xFF,                          // xor edi, edi
        0xB8, 0x3C, 0x00, 0x00, 0x00,      // mov eax, 60
        0x0F, 0x05,                          // syscall
    };
    size_t code_size = sizeof(code);
    size_t total_size = code_offset + code_size;
    uint64_t entry = base_addr + code_offset;

    // Build ELF header
    Elf64_Ehdr ehdr;
    memset(&ehdr, 0, sizeof(ehdr));
    ehdr.e_ident[0] = 0x7F;
    ehdr.e_ident[1] = 'E';
    ehdr.e_ident[2] = 'L';
    ehdr.e_ident[3] = 'F';
    ehdr.e_ident[4] = ELFCLASS64;
    ehdr.e_ident[5] = ELFDATA2LSB;
    ehdr.e_ident[6] = EV_CURRENT;
    ehdr.e_type      = ET_EXEC;
    ehdr.e_machine   = EM_X86_64;
    ehdr.e_version   = EV_CURRENT;
    ehdr.e_entry     = entry;
    ehdr.e_phoff     = sizeof(Elf64_Ehdr);
    ehdr.e_ehsize    = sizeof(Elf64_Ehdr);
    ehdr.e_phentsize = sizeof(Elf64_Phdr);
    ehdr.e_phnum     = 1;
    ehdr.e_shentsize = 64;

    // Build program header
    Elf64_Phdr phdr;
    memset(&phdr, 0, sizeof(phdr));
    phdr.p_type   = PT_LOAD;
    phdr.p_flags  = PF_R | PF_X;
    phdr.p_offset = 0;
    phdr.p_vaddr  = base_addr;
    phdr.p_paddr  = base_addr;
    phdr.p_filesz = total_size;
    phdr.p_memsz  = total_size;
    phdr.p_align  = 0x1000;

    // Assemble
    memcpy(out, &ehdr, sizeof(ehdr));
    memcpy(out + sizeof(ehdr), &phdr, sizeof(phdr));
    memcpy(out + code_offset, code, code_size);
    *out_size = total_size;
}

static void test_minimal_elf(void) {
    uint8_t binary[256];
    size_t size;
    build_minimal_elf(binary, &size);

    // Verify total size: 64 + 56 + 9 = 129 bytes
    assert(size == 64 + 56 + 9);

    // Verify magic
    assert(binary[0] == 0x7F);
    assert(binary[1] == 'E');
    assert(binary[2] == 'L');
    assert(binary[3] == 'F');
    assert(binary[4] == ELFCLASS64);
    assert(binary[5] == ELFDATA2LSB);

    // Verify entry point (at offset 24, little-endian u64)
    uint64_t entry;
    memcpy(&entry, binary + 24, sizeof(entry));
    assert(entry == 0x400000 + 120);

    // Verify program header at offset 64
    uint32_t p_type;
    memcpy(&p_type, binary + 64, sizeof(p_type));
    assert(p_type == PT_LOAD);

    uint32_t p_flags;
    memcpy(&p_flags, binary + 68, sizeof(p_flags));
    assert(p_flags == (PF_R | PF_X));

    // Verify code starts at offset 120
    assert(binary[120] == 0x31);  // xor edi, edi
    assert(binary[121] == 0xFF);
    assert(binary[127] == 0x0F);  // syscall prefix
    assert(binary[128] == 0x05);  // syscall
}

// ── Static vs Dynamic Linking ───────────────────────────────────────
// A static binary has one or two PT_LOAD segments and nothing else.
// A dynamic binary adds PT_INTERP and PT_DYNAMIC.

typedef struct {
    const char *name;
    uint32_t    p_type;
    uint32_t    p_flags;
    const char *purpose;
} SegmentInfo;

static void test_static_binary_segments(void) {
    // A static binary: typically 2 PT_LOAD segments
    SegmentInfo static_segments[] = {
        {"code",  PT_LOAD, PF_R | PF_X, "executable code + rodata"},
        {"data",  PT_LOAD, PF_R | PF_W, "initialized data + BSS"},
    };
    int num_segments = sizeof(static_segments) / sizeof(static_segments[0]);

    assert(num_segments == 2);

    // No PT_INTERP — no dynamic linker needed
    for (int i = 0; i < num_segments; i++) {
        assert(static_segments[i].p_type != PT_INTERP);
        assert(static_segments[i].p_type != PT_DYNAMIC);
    }

    // Code segment: R+X (readable, executable, NOT writable)
    assert(static_segments[0].p_flags == (PF_R | PF_X));
    // Data segment: R+W (readable, writable, NOT executable)
    assert(static_segments[1].p_flags == (PF_R | PF_W));
}

static void test_dynamic_binary_segments(void) {
    // A dynamic binary: PT_LOAD + PT_INTERP + PT_DYNAMIC + PT_PHDR
    SegmentInfo dynamic_segments[] = {
        {"phdr",     PT_PHDR,    PF_R,         "program header table itself"},
        {"interp",   PT_INTERP,  PF_R,         "path to dynamic linker"},
        {"code",     PT_LOAD,    PF_R | PF_X,  "executable code"},
        {"data",     PT_LOAD,    PF_R | PF_W,  "data + BSS"},
        {"dynamic",  PT_DYNAMIC, PF_R | PF_W,  "dynamic linking info"},
    };
    int num_segments = sizeof(dynamic_segments) / sizeof(dynamic_segments[0]);

    assert(num_segments == 5);

    // Must have PT_INTERP
    int has_interp = 0;
    int has_dynamic = 0;
    int load_count = 0;
    for (int i = 0; i < num_segments; i++) {
        if (dynamic_segments[i].p_type == PT_INTERP) has_interp = 1;
        if (dynamic_segments[i].p_type == PT_DYNAMIC) has_dynamic = 1;
        if (dynamic_segments[i].p_type == PT_LOAD) load_count++;
    }
    assert(has_interp == 1);
    assert(has_dynamic == 1);
    assert(load_count == 2);

    // PT_INTERP contents: path to the dynamic linker
    // On x86_64 Linux: "/lib64/ld-linux-x86-64.so.2"
    const char *interp_path = "/lib64/ld-linux-x86-64.so.2";
    assert(strlen(interp_path) == 27);
    // This string is the entire contents of the PT_INTERP segment
}

// ── Dynamic Linking Structures ──────────────────────────────────────
// The PT_DYNAMIC segment contains a table of Elf64_Dyn entries.
// Each entry has a tag (d_tag) and a value (d_un.d_val or d_un.d_ptr).

#define DT_NULL    0   // end of table
#define DT_NEEDED  1   // name of shared library (offset into .dynstr)
#define DT_STRTAB  5   // address of .dynstr
#define DT_SYMTAB  6   // address of .dynsym
#define DT_STRSZ   10  // size of .dynstr
#define DT_PLTGOT  3   // address of PLT/GOT

typedef struct __attribute__((packed)) {
    int64_t  d_tag;
    uint64_t d_val;
} Elf64_Dyn;

static void test_dynamic_entries(void) {
    assert(sizeof(Elf64_Dyn) == 16);

    // A typical dynamic section contains:
    Elf64_Dyn entries[] = {
        {DT_NEEDED,  0x01},       // offset in .dynstr to "libc.so.6"
        {DT_STRTAB,  0x400200},   // virtual address of .dynstr
        {DT_SYMTAB,  0x400100},   // virtual address of .dynsym
        {DT_STRSZ,   256},        // size of .dynstr
        {DT_PLTGOT,  0x403000},   // virtual address of GOT
        {DT_NULL,    0},          // end of table (required)
    };
    int num_entries = sizeof(entries) / sizeof(entries[0]);

    // Table must end with DT_NULL
    assert(entries[num_entries - 1].d_tag == DT_NULL);

    // DT_NEEDED points to a string in .dynstr, not the lib itself
    assert(entries[0].d_tag == DT_NEEDED);

    // DT_STRTAB and DT_SYMTAB are VIRTUAL ADDRESSES, not file offsets
    // To read them from the file, convert via PT_LOAD mapping
    assert(entries[1].d_val > 0x400000);  // virtual address, not offset
}

// ── GOT/PLT: How Dynamic Calls Work ────────────────────────────────
// GOT (Global Offset Table): array of pointers to external symbols.
// PLT (Procedure Linkage Table): stubs that jump through GOT entries.
//
// On first call:
//   1. PLT stub jumps to GOT entry (initially points back to PLT)
//   2. PLT pushes relocation index, jumps to resolver
//   3. Resolver (ld-linux) finds the symbol, patches GOT
//   4. Future calls: PLT jumps directly to the resolved address

static void test_got_plt(void) {
    // GOT entry size: 8 bytes (one pointer)
    size_t got_entry_size = sizeof(void *);
    assert(got_entry_size == 8);

    // PLT entry size: 16 bytes on x86_64
    //   6 bytes: jmp [GOT+N]
    //   6 bytes: push relocation_index
    //   4 bytes: jmp PLT[0] (resolver)
    size_t plt_entry_size = 16;
    assert(plt_entry_size == 16);

    // PLT[0] is special: jumps to the dynamic linker's resolver
    //   6 bytes: push [GOT+8]  (link_map pointer)
    //   6 bytes: jmp [GOT+16]  (resolver address)
    size_t plt0_size = 16;
    assert(plt0_size == 16);

    // With 10 external functions:
    size_t total_got = (10 + 3) * 8;   // 3 reserved entries
    size_t total_plt = 16 + 10 * 16;   // PLT[0] + 10 stubs
    assert(total_got == 104);
    assert(total_plt == 176);
}

// ── Binary Size Comparison ──────────────────────────────────────────

static void test_size_comparison(void) {
    // Minimal ELF (exit(0), static, no libc)
    size_t minimal_elf = 64 + 56 + 9;  // 129 bytes
    assert(minimal_elf == 129);

    // C hello world sizes (approximate)
    size_t c_static = 800000;   // gcc -static (includes all of libc)
    size_t c_dynamic = 16000;   // gcc (dynamic, depends on libc.so)

    // Static is ~6000x larger than the minimal ELF
    assert(c_static / minimal_elf > 6000);

    // Dynamic is ~120x larger
    assert(c_dynamic / minimal_elf > 100);

    // The overhead is libc, crt0, and the dynamic linker setup
    // Our minimal binary avoids ALL of that
}

int main(void) {
    printf("Binary Formats — minimal ELF construction and linking:\n\n");

    // ── Struct verification ───────────────────────────────────────────
    printf("1. Struct sizes and offsets:\n");
    test_struct_sizes();
    test_field_offsets();
    printf("   Elf64_Ehdr: %zu bytes (14 fields verified)\n", sizeof(Elf64_Ehdr));
    printf("   Elf64_Phdr: %zu bytes (8 fields verified)\n", sizeof(Elf64_Phdr));

    // ── Build minimal ELF ─────────────────────────────────────────────
    printf("\n2. Minimal ELF binary (exit(0)):\n");
    test_minimal_elf();
    printf("   Size: %zu bytes (64 ehdr + 56 phdr + 9 code)\n",
           (size_t)(64 + 56 + 9));
    printf("   Entry: 0x%X\n", 0x400000 + 120);
    printf("   Segment: 1 PT_LOAD (R+X)\n");
    printf("   No sections, no symbols, no dynamic linking\n");

    // ── Static linking ────────────────────────────────────────────────
    printf("\n3. Static binary segments:\n");
    test_static_binary_segments();
    printf("   PT_LOAD R+X (code + rodata)\n");
    printf("   PT_LOAD R+W (data + BSS)\n");
    printf("   No PT_INTERP, no PT_DYNAMIC\n");

    // ── Dynamic linking ───────────────────────────────────────────────
    printf("\n4. Dynamic binary segments:\n");
    test_dynamic_binary_segments();
    printf("   PT_PHDR    — program header table\n");
    printf("   PT_INTERP  — /lib64/ld-linux-x86-64.so.2\n");
    printf("   PT_LOAD    — code (R+X)\n");
    printf("   PT_LOAD    — data (R+W)\n");
    printf("   PT_DYNAMIC — dynamic linking info\n");

    // ── Dynamic section entries ───────────────────────────────────────
    printf("\n5. Dynamic section (.dynamic):\n");
    test_dynamic_entries();
    printf("   Elf64_Dyn: %zu bytes per entry\n", sizeof(Elf64_Dyn));
    printf("   DT_NEEDED=%d  DT_STRTAB=%d  DT_SYMTAB=%d\n",
           DT_NEEDED, DT_STRTAB, DT_SYMTAB);
    printf("   Values are virtual addresses (not file offsets!)\n");

    // ── GOT/PLT ───────────────────────────────────────────────────────
    printf("\n6. GOT/PLT (lazy binding):\n");
    test_got_plt();
    printf("   GOT entry: 8 bytes (one pointer)\n");
    printf("   PLT entry: 16 bytes (jmp + push + jmp)\n");
    printf("   First call: resolver patches GOT\n");
    printf("   Subsequent calls: direct jump via GOT\n");

    // ── Size comparison ───────────────────────────────────────────────
    printf("\n7. Binary size comparison:\n");
    test_size_comparison();
    printf("   %30s %10s\n", "Binary", "Size");
    printf("   %30s %10s\n", "------------------------------", "----------");
    printf("   %30s %7zu B\n", "Minimal ELF (exit(0))", (size_t)129);
    printf("   %30s %7d B\n", "Cyrius seed (Hello, Cyrius!)", 199);
    printf("   %30s %7s\n",   "C hello (dynamic, stripped)", "~14 KB");
    printf("   %30s %7s\n",   "C hello (static, stripped)", "~800 KB");

    printf("\nAll binary format examples passed.\n");
    return 0;
}
