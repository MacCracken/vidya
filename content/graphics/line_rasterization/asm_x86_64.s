# Vidya — Line Rasterization (Bresenham) in x86_64 Assembly
#
# All-octant integer Bresenham on a 16x16 byte framebuffer. Pure asm
# implementation of the algorithm; loop state lives in callee-saved
# r12-r15 across the fb_set call inside the iteration.

.intel_syntax noprefix
.global _start

.equ FB_W,     16
.equ FB_H,     16
.equ FB_BYTES, 256

.section .bss
.align 8
fb_buf:       .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "line_rasterization: 27/27 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

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

# fb_set(rdi=x, rsi=y, rdx=val)
fb_set:
    test    rdi, rdi
    js      .fs_done
    cmp     rdi, FB_W
    jge     .fs_done
    test    rsi, rsi
    js      .fs_done
    cmp     rsi, FB_H
    jge     .fs_done
    mov     rax, rsi
    imul    rax, FB_W
    add     rax, rdi
    lea     rcx, [rip + fb_buf]
    mov     [rcx + rax], dl
.fs_done:
    ret

# fb_get(rdi=x, rsi=y) -> rax
fb_get:
    test    rdi, rdi
    js      .fg_zero
    cmp     rdi, FB_W
    jge     .fg_zero
    test    rsi, rsi
    js      .fg_zero
    cmp     rsi, FB_H
    jge     .fg_zero
    mov     rax, rsi
    imul    rax, FB_W
    add     rax, rdi
    lea     rcx, [rip + fb_buf]
    movzx   rax, byte ptr [rcx + rax]
    ret
.fg_zero:
    xor     rax, rax
    ret

count_lit:
    lea     rdi, [rip + fb_buf]
    xor     rax, rax              # n
    xor     rcx, rcx              # i
.cl_loop:
    cmp     rcx, FB_BYTES
    jge     .cl_done
    movzx   rdx, byte ptr [rdi + rcx]
    test    rdx, rdx
    jz      .cl_next
    inc     rax
.cl_next:
    inc     rcx
    jmp     .cl_loop
.cl_done:
    ret

# iabs(rdi) -> rax
iabs:
    mov     rax, rdi
    test    rax, rax
    jns     .ia_done
    neg     rax
.ia_done:
    ret

# sign(rdi) -> rax  (-1, 0, or 1)
sign:
    xor     rax, rax
    test    rdi, rdi
    jz      .sg_done
    js      .sg_neg
    mov     rax, 1
    ret
.sg_neg:
    mov     rax, -1
.sg_done:
    ret

# draw_line(rdi=x0, rsi=y0, rdx=x1, rcx=y1, r8=val)
# r12 = sx, r13 = sy, r14 = dx, r15 = dy
# rbx = err, [rsp+8] = x, [rsp] = y, [rsp+16] = x1, [rsp+24] = y1, [rsp+32] = val, [rsp+40] = pad
draw_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 48               # locals: x, y, x1, y1, val (+8 pad for align)

    mov     [rsp + 8], rdi        # x = x0
    mov     [rsp], rsi            # y = y0
    mov     [rsp + 16], rdx       # x1
    mov     [rsp + 24], rcx       # y1
    mov     [rsp + 32], r8        # val

    # dx = iabs(x1 - x0)
    mov     rdi, rdx
    sub     rdi, [rsp + 8]
    call    iabs
    mov     r14, rax              # dx
    # dy = iabs(y1 - y0)
    mov     rdi, [rsp + 24]
    sub     rdi, [rsp]
    call    iabs
    mov     r15, rax              # dy
    # sx = sign(x1 - x0)
    mov     rdi, [rsp + 16]
    sub     rdi, [rsp + 8]
    call    sign
    mov     r12, rax              # sx
    # sy = sign(y1 - y0)
    mov     rdi, [rsp + 24]
    sub     rdi, [rsp]
    call    sign
    mov     r13, rax              # sy
    # err = dx - dy
    mov     rbx, r14
    sub     rbx, r15

.dl_loop:
    # fb_set(x, y, val)
    mov     rdi, [rsp + 8]
    mov     rsi, [rsp]
    mov     rdx, [rsp + 32]
    call    fb_set
    # if x == x1 && y == y1: return
    mov     rax, [rsp + 8]
    cmp     rax, [rsp + 16]
    jne     .dl_step
    mov     rax, [rsp]
    cmp     rax, [rsp + 24]
    je      .dl_done
.dl_step:
    # e2 = err * 2
    mov     rdx, rbx
    shl     rdx, 1                # e2
    # if e2 > -dy: err -= dy; x += sx
    mov     rax, r15
    neg     rax
    cmp     rdx, rax
    jle     .dl_check_y
    sub     rbx, r15
    mov     rax, [rsp + 8]
    add     rax, r12
    mov     [rsp + 8], rax
.dl_check_y:
    # if e2 < dx: err += dx; y += sy
    cmp     rdx, r14
    jge     .dl_loop
    add     rbx, r14
    mov     rax, [rsp]
    add     rax, r13
    mov     [rsp], rax
    jmp     .dl_loop
.dl_done:
    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# assert_eq(rdi, rsi)
assert_eq:
    cmp     rdi, rsi
    jne     fail_exit
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

# Test runner — calls draw_line then verifies expected pixels
# Each test follows: fb_clear → draw_line → count_lit check → fb_get checks

_start:
    # 1: horizontal (2,5)-(8,5), expect 7 lit
    call    fb_clear
    mov     rdi, 2
    mov     rsi, 5
    mov     rdx, 8
    mov     rcx, 5
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 7
    call    assert_eq
    mov     rdi, 2
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 8
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 6
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 2: vertical (5,2)-(5,8)
    call    fb_clear
    mov     rdi, 5
    mov     rsi, 2
    mov     rdx, 5
    mov     rcx, 8
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 7
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 2
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 6
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 3: +diagonal (2,2)-(7,7)
    call    fb_clear
    mov     rdi, 2
    mov     rsi, 2
    mov     rdx, 7
    mov     rcx, 7
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 6
    call    assert_eq
    mov     rdi, 2
    mov     rsi, 2
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 7
    mov     rsi, 7
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 4
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 4: -diagonal (2,7)-(7,2)
    call    fb_clear
    mov     rdi, 2
    mov     rsi, 7
    mov     rdx, 7
    mov     rcx, 2
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 6
    call    assert_eq
    mov     rdi, 2
    mov     rsi, 7
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 7
    mov     rsi, 2
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 4
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 5: steep (3,1)-(5,11)
    call    fb_clear
    mov     rdi, 3
    mov     rsi, 1
    mov     rdx, 5
    mov     rcx, 11
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 11
    call    assert_eq
    mov     rdi, 3
    mov     rsi, 1
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 11
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 6: single point (8,8)-(8,8)
    call    fb_clear
    mov     rdi, 8
    mov     rsi, 8
    mov     rdx, 8
    mov     rcx, 8
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 8
    mov     rsi, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 7: reversed (8,5)-(2,5)
    call    fb_clear
    mov     rdi, 8
    mov     rsi, 5
    mov     rdx, 2
    mov     rcx, 5
    mov     r8, 1
    call    draw_line
    call    count_lit
    mov     rdi, rax
    mov     rsi, 7
    call    assert_eq
    mov     rdi, 2
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 8
    mov     rsi, 5
    call    fb_get
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
