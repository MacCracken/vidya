# Vidya — Lexing and Parsing in x86_64 Assembly
#
# At the assembly level, lexing is byte-at-a-time classification:
# load a byte, compare against ranges (cmp/jb/ja), branch to handlers.
# Parsing a number means accumulating digits: result = result*10 + digit.
# A tokenizer is a loop that classifies and extracts spans of bytes.

.intel_syntax noprefix
.global _start

.section .rodata
# Test input: "  123 abc 456  "
input:      .ascii "  123 abc 456  "
input_len = . - input

msg_pass:   .ascii "All lexing and parsing examples passed.\n"
msg_len = . - msg_pass

.section .bss
# Token buffer: each token is 16 bytes [offset:4][length:4][type:4][value:4]
tokens:     .skip 256

.section .text

_start:
    # ── is_digit: classify ASCII characters ────────────────────────
    mov     dil, '0'
    call    is_digit
    cmp     eax, 1
    jne     fail

    mov     dil, '9'
    call    is_digit
    cmp     eax, 1
    jne     fail

    mov     dil, 'a'
    call    is_digit
    cmp     eax, 0
    jne     fail

    mov     dil, '/'
    call    is_digit
    cmp     eax, 0
    jne     fail

    # ── is_alpha: letter classification ────────────────────────────
    mov     dil, 'a'
    call    is_alpha
    cmp     eax, 1
    jne     fail

    mov     dil, 'Z'
    call    is_alpha
    cmp     eax, 1
    jne     fail

    mov     dil, '5'
    call    is_alpha
    cmp     eax, 0
    jne     fail

    # ── parse_number: scan digits, build integer ───────────────────
    # Parse "123" from input+2
    lea     rdi, [input + 2]
    mov     esi, 3              # 3 digits
    call    parse_number
    cmp     eax, 123
    jne     fail

    # Parse "456" from input+10
    lea     rdi, [input + 10]
    mov     esi, 3
    call    parse_number
    cmp     eax, 456
    jne     fail

    # Parse single digit "9"
    lea     rdi, [.digit_nine]
    mov     esi, 1
    call    parse_number
    cmp     eax, 9
    jne     fail

    # ── tokenize: scan input, produce token stream ─────────────────
    lea     rdi, [input]
    mov     esi, input_len
    lea     rdx, [tokens]
    call    tokenize
    # Returns eax = token count. We expect 3 tokens: "123", "abc", "456"
    cmp     eax, 3
    jne     fail

    # Verify token 0: type=1 (number), value=123
    lea     rdi, [tokens]
    cmp     dword ptr [rdi + 8], 1      # type = number
    jne     fail
    cmp     dword ptr [rdi + 12], 123   # value = 123
    jne     fail

    # Verify token 1: type=2 (identifier), offset=6, length=3
    cmp     dword ptr [rdi + 16 + 8], 2 # type = identifier
    jne     fail
    cmp     dword ptr [rdi + 16 + 0], 6 # offset = 6
    jne     fail
    cmp     dword ptr [rdi + 16 + 4], 3 # length = 3
    jne     fail

    # Verify token 2: type=1 (number), value=456
    cmp     dword ptr [rdi + 32 + 8], 1
    jne     fail
    cmp     dword ptr [rdi + 32 + 12], 456
    jne     fail

    # ── Print success ──────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

.section .rodata
.digit_nine: .ascii "9"

.section .text

# ── is_digit(dil) → eax: 1 if '0'-'9', else 0 ────────────────────
is_digit:
    movzx   eax, dil
    sub     al, '0'
    cmp     al, 10
    jb      .is_digit_yes
    xor     eax, eax
    ret
.is_digit_yes:
    mov     eax, 1
    ret

# ── is_alpha(dil) → eax: 1 if letter, else 0 ─────────────────────
is_alpha:
    movzx   eax, dil
    # Check uppercase: 'A'(0x41) to 'Z'(0x5A)
    cmp     al, 'A'
    jb      .is_alpha_no
    cmp     al, 'Z'
    jbe     .is_alpha_yes
    # Check lowercase: 'a'(0x61) to 'z'(0x7A)
    cmp     al, 'a'
    jb      .is_alpha_no
    cmp     al, 'z'
    jbe     .is_alpha_yes
.is_alpha_no:
    xor     eax, eax
    ret
.is_alpha_yes:
    mov     eax, 1
    ret

# ── parse_number(rdi=str, esi=len) → eax: parsed integer ──────────
# Scans esi bytes from rdi, accumulates: result = result*10 + (byte - '0')
parse_number:
    xor     eax, eax            # result = 0
    xor     ecx, ecx            # index = 0
.pn_loop:
    cmp     ecx, esi
    jge     .pn_done
    imul    eax, 10             # result *= 10
    movzx   edx, byte ptr [rdi + rcx]
    sub     edx, '0'            # digit value
    add     eax, edx            # result += digit
    inc     ecx
    jmp     .pn_loop
.pn_done:
    ret

# ── tokenize(rdi=input, esi=len, rdx=out) → eax: token count ──────
# Token types: 1=number, 2=identifier
# Each token: [offset:4][length:4][type:4][value:4] = 16 bytes
# Skips whitespace, scans runs of digits or letters.
tokenize:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi            # input base
    mov     r13d, esi           # input length
    mov     r14, rdx            # output buffer
    xor     r15d, r15d          # token count
    xor     ebx, ebx            # current position

.tok_skip_space:
    cmp     ebx, r13d
    jge     .tok_done
    movzx   eax, byte ptr [r12 + rbx]
    cmp     al, ' '
    je      .tok_advance
    cmp     al, '\t'
    je      .tok_advance
    cmp     al, '\n'
    je      .tok_advance
    jmp     .tok_classify

.tok_advance:
    inc     ebx
    jmp     .tok_skip_space

.tok_classify:
    # Check if digit → number token
    mov     dil, al
    push    rax
    call    is_digit
    mov     ecx, eax
    pop     rax
    test    ecx, ecx
    jnz     .tok_number

    # Check if alpha → identifier token
    mov     dil, al
    call    is_alpha
    test    eax, eax
    jnz     .tok_ident

    # Unknown character: skip
    inc     ebx
    jmp     .tok_skip_space

.tok_number:
    # Record start offset
    mov     ecx, ebx            # start
    # Scan forward while digits
.tok_num_scan:
    cmp     ebx, r13d
    jge     .tok_num_emit
    movzx   eax, byte ptr [r12 + rbx]
    sub     al, '0'
    cmp     al, 10
    jae     .tok_num_emit
    inc     ebx
    jmp     .tok_num_scan

.tok_num_emit:
    # ecx = start, ebx = end, length = ebx - ecx
    mov     edx, ebx
    sub     edx, ecx            # length

    # Parse the number value
    push    rcx
    push    rdx
    lea     rdi, [r12 + rcx]
    mov     esi, edx
    call    parse_number
    mov     r8d, eax            # value
    pop     rdx
    pop     rcx

    # Write token: offset, length, type=1, value
    mov     rax, r15
    shl     rax, 4              # token_index * 16
    mov     dword ptr [r14 + rax + 0], ecx      # offset
    mov     dword ptr [r14 + rax + 4], edx      # length
    mov     dword ptr [r14 + rax + 8], 1        # type = number
    mov     dword ptr [r14 + rax + 12], r8d     # value
    inc     r15d
    jmp     .tok_skip_space

.tok_ident:
    mov     ecx, ebx            # start
.tok_ident_scan:
    cmp     ebx, r13d
    jge     .tok_ident_emit
    movzx   eax, byte ptr [r12 + rbx]
    # Check if still alpha
    cmp     al, 'A'
    jb      .tok_ident_emit
    cmp     al, 'Z'
    jbe     .tok_ident_cont
    cmp     al, 'a'
    jb      .tok_ident_emit
    cmp     al, 'z'
    ja      .tok_ident_emit
.tok_ident_cont:
    inc     ebx
    jmp     .tok_ident_scan

.tok_ident_emit:
    mov     edx, ebx
    sub     edx, ecx            # length

    # Write token: offset, length, type=2, value=0
    mov     rax, r15
    shl     rax, 4
    mov     dword ptr [r14 + rax + 0], ecx
    mov     dword ptr [r14 + rax + 4], edx
    mov     dword ptr [r14 + rax + 8], 2        # type = identifier
    mov     dword ptr [r14 + rax + 12], 0
    inc     r15d
    jmp     .tok_skip_space

.tok_done:
    mov     eax, r15d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
