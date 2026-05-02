// Vidya — Line Rasterization (Bresenham) in AArch64 Assembly
//
// All-octant integer Bresenham on a 16x16 byte framebuffer.
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state for draw_line lives in callee-saved x19-x25 across `bl
// fb_set`. Iterator (x, y) lives on the frame because each iteration
// calls fb_set, which clobbers x0-x18.

.global _start

.equ FB_W,     16
.equ FB_H,     16
.equ FB_BYTES, 256

.bss
.align 8
fb_buf:       .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "line_rasterization: 27/27 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

fb_clear:
    adrp    x0, fb_buf
    add     x0, x0, :lo12:fb_buf
    mov     x1, #FB_BYTES / 8
    mov     x2, #0
.fc_loop:
    str     x2, [x0], #8
    subs    x1, x1, #1
    b.ne    .fc_loop
    ret

// fb_set(x0=x, x1=y, x2=val)
fb_set:
    cmp     x0, #0
    b.lt    .fs_done
    cmp     x0, #FB_W
    b.ge    .fs_done
    cmp     x1, #0
    b.lt    .fs_done
    cmp     x1, #FB_H
    b.ge    .fs_done
    lsl     x3, x1, #4            // y * 16
    add     x3, x3, x0
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    strb    w2, [x4, x3]
.fs_done:
    ret

// fb_get(x0=x, x1=y) -> x0
fb_get:
    cmp     x0, #0
    b.lt    .fg_zero
    cmp     x0, #FB_W
    b.ge    .fg_zero
    cmp     x1, #0
    b.lt    .fg_zero
    cmp     x1, #FB_H
    b.ge    .fg_zero
    lsl     x3, x1, #4
    add     x3, x3, x0
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    ldrb    w0, [x4, x3]
    ret
.fg_zero:
    mov     x0, #0
    ret

count_lit:
    adrp    x1, fb_buf
    add     x1, x1, :lo12:fb_buf
    mov     x0, #0
    mov     x2, #0
.cl_loop:
    cmp     x2, #FB_BYTES
    b.ge    .cl_done
    ldrb    w3, [x1, x2]
    cbz     w3, .cl_next
    add     x0, x0, #1
.cl_next:
    add     x2, x2, #1
    b       .cl_loop
.cl_done:
    ret

// iabs(x0) -> x0
iabs:
    cmp     x0, #0
    b.ge    .ia_done
    neg     x0, x0
.ia_done:
    ret

// sign(x0) -> x0
sign:
    cmp     x0, #0
    b.eq    .sg_zero
    b.lt    .sg_neg
    mov     x0, #1
    ret
.sg_neg:
    mov     x0, #-1
    ret
.sg_zero:
    mov     x0, #0
    ret

// draw_line(x0=x0, x1=y0, x2=x1, x3=y1, x4=val)
// Callee-saved: x19=x, x20=y, x21=x1, x22=y1, x23=sx, x24=sy, x25=dx, x26=dy, x27=err, x28=val
draw_line:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!

    mov     x19, x0               // x
    mov     x20, x1               // y
    mov     x21, x2               // x1
    mov     x22, x3               // y1
    mov     x28, x4               // val

    // dx = iabs(x1 - x0)
    sub     x0, x21, x19
    bl      iabs
    mov     x25, x0
    // dy = iabs(y1 - y0)
    sub     x0, x22, x20
    bl      iabs
    mov     x26, x0
    // sx = sign(x1 - x0)
    sub     x0, x21, x19
    bl      sign
    mov     x23, x0
    // sy = sign(y1 - y0)
    sub     x0, x22, x20
    bl      sign
    mov     x24, x0
    // err = dx - dy
    sub     x27, x25, x26

.dl_loop:
    mov     x0, x19
    mov     x1, x20
    mov     x2, x28
    bl      fb_set
    cmp     x19, x21
    b.ne    .dl_step
    cmp     x20, x22
    b.eq    .dl_done
.dl_step:
    lsl     x1, x27, #1           // e2
    neg     x2, x26               // -dy
    cmp     x1, x2
    b.le    .dl_check_y
    sub     x27, x27, x26
    add     x19, x19, x23
.dl_check_y:
    cmp     x1, x25
    b.ge    .dl_loop
    add     x27, x27, x25
    add     x20, x20, x24
    b       .dl_loop
.dl_done:
    ldp     x27, x28, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// assert_eq(x0, x1)
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
    // 1: horizontal
    bl      fb_clear
    mov     x0, #2
    mov     x1, #5
    mov     x2, #8
    mov     x3, #5
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #7
    bl      assert_eq
    mov     x0, #2
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #8
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #6
    bl      fb_get
    mov     x1, #0
    bl      assert_eq

    // 2: vertical
    bl      fb_clear
    mov     x0, #5
    mov     x1, #2
    mov     x2, #5
    mov     x3, #8
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #7
    bl      assert_eq
    mov     x0, #5
    mov     x1, #2
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #8
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #6
    mov     x1, #5
    bl      fb_get
    mov     x1, #0
    bl      assert_eq

    // 3: +diagonal
    bl      fb_clear
    mov     x0, #2
    mov     x1, #2
    mov     x2, #7
    mov     x3, #7
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #6
    bl      assert_eq
    mov     x0, #2
    mov     x1, #2
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #7
    mov     x1, #7
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #4
    bl      fb_get
    mov     x1, #0
    bl      assert_eq

    // 4: -diagonal
    bl      fb_clear
    mov     x0, #2
    mov     x1, #7
    mov     x2, #7
    mov     x3, #2
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #6
    bl      assert_eq
    mov     x0, #2
    mov     x1, #7
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #7
    mov     x1, #2
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #4
    bl      fb_get
    mov     x1, #1
    bl      assert_eq

    // 5: steep
    bl      fb_clear
    mov     x0, #3
    mov     x1, #1
    mov     x2, #5
    mov     x3, #11
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #11
    bl      assert_eq
    mov     x0, #3
    mov     x1, #1
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #11
    bl      fb_get
    mov     x1, #1
    bl      assert_eq

    // 6: single point
    bl      fb_clear
    mov     x0, #8
    mov     x1, #8
    mov     x2, #8
    mov     x3, #8
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #1
    bl      assert_eq
    mov     x0, #8
    mov     x1, #8
    bl      fb_get
    mov     x1, #1
    bl      assert_eq

    // 7: reversed
    bl      fb_clear
    mov     x0, #8
    mov     x1, #5
    mov     x2, #2
    mov     x3, #5
    mov     x4, #1
    bl      draw_line
    bl      count_lit
    mov     x1, #7
    bl      assert_eq
    mov     x0, #2
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
    bl      assert_eq
    mov     x0, #8
    mov     x1, #5
    bl      fb_get
    mov     x1, #1
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
