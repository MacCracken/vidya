// Vidya — Bloom and Glow in AArch64 Assembly
//
// 1-pixel additive bloom on 16x16 single-channel intensity buffer.
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state for apply_bloom in callee-saved x19+ across `bl fb_add`.

.global _start

.equ FB_W,      16
.equ FB_H,      16
.equ FB_BYTES,  256
.equ THRESHOLD, 128

.bss
.align 8
src_buf:      .skip FB_BYTES
dst_buf:      .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "bloom_and_glow: 20/20 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// fb_clear(x0=fb)
fb_clear:
    mov     x1, #FB_BYTES / 8
    mov     x2, #0
.fc_loop:
    str     x2, [x0], #8
    subs    x1, x1, #1
    b.ne    .fc_loop
    ret

// fb_set(x0=fb, x1=x, x2=y, x3=val)
fb_set:
    cmp     x1, #0
    b.lt    .fs_done
    cmp     x1, #FB_W
    b.ge    .fs_done
    cmp     x2, #0
    b.lt    .fs_done
    cmp     x2, #FB_H
    b.ge    .fs_done
    lsl     x4, x2, #4
    add     x4, x4, x1
    strb    w3, [x0, x4]
.fs_done:
    ret

// fb_get(x0=fb, x1=x, x2=y) -> x0
fb_get:
    cmp     x1, #0
    b.lt    .fg_zero
    cmp     x1, #FB_W
    b.ge    .fg_zero
    cmp     x2, #0
    b.lt    .fg_zero
    cmp     x2, #FB_H
    b.ge    .fg_zero
    lsl     x3, x2, #4
    add     x3, x3, x1
    ldrb    w0, [x0, x3]
    ret
.fg_zero:
    mov     x0, #0
    ret

// fb_add(x0=fb, x1=x, x2=y, x3=delta) — clamp at 255
fb_add:
    cmp     x1, #0
    b.lt    .fa_done
    cmp     x1, #FB_W
    b.ge    .fa_done
    cmp     x2, #0
    b.lt    .fa_done
    cmp     x2, #FB_H
    b.ge    .fa_done
    lsl     x4, x2, #4
    add     x4, x4, x1
    ldrb    w5, [x0, x4]
    add     x5, x5, x3
    cmp     x5, #255
    b.le    .fa_store
    mov     x5, #255
.fa_store:
    strb    w5, [x0, x4]
.fa_done:
    ret

// count_lit(x0=fb) -> x0
count_lit:
    mov     x1, #0
    mov     x2, #0
.cl_loop:
    cmp     x2, #FB_BYTES
    b.ge    .cl_done
    ldrb    w3, [x0, x2]
    cbz     w3, .cl_next
    add     x1, x1, #1
.cl_next:
    add     x2, x2, #1
    b       .cl_loop
.cl_done:
    mov     x0, x1
    ret

// apply_bloom(x0=src, x1=dst, x2=threshold)
// callee-saved: x19=src, x20=dst, x21=threshold, x22=y, x23=x, x24=glow
apply_bloom:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    // Copy src -> dst
    mov     x3, #0
.ab_copy:
    cmp     x3, #FB_BYTES
    b.ge    .ab_y_init
    ldrb    w4, [x19, x3]
    strb    w4, [x20, x3]
    add     x3, x3, #1
    b       .ab_copy
.ab_y_init:
    mov     x22, #0
.ab_y_loop:
    cmp     x22, #FB_H
    b.ge    .ab_done
    mov     x23, #0
.ab_x_loop:
    cmp     x23, #FB_W
    b.ge    .ab_y_next
    lsl     x4, x22, #4
    add     x4, x4, x23
    ldrb    w5, [x19, x4]
    cmp     x5, x21
    b.lt    .ab_x_next
    lsr     x24, x5, #1           // glow = v / 2
    // 4 neighbors
    mov     x0, x20
    sub     x1, x23, #1
    mov     x2, x22
    mov     x3, x24
    bl      fb_add
    mov     x0, x20
    add     x1, x23, #1
    mov     x2, x22
    mov     x3, x24
    bl      fb_add
    mov     x0, x20
    mov     x1, x23
    sub     x2, x22, #1
    mov     x3, x24
    bl      fb_add
    mov     x0, x20
    mov     x1, x23
    add     x2, x22, #1
    mov     x3, x24
    bl      fb_add
.ab_x_next:
    add     x23, x23, #1
    b       .ab_x_loop
.ab_y_next:
    add     x22, x22, #1
    b       .ab_y_loop
.ab_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

assert_eq:
    cmp     x0, x1
    b.ne    fail_exit
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    // Test 1: empty
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    bl      count_lit
    mov     x1, #0
    bl      assert_eq

    // Test 2: single bright (8, 8) → 200
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #8
    mov     x2, #8
    mov     x3, #200
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    // src
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #8
    mov     x2, #8
    bl      fb_get
    mov     x1, #200
    bl      assert_eq
    // L
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #7
    mov     x2, #8
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    // R
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #9
    mov     x2, #8
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    // U
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #8
    mov     x2, #7
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    // D
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #8
    mov     x2, #9
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    // diag
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #7
    mov     x2, #7
    bl      fb_get
    mov     x1, #0
    bl      assert_eq
    // count
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    bl      count_lit
    mov     x1, #5
    bl      assert_eq

    // Test 3: saturation clamp
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #8
    mov     x2, #8
    mov     x3, #200
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #9
    mov     x2, #8
    mov     x3, #250
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #9
    mov     x2, #8
    bl      fb_get
    mov     x1, #255
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #8
    mov     x2, #8
    bl      fb_get
    mov     x1, #255
    bl      assert_eq

    // Test 4: dim
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #8
    mov     x2, #8
    mov     x3, #100
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #8
    mov     x2, #8
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #7
    mov     x2, #8
    bl      fb_get
    mov     x1, #0
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    bl      count_lit
    mov     x1, #1
    bl      assert_eq

    // Test 5: corner pixel
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #0
    mov     x2, #0
    mov     x3, #200
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #0
    mov     x2, #0
    bl      fb_get
    mov     x1, #200
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #1
    mov     x2, #0
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #0
    mov     x2, #1
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    bl      count_lit
    mov     x1, #3
    bl      assert_eq

    // Test 6: two adjacent bright
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    bl      fb_clear
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #4
    mov     x2, #8
    mov     x3, #200
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    mov     x1, #6
    mov     x2, #8
    mov     x3, #200
    bl      fb_set
    adrp    x0, src_buf
    add     x0, x0, :lo12:src_buf
    adrp    x1, dst_buf
    add     x1, x1, :lo12:dst_buf
    mov     x2, #THRESHOLD
    bl      apply_bloom
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #5
    mov     x2, #8
    bl      fb_get
    mov     x1, #200
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #3
    mov     x2, #8
    bl      fb_get
    mov     x1, #100
    bl      assert_eq
    adrp    x0, dst_buf
    add     x0, x0, :lo12:dst_buf
    mov     x1, #7
    mov     x2, #8
    bl      fb_get
    mov     x1, #100
    bl      assert_eq

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
