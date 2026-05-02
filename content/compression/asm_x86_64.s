# Vidya — Compression (LZ77-shaped) in x86_64 Assembly
#
# Asm ports focus on the decoder — the spec-defined half of LZ77. The
# encoder's nested O(n²) match-finder doesn't add algorithmic value at
# the asm level. Hand-built token streams from the cyrius reference's
# greedy encoding back the test cases:
#
#   "ABC"        → [0,A, 0,B, 0,C]                 (3 literals)
#   "AAAAAAAA"   → [0,A, 1,7]                      (literal + RLE match)
#   "ABCABCABC"  → [0,A, 0,B, 0,C, 3,6]            (literals + substring)
#   bomb         → [1,200] decoded with cap=10 → -1
#
# Token format matches cyrius.cyr exactly: 2-byte tokens; b0=0 means
# literal (b1 = byte value), b0!=0 means match (b0 = offset, b1 = length).
# Match copy is byte-by-byte so offset=1 acts as RLE replication.

.intel_syntax noprefix
.global _start

.equ BUF_CAP, 512

.section .bss
.align 8
out_buf:      .skip BUF_CAP

.section .rodata
# Test 1: ABC literals
tok_abc:      .byte 0, 'A', 0, 'B', 0, 'C'
.equ tok_abc_len, . - tok_abc
exp_abc:      .ascii "ABC"
.equ exp_abc_len, . - exp_abc

# Test 2: AAAAAAAA via RLE
tok_aaa:      .byte 0, 'A', 1, 7
.equ tok_aaa_len, . - tok_aaa
exp_aaa:      .ascii "AAAAAAAA"
.equ exp_aaa_len, . - exp_aaa

# Test 3: ABCABCABC via literals + substring match
tok_abcabc:   .byte 0, 'A', 0, 'B', 0, 'C', 3, 6
.equ tok_abcabc_len, . - tok_abcabc
exp_abcabc:   .ascii "ABCABCABC"
.equ exp_abcabc_len, . - exp_abcabc

# Test 4: bomb — single match claiming length 200
tok_bomb:     .byte 1, 200
.equ tok_bomb_len, . - tok_bomb

msg_pass:     .ascii "compression: 5/5 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# decode(rdi=tok_ptr, rsi=tok_len, rdx=out_cap) -> rax = output length, or -1 on bomb.
decode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi              # tok ptr
    mov     r13, rsi              # tok len
    mov     r14, rdx              # out cap
    xor     r15, r15              # output position
    xor     rbx, rbx              # token index

.dec_loop:
    mov     rax, rbx
    add     rax, 1
    cmp     rax, r13
    jge     .dec_done
    movzx   rax, byte ptr [r12 + rbx]      # b0
    movzx   rcx, byte ptr [r12 + rbx + 1]  # b1
    add     rbx, 2
    test    rax, rax
    jnz     .dec_match
    # literal: b1 → out_buf[r15]
    mov     rdi, r15
    add     rdi, 1
    cmp     rdi, r14
    jg      .dec_bomb
    lea     rdi, [rip + out_buf]
    mov     [rdi + r15], cl
    inc     r15
    jmp     .dec_loop
.dec_match:
    # offset = rax, length = rcx
    mov     rdi, r15
    add     rdi, rcx
    cmp     rdi, r14
    jg      .dec_bomb
    # byte-by-byte copy
    lea     rdi, [rip + out_buf]
    xor     r9, r9                # k
.dm_copy:
    cmp     r9, rcx
    jge     .dm_done
    mov     r8, r15
    sub     r8, rax
    add     r8, r9
    movzx   r10, byte ptr [rdi + r8]
    mov     r8, r15
    add     r8, r9
    mov     [rdi + r8], r10b
    inc     r9
    jmp     .dm_copy
.dm_done:
    add     r15, rcx
    jmp     .dec_loop

.dec_bomb:
    mov     rax, -1
    jmp     .dec_ret
.dec_done:
    mov     rax, r15
.dec_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# memeq(rdi=a, rsi=b, rdx=n) -> rax = 1 if equal, 0 otherwise
memeq:
    xor     rax, rax
.me_loop:
    cmp     rax, rdx
    je      .me_eq
    movzx   rcx, byte ptr [rdi + rax]
    movzx   r8, byte ptr [rsi + rax]
    cmp     rcx, r8
    jne     .me_neq
    inc     rax
    jmp     .me_loop
.me_eq:
    mov     rax, 1
    ret
.me_neq:
    xor     rax, rax
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
    # Test 1: ABC literals
    lea     rdi, [rip + tok_abc]
    mov     rsi, tok_abc_len
    mov     rdx, BUF_CAP
    call    decode
    cmp     rax, exp_abc_len
    jne     fail_exit
    lea     rdi, [rip + out_buf]
    lea     rsi, [rip + exp_abc]
    mov     rdx, exp_abc_len
    call    memeq
    cmp     rax, 1
    jne     fail_exit

    # Test 2: AAAAAAAA via RLE
    lea     rdi, [rip + tok_aaa]
    mov     rsi, tok_aaa_len
    mov     rdx, BUF_CAP
    call    decode
    cmp     rax, exp_aaa_len
    jne     fail_exit
    lea     rdi, [rip + out_buf]
    lea     rsi, [rip + exp_aaa]
    mov     rdx, exp_aaa_len
    call    memeq
    cmp     rax, 1
    jne     fail_exit

    # Test 3: ABCABCABC via literals + substring
    lea     rdi, [rip + tok_abcabc]
    mov     rsi, tok_abcabc_len
    mov     rdx, BUF_CAP
    call    decode
    cmp     rax, exp_abcabc_len
    jne     fail_exit
    lea     rdi, [rip + out_buf]
    lea     rsi, [rip + exp_abcabc]
    mov     rdx, exp_abcabc_len
    call    memeq
    cmp     rax, 1
    jne     fail_exit

    # Test 4: bomb guard returns -1 with cap=10
    lea     rdi, [rip + tok_bomb]
    mov     rsi, tok_bomb_len
    mov     rdx, 10
    call    decode
    cmp     rax, -1
    jne     fail_exit

    # Test 5: empty token stream
    lea     rdi, [rip + tok_abc]   # any nonzero ptr; len=0 short-circuits
    mov     rsi, 0
    mov     rdx, BUF_CAP
    call    decode
    cmp     rax, 0
    jne     fail_exit

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
