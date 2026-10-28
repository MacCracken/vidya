# Vidya — Sprite Rendering in x86_64 Assembly
#
# Software sprite blitting to a framebuffer. Demonstrates: 1:1 blit,
# scaled blit with 16.16 fixed-point stepping, color key transparency,
# screen clipping, and painter's draw order (later draws win — a real
# renderer sorts sprites by depth first; no sort is done here).

.intel_syntax noprefix
.global _start

.section .data

test_count: .quad 0
pass_count: .quad 0

# Framebuffer (320x240, 8-bit palette indices)
.equ SCREEN_W, 320
.equ SCREEN_H, 240
.equ FB_SIZE,   76800       # 320 * 240

framebuf: .space FB_SIZE, 0

# A small 4x4 test sprite in the "atlas"
# Color key (transparent) = 0
test_sprite:
    .byte 0, 1, 1, 0
    .byte 1, 2, 2, 1
    .byte 1, 2, 2, 1
    .byte 0, 1, 1, 0

.section .rodata

.equ FX_SHIFT, 16
.equ COLOR_KEY, 0           # palette index 0 = transparent

msg_pass:      .ascii "PASS: "
msg_pass_len = . - msg_pass
msg_fail:      .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:        .ascii "\n"
msg_summary:   .ascii "All sprite rendering examples passed.\n"
msg_sum_len = . - msg_summary
msg_not_all:   .ascii "SOME TESTS FAILED\n"
msg_not_len = . - msg_not_all

msg_t1:     .ascii "clear framebuffer fills with color"
msg_t1_len = . - msg_t1
msg_t2:     .ascii "blit sprite writes non-transparent pixels"
msg_t2_len = . - msg_t2
msg_t3:     .ascii "transparency: color key pixels not written"
msg_t3_len = . - msg_t3
msg_t4:     .ascii "clipping: sprite partially off-screen"
msg_t4_len = . - msg_t4
msg_t5:     .ascii "scaled blit: 2x magnification"
msg_t5_len = . - msg_t5
msg_t6:     .ascii "painter's order: later draw overwrites earlier"
msg_t6_len = . - msg_t6

.section .text

# --- Framebuffer operations ---

# fb_clear: fill framebuffer with a single color
# rdi = color (byte value)
fb_clear:
    lea     rax, [rip + framebuf]
    mov     rcx, FB_SIZE
    # Use rep stosb for fast fill
    push    rdi
    mov     rdi, rax
    pop     rax
    rep     stosb
    ret

# fb_get_pixel: read pixel at (rdi=x, rsi=y)
# Returns byte value in rax
fb_get_pixel:
    imul    rsi, SCREEN_W
    add     rsi, rdi
    lea     rax, [rip + framebuf]
    movzx   rax, byte ptr [rax + rsi]
    ret

# fb_set_pixel: write pixel at (rdi=x, rsi=y, rdx=color)
# Bounds-checked: off-screen writes are dropped. Clobbers rax, rcx.
fb_set_pixel:
    cmp     rdi, SCREEN_W
    jge     .sp_skip
    cmp     rsi, SCREEN_H
    jge     .sp_skip
    cmp     rdi, 0
    jl      .sp_skip
    cmp     rsi, 0
    jl      .sp_skip
    imul    rcx, rsi, SCREEN_W
    add     rcx, rdi
    lea     rax, [rip + framebuf]
    mov     [rax + rcx], dl
.sp_skip:
    ret

# --- Sprite blit (1:1, with transparency) ---

# blit_sprite: draw sprite to framebuffer
# rdi=sprite_data, rsi=sprite_w, rdx=sprite_h, rcx=dst_x, r8=dst_y
blit_sprite:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi        # sprite data ptr
    mov     r13, rsi        # sprite width
    mov     r14, rdx        # sprite height
    mov     r15, rcx        # dst_x
    mov     rbx, r8         # dst_y

    # Clip bounds
    xor     r8, r8          # src_start_y = 0
    xor     r9, r9          # src_start_x = 0

    # Compute visible region
    # end_x = min(dst_x + sprite_w, SCREEN_W)
    mov     rax, r15
    add     rax, r13
    cmp     rax, SCREEN_W
    jle     .blit_ex_ok
    mov     rax, SCREEN_W
.blit_ex_ok:
    mov     rcx, rax        # end_x (screen)

    # end_y = min(dst_y + sprite_h, SCREEN_H)
    mov     rax, rbx
    add     rax, r14
    cmp     rax, SCREEN_H
    jle     .blit_ey_ok
    mov     rax, SCREEN_H
.blit_ey_ok:
    mov     rdx, rax        # end_y (screen)

    # start_x = max(dst_x, 0)
    mov     rsi, r15
    test    rsi, rsi
    jns     .blit_sx_ok
    neg     rsi
    mov     r9, rsi         # src_start_x = -dst_x
    xor     rsi, rsi
.blit_sx_ok:

    # start_y = max(dst_y, 0)
    mov     rdi, rbx
    test    rdi, rdi
    jns     .blit_sy_ok
    neg     rdi
    mov     r8, rdi         # src_start_y = -dst_y
    xor     rdi, rdi
.blit_sy_ok:

    # Row loop: rdi = screen_y, r8 = src_y
    mov     r10, rdi        # screen_y start
.blit_row:
    cmp     r10, rdx
    jge     .blit_done

    # Column loop
    mov     r11, rsi        # screen_x start
    mov     rax, r9         # src_x start
.blit_col:
    cmp     r11, rcx
    jge     .blit_next_row

    # Read source pixel
    push    rax
    push    rcx
    push    rdx
    # src offset = src_y * sprite_w + src_x
    mov     rcx, r8
    imul    rcx, r13
    add     rcx, rax
    movzx   eax, byte ptr [r12 + rcx]

    # Skip transparent (color key = 0)
    test    al, al
    jz      .blit_skip_pixel

    # Write to framebuffer
    push    rax
    mov     rax, r10
    imul    rax, SCREEN_W
    add     rax, r11
    pop     rcx             # color
    lea     rdx, [rip + framebuf]
    mov     [rdx + rax], cl

.blit_skip_pixel:
    pop     rdx
    pop     rcx
    pop     rax

    inc     r11             # screen_x++
    inc     rax             # src_x++
    jmp     .blit_col

.blit_next_row:
    inc     r10             # screen_y++
    inc     r8              # src_y++
    jmp     .blit_row

.blit_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- Scaled blit (nearest neighbour, 16.16 stepping) ---

# blit_scaled: draw sprite magnified by a 16.16 scale factor
# rdi=sprite_data, rsi=sprite_w, rdx=sprite_h, rcx=dst_x, r8=dst_y,
# r9=scale (16.16, e.g. 131072 = 2.0)
# The destination is (w*scale) x (h*scale). Each destination pixel samples
# source (d * step) >> 16 with step = 1/scale in 16.16, so the inner loop
# only adds — no per-pixel divide.
blit_scaled:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 40                 # [rsp]=dst_w [rsp+8]=dst_h [rsp+16]=step
                                    # [rsp+24]=dx  [rsp+32]=src_x (16.16)
    mov     r12, rdi                # sprite data
    mov     r13, rsi                # sprite width
    mov     r14, rcx                # dst_x
    mov     r15, r8                 # dst_y
    mov     rax, rsi
    imul    rax, r9
    sar     rax, FX_SHIFT
    mov     [rsp], rax              # dst_w = w * scale
    mov     rax, rdx
    imul    rax, r9
    sar     rax, FX_SHIFT
    mov     [rsp + 8], rax          # dst_h = h * scale
    mov     rax, 1
    shl     rax, 32
    xor     edx, edx
    div     r9
    mov     [rsp + 16], rax         # step = 1.0 / scale (16.16)
    xor     ebp, ebp                # dy
    xor     ebx, ebx                # src_y (16.16)
.bs_row:
    cmp     rbp, [rsp + 8]
    jge     .bs_done
    mov     qword ptr [rsp + 24], 0
    mov     qword ptr [rsp + 32], 0
.bs_col:
    mov     rax, [rsp + 24]
    cmp     rax, [rsp]
    jge     .bs_next_row
    # source pixel = sprite[(src_y >> 16) * w + (src_x >> 16)]
    mov     rax, rbx
    shr     rax, FX_SHIFT
    imul    rax, r13
    mov     rcx, [rsp + 32]
    shr     rcx, FX_SHIFT
    add     rax, rcx
    movzx   edx, byte ptr [r12 + rax]
    test    edx, edx
    jz      .bs_skip                # color key: transparent
    mov     rdi, r14
    add     rdi, [rsp + 24]
    lea     rsi, [r15 + rbp]
    call    fb_set_pixel            # clipped write
.bs_skip:
    inc     qword ptr [rsp + 24]
    mov     rax, [rsp + 16]
    add     [rsp + 32], rax         # src_x += step
    jmp     .bs_col
.bs_next_row:
    inc     rbp
    add     rbx, [rsp + 16]         # src_y += step
    jmp     .bs_row
.bs_done:
    add     rsp, 40
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- Test helpers ---

assert_eq:
    push    rdx
    push    rcx
    inc     qword ptr [rip + test_count]
    cmp     rdi, rsi
    jne     .af
    inc     qword ptr [rip + pass_count]
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    jmp     .am
.af:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
.am:
    pop     rdx
    pop     rsi
    mov     rax, 1
    mov     rdi, 1
    syscall
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_nl]
    mov     rdx, 1
    syscall
    ret

_start:
    # --- Test 1: Clear framebuffer ---
    mov     rdi, 42         # fill with color 42
    call    fb_clear
    # Check pixel at (100, 100)
    mov     rdi, 100
    mov     rsi, 100
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 42
    lea     rdx, [rip + msg_t1]
    mov     rcx, msg_t1_len
    call    assert_eq

    # --- Test 2: Blit sprite writes non-transparent pixels ---
    mov     rdi, 0
    call    fb_clear        # clear to 0

    lea     rdi, [rip + test_sprite]
    mov     rsi, 4          # width
    mov     rdx, 4          # height
    mov     rcx, 10         # dst_x
    mov     r8,  10         # dst_y
    call    blit_sprite

    # Pixel at (11, 11) should be 2 (center of sprite)
    mov     rdi, 11
    mov     rsi, 11
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 2
    lea     rdx, [rip + msg_t2]
    mov     rcx, msg_t2_len
    call    assert_eq

    # --- Test 3: Transparency — color key pixels not written ---
    mov     rdi, 99
    call    fb_clear        # fill with 99

    lea     rdi, [rip + test_sprite]
    mov     rsi, 4
    mov     rdx, 4
    mov     rcx, 10
    mov     r8,  10
    call    blit_sprite

    # Pixel at (10, 10) is transparent in sprite (corner = 0)
    # Should still be 99 (background), not 0
    mov     rdi, 10
    mov     rsi, 10
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 99
    lea     rdx, [rip + msg_t3]
    mov     rcx, msg_t3_len
    call    assert_eq

    # --- Test 4: Clipping — sprite at edge of screen ---
    mov     rdi, 0
    call    fb_clear

    lea     rdi, [rip + test_sprite]
    mov     rsi, 4
    mov     rdx, 4
    mov     rcx, 318        # x=318, sprite extends to 322 (2px clipped)
    mov     r8,  0
    call    blit_sprite

    # Pixel at (319, 1) should be written (within screen)
    mov     rdi, 319
    mov     rsi, 1
    call    fb_get_pixel
    # Sprite col 1 at row 1 = 2
    mov     rdi, rax
    mov     rsi, 2
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq
    # The clipped columns must not wrap onto the next row: without the
    # end_x clamp, sprite (2,0) would land at x=320 = (0,1)
    mov     rdi, 0
    mov     rsi, 1
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 0
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq

    # Top-left clip: at (-2,-2) only sprite (2..3, 2..3) is visible
    mov     rdi, 0
    call    fb_clear
    lea     rdi, [rip + test_sprite]
    mov     rsi, 4
    mov     rdx, 4
    mov     rcx, -2
    mov     r8,  -2
    call    blit_sprite
    mov     rdi, 0
    mov     rsi, 0
    call    fb_get_pixel            # sprite (2,2) = 2
    mov     rdi, rax
    mov     rsi, 2
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq
    mov     rdi, 1
    mov     rsi, 0
    call    fb_get_pixel            # sprite (3,2) = 1
    mov     rdi, rax
    mov     rsi, 1
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq

    # --- Test 5: Scaled blit (2x) ---
    # 4x4 sprite at scale 2.0 covers (100..107, 100..107); each source
    # pixel becomes a 2x2 block.
    mov     rdi, 99
    call    fb_clear

    lea     rdi, [rip + test_sprite]
    mov     rsi, 4
    mov     rdx, 4
    mov     rcx, 100
    mov     r8,  100
    mov     r9,  131072             # 2.0 in 16.16
    call    blit_scaled

    # (103,103) samples source (1,1) = 2
    mov     rdi, 103
    mov     rsi, 103
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 2
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq
    # (107,103) is the last destination column: source (3,1) = 1
    mov     rdi, 107
    mov     rsi, 103
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 1
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq
    # (108,103) is one past the 8-pixel width: untouched
    mov     rdi, 108
    mov     rsi, 103
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 99
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq
    # (101,101) samples transparent source (0,0): background shows through
    mov     rdi, 101
    mov     rsi, 101
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 99
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq

    # --- Test 6: Painter's order (draw order decides overlap) ---
    mov     rdi, 0
    call    fb_clear

    # Draw sprite A at (50,50) — color 2 at center
    lea     rdi, [rip + test_sprite]
    mov     rsi, 4
    mov     rdx, 4
    mov     rcx, 50
    mov     r8,  50
    call    blit_sprite

    # Draw a "second sprite" on top by setting pixel directly
    mov     rdi, 51
    mov     rsi, 51
    mov     rdx, 7          # color 7 overwrites color 2
    call    fb_set_pixel

    # Pixel at (51,51) should be 7 (last draw wins)
    mov     rdi, 51
    mov     rsi, 51
    call    fb_get_pixel
    mov     rdi, rax
    mov     rsi, 7
    lea     rdx, [rip + msg_t6]
    mov     rcx, msg_t6_len
    call    assert_eq

    # --- Summary ---
    mov     rax, [rip + test_count]
    cmp     rax, [rip + pass_count]
    jne     .failed

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_summary]
    mov     rdx, msg_sum_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

.failed:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_not_all]
    mov     rdx, msg_not_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
