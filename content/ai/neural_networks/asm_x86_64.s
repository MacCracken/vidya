# Vidya — Neural Network Forward Pass — x86_64 Assembly. Q15 fixed-point.
#
# Tiny 2 → 3 → 2 MLP. Same hand-designed weights as cyrius.cyr.
# Hardcoded layer sizes (avoids parametric loops in asm).

.intel_syntax noprefix
.global _start

.equ SCALE, 15
.equ ONE,   32768

.section .data
.align 8
# Hidden weights: 3 rows × 2 cols (row-major)
W_hidden:
    .quad 16384, -16384       # row 0: 0.5*x[0] - 0.5*x[1]
    .quad -16384, 16384       # row 1: -0.5*x[0] + 0.5*x[1]
    .quad 16384, 16384        # row 2: 0.5*x[0] + 0.5*x[1]

# Hidden biases (3)
b_hidden:
    .quad 0, 0, 0

# Output weights: 2 rows × 3 cols
W_output:
    .quad 16384, 0, 0         # logit[0] = 0.5 * h[0]
    .quad 0, 16384, 0         # logit[1] = 0.5 * h[1]

# Output biases (2)
b_output:
    .quad 0, 0

.section .bss
.align 8
input_buf:  .skip 16          # 2 i64
hidden_buf: .skip 24          # 3 i64
output_buf: .skip 16          # 2 i64

.section .rodata
msg_pass: .ascii "neural_networks: 8/8 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# q_mul(rdi=a, rsi=b) -> rax (sign-handled arithmetic shift)
q_mul:
    mov     rax, rdi
    imul    rax, rsi
    sar     rax, SCALE
    ret

# dense_2_to_3: input_buf → hidden_buf using W_hidden + b_hidden
dense_2_to_3:
    push    r12
    push    r13
    push    rbx
    xor     r12, r12              # j (output index)
.d23_outer:
    cmp     r12, 3
    jge     .d23_done
    lea     r8, [rip + b_hidden]
    mov     rbx, [r8 + r12*8]     # acc = b[j]
    xor     r13, r13              # i (input index)
.d23_inner:
    cmp     r13, 2
    jge     .d23_store
    # offset into W = j*2 + i
    mov     rax, r12
    shl     rax, 1                # j*2
    add     rax, r13
    lea     r8, [rip + W_hidden]
    mov     rdi, [r8 + rax*8]
    lea     r8, [rip + input_buf]
    mov     rsi, [r8 + r13*8]
    push    r12
    push    r13
    call    q_mul
    pop     r13
    pop     r12
    add     rbx, rax
    inc     r13
    jmp     .d23_inner
.d23_store:
    lea     r8, [rip + hidden_buf]
    mov     [r8 + r12*8], rbx
    inc     r12
    jmp     .d23_outer
.d23_done:
    pop     rbx
    pop     r13
    pop     r12
    ret

# dense_3_to_2: hidden_buf → output_buf using W_output + b_output
dense_3_to_2:
    push    r12
    push    r13
    push    rbx
    xor     r12, r12
.d32_outer:
    cmp     r12, 2
    jge     .d32_done
    lea     r8, [rip + b_output]
    mov     rbx, [r8 + r12*8]
    xor     r13, r13
.d32_inner:
    cmp     r13, 3
    jge     .d32_store
    mov     rax, r12
    imul    rax, 3
    add     rax, r13
    lea     r8, [rip + W_output]
    mov     rdi, [r8 + rax*8]
    lea     r8, [rip + hidden_buf]
    mov     rsi, [r8 + r13*8]
    push    r12
    push    r13
    call    q_mul
    pop     r13
    pop     r12
    add     rbx, rax
    inc     r13
    jmp     .d32_inner
.d32_store:
    lea     r8, [rip + output_buf]
    mov     [r8 + r12*8], rbx
    inc     r12
    jmp     .d32_outer
.d32_done:
    pop     rbx
    pop     r13
    pop     r12
    ret

# relu_hidden: in-place max(0, x) on hidden_buf (3 elements)
relu_hidden:
    xor     rcx, rcx
.rh_loop:
    cmp     rcx, 3
    jge     .rh_done
    lea     r8, [rip + hidden_buf]
    mov     rax, [r8 + rcx*8]
    test    rax, rax
    jns     .rh_skip
    mov     qword ptr [r8 + rcx*8], 0
.rh_skip:
    inc     rcx
    jmp     .rh_loop
.rh_done:
    ret

# argmax_output: returns rax = index of max in output_buf (2 elements)
argmax_output:
    lea     r8, [rip + output_buf]
    mov     rax, [r8 + 0]
    mov     rcx, [r8 + 8]
    cmp     rcx, rax
    jle     .am_zero
    mov     rax, 1
    ret
.am_zero:
    xor     rax, rax
    ret

# forward: input_buf → predicted class (rax)
forward:
    push    r12
    call    dense_2_to_3
    call    relu_hidden
    call    dense_3_to_2
    call    argmax_output
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

_start:
    # q_mul sanity
    mov     rdi, ONE
    mov     rsi, 100
    call    q_mul
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq

    mov     rdi, 16384
    mov     rsi, 16384
    call    q_mul
    mov     rdi, rax
    mov     rsi, 8192
    call    assert_eq

    mov     rdi, -16384
    mov     rsi, 16384
    call    q_mul
    mov     rdi, rax
    mov     rsi, -8192
    call    assert_eq

    # forward x=[0.8, 0.2] → class 0
    lea     r8, [rip + input_buf]
    mov     qword ptr [r8 + 0], 26214
    mov     qword ptr [r8 + 8], 6553
    call    forward
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # forward x=[0.2, 0.8] → class 1
    lea     r8, [rip + input_buf]
    mov     qword ptr [r8 + 0], 6553
    mov     qword ptr [r8 + 8], 26214
    call    forward
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # forward x=[1.0, 0.0] → class 0
    lea     r8, [rip + input_buf]
    mov     qword ptr [r8 + 0], 32767
    mov     qword ptr [r8 + 8], 0
    call    forward
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # forward x=[0.0, 1.0] → class 1
    lea     r8, [rip + input_buf]
    mov     qword ptr [r8 + 0], 0
    mov     qword ptr [r8 + 8], 32767
    call    forward
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # ReLU actually fires: after [1.0, 0.0], hidden[1] should be 0
    lea     r8, [rip + input_buf]
    mov     qword ptr [r8 + 0], 32767
    mov     qword ptr [r8 + 8], 0
    call    forward
    lea     r8, [rip + hidden_buf]
    mov     rdi, [r8 + 8]
    mov     rsi, 0
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
