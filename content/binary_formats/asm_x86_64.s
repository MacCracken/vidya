# Vidya — Binary Formats in x86_64 Assembly
#
# ELF for x86_64: e_machine = 0x3E (EM_X86_64 = 62). Where AArch64 uses
# fixed-width 32-bit instructions, x86_64 encodings are VARIABLE length —
# 1 to 15 bytes. That is the central difference for anyone parsing a
# binary: you cannot index into x86_64 code, you must decode forward from
# a known boundary, because instruction N's offset depends on the length
# of every instruction before it.
#
# Build: as --64 asm_x86_64.s -o elf.o && ld -o elf elf.o
#
# This file builds an ELF header in .data and asserts its fields, mirroring
# content/binary_formats/asm_aarch64.s. Every check branches to `fail`,
# which exits non-zero — so a corrupted field fails the content gate rather
# than printing a success line anyway.

.section .rodata
msg_pass:   .ascii "All binary formats examples passed.\n"
msg_len = . - msg_pass

# ── ELF header constants ────────────────────────────────────────────
.equ ELFCLASS64,    2
.equ ELFDATA2LSB,   1           # x86_64 is little-endian
.equ EM_X86_64,     0x3E        # 62 decimal
.equ ET_EXEC,       2           # executable
.equ EI_MAG0,       0x7F        # ELF magic byte 0
.equ ELF_E,         0x45        # 'E'
.equ ELF_L,         0x4C        # 'L'
.equ ELF_F,         0x46        # 'F'
.equ EV_CURRENT,    1

# Section type constants
.equ SHT_PROGBITS,  1
.equ SHT_NOBITS,    8           # .bss

.section .data
.balign 8

# Simulated ELF header — the first 20 bytes that identify the file
elf_header_sim:
    .byte   EI_MAG0             # e_ident[0] = 0x7F
    .byte   ELF_E               # e_ident[1] = 'E'
    .byte   ELF_L               # e_ident[2] = 'L'
    .byte   ELF_F               # e_ident[3] = 'F'
    .byte   ELFCLASS64          # e_ident[4] = class (64-bit)
    .byte   ELFDATA2LSB         # e_ident[5] = data (little-endian)
    .byte   EV_CURRENT          # e_ident[6] = version
    .byte   0                   # e_ident[7] = OS/ABI (ELFOSABI_NONE)
    .byte   0,0,0,0,0,0,0,0     # e_ident[8..15] = padding
    .hword  ET_EXEC             # e_type   = executable
    .hword  EM_X86_64           # e_machine = x86-64

# Sample "code section" — three REAL x86_64 encodings, deliberately of
# three different lengths. This is the property the AArch64 sibling does
# not have and cannot demonstrate.
.balign 8
code_section:
    .byte   0xB8, 0x2A, 0x00, 0x00, 0x00    # mov $42, %eax     — 5 bytes
    .byte   0x6A, 0x3C                      # push $60          — 2 bytes
    .byte   0x0F, 0x05                      # syscall           — 2 bytes
code_section_len = . - code_section

.section .text
.globl _start

_start:
    lea     elf_header_sim(%rip), %rbx

    # ── Test 1: ELF magic bytes ─────────────────────────────────────
    movzbl  0(%rbx), %eax
    cmp     $EI_MAG0, %eax
    jne     fail
    movzbl  1(%rbx), %eax
    cmp     $ELF_E, %eax
    jne     fail
    movzbl  2(%rbx), %eax
    cmp     $ELF_L, %eax
    jne     fail
    movzbl  3(%rbx), %eax
    cmp     $ELF_F, %eax
    jne     fail

    # ── Test 2: 64-bit class, little-endian, current version ────────
    movzbl  4(%rbx), %eax
    cmp     $ELFCLASS64, %eax
    jne     fail
    movzbl  5(%rbx), %eax
    cmp     $ELFDATA2LSB, %eax
    jne     fail
    movzbl  6(%rbx), %eax
    cmp     $EV_CURRENT, %eax
    jne     fail

    # ── Test 3: e_ident padding is zeroed ───────────────────────────
    movzbl  8(%rbx), %eax
    test    %eax, %eax
    jnz     fail
    movzbl  15(%rbx), %eax
    test    %eax, %eax
    jnz     fail

    # ── Test 4: e_type and e_machine (16-bit fields) ────────────────
    movzwl  16(%rbx), %eax
    cmp     $ET_EXEC, %eax
    jne     fail
    movzwl  18(%rbx), %eax
    cmp     $EM_X86_64, %eax
    jne     fail

    # ── Test 5: variable-length encoding ────────────────────────────
    # Three instructions occupy 9 bytes, NOT 3 * 4. On AArch64 the same
    # three would be exactly 12. Asserting the total is what pins the
    # variable-length property down.
    mov     $code_section_len, %eax
    cmp     $9, %eax
    jne     fail

    # First instruction is 5 bytes (0xB8 + imm32), so byte 5 must be the
    # opcode of the SECOND instruction — 0x6A (push imm8). If encodings
    # were fixed-width this offset would be wrong.
    lea     code_section(%rip), %rcx
    movzbl  0(%rcx), %eax
    cmp     $0xB8, %eax
    jne     fail
    movzbl  5(%rcx), %eax
    cmp     $0x6A, %eax
    jne     fail
    movzbl  7(%rcx), %eax
    cmp     $0x0F, %eax
    jne     fail

    # ── Test 6: section type constants ──────────────────────────────
    mov     $SHT_PROGBITS, %eax
    cmp     $1, %eax
    jne     fail
    mov     $SHT_NOBITS, %eax
    cmp     $8, %eax
    jne     fail

    # write(1, msg_pass, msg_len)
    mov     $1, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    # exit(0)
    mov     $60, %rax
    xor     %edi, %edi
    syscall

fail:
    # exit(1) — a failed assertion must fail the gate, not print success
    mov     $60, %rax
    mov     $1, %rdi
    syscall

# Linux x86_64 syscall ABI:
#   Number in RAX
#   Arguments: RDI, RSI, RDX, R10, R8, R9
#   Return value in RAX
#   Clobbers: RCX, R11
#
# Key syscalls for bootstrap tools:
#   0  = read(fd, buf, count)
#   1  = write(fd, buf, count)
#   2  = open(path, flags, mode)
#   3  = close(fd)
#   60 = exit(status)
