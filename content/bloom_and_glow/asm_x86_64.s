# Vidya — Bloom and Glow in x86_64 Assembly
#
# 1-pixel additive bloom on 16x16 single-channel intensity buffer.
# src + dst .bss arenas. apply_bloom: copy src→dst, then for each
# pixel >= THRESHOLD add (v / GLOW_FRAC) to its 4 cardinal neighbors
# in dst with per-pixel saturation clamp at 255.

.intel_syntax noprefix
.global _start

.equ FB_W,        16
.equ FB_H,        16
.equ FB_BYTES,    256
.equ THRESHOLD,   128
.equ GLOW_FRAC,   2

.section .bss
.align 8
src_buf:      .skip FB_BYTES
dst_buf:      .skip FB_BYTES

.section .rodata
msg_pass:     .ascii "bloom_and_glow: 20/20 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# fb_clear(rdi=fb)
fb_clear:
    mov     rcx, FB_BYTES / 8
    xor     rax, rax
.fc_loop:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .fc_loop
    ret

# fb_set(rdi=fb, rsi=x, rdx=y, rcx=val)
fb_set:
    test    rsi, rsi
    js      .fs_done
    cmp     rsi, FB_W
    jge     .fs_done
    test    rdx, rdx
    js      .fs_done
    cmp     rdx, FB_H
    jge     .fs_done
    mov     rax, rdx
    shl     rax, 4         # y * 16
    add     rax, rsi
    mov     [rdi + rax], cl
.fs_done:
    ret

# fb_get(rdi=fb, rsi=x, rdx=y) -> rax
fb_get:
    test    rsi, rsi
    js      .fg_zero
    cmp     rsi, FB_W
    jge     .fg_zero
    test    rdx, rdx
    js      .fg_zero
    cmp     rdx, FB_H
    jge     .fg_zero
    mov     rax, rdx
    shl     rax, 4         # y * 16
    add     rax, rsi
    movzx   rax, byte ptr [rdi + rax]
    ret
.fg_zero:
    xor     rax, rax
    ret

# fb_add(rdi=fb, rsi=x, rdx=y, rcx=delta) — saturation clamp at 255
fb_add:
    test    rsi, rsi
    js      .fa_done
    cmp     rsi, FB_W
    jge     .fa_done
    test    rdx, rdx
    js      .fa_done
    cmp     rdx, FB_H
    jge     .fa_done
    mov     rax, rdx
    shl     rax, 4         # y * 16
    add     rax, rsi
    movzx   r8, byte ptr [rdi + rax]
    add     r8, rcx
    cmp     r8, 255
    jbe     .fa_store
    mov     r8, 255
.fa_store:
    mov     [rdi + rax], r8b
.fa_done:
    ret

# count_lit(rdi=fb) -> rax
count_lit:
    xor     rax, rax
    xor     rcx, rcx
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

# apply_bloom(rdi=src, rsi=dst, rdx=threshold)
# Loop state cached in callee-saved across fb_add: r12=src, r13=dst,
# r14=threshold, r15=y, rbx=x.
apply_bloom:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    # Copy src -> dst
    xor     rcx, rcx
.ab_copy:
    cmp     rcx, FB_BYTES
    jge     .ab_y_init
    mov     al, [r12 + rcx]
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .ab_copy
.ab_y_init:
    xor     r15, r15
.ab_y_loop:
    cmp     r15, FB_H
    jge     .ab_done
    xor     rbx, rbx
.ab_x_loop:
    cmp     rbx, FB_W
    jge     .ab_y_next
    # v = src[y * FB_W + x]
    mov     rax, r15
    shl     rax, 4         # y * 16
    add     rax, rbx
    movzx   rdx, byte ptr [r12 + rax]
    cmp     rdx, r14
    jl      .ab_x_next
    # glow = v / GLOW_FRAC
    shr     rdx, 1                # GLOW_FRAC = 2 → shr 1
    # Add to 4 neighbors
    mov     rdi, r13
    mov     rsi, rbx
    dec     rsi                   # x - 1
    mov     rbp, rdx              # save glow in callee-saved (fb_add clobbers r8)
    mov     rdx, r15
    mov     rcx, rbp
    call    fb_add
    mov     rdi, r13
    mov     rsi, rbx
    inc     rsi                   # x + 1
    mov     rdx, r15
    mov     rcx, rbp
    call    fb_add
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, r15
    dec     rdx                   # y - 1
    mov     rcx, rbp
    call    fb_add
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, r15
    inc     rdx                   # y + 1
    mov     rcx, rbp
    call    fb_add
.ab_x_next:
    inc     rbx
    jmp     .ab_x_loop
.ab_y_next:
    inc     r15
    jmp     .ab_y_loop
.ab_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
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

_start:
    # Test 1: empty
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + dst_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    lea     rdi, [rip + dst_buf]
    call    count_lit
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # Test 2: single bright at center (8, 8)
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    mov     rsi, 8
    mov     rdx, 8
    mov     rcx, 200
    call    fb_set
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    # src(8,8)=200
    lea     rdi, [rip + dst_buf]
    mov     rsi, 8
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 200
    call    assert_eq
    # neighbors = 100
    lea     rdi, [rip + dst_buf]
    mov     rsi, 7
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 9
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 8
    mov     rdx, 7
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 8
    mov     rdx, 9
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    # diagonal untouched
    lea     rdi, [rip + dst_buf]
    mov     rsi, 7
    mov     rdx, 7
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    # count = 5
    lea     rdi, [rip + dst_buf]
    call    count_lit
    mov     rdi, rax
    mov     rsi, 5
    call    assert_eq

    # Test 3: saturation clamp
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    mov     rsi, 8
    mov     rdx, 8
    mov     rcx, 200
    call    fb_set
    lea     rdi, [rip + src_buf]
    mov     rsi, 9
    mov     rdx, 8
    mov     rcx, 250
    call    fb_set
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    lea     rdi, [rip + dst_buf]
    mov     rsi, 9
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 255
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 8
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 255
    call    assert_eq

    # Test 4: dim pixel below threshold
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    mov     rsi, 8
    mov     rdx, 8
    mov     rcx, 100
    call    fb_set
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    lea     rdi, [rip + dst_buf]
    mov     rsi, 8
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 7
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    call    count_lit
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 5: corner pixel
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    mov     rsi, 0
    mov     rdx, 0
    mov     rcx, 200
    call    fb_set
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    lea     rdi, [rip + dst_buf]
    mov     rsi, 0
    mov     rdx, 0
    call    fb_get
    mov     rdi, rax
    mov     rsi, 200
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 1
    mov     rdx, 0
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 0
    mov     rdx, 1
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    call    count_lit
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # Test 6: two adjacent bright pixels — sums at midpoint
    lea     rdi, [rip + src_buf]
    call    fb_clear
    lea     rdi, [rip + src_buf]
    mov     rsi, 4
    mov     rdx, 8
    mov     rcx, 200
    call    fb_set
    lea     rdi, [rip + src_buf]
    mov     rsi, 6
    mov     rdx, 8
    mov     rcx, 200
    call    fb_set
    lea     rdi, [rip + src_buf]
    lea     rsi, [rip + dst_buf]
    mov     rdx, THRESHOLD
    call    apply_bloom
    lea     rdi, [rip + dst_buf]
    mov     rsi, 5
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 200
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 3
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    lea     rdi, [rip + dst_buf]
    mov     rsi, 7
    mov     rdx, 8
    call    fb_get
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
