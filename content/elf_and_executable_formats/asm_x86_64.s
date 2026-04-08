# Vidya — ELF and Executable Formats in x86_64 Assembly
#
# This program IS an ELF binary. By existing, it demonstrates:
# - _start as the ELF entry point (e_entry in the ELF header)
# - .text section for executable code
# - .data section for initialized writable data
# - .rodata section for read-only constants
# - .bss section for zero-initialized data
# - Symbol definitions (_start, data labels) become ELF symbol table entries
# - The linker resolves relocations (lea label(%rip)) at link time
#
# After linking, `readelf -h out` shows the ELF header.
# `readelf -S out` shows the section headers this source creates.
# `readelf -s out` shows the symbols defined here.
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

# ── ELF magic bytes for reference ────────────────────────────────────
.equ ELF_MAG0, 0x7F               # \x7f
.equ ELF_MAG1, 0x45               # 'E'
.equ ELF_MAG2, 0x4C               # 'L'
.equ ELF_MAG3, 0x46               # 'F'

# ── ELF class and data encoding ──────────────────────────────────────
.equ ELFCLASS64,    2              # 64-bit objects
.equ ELFDATA2LSB,   1              # little-endian

# ── ELF type constants ──────────────────────────────────────────────
.equ ET_EXEC, 2                    # executable file
.equ ET_DYN,  3                    # shared object
.equ ET_REL,  1                    # relocatable file

# ── ELF section type constants ───────────────────────────────────────
.equ SHT_PROGBITS, 1               # .text, .data, .rodata
.equ SHT_NOBITS,   8               # .bss (no file space)
.equ SHT_SYMTAB,   2               # symbol table

_start:
    # ── Test 1: Verify .data section is writable ─────────────────────
    # The .data section in the ELF has SHF_WRITE flag set.
    lea     data_val(%rip), %rdi
    movq    (%rdi), %rax
    cmp     $0xE1F0, %rax          # check initial value
    jne     fail
    movq    $0xDEAD, (%rdi)        # write (proves SHF_WRITE)
    cmpq    $0xDEAD, (%rdi)
    jne     fail
    movq    $0xE1F0, (%rdi)        # restore

    # ── Test 2: Verify .rodata section is readable ───────────────────
    # .rodata has SHF_ALLOC but not SHF_WRITE.
    lea     ro_magic(%rip), %rsi
    movzbl  (%rsi), %eax
    cmp     $ELF_MAG0, %eax        # 0x7F
    jne     fail
    movzbl  1(%rsi), %eax
    cmp     $ELF_MAG1, %eax        # 'E'
    jne     fail
    movzbl  2(%rsi), %eax
    cmp     $ELF_MAG2, %eax        # 'L'
    jne     fail
    movzbl  3(%rsi), %eax
    cmp     $ELF_MAG3, %eax        # 'F'
    jne     fail

    # ── Test 3: Verify .bss section is zero-initialized ──────────────
    # The ELF loader zeros .bss (SHT_NOBITS — takes no space in file).
    lea     bss_area(%rip), %rdi
    cmpq    $0, (%rdi)
    jne     fail
    cmpq    $0, 8(%rdi)
    jne     fail

    # ── Test 4: Symbol addresses are resolved ────────────────────────
    # The linker resolves symbol references to virtual addresses.
    # These LEA instructions become RIP-relative addressing after linking.
    lea     _start(%rip), %rax
    test    %rax, %rax
    jz      fail                   # _start should have a nonzero address

    lea     data_val(%rip), %rbx
    test    %rbx, %rbx
    jz      fail

    # .text and .data should be at different addresses
    cmp     %rax, %rbx
    je      fail

    # ── Test 5: Multiple .data symbols at distinct addresses ─────────
    lea     data_val(%rip), %rax
    lea     data_marker(%rip), %rbx
    cmp     %rax, %rbx
    je      fail                   # different symbols, different addresses

    # ── Test 6: ELF constant verification ────────────────────────────
    mov     $ELFCLASS64, %eax
    cmp     $2, %eax
    jne     fail

    mov     $ET_EXEC, %eax
    cmp     $2, %eax
    jne     fail

    mov     $SHT_NOBITS, %eax
    cmp     $8, %eax
    jne     fail

    # ── All passed ───────────────────────────────────────────────────
    mov     $1, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $60, %rax
    xor     %rdi, %rdi
    syscall

fail:
    mov     $60, %rax
    mov     $1, %rdi
    syscall

# ── .data section ────────────────────────────────────────────────────
# In the ELF file, this becomes a PT_LOAD segment with PF_R|PF_W.
# Section type: SHT_PROGBITS (occupies space in the file).
.section .data

.globl data_val
data_val:
    .quad   0xE1F0                 # initialized data — stored in ELF file

.globl data_marker
data_marker:
    .quad   0xFACE                 # another symbol in .data

# ── .rodata section ──────────────────────────────────────────────────
# Read-only data. In the ELF, this is in a PT_LOAD segment with PF_R only.
.section .rodata

ro_magic:
    .byte   0x7F, 0x45, 0x4C, 0x46 # ELF magic: \x7fELF

msg_pass:
    .ascii  "All ELF and executable formats examples passed.\n"
    msg_len = . - msg_pass

# ── .bss section ─────────────────────────────────────────────────────
# Uninitialized data. SHT_NOBITS — takes zero bytes in the ELF file.
# The OS loader zeroes this memory at load time.
.section .bss

.globl bss_area
bss_area:
    .skip   64                     # 64 zero bytes, costs nothing in ELF file
