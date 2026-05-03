// Vidya — Audio DSP — AArch64 Assembly. Q15 fixed-point.
//
// Focused subset (matches x86_64 port): q_mul, clip, biquad lowpass
// DC + Nyquist tests, peak, mean-absolute. FIR convolution lives in
// cyrius.cyr.

.global _start

.equ SCALE, 15
.equ ONE,   32768
.equ SMAX,  32767

.bss
.align 8
bq_b0: .skip 8
bq_b1: .skip 8
bq_b2: .skip 8
bq_a1: .skip 8
bq_a2: .skip 8
bq_x1: .skip 8
bq_x2: .skip 8
bq_y1: .skip 8
bq_y2: .skip 8
sample_buf: .skip 64

.section .rodata
msg_pass: .ascii "audio_dsp: 10/10 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// q_mul(x0=a, x1=b) -> x0 = (a*b) >> SCALE (arithmetic shift)
q_mul:
    mul     x0, x0, x1
    asr     x0, x0, #SCALE
    ret

// abs_i(x0) -> x0
abs_i:
    cmp     x0, #0
    b.ge    .ai_done
    neg     x0, x0
.ai_done:
    ret

// clip(x0=s) -> x0
clip:
    mov     x1, #SMAX
    cmp     x0, x1
    b.le    .cl_lo
    mov     x0, x1
    ret
.cl_lo:
    mov     x1, #-32767
    cmp     x0, x1
    b.ge    .cl_done
    mov     x0, x1
.cl_done:
    ret

// biquad_set(x0=b0, x1=b1, x2=b2, x3=a1, x4=a2)
biquad_set:
    LDADDR  x5, bq_b0
    str     x0, [x5]
    LDADDR  x5, bq_b1
    str     x1, [x5]
    LDADDR  x5, bq_b2
    str     x2, [x5]
    LDADDR  x5, bq_a1
    str     x3, [x5]
    LDADDR  x5, bq_a2
    str     x4, [x5]
    LDADDR  x5, bq_x1
    str     xzr, [x5]
    LDADDR  x5, bq_x2
    str     xzr, [x5]
    LDADDR  x5, bq_y1
    str     xzr, [x5]
    LDADDR  x5, bq_y2
    str     xzr, [x5]
    ret

// biquad_lowpass_1pole(x0=a_q15)
biquad_lowpass_1pole:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x5, x0                  // save a_q15 in x5
    mov     w6, #ONE
    sub     x3, x0, x6              // a1 = a_q15 - ONE
    mov     x0, x5                  // b0 = a_q15
    mov     x1, #0                  // b1
    mov     x2, #0                  // b2
    mov     x4, #0                  // a2
    bl      biquad_set
    ldp     x29, x30, [sp], #16
    ret

// biquad_step(x0=x) -> x0
biquad_step:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    mov     x19, x0                 // save x
    LDADDR  x20, bq_b0              // (no, just compute acc)
    // acc = q_mul(b0, x)
    LDADDR  x2, bq_b0
    ldr     x0, [x2]
    mov     x1, x19
    bl      q_mul
    mov     x21, x0                 // acc
    LDADDR  x2, bq_b1
    ldr     x0, [x2]
    LDADDR  x2, bq_x1
    ldr     x1, [x2]
    bl      q_mul
    add     x21, x21, x0
    LDADDR  x2, bq_b2
    ldr     x0, [x2]
    LDADDR  x2, bq_x2
    ldr     x1, [x2]
    bl      q_mul
    add     x21, x21, x0
    LDADDR  x2, bq_a1
    ldr     x0, [x2]
    LDADDR  x2, bq_y1
    ldr     x1, [x2]
    bl      q_mul
    sub     x21, x21, x0
    LDADDR  x2, bq_a2
    ldr     x0, [x2]
    LDADDR  x2, bq_y2
    ldr     x1, [x2]
    bl      q_mul
    sub     x21, x21, x0
    // shift state
    LDADDR  x2, bq_x1
    ldr     x0, [x2]
    LDADDR  x2, bq_x2
    str     x0, [x2]
    LDADDR  x2, bq_x1
    str     x19, [x2]
    LDADDR  x2, bq_y1
    ldr     x0, [x2]
    LDADDR  x2, bq_y2
    str     x0, [x2]
    LDADDR  x2, bq_y1
    str     x21, [x2]
    mov     x0, x21
    ldr     x21, [sp, #32]
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// peak(x0=buf, x1=n) -> x0
peak:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    mov     x19, x0                 // buf
    mov     x20, x1                 // n
    mov     x2, #0                  // p (held in x2)
    mov     x3, #0                  // i
    str     x2, [sp, #-16]!         // save p (use stack)
.pk_loop:
    cmp     x3, x20
    b.ge    .pk_done
    ldr     x0, [x19, x3, lsl #3]
    str     x3, [sp, #-16]!         // save i
    bl      abs_i
    ldr     x3, [sp], #16           // restore i
    ldr     x4, [sp]                // peek p
    cmp     x0, x4
    b.le    .pk_skip
    str     x0, [sp]                // update p
.pk_skip:
    add     x3, x3, #1
    b       .pk_loop
.pk_done:
    ldr     x0, [sp], #16           // pop p
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// mean_absolute(x0=buf, x1=n) -> x0
mean_absolute:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    mov     x19, x0
    mov     x20, x1
    mov     x21, #0                 // sum (held on stack to avoid call clobber issues)
    str     x21, [sp, #-16]!
    mov     x3, #0
.ma_loop:
    cmp     x3, x20
    b.ge    .ma_done
    ldr     x0, [x19, x3, lsl #3]
    str     x3, [sp, #-16]!
    bl      abs_i
    ldr     x3, [sp], #16
    ldr     x4, [sp]
    add     x4, x4, x0
    str     x4, [sp]
    add     x3, x3, #1
    b       .ma_loop
.ma_done:
    ldr     x0, [sp], #16           // sum
    sdiv    x0, x0, x20
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

assert_eq:
    cmp     x0, x1
    b.ne    .ae_fail
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

// assert_between(x0=val, x1=lo, x2=hi)
assert_between:
    cmp     x0, x1
    b.lt    .ae_fail
    cmp     x0, x2
    b.gt    .ae_fail
    ret

_start:
    // q_mul(ONE, 100) = 100
    mov     w0, #ONE
    mov     x1, #100
    bl      q_mul
    mov     x1, #100
    bl      assert_eq
    // q_mul(ONE/2, ONE/2) = ONE/4
    mov     w0, #(ONE/2)
    mov     w1, #(ONE/2)
    bl      q_mul
    mov     w1, #(ONE/4)
    bl      assert_eq

    // clip tests
    mov     x0, #50000
    bl      clip
    mov     w1, #SMAX
    bl      assert_eq
    mov     x0, #-50000
    bl      clip
    mov     x1, #-32767
    bl      assert_eq
    mov     x0, #1234
    bl      clip
    mov     x1, #1234
    bl      assert_eq

    // Biquad DC test
    mov     x0, #3277
    bl      biquad_lowpass_1pole
    mov     x19, #200
.bq_dc:
    mov     x0, #30000
    bl      biquad_step
    sub     x19, x19, #1
    cbnz    x19, .bq_dc
    LDADDR  x2, bq_y1
    ldr     x0, [x2]
    mov     x1, #29900
    mov     x2, #30100
    bl      assert_between

    // Biquad Nyquist test
    mov     x0, #3277
    bl      biquad_lowpass_1pole
    mov     x19, #200
    mov     x20, #0                 // i
.bq_ny:
    and     x3, x20, #1
    cbz     x3, .bq_ny_pos
    mov     x0, #-20000
    b       .bq_ny_step
.bq_ny_pos:
    mov     x0, #20000
.bq_ny_step:
    bl      biquad_step
    add     x20, x20, #1
    sub     x19, x19, #1
    cbnz    x19, .bq_ny
    LDADDR  x2, bq_y1
    ldr     x0, [x2]
    bl      abs_i
    mov     x1, #0
    mov     x2, #1999
    bl      assert_between

    // peak test
    LDADDR  x2, sample_buf
    mov     x0, #100
    str     x0, [x2, #0]
    mov     x0, #-5000
    str     x0, [x2, #8]
    mov     x0, #200
    str     x0, [x2, #16]
    mov     x0, #3000
    str     x0, [x2, #24]
    mov     x0, #-1500
    str     x0, [x2, #32]
    LDADDR  x0, sample_buf
    mov     x1, #5
    bl      peak
    mov     x1, #5000
    bl      assert_eq

    // mean_absolute constant 4000
    LDADDR  x2, sample_buf
    mov     x3, #0
.ma_init1:
    cmp     x3, #8
    b.ge    .ma_init1_done
    mov     w0, #4000
    str     x0, [x2, x3, lsl #3]
    add     x3, x3, #1
    b       .ma_init1
.ma_init1_done:
    LDADDR  x0, sample_buf
    mov     x1, #8
    bl      mean_absolute
    mov     w1, #4000
    bl      assert_eq

    // mean_absolute alternating ±4000
    LDADDR  x2, sample_buf
    mov     x3, #0
.ma_init2:
    cmp     x3, #8
    b.ge    .ma_init2_done
    and     x4, x3, #1
    cbnz    x4, .ma_init2_neg
    mov     w0, #4000
    b       .ma_init2_st
.ma_init2_neg:
    mov     x0, #-4000
.ma_init2_st:
    str     x0, [x2, x3, lsl #3]
    add     x3, x3, #1
    b       .ma_init2
.ma_init2_done:
    LDADDR  x0, sample_buf
    mov     x1, #8
    bl      mean_absolute
    mov     w1, #4000
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
