// Vidya — Sprite Rendering in AArch64 Assembly
//
// Software sprite blitting onto a flat 8-bit palette framebuffer.
// AArch64 has no implicit 16-bit immediates; constants like FB_SIZE
// (76800) must be loaded with `ldr xN, =literal` so the assembler
// pools them. The framebuffer is reserved with `.skip 76800` in
// .bss and addressed by `adrp` + `add :lo12:` (PC-relative GOT-style
// stride pointer arithmetic). Functions that issue `bl` save x29/x30
// in the prologue.

.global _start

.equ SCREEN_W,  320
.equ SCREEN_H,  240
.equ COLOR_KEY, 0
.equ FX_SHIFT,  16

.section .rodata
msg_pass:    .ascii "All sprite_rendering examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

// 4x4 test sprite (rounded square, color-key 0 = transparent corners)
.align 3
test_sprite:
    .byte 0, 1, 1, 0
    .byte 1, 2, 2, 1
    .byte 1, 2, 2, 1
    .byte 0, 1, 1, 0

.section .bss
.align 4
framebuf:
    .skip 76800        // FB_SIZE = SCREEN_W * SCREEN_H

.section .text

// ── fb_clear: fill framebuffer with x0 (color byte) ─────────────────
// Clobbers x9, x10, x11.
fb_clear:
    adrp    x9, framebuf
    add     x9, x9, :lo12:framebuf
    ldr     x10, =76800
    and     x11, x0, #0xff
.Lfb_clear_loop:
    cbz     x10, .Lfb_clear_done
    strb    w11, [x9], #1
    sub     x10, x10, #1
    b       .Lfb_clear_loop
.Lfb_clear_done:
    ret

// ── fb_get: x0 = x, x1 = y → result byte in x0 ──────────────────────
fb_get:
    cmp     x0, #0
    b.lt    .Lget_zero
    cmp     x0, #SCREEN_W
    b.ge    .Lget_zero
    cmp     x1, #0
    b.lt    .Lget_zero
    cmp     x1, #SCREEN_H
    b.ge    .Lget_zero
    ldr     x9, =SCREEN_W
    mul     x9, x1, x9
    add     x9, x9, x0           // offset = y*W + x
    adrp    x10, framebuf
    add     x10, x10, :lo12:framebuf
    ldrb    w0, [x10, x9]
    ret
.Lget_zero:
    mov     x0, #0
    ret

// ── fb_set: x0 = x, x1 = y, x2 = color ──────────────────────────────
fb_set:
    cmp     x0, #0
    b.lt    .Lset_done
    cmp     x0, #SCREEN_W
    b.ge    .Lset_done
    cmp     x1, #0
    b.lt    .Lset_done
    cmp     x1, #SCREEN_H
    b.ge    .Lset_done
    ldr     x9, =SCREEN_W
    mul     x9, x1, x9
    add     x9, x9, x0
    adrp    x10, framebuf
    add     x10, x10, :lo12:framebuf
    strb    w2, [x10, x9]
.Lset_done:
    ret

// ── blit: x0 = sprite_data, x1 = sw, x2 = sh, x3 = dst_x, x4 = dst_y
// Clipping + transparency + flat-byte write. Uses callee-saved
// x19..x27; saves x29/x30 because we may add `bl` later.
blit:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    str     x27, [sp, #80]

    mov     x19, x0              // sprite data
    mov     x20, x1              // sw
    mov     x21, x2              // sh
    mov     x22, x3              // dst_x
    mov     x23, x4              // dst_y

    mov     x24, #0              // start_x
    mov     x25, #0              // start_y
    mov     x26, x20             // end_x = sw
    mov     x27, x21             // end_y = sh

    // Clip left: if dst_x < 0 { start_x = -dst_x; dst_x = 0; }
    cmp     x22, #0
    b.ge    .Lblit_chk_top
    sub     x24, xzr, x22
    mov     x22, #0
.Lblit_chk_top:
    cmp     x23, #0
    b.ge    .Lblit_chk_right
    sub     x25, xzr, x23
    mov     x23, #0
.Lblit_chk_right:
    // if dst_x + (end_x - start_x) > SCREEN_W: end_x = start_x + (SCREEN_W - dst_x)
    sub     x9, x26, x24
    add     x9, x9, x22
    cmp     x9, #SCREEN_W
    b.le    .Lblit_chk_bottom
    mov     x10, #SCREEN_W
    sub     x10, x10, x22
    add     x26, x24, x10
.Lblit_chk_bottom:
    sub     x9, x27, x25
    add     x9, x9, x23
    cmp     x9, #SCREEN_H
    b.le    .Lblit_rows
    mov     x10, #SCREEN_H
    sub     x10, x10, x23
    add     x27, x25, x10

.Lblit_rows:
    // sy = start_y
    mov     x0, x25              // sy
.Lblit_row_loop:
    cmp     x0, x27
    b.ge    .Lblit_done
    // sx = start_x
    mov     x1, x24
.Lblit_col_loop:
    cmp     x1, x26
    b.ge    .Lblit_next_row
    // pixel = sprite[sy*sw + sx]
    mul     x9, x0, x20
    add     x9, x9, x1
    ldrb    w10, [x19, x9]
    cbz     x10, .Lblit_skip      // transparent
    // dx = dst_x + (sx - start_x), dy = dst_y + (sy - start_y)
    sub     x11, x1, x24
    add     x11, x11, x22         // dx
    sub     x12, x0, x25
    add     x12, x12, x23         // dy
    ldr     x13, =SCREEN_W
    mul     x13, x12, x13
    add     x13, x13, x11
    adrp    x14, framebuf
    add     x14, x14, :lo12:framebuf
    strb    w10, [x14, x13]
.Lblit_skip:
    add     x1, x1, #1
    b       .Lblit_col_loop
.Lblit_next_row:
    add     x0, x0, #1
    b       .Lblit_row_loop

.Lblit_done:
    ldr     x27, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

// ── blit_scaled: x0=data, x1=sw, x2=sh, x3=dst_x, x4=dst_y, x5=dst_w, x6=dst_h
blit_scaled:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    cmp     x5, #0
    b.le    .Lscaled_done
    cmp     x6, #0
    b.le    .Lscaled_done

    mov     x19, x0              // data
    mov     x20, x1              // sw
    mov     x22, x3              // dst_x
    mov     x23, x4              // dst_y
    mov     x24, x5              // dst_w
    mov     x25, x6              // dst_h

    // step_x = (sw << 16) / dst_w
    lsl     x9, x20, #FX_SHIFT
    sdiv    x26, x9, x24         // step_x
    // step_y = (sh << 16) / dst_h
    lsl     x9, x2, #FX_SHIFT
    sdiv    x27, x9, x25         // step_y

    mov     x28, #0              // src_y
    mov     x0, #0               // dy

.Lscaled_row:
    cmp     x0, x25
    b.ge    .Lscaled_done
    add     x9, x23, x0          // screen_y
    cmp     x9, #0
    b.lt    .Lscaled_next_row
    cmp     x9, #SCREEN_H
    b.ge    .Lscaled_next_row
    // row_base = (src_y >> 16) * sw
    asr     x10, x28, #FX_SHIFT
    mul     x10, x10, x20        // row_base
    mov     x11, #0              // src_x
    mov     x1, #0               // dx
.Lscaled_col:
    cmp     x1, x24
    b.ge    .Lscaled_next_row
    add     x12, x22, x1         // screen_x
    cmp     x12, #0
    b.lt    .Lscaled_step
    cmp     x12, #SCREEN_W
    b.ge    .Lscaled_step
    // pixel = data[row_base + (src_x >> 16)]
    asr     x13, x11, #FX_SHIFT
    add     x13, x13, x10
    ldrb    w14, [x19, x13]
    cbz     x14, .Lscaled_step
    // fb[screen_y * SCREEN_W + screen_x] = pixel
    ldr     x15, =SCREEN_W
    mul     x15, x9, x15
    add     x15, x15, x12
    adrp    x16, framebuf
    add     x16, x16, :lo12:framebuf
    strb    w14, [x16, x15]
.Lscaled_step:
    add     x11, x11, x26        // src_x += step_x
    add     x1, x1, #1
    b       .Lscaled_col
.Lscaled_next_row:
    add     x28, x28, x27        // src_y += step_y
    add     x0, x0, #1
    b       .Lscaled_row

.Lscaled_done:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #112
    ret

// ── _start: run all tests, exit 0 on success ────────────────────────
_start:
    // Test 1: clear
    mov     x0, #42
    bl      fb_clear
    mov     x0, #100
    mov     x1, #100
    bl      fb_get
    cmp     x0, #42
    b.ne    fail

    // Test 2: blit opaque — center pixel
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #10
    mov     x4, #10
    bl      blit
    mov     x0, #11
    mov     x1, #11
    bl      fb_get
    cmp     x0, #2
    b.ne    fail

    // Test 3: transparency
    mov     x0, #99
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #10
    mov     x4, #10
    bl      blit
    mov     x0, #10
    mov     x1, #10
    bl      fb_get
    cmp     x0, #99
    b.ne    fail
    mov     x0, #11
    mov     x1, #10
    bl      fb_get
    cmp     x0, #1
    b.ne    fail

    // Test 4: clipping right
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #318
    mov     x4, #0
    bl      blit
    mov     x0, #319
    mov     x1, #1
    bl      fb_get
    cmp     x0, #2
    b.ne    fail

    // Test 5: clipping left
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #-2
    mov     x4, #0
    bl      blit
    mov     x0, #0
    mov     x1, #1
    bl      fb_get
    cmp     x0, #2
    b.ne    fail

    // Test 6: scaled blit (2x)
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #20
    mov     x4, #20
    mov     x5, #8
    mov     x6, #8
    bl      blit_scaled
    mov     x0, #22
    mov     x1, #22
    bl      fb_get
    cmp     x0, #2
    b.ne    fail

    // Test 7: depth sort
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #50
    mov     x4, #50
    bl      blit
    mov     x0, #51
    mov     x1, #51
    mov     x2, #7
    bl      fb_set
    mov     x0, #51
    mov     x1, #51
    bl      fb_get
    cmp     x0, #7
    b.ne    fail

    // Test 8: scaled shrink — has at least one non-zero pixel
    mov     x0, #0
    bl      fb_clear
    adrp    x0, test_sprite
    add     x0, x0, :lo12:test_sprite
    mov     x1, #4
    mov     x2, #4
    mov     x3, #100
    mov     x4, #100
    mov     x5, #2
    mov     x6, #2
    bl      blit_scaled
    mov     x0, #100
    mov     x1, #100
    bl      fb_get
    cbnz    x0, .Lshrink_ok
    mov     x0, #101
    mov     x1, #100
    bl      fb_get
    cbnz    x0, .Lshrink_ok
    mov     x0, #100
    mov     x1, #101
    bl      fb_get
    cbnz    x0, .Lshrink_ok
    mov     x0, #101
    mov     x1, #101
    bl      fb_get
    cbnz    x0, .Lshrink_ok
    b       fail
.Lshrink_ok:

    // All passed
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
