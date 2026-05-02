// Vidya — Framebuffer Rendering in AArch64 Assembly
//
// 16x16 BGRA8888 framebuffer mirroring cyrius.cyr.
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// callee-saved x19+ across `bl`. fb_set may clobber x0–x18; loop state
// for draw_hline/draw_vline cached in x19–x22.

.global _start

.equ FB_W,     16
.equ FB_H,     16
.equ FB_BPP,   4
.equ FB_BYTES, 1024

.bss
.align 8
fb_buf:       .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "framebuffer_rendering: 18/18 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// fb_clear — zero the whole framebuffer
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

// fb_set(x0=x, x1=y, x2=color) -> x0 = 1 or 0
fb_set:
    cmp     x0, #0
    b.lt    .fs_oob
    cmp     x0, #FB_W
    b.ge    .fs_oob
    cmp     x1, #0
    b.lt    .fs_oob
    cmp     x1, #FB_H
    b.ge    .fs_oob
    // offset = (y * 16 + x) * 4
    lsl     x3, x1, #4            // y * 16
    add     x3, x3, x0
    lsl     x3, x3, #2
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    add     x4, x4, x3
    strb    w2, [x4]              // B
    lsr     x5, x2, #8
    strb    w5, [x4, #1]          // G
    lsr     x5, x2, #16
    strb    w5, [x4, #2]          // R
    mov     w5, #255
    strb    w5, [x4, #3]          // A
    mov     x0, #1
    ret
.fs_oob:
    mov     x0, #0
    ret

// fb_get(x0=x, x1=y) -> x0 = color (0 if OOB)
fb_get:
    cmp     x0, #0
    b.lt    .fg_oob
    cmp     x0, #FB_W
    b.ge    .fg_oob
    cmp     x1, #0
    b.lt    .fg_oob
    cmp     x1, #FB_H
    b.ge    .fg_oob
    lsl     x3, x1, #4
    add     x3, x3, x0
    lsl     x3, x3, #2
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    add     x4, x4, x3
    ldrb    w5, [x4]              // B
    ldrb    w6, [x4, #1]          // G
    ldrb    w7, [x4, #2]          // R
    lsl     x7, x7, #16
    lsl     x6, x6, #8
    orr     x0, x7, x6
    orr     x0, x0, x5
    ret
.fg_oob:
    mov     x0, #0
    ret

// draw_hline(x0=x, x1=y, x2=len, x3=color) — caches loop state in callee-saveds
draw_hline:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    mov     x19, x0               // x
    mov     x20, x1               // y
    mov     x21, x2               // len
    mov     x22, x3               // color
    mov     x23, #0               // i (callee-saved x23 too — but we have stp for x19-x22 only)
    // Use x4 for i since we don't call between iterations of i — wait, fb_set IS called.
    // Need i in callee-saved.
    mov     x0, x21
    // fall through — we already accidentally use x4. Fix: use x23 above + add stp.
.dh_loop:
    cmp     x23, x21
    b.ge    .dh_done
    add     x0, x19, x23
    mov     x1, x20
    mov     x2, x22
    bl      fb_set
    add     x23, x23, #1
    b       .dh_loop
.dh_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// draw_vline(x0=x, x1=y, x2=len, x3=color)
draw_vline:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, #0
.dv_loop:
    cmp     x23, x21
    b.ge    .dv_done
    mov     x0, x19
    add     x1, x20, x23
    mov     x2, x22
    bl      fb_set
    add     x23, x23, #1
    b       .dv_loop
.dv_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// count_lit -> x0 = pixel count
count_lit:
    adrp    x1, fb_buf
    add     x1, x1, :lo12:fb_buf
    mov     x0, #0                // n
    mov     x2, #0                // i
.cl_loop:
    cmp     x2, #FB_BYTES
    b.ge    .cl_done
    ldrb    w3, [x1, x2]
    add     x4, x2, #1
    ldrb    w5, [x1, x4]
    add     x4, x2, #2
    ldrb    w6, [x1, x4]
    orr     w7, w3, w5
    orr     w7, w7, w6
    cbz     w7, .cl_next
    add     x0, x0, #1
.cl_next:
    add     x2, x2, #FB_BPP
    b       .cl_loop
.cl_done:
    ret

// assert_eq(x0=got, x1=want) — fail-exit if got != want
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
    // 1. clear → 0 lit
    bl      fb_clear
    bl      count_lit
    mov     x1, #0
    bl      assert_eq

    // 2. red at (5, 7)
    mov     x0, #5
    mov     x1, #7
    ldr     x2, =0xFF0000
    bl      fb_set
    // offset = 468
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    ldrb    w0, [x4, #468]
    mov     x1, #0
    bl      assert_eq
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    ldrb    w0, [x4, #469]
    mov     x1, #0
    bl      assert_eq
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    ldrb    w0, [x4, #470]
    mov     x1, #255
    bl      assert_eq
    adrp    x4, fb_buf
    add     x4, x4, :lo12:fb_buf
    ldrb    w0, [x4, #471]
    mov     x1, #255
    bl      assert_eq

    // 3. fb_get == 0xFF0000
    mov     x0, #5
    mov     x1, #7
    bl      fb_get
    ldr     x1, =0xFF0000
    bl      assert_eq

    // 4. OOB writes don't change count
    bl      count_lit
    mov     x19, x0               // before, callee-saved
    mov     x0, #-1
    mov     x1, #5
    ldr     x2, =0x00FF00
    bl      fb_set
    mov     x0, #FB_W
    mov     x1, #5
    ldr     x2, =0x00FF00
    bl      fb_set
    mov     x0, #5
    mov     x1, #-1
    ldr     x2, =0x00FF00
    bl      fb_set
    mov     x0, #5
    mov     x1, #FB_H
    ldr     x2, =0x00FF00
    bl      fb_set
    bl      count_lit
    mov     x1, x19
    bl      assert_eq

    // 5. fb_set return contract
    mov     x0, #3
    mov     x1, #3
    ldr     x2, =0x0000FF
    bl      fb_set
    mov     x1, #1
    bl      assert_eq
    mov     x0, #-5
    mov     x1, #3
    ldr     x2, =0x0000FF
    bl      fb_set
    mov     x1, #0
    bl      assert_eq

    // 6. hline
    bl      fb_clear
    mov     x0, #2
    mov     x1, #8
    mov     x2, #4
    ldr     x3, =0x00FF00
    bl      draw_hline
    bl      count_lit
    mov     x1, #4
    bl      assert_eq
    mov     x0, #2
    mov     x1, #8
    bl      fb_get
    ldr     x1, =0x00FF00
    bl      assert_eq
    mov     x0, #5
    mov     x1, #8
    bl      fb_get
    ldr     x1, =0x00FF00
    bl      assert_eq
    mov     x0, #6
    mov     x1, #8
    bl      fb_get
    mov     x1, #0
    bl      assert_eq

    // 7. vline
    bl      fb_clear
    mov     x0, #7
    mov     x1, #2
    mov     x2, #4
    ldr     x3, =0x0000FF
    bl      draw_vline
    bl      count_lit
    mov     x1, #4
    bl      assert_eq
    mov     x0, #7
    mov     x1, #2
    bl      fb_get
    ldr     x1, =0x0000FF
    bl      assert_eq
    mov     x0, #7
    mov     x1, #5
    bl      fb_get
    ldr     x1, =0x0000FF
    bl      assert_eq
    mov     x0, #7
    mov     x1, #6
    bl      fb_get
    mov     x1, #0
    bl      assert_eq

    // 8. hline clipped
    bl      fb_clear
    mov     x0, #14
    mov     x1, #5
    mov     x2, #4
    ldr     x3, =0xFF0000
    bl      draw_hline
    bl      count_lit
    mov     x1, #2
    bl      assert_eq

    // success
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
