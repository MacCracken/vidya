# Vidya — Strings in x86_64 Assembly
#
# At the assembly level, strings are just bytes in memory. There is no
# string type — you work with addresses and lengths. Null-terminated
# (C-style) and length-prefixed are the two conventions. All string
# operations are explicit: compare byte-by-byte, copy with rep movsb.

.intel_syntax noprefix
.global _start

.section .rodata
hello:      .asciz "hello"
hello_len = . - hello - 1           # length without null: 5
world:      .ascii "world"
world_len = . - world
msg_pass:   .ascii "All string examples passed.\n"
msg_len = . - msg_pass

.section .bss
buffer:     .skip 128

.section .text

_start:
    # ── String length (null-terminated) ─────────────────────────────
    lea     rdi, [hello]
    call    strlen
    cmp     rax, 5
    jne     fail

    # ── String comparison ───────────────────────────────────────────
    lea     rsi, [hello]
    lea     rdi, [hello]
    mov     rcx, 5
    call    memcmp
    test    eax, eax
    jnz     fail

    # ── String copy with rep movsb ──────────────────────────────────
    lea     rsi, [hello]
    lea     rdi, [buffer]
    mov     rcx, 5
    rep     movsb

    # Verify copy
    lea     rsi, [hello]
    lea     rdi, [buffer]
    mov     rcx, 5
    call    memcmp
    test    eax, eax
    jnz     fail

    # ── String concatenation in buffer ──────────────────────────────
    # Build "helloworld" in buffer
    lea     rdi, [buffer]
    lea     rsi, [hello]
    mov     rcx, 5
    rep     movsb
    # rdi now points past "hello"
    lea     rsi, [world]
    mov     rcx, 5
    rep     movsb
    mov     byte ptr [rdi], 0       # null terminate

    # Verify length is 10
    lea     rdi, [buffer]
    call    strlen
    cmp     rax, 10
    jne     fail

    # ── Character case conversion ───────────────────────────────────
    # Uppercase check: 'A'=0x41 to 'Z'=0x5A
    mov     al, 'A'
    cmp     al, 0x41
    jb      fail
    cmp     al, 0x5A
    ja      fail

    # Lowercase to uppercase: clear bit 5
    mov     al, 'a'
    and     al, 0xDF
    cmp     al, 'A'
    jne     fail

    # Uppercase to lowercase: set bit 5
    mov     al, 'A'
    or      al, 0x20
    cmp     al, 'a'
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1                  # sys_write
    mov     rdi, 1                  # fd = stdout
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    # ── Exit 0 ──────────────────────────────────────────────────────
    mov     rax, 60                 # sys_exit
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── strlen: count bytes until null ──────────────────────────────────
# rdi = string pointer, returns rax = length
strlen:
    xor     rax, rax
.strlen_loop:
    cmp     byte ptr [rdi + rax], 0
    je      .strlen_done
    inc     rax
    jmp     .strlen_loop
.strlen_done:
    ret

# ── memcmp: compare rcx bytes at rsi and rdi ───────────────────────
# returns eax = 0 if equal
memcmp:
    push    rsi
    push    rdi
    push    rcx
.memcmp_loop:
    test    rcx, rcx
    jz      .memcmp_equal
    mov     al, byte ptr [rsi]
    cmp     al, byte ptr [rdi]
    jne     .memcmp_diff
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .memcmp_loop
.memcmp_diff:
    sub     al, byte ptr [rdi]
    movsx   eax, al
    pop     rcx
    pop     rdi
    pop     rsi
    ret
.memcmp_equal:
    xor     eax, eax
    pop     rcx
    pop     rdi
    pop     rsi
    ret
