// Vidya — Performance in AArch64 Assembly
//
// AArch64 performance: branchless code with CSEL/CSINC, SIMD via NEON,
// alignment for cache lines, and understanding the weak memory model.
// Key differences from x86_64: no variable-length instructions,
// fixed 4-byte instruction width enables simpler fetch/decode.

.global _start

.section .data
.align 4
array:      .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
arr_count = (. - array) / 4

.section .rodata
msg_pass:   .ascii "All performance examples passed.\n"
msg_len = . - msg_pass

.section .bss
.align 6                        // 64-byte cache line alignment
buffer:     .skip 256

.section .text

_start:
    // ── Branchless min/max with CSEL ───────────────────────────────
    // No branch prediction penalty
    mov     w0, #42
    mov     w1, #99
    cmp     w0, w1
    csel    w2, w0, w1, lt      // w2 = min(42, 99) = 42
    cmp     w2, #42
    b.ne    fail

    csel    w2, w0, w1, gt      // w2 = max(42, 99) = 99
    cmp     w2, #99
    b.ne    fail

    // ── Branchless absolute value with CNEG ────────────────────────
    mov     w0, #-42
    cmp     w0, #0
    cneg    w0, w0, lt          // negate if negative
    cmp     w0, #42
    b.ne    fail

    // ── MADD/MSUB: fused multiply-add (1 cycle) ───────────────────
    // w0 = w1 * w2 + w3 in one instruction
    mov     w1, #10
    mov     w2, #5
    mov     w3, #7
    madd    w0, w1, w2, w3      // 10*5 + 7 = 57
    cmp     w0, #57
    b.ne    fail

    // ── Shift instead of multiply/divide ───────────────────────────
    mov     w0, #7
    lsl     w0, w0, #3          // * 8
    cmp     w0, #56
    b.ne    fail

    mov     w0, #64
    lsr     w0, w0, #2          // / 4
    cmp     w0, #16
    b.ne    fail

    // ── Loop unrolling ─────────────────────────────────────────────
    // Sum 16 ints, 4 at a time
    adr     x1, array
    mov     w0, #0
    mov     w2, #0              // i = 0
.Lunroll_loop:
    cmp     w2, arr_count
    b.ge    .Lunroll_done
    ldr     w3, [x1, w2, uxtw #2]
    add     w2, w2, #1
    ldr     w4, [x1, w2, uxtw #2]
    add     w2, w2, #1
    ldr     w5, [x1, w2, uxtw #2]
    add     w2, w2, #1
    ldr     w6, [x1, w2, uxtw #2]
    add     w2, w2, #1
    add     w0, w0, w3
    add     w0, w0, w4
    add     w0, w0, w5
    add     w0, w0, w6
    b       .Lunroll_loop
.Lunroll_done:
    cmp     w0, #136            // 1+2+...+16 = 136
    b.ne    fail

    // ── PRFM: prefetch hint ────────────────────────────────────────
    // Hint the memory system to load a cache line
    adr     x0, buffer
    prfm    pldl1keep, [x0]     // prefetch for load, L1, keep
    // prfm pstl1keep, [x0]    // prefetch for store

    // ── STP for fast memory fill ───────────────────────────────────
    // Store pair fills 16 bytes per instruction
    adr     x0, buffer
    mov     x1, #0xDEAD
    movk    x1, #0xBEEF, lsl #16
    mov     x2, x1
    mov     x3, x0              // write pointer
    add     x4, x0, #256       // end pointer
.Lfill_loop:
    cmp     x3, x4
    b.ge    .Lfill_done
    stp     x1, x2, [x3], #16  // store 16 bytes, post-increment
    b       .Lfill_loop
.Lfill_done:

    // Verify fill
    ldr     x1, [x0]
    ldr     x2, [x0, #248]
    cmp     x1, x2
    b.ne    fail

    // ── CLZ: count leading zeros (hardware log2) ───────────────────
    mov     x0, #0x1000         // bit 12 set
    clz     x1, x0              // 64 - 13 = 51 leading zeros
    cmp     x1, #51
    b.ne    fail

    // ── RBIT + CLZ = count trailing zeros ──────────────────────────
    mov     x0, #0x1000
    rbit    x0, x0              // reverse bits
    clz     x1, x0             // leading zeros of reversed = trailing zeros of original
    cmp     x1, #12
    b.ne    fail

    // ── REV: byte-swap for endian conversion ───────────────────────
    mov     x0, #0x0708
    movk    x0, #0x0506, lsl #16
    movk    x0, #0x0304, lsl #32
    movk    x0, #0x0102, lsl #48
    rev     x0, x0              // reverse byte order
    // Verify most significant byte is now 0x08
    lsr     x1, x0, #56
    cmp     x1, #8
    b.ne    fail

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
