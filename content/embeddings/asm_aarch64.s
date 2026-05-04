// Vidya — Embeddings and Vector Search — AArch64 Assembly. Q15 fixed-point.
//
// Same focused subset as x86_64: dot + brute-force nearest. Top-k
// in cyrius.cyr.

.global _start

.equ SCALE,    15
.equ ONE,      32768
.equ DIM,      4
.equ N_CORPUS, 4

.data
.align 8
corpus:
    .quad 32767, 0, 0, 0
    .quad 0, 32767, 0, 0
    .quad 16384, 16384, 16384, 16384
    .quad -32767, 0, 0, 0

.bss
.align 8
query_buf: .skip 32

.section .rodata
msg_pass: .ascii "embeddings: 9/9 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// q_mul(x0=a, x1=b) -> x0
q_mul:
    mul     x0, x0, x1
    asr     x0, x0, #SCALE
    ret

// dot(x0=a_ptr, x1=b_ptr, x2=n) -> x0
dot:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    mov     x19, x0                       // a
    mov     x20, x1                       // b
    mov     x21, x2                       // n
    mov     x22, #0                       // acc
    mov     x4, #0                        // i
.dot_loop:
    cmp     x4, x21
    b.ge    .dot_done
    ldr     x0, [x19, x4, lsl #3]
    ldr     x1, [x20, x4, lsl #3]
    str     x4, [sp, #-16]!
    bl      q_mul
    ldr     x4, [sp], #16
    add     x22, x22, x0
    add     x4, x4, #1
    b       .dot_loop
.dot_done:
    mov     x0, x22
    ldr     x22, [sp, #40]
    ldr     x21, [sp, #32]
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// corpus_sim(x0=query, x1=idx) -> x0
corpus_sim:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0                       // save query
    // corpus row ptr: corpus + idx * 32
    lsl     x2, x1, #5
    LDADDR  x3, corpus
    add     x1, x2, x3
    mov     x0, x19
    mov     x2, #DIM
    bl      dot
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// nearest(x0=query) -> x0 = idx
nearest:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    mov     x19, x0                       // query
    mov     x20, #0                       // best_idx
    mov     x1, #0
    bl      corpus_sim
    mov     x21, x0                       // best_sim
    mov     x4, #1                        // i
.near_loop:
    cmp     x4, #N_CORPUS
    b.ge    .near_done
    str     x4, [sp, #-16]!
    mov     x0, x19
    mov     x1, x4
    bl      corpus_sim
    ldr     x4, [sp], #16
    cmp     x0, x21
    b.le    .near_skip
    mov     x21, x0
    mov     x20, x4
.near_skip:
    add     x4, x4, #1
    b       .near_loop
.near_done:
    mov     x0, x20
    ldr     x21, [sp, #32]
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

assert_eq:
    cmp     x0, x1
    b.ne    .ae_fail
    ret

assert_between:
    cmp     x0, x1
    b.lt    .ae_fail
    cmp     x0, x2
    b.gt    .ae_fail
    ret
.ae_fail:
    mov     x8, #64
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    svc     #0
    mov     x8, #93
    mov     x0, #1
    svc     #0

_start:
    // self-sim of v0 ≈ ONE
    LDADDR  x0, corpus
    mov     x1, #0
    bl      corpus_sim
    mov     x1, #32760
    mov     x2, #32768
    bl      assert_between

    // orthogonal: dot(v0, v1) = 0
    LDADDR  x0, corpus
    mov     x1, #1
    bl      corpus_sim
    mov     x1, #0
    bl      assert_eq

    // opposite: dot(v0, v3) ≈ -ONE
    LDADDR  x0, corpus
    mov     x1, #3
    bl      corpus_sim
    mov     x1, #-32768
    mov     x2, #-32760
    bl      assert_between

    // diagonal self-sim: dot(v2, v2) = ONE
    LDADDR  x0, corpus
    add     x0, x0, #64                   // v2 at offset 2*32 = 64
    mov     x1, #2
    bl      corpus_sim
    mov     w1, #ONE
    bl      assert_eq

    // nearest [0.9, 0, 0, 0] → 0
    LDADDR  x4, query_buf
    mov     x0, #29490
    str     x0, [x4, #0]
    str     xzr, [x4, #8]
    str     xzr, [x4, #16]
    str     xzr, [x4, #24]
    LDADDR  x0, query_buf
    bl      nearest
    mov     x1, #0
    bl      assert_eq

    // nearest [0, 1, 0, 0] → 1
    LDADDR  x4, query_buf
    str     xzr, [x4, #0]
    mov     w0, #32767
    str     x0, [x4, #8]
    str     xzr, [x4, #16]
    str     xzr, [x4, #24]
    LDADDR  x0, query_buf
    bl      nearest
    mov     x1, #1
    bl      assert_eq

    // nearest [0.5, 0.5, 0.5, 0.5] → 2
    LDADDR  x4, query_buf
    mov     w0, #16384
    str     x0, [x4, #0]
    str     x0, [x4, #8]
    str     x0, [x4, #16]
    str     x0, [x4, #24]
    LDADDR  x0, query_buf
    bl      nearest
    mov     x1, #2
    bl      assert_eq

    // nearest [-0.9, 0, 0, 0] → 3
    LDADDR  x4, query_buf
    mov     x0, #-29490
    str     x0, [x4, #0]
    str     xzr, [x4, #8]
    str     xzr, [x4, #16]
    str     xzr, [x4, #24]
    LDADDR  x0, query_buf
    bl      nearest
    mov     x1, #3
    bl      assert_eq

    // determinism
    LDADDR  x4, query_buf
    mov     x0, #29490
    str     x0, [x4, #0]
    str     xzr, [x4, #8]
    str     xzr, [x4, #16]
    str     xzr, [x4, #24]
    LDADDR  x0, query_buf
    bl      nearest
    mov     x19, x0
    LDADDR  x0, query_buf
    bl      nearest
    mov     x1, x19
    bl      assert_eq

    // success
    mov     x8, #64
    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    svc     #0
    mov     x8, #93
    mov     x0, #0
    svc     #0
