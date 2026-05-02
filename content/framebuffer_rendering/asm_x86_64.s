# Vidya — Framebuffer Rendering in x86_64 Assembly
#
# 16x16 BGRA8888 framebuffer mirroring cyrius.cyr. .bss for the buffer,
# .text for the helpers. fb_set returns 1 on success / 0 on OOB so the
# caller can verify the bounds-check contract without re-deriving it.

.intel_syntax noprefix
.global _start

.equ FB_W, 16
.equ FB_H, 16
.equ FB_BPP, 4
.equ FB_BYTES, 1024

.section .bss
.align 8
fb_buf:       .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "framebuffer_rendering: 18/18 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# fb_clear — zero the whole framebuffer
fb_clear:
    lea     rdi, [rip + fb_buf]
    mov     rcx, FB_BYTES / 8
    xor     rax, rax
.fc_loop:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .fc_loop
    ret

# fb_set(rdi=x, rsi=y, rdx=color) -> rax = 1 (set) or 0 (OOB)
fb_set:
    test    rdi, rdi
    js      .fs_oob
    cmp     rdi, FB_W
    jge     .fs_oob
    test    rsi, rsi
    js      .fs_oob
    cmp     rsi, FB_H
    jge     .fs_oob
    # offset = (y * FB_W + x) * FB_BPP
    mov     rax, rsi
    imul    rax, FB_W
    add     rax, rdi
    shl     rax, 2
    lea     rcx, [rip + fb_buf]
    add     rcx, rax
    mov     al, dl                # B
    mov     [rcx], al
    mov     rax, rdx
    shr     rax, 8
    mov     [rcx + 1], al         # G
    mov     rax, rdx
    shr     rax, 16
    mov     [rcx + 2], al         # R
    mov     byte ptr [rcx + 3], 255  # A
    mov     rax, 1
    ret
.fs_oob:
    xor     rax, rax
    ret

# fb_get(rdi=x, rsi=y) -> rax = color (0 if OOB)
fb_get:
    test    rdi, rdi
    js      .fg_oob
    cmp     rdi, FB_W
    jge     .fg_oob
    test    rsi, rsi
    js      .fg_oob
    cmp     rsi, FB_H
    jge     .fg_oob
    mov     rax, rsi
    imul    rax, FB_W
    add     rax, rdi
    shl     rax, 2
    lea     rcx, [rip + fb_buf]
    add     rcx, rax
    movzx   r8, byte ptr [rcx + 2]      # R
    shl     r8, 16
    movzx   r9, byte ptr [rcx + 1]      # G
    shl     r9, 8
    movzx   r10, byte ptr [rcx]         # B
    mov     rax, r8
    or      rax, r9
    or      rax, r10
    ret
.fg_oob:
    xor     rax, rax
    ret

# draw_hline(rdi=x, rsi=y, rdx=len, rcx=color)
draw_hline:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi              # x
    mov     r12, rsi              # y
    mov     r13, rdx              # len
    mov     r14, rcx              # color
    xor     r15, r15              # i
.dh_loop:
    cmp     r15, r13
    jge     .dh_done
    mov     rdi, rbx
    add     rdi, r15
    mov     rsi, r12
    mov     rdx, r14
    call    fb_set
    inc     r15
    jmp     .dh_loop
.dh_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# draw_vline(rdi=x, rsi=y, rdx=len, rcx=color)
draw_vline:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    xor     r15, r15
.dv_loop:
    cmp     r15, r13
    jge     .dv_done
    mov     rdi, rbx
    mov     rsi, r12
    add     rsi, r15
    mov     rdx, r14
    call    fb_set
    inc     r15
    jmp     .dv_loop
.dv_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# count_lit -> rax = number of pixels with any non-zero RGB byte
count_lit:
    lea     rdi, [rip + fb_buf]
    xor     rax, rax              # n
    xor     rcx, rcx              # i
.cl_loop:
    cmp     rcx, FB_BYTES
    jge     .cl_done
    movzx   r8, byte ptr [rdi + rcx]
    movzx   r9, byte ptr [rdi + rcx + 1]
    movzx   r10, byte ptr [rdi + rcx + 2]
    mov     r11, r8
    or      r11, r9
    or      r11, r10
    test    r11, r11
    jz      .cl_next
    inc     rax
.cl_next:
    add     rcx, FB_BPP
    jmp     .cl_loop
.cl_done:
    ret

fail_exit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

# assert_eq(rdi=got, rsi=want) — fail-exit if got != want
assert_eq:
    cmp     rdi, rsi
    jne     fail_exit
    ret

_start:
    # 1. clear → 0 lit
    call    fb_clear
    call    count_lit
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 2. red at (5, 7); BGRA byte check
    mov     rdi, 5
    mov     rsi, 7
    mov     rdx, 0xFF0000
    call    fb_set
    # offset = (7*16 + 5) * 4 = 468
    lea     rax, [rip + fb_buf]
    movzx   rdi, byte ptr [rax + 468]
    mov     rsi, 0
    call    assert_eq
    movzx   rdi, byte ptr [rax + 469]
    mov     rsi, 0
    call    assert_eq
    movzx   rdi, byte ptr [rax + 470]
    mov     rsi, 255
    call    assert_eq
    movzx   rdi, byte ptr [rax + 471]
    mov     rsi, 255
    call    assert_eq

    # 3. fb_get(5, 7) == 0xFF0000
    mov     rdi, 5
    mov     rsi, 7
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0xFF0000
    call    assert_eq

    # 4. OOB writes don't change count
    call    count_lit
    mov     r12, rax              # before
    mov     rdi, -1
    mov     rsi, 5
    mov     rdx, 0x00FF00
    call    fb_set
    mov     rdi, FB_W
    mov     rsi, 5
    mov     rdx, 0x00FF00
    call    fb_set
    mov     rdi, 5
    mov     rsi, -1
    mov     rdx, 0x00FF00
    call    fb_set
    mov     rdi, 5
    mov     rsi, FB_H
    mov     rdx, 0x00FF00
    call    fb_set
    call    count_lit
    mov     rdi, rax
    mov     rsi, r12
    call    assert_eq

    # 5. fb_set return value
    mov     rdi, 3
    mov     rsi, 3
    mov     rdx, 0x0000FF
    call    fb_set
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, -5
    mov     rsi, 3
    mov     rdx, 0x0000FF
    call    fb_set
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 6. hline
    call    fb_clear
    mov     rdi, 2
    mov     rsi, 8
    mov     rdx, 4
    mov     rcx, 0x00FF00
    call    draw_hline
    call    count_lit
    mov     rdi, rax
    mov     rsi, 4
    call    assert_eq
    mov     rdi, 2
    mov     rsi, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0x00FF00
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0x00FF00
    call    assert_eq
    mov     rdi, 6
    mov     rsi, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 7. vline
    call    fb_clear
    mov     rdi, 7
    mov     rsi, 2
    mov     rdx, 4
    mov     rcx, 0x0000FF
    call    draw_vline
    call    count_lit
    mov     rdi, rax
    mov     rsi, 4
    call    assert_eq
    mov     rdi, 7
    mov     rsi, 2
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0x0000FF
    call    assert_eq
    mov     rdi, 7
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0x0000FF
    call    assert_eq
    mov     rdi, 7
    mov     rsi, 6
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 8. hline clipped
    call    fb_clear
    mov     rdi, 14
    mov     rsi, 5
    mov     rdx, 4
    mov     rcx, 0xFF0000
    call    draw_hline
    call    count_lit
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    # success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
