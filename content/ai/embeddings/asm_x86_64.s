# Vidya — Embeddings and Vector Search — x86_64 Assembly. Q15 fixed-point.
#
# Focused subset: dot product + brute-force nearest. Top-k filter
# (mark/scan/zero pattern) lives in cyrius.cyr — too verbose for asm.

.intel_syntax noprefix
.global _start

.equ SCALE,    15
.equ ONE,      32768
.equ DIM,      4
.equ N_CORPUS, 4

.section .data
.align 8
# Corpus: 4 vectors × 4 dims = 16 i64, row-major.
corpus:
    .quad 32767, 0, 0, 0                         # v0: x-axis
    .quad 0, 32767, 0, 0                         # v1: y-axis
    .quad 16384, 16384, 16384, 16384             # v2: diagonal
    .quad -32767, 0, 0, 0                        # v3: -x-axis

.section .bss
.align 8
query_buf: .skip 32       # 4 i64

.section .rodata
msg_pass: .ascii "embeddings: 9/9 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# q_mul(rdi=a, rsi=b) -> rax = (a*b) >> SCALE (arithmetic)
q_mul:
    mov     rax, rdi
    imul    rax, rsi
    sar     rax, SCALE
    ret

# dot(rdi=a_ptr, rsi=b_ptr, rdx=n) -> rax (Q15 sum)
dot:
    push    r12
    push    r13
    push    r14
    push    rbx
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx              # n
    xor     rbx, rbx              # acc
    xor     rcx, rcx              # i
.dot_loop:
    cmp     rcx, r14
    jge     .dot_done
    mov     rdi, [r12 + rcx*8]
    mov     rsi, [r13 + rcx*8]
    push    rcx
    call    q_mul
    pop     rcx
    add     rbx, rax
    inc     rcx
    jmp     .dot_loop
.dot_done:
    mov     rax, rbx
    pop     rbx
    pop     r14
    pop     r13
    pop     r12
    ret

# corpus_sim(rdi=query_ptr, rsi=corpus_idx) -> rax = similarity
corpus_sim:
    push    r12
    mov     r12, rdi              # save query
    # Compute corpus row pointer: corpus + idx * DIM * 8
    mov     rax, rsi
    shl     rax, 5                # idx * 32 (DIM=4 × 8 bytes)
    lea     r8, [rip + corpus]
    add     rax, r8
    # Now call dot(query, corpus_row, DIM)
    mov     rdi, r12
    mov     rsi, rax
    mov     rdx, DIM
    call    dot
    pop     r12
    ret

# nearest(rdi=query_ptr) -> rax = corpus index
nearest:
    push    r12
    push    r13
    push    rbx
    mov     r12, rdi              # query
    # Initialize best with idx 0
    mov     rdi, r12
    mov     rsi, 0
    call    corpus_sim
    mov     rbx, rax              # best_sim
    xor     r13, r13              # best_idx
    mov     rcx, 1
.near_loop:
    cmp     rcx, N_CORPUS
    jge     .near_done
    mov     rdi, r12
    mov     rsi, rcx
    push    rcx
    call    corpus_sim
    pop     rcx
    cmp     rax, rbx
    jle     .near_skip
    mov     rbx, rax
    mov     r13, rcx
.near_skip:
    inc     rcx
    jmp     .near_loop
.near_done:
    mov     rax, r13
    pop     rbx
    pop     r13
    pop     r12
    ret

assert_eq:
    cmp     rdi, rsi
    jne     .ae_fail
    ret

assert_between:
    cmp     rdi, rsi
    jl      .ae_fail
    cmp     rdi, rdx
    jg      .ae_fail
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
    # self-sim of v0: dot(v0, v0) ≈ ONE
    lea     rdi, [rip + corpus]
    mov     rsi, 0
    call    corpus_sim
    mov     rdi, rax
    mov     rsi, 32760
    mov     rdx, 32768
    call    assert_between

    # orthogonal: dot(v0, v1) = 0
    lea     rdi, [rip + corpus]
    mov     rsi, 1
    call    corpus_sim
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # opposite: dot(v0, v3) ≈ -ONE
    lea     rdi, [rip + corpus]
    mov     rsi, 3
    call    corpus_sim
    mov     rdi, rax
    mov     rsi, -32768
    mov     rdx, -32760
    call    assert_between

    # diagonal self-sim: dot(v2, v2) = ONE
    lea     rdi, [rip + corpus + 64]    # v2 at offset 2*32 = 64
    mov     rsi, 2
    call    corpus_sim
    mov     rdi, rax
    mov     rsi, ONE
    call    assert_eq

    # nearest(query=[0.9, 0, 0, 0]) → 0
    lea     r8, [rip + query_buf]
    mov     qword ptr [r8 + 0],  29490
    mov     qword ptr [r8 + 8],  0
    mov     qword ptr [r8 + 16], 0
    mov     qword ptr [r8 + 24], 0
    lea     rdi, [rip + query_buf]
    call    nearest
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # nearest(query=[0, 1, 0, 0]) → 1
    lea     r8, [rip + query_buf]
    mov     qword ptr [r8 + 0],  0
    mov     qword ptr [r8 + 8],  32767
    mov     qword ptr [r8 + 16], 0
    mov     qword ptr [r8 + 24], 0
    lea     rdi, [rip + query_buf]
    call    nearest
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # nearest(query=[0.5, 0.5, 0.5, 0.5]) → 2
    lea     r8, [rip + query_buf]
    mov     qword ptr [r8 + 0],  16384
    mov     qword ptr [r8 + 8],  16384
    mov     qword ptr [r8 + 16], 16384
    mov     qword ptr [r8 + 24], 16384
    lea     rdi, [rip + query_buf]
    call    nearest
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    # nearest(query=[-0.9, 0, 0, 0]) → 3
    lea     r8, [rip + query_buf]
    mov     qword ptr [r8 + 0],  -29490
    mov     qword ptr [r8 + 8],  0
    mov     qword ptr [r8 + 16], 0
    mov     qword ptr [r8 + 24], 0
    lea     rdi, [rip + query_buf]
    call    nearest
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # determinism: nearest twice → same answer
    lea     r8, [rip + query_buf]
    mov     qword ptr [r8 + 0],  29490
    mov     qword ptr [r8 + 8],  0
    mov     qword ptr [r8 + 16], 0
    mov     qword ptr [r8 + 24], 0
    lea     rdi, [rip + query_buf]
    call    nearest
    push    rax
    lea     rdi, [rip + query_buf]
    call    nearest
    pop     rdi
    mov     rsi, rax
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
