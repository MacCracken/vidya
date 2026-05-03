// Vidya — Neural Network Forward Pass — AArch64 Assembly. Q15 fixed-point.
//
// Same 2 → 3 → 2 MLP as cyrius.cyr / x86_64 port. 8 asserts.

.global _start

.equ SCALE, 15
.equ ONE,   32768

.data
.align 8
W_hidden:
    .quad 16384, -16384
    .quad -16384, 16384
    .quad 16384, 16384
b_hidden:
    .quad 0, 0, 0
W_output:
    .quad 16384, 0, 0
    .quad 0, 16384, 0
b_output:
    .quad 0, 0

.bss
.align 8
input_buf:  .skip 16
hidden_buf: .skip 24
output_buf: .skip 16

.section .rodata
msg_pass: .ascii "neural_networks: 8/8 ok\n"
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

// dense_2_to_3: input_buf → hidden_buf
dense_2_to_3:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    mov     x19, #0                       // j
.d23_outer:
    cmp     x19, #3
    b.ge    .d23_done
    LDADDR  x1, b_hidden
    ldr     x21, [x1, x19, lsl #3]        // acc = b[j]; in stack-allocated reg
    str     x21, [sp, #-16]!              // save acc
    mov     x20, #0                       // i
.d23_inner:
    cmp     x20, #2
    b.ge    .d23_store
    // W index = j*2 + i
    lsl     x2, x19, #1
    add     x2, x2, x20
    LDADDR  x3, W_hidden
    ldr     x0, [x3, x2, lsl #3]
    LDADDR  x3, input_buf
    ldr     x1, [x3, x20, lsl #3]
    bl      q_mul
    ldr     x21, [sp]
    add     x21, x21, x0
    str     x21, [sp]
    add     x20, x20, #1
    b       .d23_inner
.d23_store:
    ldr     x21, [sp], #16
    LDADDR  x1, hidden_buf
    str     x21, [x1, x19, lsl #3]
    add     x19, x19, #1
    b       .d23_outer
.d23_done:
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// dense_3_to_2: hidden_buf → output_buf
dense_3_to_2:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    mov     x19, #0
.d32_outer:
    cmp     x19, #2
    b.ge    .d32_done
    LDADDR  x1, b_output
    ldr     x21, [x1, x19, lsl #3]
    str     x21, [sp, #-16]!
    mov     x20, #0
.d32_inner:
    cmp     x20, #3
    b.ge    .d32_store
    mov     x2, x19
    mov     x4, #3
    mul     x2, x2, x4
    add     x2, x2, x20
    LDADDR  x3, W_output
    ldr     x0, [x3, x2, lsl #3]
    LDADDR  x3, hidden_buf
    ldr     x1, [x3, x20, lsl #3]
    bl      q_mul
    ldr     x21, [sp]
    add     x21, x21, x0
    str     x21, [sp]
    add     x20, x20, #1
    b       .d32_inner
.d32_store:
    ldr     x21, [sp], #16
    LDADDR  x1, output_buf
    str     x21, [x1, x19, lsl #3]
    add     x19, x19, #1
    b       .d32_outer
.d32_done:
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// relu_hidden: in-place on hidden_buf (3 elements)
relu_hidden:
    LDADDR  x1, hidden_buf
    mov     x2, #0
.rh_loop:
    cmp     x2, #3
    b.ge    .rh_done
    ldr     x3, [x1, x2, lsl #3]
    cmp     x3, #0
    b.ge    .rh_skip
    str     xzr, [x1, x2, lsl #3]
.rh_skip:
    add     x2, x2, #1
    b       .rh_loop
.rh_done:
    ret

// argmax_output: returns x0 = index of max in output_buf (2 elements)
argmax_output:
    LDADDR  x1, output_buf
    ldr     x2, [x1, #0]
    ldr     x3, [x1, #8]
    cmp     x3, x2
    b.le    .am_zero
    mov     x0, #1
    ret
.am_zero:
    mov     x0, #0
    ret

// forward: input_buf → x0 = predicted class
forward:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      dense_2_to_3
    bl      relu_hidden
    bl      dense_3_to_2
    bl      argmax_output
    ldp     x29, x30, [sp], #16
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

_start:
    // q_mul sanity
    mov     w0, #ONE
    mov     x1, #100
    bl      q_mul
    mov     x1, #100
    bl      assert_eq

    mov     w0, #16384
    mov     w1, #16384
    bl      q_mul
    mov     x1, #8192
    bl      assert_eq

    mov     x0, #-16384
    mov     x1, #16384
    bl      q_mul
    mov     x1, #-8192
    bl      assert_eq

    // forward x=[0.8, 0.2]
    LDADDR  x4, input_buf
    mov     x0, #26214
    str     x0, [x4, #0]
    mov     x0, #6553
    str     x0, [x4, #8]
    bl      forward
    mov     x1, #0
    bl      assert_eq

    // forward x=[0.2, 0.8]
    LDADDR  x4, input_buf
    mov     x0, #6553
    str     x0, [x4, #0]
    mov     x0, #26214
    str     x0, [x4, #8]
    bl      forward
    mov     x1, #1
    bl      assert_eq

    // forward x=[1.0, 0.0]
    LDADDR  x4, input_buf
    mov     w0, #32767
    str     x0, [x4, #0]
    str     xzr, [x4, #8]
    bl      forward
    mov     x1, #0
    bl      assert_eq

    // forward x=[0.0, 1.0]
    LDADDR  x4, input_buf
    str     xzr, [x4, #0]
    mov     w0, #32767
    str     x0, [x4, #8]
    bl      forward
    mov     x1, #1
    bl      assert_eq

    // ReLU actually fires: after [1.0, 0.0], hidden[1] = 0
    LDADDR  x4, input_buf
    mov     w0, #32767
    str     x0, [x4, #0]
    str     xzr, [x4, #8]
    bl      forward
    LDADDR  x4, hidden_buf
    ldr     x0, [x4, #8]
    mov     x1, #0
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
