# Vidya — Security Practices in x86_64 Assembly
#
# At the assembly level, security means: constant-time comparison
# (no branches on secret data), zeroing secrets from memory (can't
# be optimized away at this level), stack canaries, and safe memory
# operations. These are the primitives that higher-level security
# functions are built on.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:       .ascii "All security examples passed.\n"
msg_len = . - msg_pass

secret_a:       .ascii "secret_token_24"
secret_b:       .ascii "secret_token_24"
secret_c:       .ascii "secret_token_25"
secret_len = 15

.section .bss
zero_buf:       .skip 32
scratch:        .skip 64

.section .text

_start:
    # ── Test 1: constant-time comparison (equal) ───────────────────────
    # XOR each byte pair, OR into accumulator — never branch on data
    lea     rsi, [secret_a]
    lea     rdi, [secret_b]
    mov     rcx, secret_len
    call    constant_time_eq
    test    al, al
    jz      fail                    # should be equal

    # ── Test 2: constant-time comparison (different) ───────────────────
    lea     rsi, [secret_a]
    lea     rdi, [secret_c]
    mov     rcx, secret_len
    call    constant_time_eq
    test    al, al
    jnz     fail                    # should NOT be equal

    # ── Test 3: constant-time comparison (empty) ───────────────────────
    lea     rsi, [secret_a]
    lea     rdi, [secret_a]
    xor     rcx, rcx                # length 0
    call    constant_time_eq
    test    al, al
    jz      fail                    # empty == empty

    # ── Test 4: secure memory zeroing ──────────────────────────────────
    # Write known pattern, then zero it, then verify zeros
    lea     rdi, [zero_buf]
    mov     rcx, 32
    mov     al, 0xAA
    rep stosb                       # fill with 0xAA

    # Verify it's 0xAA
    lea     rsi, [zero_buf]
    mov     rcx, 32
.verify_pattern:
    lodsb
    cmp     al, 0xAA
    jne     fail
    loop    .verify_pattern

    # Secure zero — at assembly level, this CAN'T be optimized away
    lea     rdi, [zero_buf]
    mov     rcx, 32
    call    secure_zero

    # Verify all zeros
    lea     rsi, [zero_buf]
    mov     rcx, 32
.verify_zeros:
    lodsb
    test    al, al
    jnz     fail
    loop    .verify_zeros

    # ── Test 5: bounds-checked copy ────────────────────────────────────
    # Copy with length check: src_len must be <= dst_size
    lea     rdi, [scratch]          # dst
    mov     rdx, 64                 # dst_size
    lea     rsi, [secret_a]         # src
    mov     rcx, secret_len         # src_len
    call    safe_copy
    test    eax, eax
    jnz     fail                    # should succeed

    # Verify copied content
    lea     rsi, [scratch]
    lea     rdi, [secret_a]
    mov     rcx, secret_len
    call    constant_time_eq
    test    al, al
    jz      fail

    # Overflow attempt: src_len > dst_size
    lea     rdi, [scratch]
    mov     rdx, 4                  # dst_size = 4 (too small)
    lea     rsi, [secret_a]
    mov     rcx, secret_len         # src_len = 15
    call    safe_copy
    cmp     eax, -1
    jne     fail                    # should return -1

    # ── Test 6: input byte validation ──────────────────────────────────
    # Check that all bytes in a buffer are alphanumeric or underscore
    lea     rsi, [secret_a]         # "secret_token_24" — valid
    mov     rcx, secret_len
    call    validate_alnum
    test    al, al
    jz      fail                    # should be valid

    # ── All passed ─────────────────────────────────────────────────────
    mov     rax, 1                  # sys_write
    mov     rdi, 1                  # stdout
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60                 # sys_exit
    xor     rdi, rdi                # exit code 0
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── constant_time_eq(rsi=a, rdi=b, rcx=len) → al (1=equal, 0=not) ─
# No branches on data — only the loop counter is branched on.
constant_time_eq:
    xor     eax, eax                # accumulator = 0
    test    rcx, rcx
    jz      .cte_done               # length 0 → equal
    xor     edx, edx
.cte_loop:
    movzx   r8d, byte ptr [rsi + rdx]
    xor     r8b, byte ptr [rdi + rdx]
    or      al, r8b                 # accumulate differences
    inc     rdx
    cmp     rdx, rcx
    jb      .cte_loop
.cte_done:
    # al == 0 means equal; convert to 1=equal, 0=different
    test    al, al
    setz    al
    ret

# ── secure_zero(rdi=buf, rcx=len) ─────────────────────────────────────
# Zero memory byte-by-byte. At assembly level, no compiler can elide this.
secure_zero:
    test    rcx, rcx
    jz      .sz_done
    xor     eax, eax
    rep stosb
.sz_done:
    ret

# ── safe_copy(rdi=dst, rdx=dst_size, rsi=src, rcx=src_len) → eax ──
# Returns 0 on success, -1 if src_len > dst_size.
safe_copy:
    cmp     rcx, rdx
    ja      .sc_overflow
    # rcx = src_len, rsi = src, rdi = dst
    push    rdi
    push    rsi
    push    rcx
    rep movsb
    pop     rcx
    pop     rsi
    pop     rdi
    xor     eax, eax                # return 0
    ret
.sc_overflow:
    mov     eax, -1
    ret

# ── validate_alnum(rsi=buf, rcx=len) → al (1=valid, 0=invalid) ────
# Checks each byte is [a-zA-Z0-9_]
validate_alnum:
    test    rcx, rcx
    jz      .va_invalid             # empty = invalid
    xor     edx, edx
.va_loop:
    movzx   eax, byte ptr [rsi + rdx]
    # Check: a-z
    cmp     al, 'a'
    jb      .va_not_lower
    cmp     al, 'z'
    jbe     .va_next
.va_not_lower:
    # Check: A-Z
    cmp     al, 'A'
    jb      .va_not_upper
    cmp     al, 'Z'
    jbe     .va_next
.va_not_upper:
    # Check: 0-9
    cmp     al, '0'
    jb      .va_not_digit
    cmp     al, '9'
    jbe     .va_next
.va_not_digit:
    # Check: underscore
    cmp     al, '_'
    jne     .va_invalid
.va_next:
    inc     rdx
    cmp     rdx, rcx
    jb      .va_loop
    mov     al, 1
    ret
.va_invalid:
    xor     eax, eax
    ret
