// Vidya — SQL Parsing in AArch64 Assembly
//
// AArch64 SQL lexer: same shape as the x86_64 version but uses LDRB
// to load bytes one at a time. Character classification is range-
// checked with CMP / B.HI / B.LS. Keyword matching uppercases each
// byte (sub 32 if in 'a'..'z') before comparing against the literal.
// Functions that call `bl` save x29+x30 in their prologue per AAPCS.
// Caller-saved x0–x18 are NOT preserved across `bl`, so we stash
// loop state in x19+ (callee-saved) where needed.

.global _start

// Token kind constants
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
.align 3
sql1: .asciz "SELECT * FROM users WHERE id = 1"
sql2: .asciz "select * from T"
sql3: .asciz "selected"
sql4: .asciz "12345"

kw_select: .ascii "SELECT"
.equ kw_select_len, 6
kw_from:   .ascii "FROM"
.equ kw_from_len, 4
kw_where:  .ascii "WHERE"
.equ kw_where_len, 5

msg_pass:  .ascii "All sql_parsing examples passed.\n"
.equ msg_pass_len, 33

.section .bss
.align 4
tok_buf:   .skip 1024            // 64 tokens × 16 bytes (kind, ptr)

.section .text

// ── strlen(x0=str) -> x0=len ────────────────────────────────────
strlen:
    mov     x1, x0
.Lsl_loop:
    ldrb    w2, [x1]
    cbz     w2, .Lsl_done
    add     x1, x1, #1
    b       .Lsl_loop
.Lsl_done:
    sub     x0, x1, x0
    ret

// ── is_alpha(w0=char) -> w0 ∈ {0,1} ─────────────────────────────
is_alpha:
    cmp     w0, #'_'
    b.eq    .Lia_yes
    orr     w1, w0, #0x20         // lowercase if uppercase
    sub     w1, w1, #'a'
    cmp     w1, #25
    b.hi    .Lia_no
    mov     w0, #1
    ret
.Lia_no:
    mov     w0, #0
    ret
.Lia_yes:
    mov     w0, #1
    ret

// ── is_alnum(w0=char) -> w0 ∈ {0,1} ─────────────────────────────
// Save x19 BEFORE clobbering it — it's callee-saved and the caller
// (tokenize) uses x19 as the SQL base pointer.
is_alnum:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]        // save x19 first
    mov     w19, w0               // now safe to use x19 as scratch
    bl      is_alpha
    cbnz    w0, .Lin_yes
    mov     w0, w19
    sub     w0, w0, #'0'
    cmp     w0, #9
    b.hi    .Lin_no
.Lin_yes:
    mov     w0, #1
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lin_no:
    mov     w0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ── kw_match(x0=text, x1=len, x2=kw, x3=kwlen) -> w0 ∈ {0,1} ────
// Compares uppercased text bytes against kw bytes.
kw_match:
    cmp     x1, x3
    b.ne    .Lkm_no
    mov     x4, #0                // i
.Lkm_loop:
    cmp     x4, x1
    b.eq    .Lkm_yes
    ldrb    w5, [x0, x4]
    cmp     w5, #'a'
    b.lo    .Lkm_keep
    cmp     w5, #'z'
    b.hi    .Lkm_keep
    sub     w5, w5, #32           // uppercase
.Lkm_keep:
    ldrb    w6, [x2, x4]
    cmp     w5, w6
    b.ne    .Lkm_no
    add     x4, x4, #1
    b       .Lkm_loop
.Lkm_yes:
    mov     w0, #1
    ret
.Lkm_no:
    mov     w0, #0
    ret

// ── classify(x0=text, x1=len) -> x0=kind ────────────────────────
// We must save text+len across the `bl` calls (caller-saved).
classify:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0               // text
    mov     x20, x1               // len

    // Try SELECT
    adrp    x2, kw_select
    add     x2, x2, :lo12:kw_select
    mov     x3, #kw_select_len
    bl      kw_match
    cbz     w0, .Lcl_not_select
    mov     x0, #T_SELECT
    b       .Lcl_done

.Lcl_not_select:
    mov     x0, x19
    mov     x1, x20
    adrp    x2, kw_from
    add     x2, x2, :lo12:kw_from
    mov     x3, #kw_from_len
    bl      kw_match
    cbz     w0, .Lcl_not_from
    mov     x0, #T_FROM
    b       .Lcl_done

.Lcl_not_from:
    mov     x0, x19
    mov     x1, x20
    adrp    x2, kw_where
    add     x2, x2, :lo12:kw_where
    mov     x3, #kw_where_len
    bl      kw_match
    cbz     w0, .Lcl_ident
    mov     x0, #T_WHERE
    b       .Lcl_done

.Lcl_ident:
    mov     x0, #T_IDENT

.Lcl_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ── tokenize(x0=sql) -> x0=token count ──────────────────────────
// Walks the SQL string, writing 16-byte records {kind:i64, ptr:i64}
// to tok_buf. Trailing T_EOF written but not included in count.
// Callee-saved registers (x19..x24) hold loop state across bl calls.
tokenize:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // sql base
    bl      strlen
    mov     x20, x0                 // slen

    adrp    x21, tok_buf
    add     x21, x21, :lo12:tok_buf // dst
    mov     x22, #0                 // count
    mov     x23, #0                 // pos

.Ltk_loop:
    cmp     x23, x20
    b.ge    .Ltk_done

    ldrb    w24, [x19, x23]         // current char

    // skip whitespace
    cmp     w24, #' '
    b.eq    .Ltk_skip
    cmp     w24, #'\t'
    b.eq    .Ltk_skip
    cmp     w24, #'\n'
    b.eq    .Ltk_skip
    cmp     w24, #'\r'
    b.eq    .Ltk_skip
    b       .Ltk_chk_alpha
.Ltk_skip:
    add     x23, x23, #1
    b       .Ltk_loop

.Ltk_chk_alpha:
    mov     w0, w24
    bl      is_alpha
    cbz     w0, .Ltk_chk_digit

    // Identifier / keyword
    mov     x9, x23                 // start
.Ltk_id_scan:
    cmp     x23, x20
    b.ge    .Ltk_id_emit_setup
    ldrb    w0, [x19, x23]
    str     x9, [sp, #-16]!         // save start
    bl      is_alnum
    ldr     x9, [sp], #16
    cbz     w0, .Ltk_id_emit_setup
    add     x23, x23, #1
    b       .Ltk_id_scan
.Ltk_id_emit_setup:
    add     x0, x19, x9             // text
    sub     x1, x23, x9             // len
    mov     x10, x9                 // save start ptr offset
    str     x10, [sp, #-16]!
    bl      classify
    ldr     x10, [sp], #16
    // x0 now has kind
    str     x0, [x21]               // kind
    add     x11, x19, x10           // text ptr
    str     x11, [x21, #8]          // ptr
    add     x21, x21, #16
    add     x22, x22, #1
    b       .Ltk_loop

.Ltk_chk_digit:
    cmp     w24, #'0'
    b.lo    .Ltk_chk_punct
    cmp     w24, #'9'
    b.hi    .Ltk_chk_punct

    mov     x9, x23                 // start
.Ltk_int_scan:
    cmp     x23, x20
    b.ge    .Ltk_int_emit
    ldrb    w0, [x19, x23]
    cmp     w0, #'0'
    b.lo    .Ltk_int_emit
    cmp     w0, #'9'
    b.hi    .Ltk_int_emit
    add     x23, x23, #1
    b       .Ltk_int_scan
.Ltk_int_emit:
    mov     x0, #T_INT
    str     x0, [x21]
    add     x11, x19, x9
    str     x11, [x21, #8]
    add     x21, x21, #16
    add     x22, x22, #1
    b       .Ltk_loop

.Ltk_chk_punct:
    cmp     w24, #'*'
    b.eq    .Ltk_em_star
    cmp     w24, #'='
    b.eq    .Ltk_em_eq
    cmp     w24, #'('
    b.eq    .Ltk_em_lparen
    cmp     w24, #')'
    b.eq    .Ltk_em_rparen
    cmp     w24, #','
    b.eq    .Ltk_em_comma
    // Unknown: skip
    add     x23, x23, #1
    b       .Ltk_loop

.Ltk_em_star:
    mov     x0, #T_STAR
    b       .Ltk_em_punct
.Ltk_em_eq:
    mov     x0, #T_EQ
    b       .Ltk_em_punct
.Ltk_em_lparen:
    mov     x0, #T_LPAREN
    b       .Ltk_em_punct
.Ltk_em_rparen:
    mov     x0, #T_RPAREN
    b       .Ltk_em_punct
.Ltk_em_comma:
    mov     x0, #T_COMMA
.Ltk_em_punct:
    str     x0, [x21]
    add     x11, x19, x23
    str     x11, [x21, #8]
    add     x21, x21, #16
    add     x22, x22, #1
    add     x23, x23, #1
    b       .Ltk_loop

.Ltk_done:
    // Append EOF sentinel
    mov     x0, #T_EOF
    str     x0, [x21]
    str     xzr, [x21, #8]

    mov     x0, x22
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// ── tk_kind(x0=index) -> x0 = kind ──────────────────────────────
tk_kind:
    adrp    x1, tok_buf
    add     x1, x1, :lo12:tok_buf
    lsl     x0, x0, #4              // i * 16
    add     x1, x1, x0
    ldr     x0, [x1]
    ret

// ── _start: run all the SQL tokenizer tests ─────────────────────
_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: canonical SELECT (8 tokens) ─────────────────────
    adrp    x0, sql1
    add     x0, x0, :lo12:sql1
    bl      tokenize
    cmp     x0, #8
    b.ne    fail

    mov     x0, #0
    bl      tk_kind
    cmp     x0, #T_SELECT
    b.ne    fail
    mov     x0, #1
    bl      tk_kind
    cmp     x0, #T_STAR
    b.ne    fail
    mov     x0, #2
    bl      tk_kind
    cmp     x0, #T_FROM
    b.ne    fail
    mov     x0, #3
    bl      tk_kind
    cmp     x0, #T_IDENT
    b.ne    fail
    mov     x0, #4
    bl      tk_kind
    cmp     x0, #T_WHERE
    b.ne    fail
    mov     x0, #5
    bl      tk_kind
    cmp     x0, #T_IDENT
    b.ne    fail
    mov     x0, #6
    bl      tk_kind
    cmp     x0, #T_EQ
    b.ne    fail
    mov     x0, #7
    bl      tk_kind
    cmp     x0, #T_INT
    b.ne    fail

    // ── Test 2: lowercase keywords ──────────────────────────────
    adrp    x0, sql2
    add     x0, x0, :lo12:sql2
    bl      tokenize
    cmp     x0, #4
    b.ne    fail
    mov     x0, #0
    bl      tk_kind
    cmp     x0, #T_SELECT
    b.ne    fail
    mov     x0, #2
    bl      tk_kind
    cmp     x0, #T_FROM
    b.ne    fail

    // ── Test 3: 'selected' is identifier ────────────────────────
    adrp    x0, sql3
    add     x0, x0, :lo12:sql3
    bl      tokenize
    cmp     x0, #1
    b.ne    fail
    mov     x0, #0
    bl      tk_kind
    cmp     x0, #T_IDENT
    b.ne    fail

    // ── Test 4: integer literal ─────────────────────────────────
    adrp    x0, sql4
    add     x0, x0, :lo12:sql4
    bl      tokenize
    cmp     x0, #1
    b.ne    fail
    mov     x0, #0
    bl      tk_kind
    cmp     x0, #T_INT
    b.ne    fail

    // ── Print success ───────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    svc     #0

    ldp     x29, x30, [sp], #16
    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0
