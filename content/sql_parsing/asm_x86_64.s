# Vidya — SQL Parsing in x86_64 Assembly
#
# At the assembly level the SQL lexer is a byte-by-byte LODSB-style
# walk: load a byte (movzx rax,[rsi]), classify with cmp/jb/ja against
# ASCII ranges, and dispatch to the correct emit handler. Keyword
# detection uppercases each byte (or'd with 0x20-mask after range check)
# and compares against a literal. Tokens are written into a fixed
# buffer of 16-byte records {kind:8, ptr:8} for simplicity.

.intel_syntax noprefix
.global _start

# Token kind constants
.equ T_EOF,    0
.equ T_IDENT,  1
.equ T_INT,    2
.equ T_STAR,   3
.equ T_EQ,     4
.equ T_LPAREN, 5
.equ T_RPAREN, 6
.equ T_COMMA,  7
.equ T_SELECT, 10
.equ T_FROM,   11
.equ T_WHERE,  12

.section .rodata
sql1: .asciz "SELECT * FROM users WHERE id = 1"
sql2: .asciz "select * from T"
sql3: .asciz "selected"
sql4: .asciz "12345"

kw_select: .ascii "SELECT"
kw_select_len = . - kw_select
kw_from:   .ascii "FROM"
kw_from_len = . - kw_from
kw_where:  .ascii "WHERE"
kw_where_len = . - kw_where

msg_pass: .ascii "All sql_parsing examples passed.\n"
msg_pass_len = . - msg_pass

.section .bss
# 64 tokens × 16 bytes = 1024 B
.align 16
tok_buf: .skip 1024
tok_count: .skip 8

.section .text

# ── strlen(rdi) -> rax ────────────────────────────────────────────
strlen:
    xor     rax, rax
.Lsl_loop:
    cmp     byte ptr [rdi + rax], 0
    je      .Lsl_done
    inc     rax
    jmp     .Lsl_loop
.Lsl_done:
    ret

# ── is_alpha(al) -> al ∈ {0,1} ─────────────────────────────────────
is_alpha:
    cmp     al, '_'
    je      .Lia_yes
    cmp     al, 'A'
    jb      .Lia_no
    cmp     al, 'Z'
    jbe     .Lia_yes
    cmp     al, 'a'
    jb      .Lia_no
    cmp     al, 'z'
    jbe     .Lia_yes
.Lia_no:
    xor     eax, eax
    ret
.Lia_yes:
    mov     eax, 1
    ret

# ── is_alnum(al) -> al ∈ {0,1} ─────────────────────────────────────
is_alnum:
    push    rax
    call    is_alpha
    test    al, al
    jnz     .Lin_yes_pop
    pop     rax
    cmp     al, '0'
    jb      .Lin_no
    cmp     al, '9'
    jbe     .Lin_yes
.Lin_no:
    xor     eax, eax
    ret
.Lin_yes_pop:
    add     rsp, 8
.Lin_yes:
    mov     eax, 1
    ret

# ── kw_match(rsi=text, rcx=len, rdi=kw, rdx=kwlen) -> al ∈ {0,1} ──
# Compares text[i] uppercased vs kw[i]. Returns 1 if equal.
kw_match:
    cmp     rcx, rdx
    jne     .Lkm_no
    xor     r8, r8                  # i = 0
.Lkm_loop:
    cmp     r8, rcx
    je      .Lkm_yes
    movzx   eax, byte ptr [rsi + r8]
    cmp     al, 'a'
    jb      .Lkm_keep
    cmp     al, 'z'
    ja      .Lkm_keep
    sub     al, 32                  # uppercase
.Lkm_keep:
    movzx   r9d, byte ptr [rdi + r8]
    cmp     al, r9b
    jne     .Lkm_no
    inc     r8
    jmp     .Lkm_loop
.Lkm_yes:
    mov     eax, 1
    ret
.Lkm_no:
    xor     eax, eax
    ret

# ── classify(rsi=text, rcx=len) -> rax = token kind ───────────────
classify:
    push    rsi
    push    rcx
    lea     rdi, [rip + kw_select]
    mov     rdx, kw_select_len
    call    kw_match
    pop     rcx
    pop     rsi
    test    al, al
    jz      .Lcl_not_select
    mov     eax, T_SELECT
    ret
.Lcl_not_select:
    push    rsi
    push    rcx
    lea     rdi, [rip + kw_from]
    mov     rdx, kw_from_len
    call    kw_match
    pop     rcx
    pop     rsi
    test    al, al
    jz      .Lcl_not_from
    mov     eax, T_FROM
    ret
.Lcl_not_from:
    push    rsi
    push    rcx
    lea     rdi, [rip + kw_where]
    mov     rdx, kw_where_len
    call    kw_match
    pop     rcx
    pop     rsi
    test    al, al
    jz      .Lcl_ident
    mov     eax, T_WHERE
    ret
.Lcl_ident:
    mov     eax, T_IDENT
    ret

# ── tokenize(rdi=sql) -> rax = token count ────────────────────────
# Walks the SQL string byte-by-byte. Writes 16-byte records to
# tok_buf: { kind:i64, ptr:i64 }. Trailing T_EOF written; not counted
# in the returned count for ease of testing (matches Patra style:
# `_ntoks` excludes the EOF terminator).
tokenize:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                # base of sql
    call    strlen
    mov     r13, rax                # slen

    lea     r14, [rip + tok_buf]    # dest pointer
    xor     r15, r15                # token count
    xor     rbx, rbx                # pos

.Ltk_loop:
    cmp     rbx, r13
    jge     .Ltk_done

    movzx   eax, byte ptr [r12 + rbx]

    # Skip whitespace
    cmp     al, ' '
    je      .Ltk_skip
    cmp     al, '\t'
    je      .Ltk_skip
    cmp     al, '\n'
    je      .Ltk_skip
    cmp     al, '\r'
    jne     .Ltk_chk_alpha
.Ltk_skip:
    inc     rbx
    jmp     .Ltk_loop

.Ltk_chk_alpha:
    push    rax
    call    is_alpha
    mov     ecx, eax
    pop     rax
    test    ecx, ecx
    jz      .Ltk_chk_digit

    # Identifier / keyword: scan run of alnum
    mov     r8, rbx                 # start
.Ltk_id_scan:
    cmp     rbx, r13
    jge     .Ltk_id_emit
    movzx   eax, byte ptr [r12 + rbx]
    push    rax
    push    r8
    call    is_alnum
    mov     ecx, eax
    pop     r8
    pop     rax
    test    ecx, ecx
    jz      .Ltk_id_emit
    inc     rbx
    jmp     .Ltk_id_scan
.Ltk_id_emit:
    # rsi = sql + start, rcx = rbx - start
    mov     rsi, r12
    add     rsi, r8
    mov     rcx, rbx
    sub     rcx, r8
    push    rsi
    call    classify
    pop     rsi
    # rax = token kind
    mov     qword ptr [r14], rax
    mov     qword ptr [r14 + 8], rsi
    add     r14, 16
    inc     r15
    jmp     .Ltk_loop

.Ltk_chk_digit:
    cmp     al, '0'
    jb      .Ltk_chk_punct
    cmp     al, '9'
    ja      .Ltk_chk_punct

    mov     r8, rbx                 # start
.Ltk_int_scan:
    cmp     rbx, r13
    jge     .Ltk_int_emit
    movzx   eax, byte ptr [r12 + rbx]
    cmp     al, '0'
    jb      .Ltk_int_emit
    cmp     al, '9'
    ja      .Ltk_int_emit
    inc     rbx
    jmp     .Ltk_int_scan
.Ltk_int_emit:
    mov     rsi, r12
    add     rsi, r8
    mov     qword ptr [r14], T_INT
    mov     qword ptr [r14 + 8], rsi
    add     r14, 16
    inc     r15
    jmp     .Ltk_loop

.Ltk_chk_punct:
    # Map single-char punctuation to token kind
    cmp     al, '*'
    je      .Ltk_emit_star
    cmp     al, '='
    je      .Ltk_emit_eq
    cmp     al, '('
    je      .Ltk_emit_lparen
    cmp     al, ')'
    je      .Ltk_emit_rparen
    cmp     al, ','
    je      .Ltk_emit_comma
    # Unknown: skip
    inc     rbx
    jmp     .Ltk_loop

.Ltk_emit_star:
    mov     ecx, T_STAR
    jmp     .Ltk_emit_punct
.Ltk_emit_eq:
    mov     ecx, T_EQ
    jmp     .Ltk_emit_punct
.Ltk_emit_lparen:
    mov     ecx, T_LPAREN
    jmp     .Ltk_emit_punct
.Ltk_emit_rparen:
    mov     ecx, T_RPAREN
    jmp     .Ltk_emit_punct
.Ltk_emit_comma:
    mov     ecx, T_COMMA
.Ltk_emit_punct:
    movsx   rcx, ecx
    mov     qword ptr [r14], rcx
    mov     rsi, r12
    add     rsi, rbx
    mov     qword ptr [r14 + 8], rsi
    add     r14, 16
    inc     r15
    inc     rbx
    jmp     .Ltk_loop

.Ltk_done:
    # Append EOF sentinel (not counted in r15)
    mov     qword ptr [r14], T_EOF
    mov     qword ptr [r14 + 8], 0

    mov     rax, r15
    lea     r10, [rip + tok_count]
    mov     qword ptr [r10], r15

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ── tk(i) -> rax = kind of token i ────────────────────────────────
# Reads tok_buf[i].kind
tk_kind:
    # rdi = i
    lea     rax, [rip + tok_buf]
    shl     rdi, 4                  # i * 16
    add     rax, rdi
    mov     rax, qword ptr [rax]
    ret

# ── _start: drive the test cases ──────────────────────────────────
_start:
    # ── Test 1: SELECT * FROM users WHERE id = 1 (8 tokens) ───────
    lea     rdi, [rip + sql1]
    call    tokenize
    cmp     rax, 8
    jne     fail

    xor     rdi, rdi
    call    tk_kind
    cmp     rax, T_SELECT
    jne     fail

    mov     rdi, 1
    call    tk_kind
    cmp     rax, T_STAR
    jne     fail

    mov     rdi, 2
    call    tk_kind
    cmp     rax, T_FROM
    jne     fail

    mov     rdi, 3
    call    tk_kind
    cmp     rax, T_IDENT
    jne     fail

    mov     rdi, 4
    call    tk_kind
    cmp     rax, T_WHERE
    jne     fail

    mov     rdi, 5
    call    tk_kind
    cmp     rax, T_IDENT
    jne     fail

    mov     rdi, 6
    call    tk_kind
    cmp     rax, T_EQ
    jne     fail

    mov     rdi, 7
    call    tk_kind
    cmp     rax, T_INT
    jne     fail

    # ── Test 2: lowercase keywords ────────────────────────────────
    lea     rdi, [rip + sql2]
    call    tokenize
    cmp     rax, 4
    jne     fail
    xor     rdi, rdi
    call    tk_kind
    cmp     rax, T_SELECT
    jne     fail
    mov     rdi, 2
    call    tk_kind
    cmp     rax, T_FROM
    jne     fail

    # ── Test 3: 'selected' is identifier, not SELECT ──────────────
    lea     rdi, [rip + sql3]
    call    tokenize
    cmp     rax, 1
    jne     fail
    xor     rdi, rdi
    call    tk_kind
    cmp     rax, T_IDENT
    jne     fail

    # ── Test 4: integer literal ──────────────────────────────────
    lea     rdi, [rip + sql4]
    call    tokenize
    cmp     rax, 1
    jne     fail
    xor     rdi, rdi
    call    tk_kind
    cmp     rax, T_INT
    jne     fail

    # ── Print success message ────────────────────────────────────
    mov     rax, 1                  # write
    mov     rdi, 1                  # stdout
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall

    mov     rax, 60                 # exit
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall
