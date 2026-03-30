# Vidya — Type Systems in x86_64 Assembly
#
# Assembly has no type system. The CPU sees only bits — bytes, words,
# dwords, qwords. The programmer tracks what each register/memory
# location "means". Type safety is entirely a convention enforced by
# the programmer. This file demonstrates how typed operations map
# to untyped machine instructions.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All type system examples passed.\n"
msg_len = . - msg_pass

.section .data
# Different "types" are just different sizes in memory
byte_val:   .byte 0xFF          # 8-bit unsigned: 255
word_val:   .word 0xFFFF        # 16-bit unsigned: 65535
dword_val:  .long 0x7FFFFFFF    # 32-bit signed max: 2147483647
qword_val:  .quad 0x7FFFFFFFFFFFFFFF  # 64-bit signed max

.section .text

_start:
    # ── Size matters: same bits, different interpretation ───────────
    # Load a byte (8 bits)
    movzx   eax, byte ptr [byte_val]    # zero-extend to 32-bit
    cmp     eax, 255
    jne     fail

    # Sign-extend: same bits, different value
    movsx   eax, byte ptr [byte_val]    # sign-extend 0xFF
    cmp     eax, -1                     # 0xFF sign-extended = -1
    jne     fail

    # ── Integer sizes ───────────────────────────────────────────────
    movzx   eax, word ptr [word_val]
    cmp     eax, 65535
    jne     fail

    mov     eax, [dword_val]
    cmp     eax, 0x7FFFFFFF
    jne     fail

    mov     rax, [qword_val]
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    cmp     rax, rcx
    jne     fail

    # ── Signed vs unsigned comparison ───────────────────────────────
    # Same bits, different branch instructions
    mov     eax, 0xFFFFFFFF     # unsigned: 4294967295, signed: -1

    # Unsigned comparison: 0xFFFFFFFF > 0
    cmp     eax, 0
    jbe     fail                # unsigned: should be above

    # Signed comparison: -1 < 0
    cmp     eax, 0
    jge     fail                # signed: should be less

    # ── Signed vs unsigned arithmetic ───────────────────────────────
    # Addition is the same for signed and unsigned
    mov     eax, 3
    add     eax, 4
    cmp     eax, 7
    jne     fail

    # Multiplication differs: imul (signed) vs mul (unsigned)
    mov     eax, -3
    mov     ecx, 4
    imul    eax, ecx            # signed: -3 * 4 = -12
    cmp     eax, -12
    jne     fail

    # ── Floating point (SSE2) ───────────────────────────────────────
    # Floats live in xmm registers, not general-purpose registers
    # Different instructions: addsd (double), addss (float)

    # Load 3.14 into xmm0
    mov     rax, 0x40091EB851EB851F  # IEEE 754 encoding of 3.14
    movq    xmm0, rax

    # Load 2.0 into xmm1
    mov     rax, 0x4000000000000000  # IEEE 754 encoding of 2.0
    movq    xmm1, rax

    # Add: 3.14 + 2.0 = 5.14
    addsd   xmm0, xmm1

    # Compare with 5.14
    mov     rax, 0x4014666666666666  # IEEE 754 encoding of 5.1 (approx)
    movq    xmm1, rax
    ucomisd xmm0, xmm1
    jb      fail                # xmm0 should be >= 5.1

    # ── Pointer "types": just addresses ─────────────────────────────
    # A pointer is a 64-bit integer holding a memory address
    lea     rax, [byte_val]     # "pointer to byte"
    lea     rbx, [qword_val]    # "pointer to qword"
    # Both are just 64-bit addresses — no type distinction in hardware

    # Dereference with different sizes — programmer's responsibility
    movzx   ecx, byte ptr [rax]     # read 1 byte
    cmp     ecx, 255
    jne     fail

    mov     rcx, [rbx]              # read 8 bytes
    mov     rdx, 0x7FFFFFFFFFFFFFFF
    cmp     rcx, rdx
    jne     fail

    # ── Struct layout: manual offset calculation ────────────────────
    # struct Point { int x; int y; }  →  x at offset 0, y at offset 4
    sub     rsp, 16             # allocate struct on stack
    mov     dword ptr [rsp + 0], 3      # point.x = 3
    mov     dword ptr [rsp + 4], 4      # point.y = 4

    # Access fields by offset
    mov     eax, [rsp + 0]     # load x
    mov     ecx, [rsp + 4]     # load y
    add     eax, ecx           # x + y
    cmp     eax, 7
    jne     fail
    add     rsp, 16

    # ── Enum: just integer constants ────────────────────────────────
    .equ    COLOR_RED,   0
    .equ    COLOR_GREEN, 1
    .equ    COLOR_BLUE,  2

    mov     eax, COLOR_GREEN
    cmp     eax, 1
    jne     fail

    # ── Boolean: any nonzero = true ─────────────────────────────────
    mov     eax, 1
    test    eax, eax
    jz      fail                # nonzero = true

    xor     eax, eax
    test    eax, eax
    jnz     fail                # zero = false

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall
