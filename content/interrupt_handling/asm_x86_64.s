# Vidya — Interrupt Handling in x86_64 Assembly
#
# IDT gate descriptor layout, exception vector constants, and PIC port
# constants. In long mode each IDT entry is 16 bytes. The handler address
# is split across three fields (bits 0-15, 16-31, 32-63). This file
# builds a mock IDT in .data, verifies the split-address encoding,
# and defines the constants a real interrupt controller setup would use.
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

# ── Exception vector constants ──────────────────────────────────────
.equ VEC_DIVIDE_ERROR,      0
.equ VEC_DEBUG,             1
.equ VEC_NMI,               2
.equ VEC_BREAKPOINT,        3
.equ VEC_OVERFLOW,          4
.equ VEC_BOUND_RANGE,       5
.equ VEC_INVALID_OPCODE,    6
.equ VEC_DEVICE_NOT_AVAIL,  7
.equ VEC_DOUBLE_FAULT,      8
.equ VEC_INVALID_TSS,       10
.equ VEC_SEG_NOT_PRESENT,   11
.equ VEC_STACK_FAULT,       12
.equ VEC_GENERAL_PROT,      13
.equ VEC_PAGE_FAULT,        14
.equ VEC_X87_FPE,           16
.equ VEC_ALIGNMENT_CHECK,   17
.equ VEC_MACHINE_CHECK,     18
.equ VEC_SIMD_FPE,          19

# ── PIC port constants ──────────────────────────────────────────────
.equ PIC1_CMD,  0x20       # Master PIC command port
.equ PIC1_DATA, 0x21       # Master PIC data port
.equ PIC2_CMD,  0xA0       # Slave PIC command port
.equ PIC2_DATA, 0xA1       # Slave PIC data port
.equ PIC_EOI,   0x20       # End-of-interrupt command

# ── IDT gate descriptor field offsets ────────────────────────────────
# Bytes 0-1:   offset_low   (handler address bits 0-15)
# Bytes 2-3:   selector     (code segment selector)
# Byte  4:     IST          (interrupt stack table index, bits 0-2)
# Byte  5:     type_attr    (gate type + DPL + present)
# Bytes 6-7:   offset_mid   (handler address bits 16-31)
# Bytes 8-11:  offset_high  (handler address bits 32-63)
# Bytes 12-15: reserved     (must be zero)
.equ IDT_ENTRY_SIZE, 16

# Gate type constants (byte 5 of IDT entry)
.equ GATE_INTERRUPT, 0x8E  # Present=1, DPL=0, type=interrupt gate (0xE)
.equ GATE_TRAP,      0x8F  # Present=1, DPL=0, type=trap gate (0xF)
.equ GATE_USER_INT,  0xEE  # Present=1, DPL=3, type=interrupt gate

_start:
    # ── Test 1: Verify IDT entry layout ──────────────────────────────
    # Our mock handler address is 0x0000FFFF_12345678.
    # offset_low  = 0x5678  (bits 0-15)
    # offset_mid  = 0x1234  (bits 16-31)
    # offset_high = 0x0000FFFF (bits 32-63)
    #
    # Verify the split-address encoding in the mock IDT entry.

    lea     idt_entry0(%rip), %rsi

    # Extract offset_low (bytes 0-1)
    movzwl  0(%rsi), %eax
    cmp     $0x5678, %eax
    jne     fail

    # Extract selector (bytes 2-3) — should be 0x08 (kernel code segment)
    movzwl  2(%rsi), %eax
    cmp     $0x08, %eax
    jne     fail

    # Extract type_attr (byte 5) — should be interrupt gate (0x8E)
    movzbl  5(%rsi), %eax
    cmp     $GATE_INTERRUPT, %eax
    jne     fail

    # Extract offset_mid (bytes 6-7)
    movzwl  6(%rsi), %eax
    cmp     $0x1234, %eax
    jne     fail

    # Extract offset_high (bytes 8-11)
    movl    8(%rsi), %eax
    cmp     $0x0000FFFF, %eax
    jne     fail

    # Reserved (bytes 12-15) must be zero
    movl    12(%rsi), %eax
    test    %eax, %eax
    jnz     fail

    # ── Test 2: Reconstruct full handler address from IDT entry ──────
    # Full address = (offset_high << 32) | (offset_mid << 16) | offset_low
    movzwl  0(%rsi), %eax          # offset_low
    movzwl  6(%rsi), %ecx          # offset_mid
    shl     $16, %rcx
    or      %rcx, %rax
    movl    8(%rsi), %ecx          # offset_high
    shlq    $32, %rcx
    or      %rcx, %rax
    movq    $0x0000FFFF12345678, %rdx
    cmp     %rdx, %rax
    jne     fail

    # ── Test 3: Verify second IDT entry (trap gate) ──────────────────
    lea     idt_entry1(%rip), %rsi

    # Type should be trap gate
    movzbl  5(%rsi), %eax
    cmp     $GATE_TRAP, %eax
    jne     fail

    # Handler address should be 0x00000000_AABBCCDD
    movzwl  0(%rsi), %eax          # offset_low = 0xCCDD
    cmp     $0xCCDD, %eax
    jne     fail
    movzwl  6(%rsi), %eax          # offset_mid = 0xAABB
    cmp     $0xAABB, %eax
    jne     fail

    # ── Test 4: Verify vector constants ──────────────────────────────
    mov     $VEC_DIVIDE_ERROR, %eax
    test    %eax, %eax
    jnz     fail                   # vector 0

    mov     $VEC_PAGE_FAULT, %eax
    cmp     $14, %eax
    jne     fail

    mov     $VEC_DOUBLE_FAULT, %eax
    cmp     $8, %eax
    jne     fail

    # ── Test 5: Verify PIC port constants ────────────────────────────
    mov     $PIC1_CMD, %eax
    cmp     $0x20, %eax
    jne     fail

    mov     $PIC1_DATA, %eax
    cmp     $0x21, %eax
    jne     fail

    mov     $PIC2_CMD, %eax
    cmp     $0xA0, %eax
    jne     fail

    mov     $PIC2_DATA, %eax
    cmp     $0xA1, %eax
    jne     fail

    # ── Test 6: IDT entry size ───────────────────────────────────────
    mov     $IDT_ENTRY_SIZE, %eax
    cmp     $16, %eax
    jne     fail

    # ── All passed ───────────────────────────────────────────────────
    mov     $1, %rax               # sys_write
    mov     $1, %rdi               # fd = stdout
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $60, %rax              # sys_exit
    xor     %rdi, %rdi             # status = 0
    syscall

fail:
    mov     $60, %rax
    mov     $1, %rdi
    syscall

# ── Mock IDT entries in .data ────────────────────────────────────────
# These demonstrate the 16-byte gate descriptor layout.
# A real kernel would fill these at runtime; here we show the encoding.

.section .data

# IDT entry 0: interrupt gate for handler at 0x0000FFFF_12345678
#   offset_low  = 0x5678
#   selector    = 0x0008 (kernel CS)
#   IST         = 0
#   type_attr   = 0x8E (interrupt gate, DPL=0, present)
#   offset_mid  = 0x1234
#   offset_high = 0x0000FFFF
#   reserved    = 0
idt_entry0:
    .word   0x5678          # offset_low  (handler bits 0-15)
    .word   0x0008          # selector    (kernel code segment)
    .byte   0x00            # IST index   (0 = no IST)
    .byte   0x8E            # type_attr   (interrupt gate, present, DPL=0)
    .word   0x1234          # offset_mid  (handler bits 16-31)
    .long   0x0000FFFF      # offset_high (handler bits 32-63)
    .long   0x00000000      # reserved

# IDT entry 1: trap gate for handler at 0x00000000_AABBCCDD
idt_entry1:
    .word   0xCCDD          # offset_low
    .word   0x0008          # selector
    .byte   0x00            # IST
    .byte   0x8F            # type_attr (trap gate, present, DPL=0)
    .word   0xAABB          # offset_mid
    .long   0x00000000      # offset_high
    .long   0x00000000      # reserved

.section .rodata
msg_pass:
    .ascii "All interrupt handling examples passed.\n"
    msg_len = . - msg_pass
