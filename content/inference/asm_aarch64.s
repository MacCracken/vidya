// Vidya — LLM Inference (Decoding) — AArch64 Assembly.
//
// Same focused subset as x86_64: argmax + bigram lookup + decode
// loop with EOS termination. 9 asserts.

.global _start

.equ VOCAB_SIZE, 8
.equ TOK_EOS,    1

.data
.align 8
bigram:
    .quad 0, 0, 0, 0, 0, 0, 0, 0
    .quad 0, 0, 0, 0, 0, 0, 0, 0
    .quad 0, 0, 0, 1000, 100, 0, 0, 0
    .quad 0, 0, 0, 0, 0, 200, 800, 0
    .quad 0, 0, 0, 0, 0, 700, 0, 0
    .quad 0, 600, 0, 0, 0, 0, 0, 0
    .quad 0, 0, 0, 100, 0, 0, 0, 900
    .quad 0, 950, 0, 0, 0, 0, 0, 0

.bss
.align 8
output_buf: .skip 128

.section .rodata
msg_pass: .ascii "inference: 9/9 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// argmax_logits(x0=row_ptr, x1=n_vocab) -> x0 = idx
argmax_logits:
    mov     x2, #0                      // best_idx
    ldr     x3, [x0]                    // best_val = logits[0]
    mov     x4, #1
.am_loop:
    cmp     x4, x1
    b.ge    .am_done
    ldr     x5, [x0, x4, lsl #3]
    cmp     x5, x3
    b.le    .am_skip
    mov     x3, x5
    mov     x2, x4
.am_skip:
    add     x4, x4, #1
    b       .am_loop
.am_done:
    mov     x0, x2
    ret

// bigram_logits_ptr(x0=prev_token) -> x0 = pointer to row
bigram_logits_ptr:
    lsl     x0, x0, #6                  // prev * 64 (bytes per row)
    LDADDR  x1, bigram
    add     x0, x0, x1
    ret

// decode_sequence(x0=start, x1=output_ptr, x2=max_len) -> x0 = count
decode_sequence:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    str     x19, [sp, #16]
    str     x20, [sp, #24]
    str     x21, [sp, #32]
    str     x22, [sp, #40]
    mov     x19, x0                     // current
    mov     x20, x1                     // output_ptr
    mov     x21, x2                     // max_len
    mov     x22, #0                     // count
.ds_loop:
    cmp     x22, x21
    b.ge    .ds_done
    mov     x0, x19
    bl      bigram_logits_ptr
    mov     x1, #VOCAB_SIZE
    bl      argmax_logits               // x0 = next_tok
    str     x0, [x20, x22, lsl #3]
    add     x22, x22, #1
    cmp     x0, #TOK_EOS
    b.eq    .ds_done
    mov     x19, x0
    b       .ds_loop
.ds_done:
    mov     x0, x22
    ldr     x22, [sp, #40]
    ldr     x21, [sp, #32]
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #48
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
    // argmax for "hello" (2) → 3
    mov     x0, #2
    bl      bigram_logits_ptr
    mov     x1, #VOCAB_SIZE
    bl      argmax_logits
    mov     x1, #3
    bl      assert_eq

    // argmax for "world" (3) → 6
    mov     x0, #3
    bl      bigram_logits_ptr
    mov     x1, #VOCAB_SIZE
    bl      argmax_logits
    mov     x1, #6
    bl      assert_eq

    // argmax for "bar" (5) → 1 (EOS)
    mov     x0, #5
    bl      bigram_logits_ptr
    mov     x1, #VOCAB_SIZE
    bl      argmax_logits
    mov     x1, #1
    bl      assert_eq

    // decode_sequence(2, output, 10) → 4 tokens [3, 6, 7, 1]
    mov     x0, #2
    LDADDR  x1, output_buf
    mov     x2, #10
    bl      decode_sequence
    mov     x1, #4
    bl      assert_eq

    LDADDR  x4, output_buf
    ldr     x0, [x4, #0]
    mov     x1, #3
    bl      assert_eq
    LDADDR  x4, output_buf
    ldr     x0, [x4, #8]
    mov     x1, #6
    bl      assert_eq
    LDADDR  x4, output_buf
    ldr     x0, [x4, #16]
    mov     x1, #7
    bl      assert_eq
    LDADDR  x4, output_buf
    ldr     x0, [x4, #24]
    mov     x1, #1
    bl      assert_eq

    // decode_sequence(2, output, 2) → capped at 2
    mov     x0, #2
    LDADDR  x1, output_buf
    mov     x2, #2
    bl      decode_sequence
    mov     x1, #2
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
