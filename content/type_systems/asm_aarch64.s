// Vidya — Type Systems in AArch64 Assembly
//
// AArch64 has no type system — registers are 64-bit (X) or 32-bit (W)
// views of the same hardware. The programmer tracks meaning. Different
// instructions interpret bits differently: ADD vs FADD, SXTB vs UXTB.
// AArch64 separates integer (X/W) and floating-point (D/S) registers.

.global _start

.section .data
byte_val:   .byte 0xFF
.align 2
word_val:   .hword 0xFFFF
.align 4
dword_val:  .word 0x7FFFFFFF
.align 8
qword_val:  .quad 0x7FFFFFFFFFFFFFFF

.section .rodata
msg_pass:   .ascii "All type system examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Sized loads: same bits, different interpretation ────────────
    // Zero-extend byte to 32-bit
    adr     x0, byte_val
    ldrb    w1, [x0]           // unsigned: 255
    cmp     w1, #255
    b.ne    fail

    // Sign-extend byte to 32-bit
    ldrsb   w1, [x0]           // signed: -1
    cmn     w1, #1             // compare with -1
    b.ne    fail

    // 16-bit unsigned
    adr     x0, word_val
    ldrh    w1, [x0]
    mov     w2, #0xFFFF
    cmp     w1, w2
    b.ne    fail

    // 32-bit
    adr     x0, dword_val
    ldr     w1, [x0]
    mov     w2, #0x7FFFFFFF
    cmp     w1, w2
    b.ne    fail

    // 64-bit
    adr     x0, qword_val
    ldr     x1, [x0]
    mov     x2, #0x7FFFFFFFFFFFFFFF
    cmp     x1, x2
    b.ne    fail

    // ── W vs X registers ───────────────────────────────────────────
    // W registers are the lower 32 bits of X registers
    // Writing to W clears the upper 32 bits of X
    mov     x0, #-1            // all 64 bits set
    mov     w0, #42             // clears upper 32 bits
    cmp     x0, #42             // full 64-bit compare
    b.ne    fail

    // ── Signed vs unsigned arithmetic ──────────────────────────────
    // Addition: same instruction for both
    mov     w0, #3
    add     w0, w0, #4
    cmp     w0, #7
    b.ne    fail

    // Signed multiply
    mov     w0, #-3
    mov     w1, #4
    mul     w0, w0, w1          // -3 * 4 = -12
    cmn     w0, #12
    b.ne    fail

    // ── Extension instructions ─────────────────────────────────────
    // SXTB: sign-extend byte to word
    mov     w0, #0xFF
    sxtb    w0, w0              // w0 = -1 (sign-extended)
    cmn     w0, #1
    b.ne    fail

    // UXTB: zero-extend byte to word
    mov     w0, #0xFF
    uxtb    w0, w0              // w0 = 255 (zero-extended)
    cmp     w0, #255
    b.ne    fail

    // ── Floating point (separate register file) ────────────────────
    // FP registers: D0-D31 (64-bit double), S0-S31 (32-bit float)
    fmov    d0, #3.0
    fmov    d1, #2.0
    fadd    d0, d0, d1          // 3.0 + 2.0 = 5.0
    fmov    d2, #5.0
    fcmp    d0, d2
    b.ne    fail

    // Float multiply
    fmov    d0, #3.0
    fmov    d1, #4.0
    fmul    d0, d0, d1          // 3.0 * 4.0 = 12.0
    // Convert to int for comparison
    fcvtzs  x0, d0              // float to signed int
    cmp     x0, #12
    b.ne    fail

    // ── Struct layout on stack ─────────────────────────────────────
    // struct Point { int x; int y; } at sp
    sub     sp, sp, #16         // 16-byte aligned
    mov     w0, #3
    str     w0, [sp, #0]       // point.x = 3
    mov     w0, #4
    str     w0, [sp, #4]       // point.y = 4

    ldr     w0, [sp, #0]       // load x
    ldr     w1, [sp, #4]       // load y
    add     w0, w0, w1
    cmp     w0, #7
    b.ne    fail
    add     sp, sp, #16

    // ── Boolean: CBZ/CBNZ ──────────────────────────────────────────
    // Zero = false, nonzero = true
    mov     w0, #1
    cbnz    w0, .Ltrue1         // branch if nonzero (true)
    b       fail
.Ltrue1:

    mov     w0, #0
    cbz     w0, .Lfalse1        // branch if zero (false)
    b       fail
.Lfalse1:

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0
