# Vidya — LLM Inference (Decoding) — x86_64 Assembly.
#
# Focused subset: argmax + bigram lookup + autoregressive decode
# loop with EOS termination. Top-k filter (triple-nested loop)
# lives in cyrius.cyr — too verbose for asm.

.intel_syntax noprefix
.global _start

.equ VOCAB_SIZE, 8
.equ TOK_EOS,    1

.section .data
.align 8
# bigram[prev][next] — 64 i64 cells, row-major.
bigram:
    # row 0 (UNK):
    .quad 0, 0, 0, 0, 0, 0, 0, 0
    # row 1 (EOS):
    .quad 0, 0, 0, 0, 0, 0, 0, 0
    # row 2 (hello): predict world(3)=1000, foo(4)=100
    .quad 0, 0, 0, 1000, 100, 0, 0, 0
    # row 3 (world): predict the(6)=800, bar(5)=200
    .quad 0, 0, 0, 0, 0, 200, 800, 0
    # row 4 (foo): predict bar(5)=700
    .quad 0, 0, 0, 0, 0, 700, 0, 0
    # row 5 (bar): predict EOS(1)=600
    .quad 0, 600, 0, 0, 0, 0, 0, 0
    # row 6 (the): predict end(7)=900, world(3)=100
    .quad 0, 0, 0, 100, 0, 0, 0, 900
    # row 7 (end): predict EOS(1)=950
    .quad 0, 950, 0, 0, 0, 0, 0, 0

.section .bss
.align 8
output_buf: .skip 128         # 16 i64

.section .rodata
msg_pass: .ascii "inference: 9/9 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# argmax_logits(rdi=bigram_row_ptr, rsi=n_vocab) -> rax = idx
argmax_logits:
    xor     rax, rax              # best_idx = 0
    mov     rcx, [rdi]            # best_val = logits[0]
    mov     rdx, 1                # i = 1
.am_loop:
    cmp     rdx, rsi
    jge     .am_done
    mov     r8, [rdi + rdx*8]
    cmp     r8, rcx
    jle     .am_skip
    mov     rcx, r8
    mov     rax, rdx
.am_skip:
    inc     rdx
    jmp     .am_loop
.am_done:
    ret

# bigram_logits_ptr(rdi=prev_token) -> rax = pointer to bigram row
bigram_logits_ptr:
    mov     rax, rdi
    shl     rax, 3                # prev * 8 (row index in vocab units)
    shl     rax, 3                # × 8 bytes per i64 = prev * 64
    lea     r8, [rip + bigram]
    add     rax, r8
    ret

# decode_sequence(rdi=start_tok, rsi=output_ptr, rdx=max_len) -> rax = count
decode_sequence:
    push    r12
    push    r13
    push    r14
    push    rbx
    mov     r12, rdi              # current
    mov     r13, rsi              # output_ptr
    mov     r14, rdx              # max_len
    xor     rbx, rbx              # count
.ds_loop:
    cmp     rbx, r14
    jge     .ds_done
    mov     rdi, r12
    call    bigram_logits_ptr
    mov     rdi, rax              # row ptr
    mov     rsi, VOCAB_SIZE
    call    argmax_logits         # rax = next_tok
    mov     [r13 + rbx*8], rax
    inc     rbx
    cmp     rax, TOK_EOS
    je      .ds_done
    mov     r12, rax
    jmp     .ds_loop
.ds_done:
    mov     rax, rbx
    pop     rbx
    pop     r14
    pop     r13
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
    # argmax test: bigram row for "hello" (2) → idx 3 (world)
    mov     rdi, 2
    call    bigram_logits_ptr
    mov     rdi, rax
    mov     rsi, VOCAB_SIZE
    call    argmax_logits
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # argmax test: bigram row for "world" (3) → idx 6 (the)
    mov     rdi, 3
    call    bigram_logits_ptr
    mov     rdi, rax
    mov     rsi, VOCAB_SIZE
    call    argmax_logits
    mov     rdi, rax
    mov     rsi, 6
    call    assert_eq

    # argmax test: bigram row for "bar" (5) → idx 1 (EOS)
    mov     rdi, 5
    call    bigram_logits_ptr
    mov     rdi, rax
    mov     rsi, VOCAB_SIZE
    call    argmax_logits
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # decode_sequence(2, output, 10) → 4 tokens [3, 6, 7, 1]
    mov     rdi, 2
    lea     rsi, [rip + output_buf]
    mov     rdx, 10
    call    decode_sequence
    mov     rdi, rax
    mov     rsi, 4
    call    assert_eq

    lea     r8, [rip + output_buf]
    mov     rdi, [r8 + 0]
    mov     rsi, 3
    call    assert_eq
    lea     r8, [rip + output_buf]
    mov     rdi, [r8 + 8]
    mov     rsi, 6
    call    assert_eq
    lea     r8, [rip + output_buf]
    mov     rdi, [r8 + 16]
    mov     rsi, 7
    call    assert_eq
    lea     r8, [rip + output_buf]
    mov     rdi, [r8 + 24]
    mov     rsi, 1
    call    assert_eq

    # decode_sequence(2, output, 2) → capped at 2 (no EOS reached)
    mov     rdi, 2
    lea     rsi, [rip + output_buf]
    mov     rdx, 2
    call    decode_sequence
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
