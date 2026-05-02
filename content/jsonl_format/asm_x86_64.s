# Vidya — JSON Lines (JSONL) in x86_64 Assembly
#
# Asm port focuses on the JSON-string escape/unescape with bounds-
# check — the algorithmically meaningful piece. Line indexing is
# trivial scanning that doesn't gain anything in asm, so it's
# elided. The 8-assertion equivalent here:
#   1. escape produces 18 bytes from 12-byte input (5 special chars)
#   2. escape with cap=4 returns -1 (bounds check)
#   3. unescape recovers 12 bytes
#   4. round-trip bytes match

.intel_syntax noprefix
.global _start

.section .data
src:          .byte 's', 'a', 'y', ' ', '"', 'h', 'i', '"', 9, 10, 13, 92
.equ src_len, . - src

.section .bss
.align 8
esc_buf:      .skip 256
unesc_buf:    .skip 256

.section .rodata
msg_pass:     .ascii "jsonl_format: 4/4 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# json_escape(rdi=dst, rsi=dst_cap, rdx=src, rcx=src_len) -> rax = w or -1
json_escape:
    # Bounds check: src_len * 2 > dst_cap → -1
    mov     rax, rcx
    shl     rax, 1
    cmp     rax, rsi
    jg      .je_bomb
    xor     rax, rax              # w = 0
    xor     r8, r8                # i = 0
.je_loop:
    cmp     r8, rcx
    jge     .je_done
    movzx   r9, byte ptr [rdx + r8]
    cmp     r9, 34                # "
    je      .je_quote
    cmp     r9, 92                # \
    je      .je_back
    cmp     r9, 10                # \n
    je      .je_nl
    cmp     r9, 9                 # \t
    je      .je_tab
    cmp     r9, 13                # \r
    je      .je_cr
    # plain
    mov     [rdi + rax], r9b
    inc     rax
    jmp     .je_next
.je_quote:
    mov     byte ptr [rdi + rax], 92
    mov     byte ptr [rdi + rax + 1], 34
    add     rax, 2
    jmp     .je_next
.je_back:
    mov     byte ptr [rdi + rax], 92
    mov     byte ptr [rdi + rax + 1], 92
    add     rax, 2
    jmp     .je_next
.je_nl:
    mov     byte ptr [rdi + rax], 92
    mov     byte ptr [rdi + rax + 1], 110
    add     rax, 2
    jmp     .je_next
.je_tab:
    mov     byte ptr [rdi + rax], 92
    mov     byte ptr [rdi + rax + 1], 116
    add     rax, 2
    jmp     .je_next
.je_cr:
    mov     byte ptr [rdi + rax], 92
    mov     byte ptr [rdi + rax + 1], 114
    add     rax, 2
.je_next:
    inc     r8
    jmp     .je_loop
.je_done:
    ret
.je_bomb:
    mov     rax, -1
    ret

# json_unescape(rdi=dst, rsi=src, rdx=src_len) -> rax = w
json_unescape:
    xor     rax, rax              # w
    xor     r8, r8                # i
.ju_loop:
    cmp     r8, rdx
    jge     .ju_done
    movzx   r9, byte ptr [rsi + r8]
    cmp     r9, 92
    jne     .ju_plain
    mov     r10, r8
    inc     r10
    cmp     r10, rdx
    jge     .ju_plain
    movzx   r11, byte ptr [rsi + r10]
    cmp     r11, 34
    je      .ju_q
    cmp     r11, 92
    je      .ju_b
    cmp     r11, 110
    je      .ju_nl
    cmp     r11, 116
    je      .ju_tab
    cmp     r11, 114
    je      .ju_cr
.ju_plain:
    mov     [rdi + rax], r9b
    inc     rax
    inc     r8
    jmp     .ju_loop
.ju_q:
    mov     byte ptr [rdi + rax], 34
    inc     rax
    add     r8, 2
    jmp     .ju_loop
.ju_b:
    mov     byte ptr [rdi + rax], 92
    inc     rax
    add     r8, 2
    jmp     .ju_loop
.ju_nl:
    mov     byte ptr [rdi + rax], 10
    inc     rax
    add     r8, 2
    jmp     .ju_loop
.ju_tab:
    mov     byte ptr [rdi + rax], 9
    inc     rax
    add     r8, 2
    jmp     .ju_loop
.ju_cr:
    mov     byte ptr [rdi + rax], 13
    inc     rax
    add     r8, 2
    jmp     .ju_loop
.ju_done:
    ret

# memeq(rdi=a, rsi=b, rdx=n) -> rax = 1 if equal
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
    # 1. escape produces 18 bytes
    lea     rdi, [rip + esc_buf]
    mov     rsi, 256
    lea     rdx, [rip + src]
    mov     rcx, src_len
    call    json_escape
    cmp     rax, 18
    jne     fail_exit
    mov     r12, rax              # cache escaped len in callee-saved

    # 2. bounds check returns -1
    lea     rdi, [rip + esc_buf]
    mov     rsi, 4
    lea     rdx, [rip + src]
    mov     rcx, 4
    call    json_escape
    cmp     rax, -1
    jne     fail_exit

    # Re-escape into esc_buf for unescape (test 2 clobbered first 4 bytes)
    lea     rdi, [rip + esc_buf]
    mov     rsi, 256
    lea     rdx, [rip + src]
    mov     rcx, src_len
    call    json_escape

    # 3. unescape recovers 12 bytes
    lea     rdi, [rip + unesc_buf]
    lea     rsi, [rip + esc_buf]
    mov     rdx, r12              # = 18
    call    json_unescape
    cmp     rax, src_len
    jne     fail_exit

    # 4. round-trip bytes match
    lea     rdi, [rip + unesc_buf]
    lea     rsi, [rip + src]
    mov     rdx, src_len
    call    memeq
    cmp     rax, 1
    jne     fail_exit

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
