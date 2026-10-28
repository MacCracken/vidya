# Vidya — Audio DSP — x86_64 Assembly. Q15 fixed-point.
#
# Focused subset: q_mul, clip, biquad lowpass DC test + Nyquist
# attenuation test, peak, mean-absolute. FIR convolution lives in
# cyrius.cyr — variable-size kernels are too verbose for asm.

.intel_syntax noprefix
.global _start

.equ SCALE, 15
.equ ONE,   32768
.equ SMAX,  32767
# SMIN = -32767 inlined as -32767 in mov instructions

.section .bss
.align 8
bq_b0: .skip 8
bq_b1: .skip 8
bq_b2: .skip 8
bq_a1: .skip 8
bq_a2: .skip 8
bq_x1: .skip 8
bq_x2: .skip 8
bq_y1: .skip 8
bq_y2: .skip 8
sample_buf: .skip 64

.section .rodata
msg_pass: .ascii "audio_dsp: 10/10 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# q_mul(rdi=a, rsi=b) -> rax = (a*b) >> SCALE with sign handling
q_mul:
    mov     rax, rdi
    imul    rax, rsi              # rax = a*b (signed)
    sar     rax, SCALE            # arithmetic shift right (preserves sign)
    ret

# abs_i(rdi) -> rax
abs_i:
    mov     rax, rdi
    test    rax, rax
    jns     .ai_done
    neg     rax
.ai_done:
    ret

# clip(rdi=s) -> rax
clip:
    mov     rax, rdi
    cmp     rax, SMAX
    jle     .cl_lo
    mov     rax, SMAX
    ret
.cl_lo:
    cmp     rax, -32767
    jge     .cl_done
    mov     rax, -32767
.cl_done:
    ret

# biquad_set(rdi=b0,rsi=b1,rdx=b2,rcx=a1,r8=a2)
biquad_set:
    mov     [rip + bq_b0], rdi
    mov     [rip + bq_b1], rsi
    mov     [rip + bq_b2], rdx
    mov     [rip + bq_a1], rcx
    mov     [rip + bq_a2], r8
    mov     qword ptr [rip + bq_x1], 0
    mov     qword ptr [rip + bq_x2], 0
    mov     qword ptr [rip + bq_y1], 0
    mov     qword ptr [rip + bq_y2], 0
    ret

# biquad_lowpass_1pole(rdi=a_q15)
biquad_lowpass_1pole:
    mov     rax, rdi
    sub     rax, ONE              # a1 = a_q15 - ONE
    mov     rcx, rax              # rcx = a1
    xor     rsi, rsi              # b1 = 0
    xor     rdx, rdx              # b2 = 0
    xor     r8, r8                # a2 = 0
    call    biquad_set
    ret

# biquad_step(rdi=x) -> rax
biquad_step:
    push    r12
    push    r13
    push    r14
    push    rbx
    mov     r12, rdi              # save x
    # acc = q_mul(b0, x)
    mov     rdi, [rip + bq_b0]
    mov     rsi, r12
    call    q_mul
    mov     rbx, rax              # rbx = acc
    # acc += q_mul(b1, x1)
    mov     rdi, [rip + bq_b1]
    mov     rsi, [rip + bq_x1]
    call    q_mul
    add     rbx, rax
    # acc += q_mul(b2, x2)
    mov     rdi, [rip + bq_b2]
    mov     rsi, [rip + bq_x2]
    call    q_mul
    add     rbx, rax
    # acc -= q_mul(a1, y1)
    mov     rdi, [rip + bq_a1]
    mov     rsi, [rip + bq_y1]
    call    q_mul
    sub     rbx, rax
    # acc -= q_mul(a2, y2)
    mov     rdi, [rip + bq_a2]
    mov     rsi, [rip + bq_y2]
    call    q_mul
    sub     rbx, rax
    # state shift
    mov     r13, [rip + bq_x1]
    mov     [rip + bq_x2], r13
    mov     [rip + bq_x1], r12
    mov     r13, [rip + bq_y1]
    mov     [rip + bq_y2], r13
    mov     [rip + bq_y1], rbx
    mov     rax, rbx
    pop     rbx
    pop     r14
    pop     r13
    pop     r12
    ret

# peak(rdi=buf, rsi=n) -> rax
peak:
    push    r12
    push    r13
    push    rbx
    xor     rax, rax              # p
    xor     rcx, rcx              # i
.pk_loop:
    cmp     rcx, rsi
    jge     .pk_done
    mov     r12, [rdi + rcx*8]
    push    rdi
    push    rsi
    push    rcx
    mov     rdi, r12
    push    rax                   # save p
    call    abs_i
    mov     rbx, rax              # |s|
    pop     rax                   # restore p
    pop     rcx
    pop     rsi
    pop     rdi
    cmp     rbx, rax
    jle     .pk_skip
    mov     rax, rbx
.pk_skip:
    inc     rcx
    jmp     .pk_loop
.pk_done:
    pop     rbx
    pop     r13
    pop     r12
    ret

# mean_absolute(rdi=buf, rsi=n) -> rax
mean_absolute:
    push    r12
    push    rbx
    xor     rbx, rbx              # sum
    mov     r12, rsi              # save n
    xor     rcx, rcx              # i
.ma_loop:
    cmp     rcx, rsi
    jge     .ma_done
    push    rdi
    push    rsi
    push    rcx
    mov     r8, [rdi + rcx*8]
    mov     rdi, r8
    call    abs_i
    pop     rcx
    pop     rsi
    pop     rdi
    add     rbx, rax
    inc     rcx
    jmp     .ma_loop
.ma_done:
    mov     rax, rbx
    cqo
    idiv    r12
    pop     rbx
    pop     r12
    ret

assert_eq:
    cmp     rdi, rsi
    jne     .ae_fail
    ret
.ae_fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

# assert_between(rdi=val, rsi=lo, rdx=hi)
assert_between:
    cmp     rdi, rsi
    jl      .ae_fail
    cmp     rdi, rdx
    jg      .ae_fail
    ret

_start:
    # q_mul tests
    mov     rdi, ONE
    mov     rsi, 100
    call    q_mul
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    mov     rdi, ONE / 2
    mov     rsi, ONE / 2
    call    q_mul
    mov     rdi, rax
    mov     rsi, ONE / 4
    call    assert_eq

    # clip tests
    mov     rdi, 50000
    call    clip
    mov     rdi, rax
    mov     rsi, SMAX
    call    assert_eq
    mov     rdi, -50000
    call    clip
    mov     rdi, rax
    mov     rsi, -32767
    call    assert_eq
    mov     rdi, 1234
    call    clip
    mov     rdi, rax
    mov     rsi, 1234
    call    assert_eq

    # Biquad lowpass DC test
    mov     rdi, 3277
    call    biquad_lowpass_1pole
    mov     rcx, 200
.bq_dc:
    push    rcx
    mov     rdi, 30000
    call    biquad_step
    pop     rcx
    dec     rcx
    jnz     .bq_dc
    mov     rdi, [rip + bq_y1]
    mov     rsi, 29900
    mov     rdx, 30100
    call    assert_between

    # Biquad lowpass Nyquist attenuation
    mov     rdi, 3277
    call    biquad_lowpass_1pole
    mov     rcx, 200
    xor     r12, r12              # i
.bq_ny:
    push    rcx
    push    r12
    mov     rax, r12
    and     rax, 1
    cmp     rax, 0
    jne     .bq_ny_neg
    mov     rdi, 20000
    jmp     .bq_ny_step
.bq_ny_neg:
    mov     rdi, -20000
.bq_ny_step:
    call    biquad_step
    pop     r12
    pop     rcx
    inc     r12
    dec     rcx
    jnz     .bq_ny
    mov     rdi, [rip + bq_y1]
    call    abs_i
    mov     rdi, rax
    mov     rsi, 0
    mov     rdx, 1999
    call    assert_between

    # peak test: [100, -5000, 200, 3000, -1500] → 5000
    mov     qword ptr [rip + sample_buf + 0],   100
    mov     qword ptr [rip + sample_buf + 8],  -5000
    mov     qword ptr [rip + sample_buf + 16],  200
    mov     qword ptr [rip + sample_buf + 24],  3000
    mov     qword ptr [rip + sample_buf + 32], -1500
    lea     rdi, [rip + sample_buf]
    mov     rsi, 5
    call    peak
    mov     rdi, rax
    mov     rsi, 5000
    call    assert_eq

    # mean_absolute: 8 × 4000 → 4000
    lea     r9, [rip + sample_buf]
    mov     rcx, 0
.ma_init1:
    cmp     rcx, 8
    jge     .ma_init1_done
    mov     qword ptr [r9 + rcx*8], 4000
    inc     rcx
    jmp     .ma_init1
.ma_init1_done:
    lea     rdi, [rip + sample_buf]
    mov     rsi, 8
    call    mean_absolute
    mov     rdi, rax
    mov     rsi, 4000
    call    assert_eq

    # mean_absolute: alternating ±4000 → 4000
    lea     r9, [rip + sample_buf]
    mov     rcx, 0
.ma_init2:
    cmp     rcx, 8
    jge     .ma_init2_done
    mov     rax, rcx
    and     rax, 1
    cmp     rax, 0
    jne     .ma_init2_neg
    mov     qword ptr [r9 + rcx*8], 4000
    jmp     .ma_init2_next
.ma_init2_neg:
    mov     qword ptr [r9 + rcx*8], -4000
.ma_init2_next:
    inc     rcx
    jmp     .ma_init2
.ma_init2_done:
    lea     rdi, [rip + sample_buf]
    mov     rsi, 8
    call    mean_absolute
    mov     rdi, rax
    mov     rsi, 4000
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
