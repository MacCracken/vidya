// Vidya — Lexing and Parsing in AArch64 Assembly
//
// Character classification and number parsing at the machine level.
// LDRB loads a single byte, CMP classifies it. A lexer walks bytes
// one at a time: is it a digit? a letter? whitespace? punctuation?
// Parsing a number from a string is repeated: result = result*10 + digit.

.global _start

.section .rodata
msg_pass:   .ascii "All lexing and parsing examples passed.\n"
msg_len = . - msg_pass

// Test strings
str_number:     .ascii "12345"
str_number_len = . - str_number

str_mixed:      .ascii "abc 42\n"
str_mixed_len = . - str_mixed

str_zero:       .ascii "0"
str_zero_len = . - str_zero

str_255:        .ascii "255"
str_255_len = . - str_255

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: classify digit '5' ──────────────────────────────────
    mov     w0, #'5'
    bl      is_digit
    cmp     w0, #1
    b.ne    fail

    // ── Test 2: classify non-digit 'A' ──────────────────────────────
    mov     w0, #'A'
    bl      is_digit
    cmp     w0, #0
    b.ne    fail

    // ── Test 3: classify alpha 'z' ──────────────────────────────────
    mov     w0, #'z'
    bl      is_alpha
    cmp     w0, #1
    b.ne    fail

    // ── Test 4: classify alpha 'A' ──────────────────────────────────
    mov     w0, #'A'
    bl      is_alpha
    cmp     w0, #1
    b.ne    fail

    // ── Test 5: classify non-alpha '9' ──────────────────────────────
    mov     w0, #'9'
    bl      is_alpha
    cmp     w0, #0
    b.ne    fail

    // ── Test 6: classify whitespace ' ' ─────────────────────────────
    mov     w0, #' '
    bl      is_whitespace
    cmp     w0, #1
    b.ne    fail

    // ── Test 7: classify whitespace '\n' ────────────────────────────
    mov     w0, #'\n'
    bl      is_whitespace
    cmp     w0, #1
    b.ne    fail

    // ── Test 8: classify non-whitespace 'x' ─────────────────────────
    mov     w0, #'x'
    bl      is_whitespace
    cmp     w0, #0
    b.ne    fail

    // ── Test 9: parse number "12345" ────────────────────────────────
    adr     x0, str_number
    mov     w1, str_number_len
    bl      parse_number
    mov     w2, #12345
    cmp     w0, w2
    b.ne    fail

    // ── Test 10: parse number "0" ───────────────────────────────────
    adr     x0, str_zero
    mov     w1, str_zero_len
    bl      parse_number
    cmp     w0, #0
    b.ne    fail

    // ── Test 11: parse number "255" ─────────────────────────────────
    adr     x0, str_255
    mov     w1, str_255_len
    bl      parse_number
    cmp     w0, #255
    b.ne    fail

    // ── Test 12: count digits in "abc 42\n" ─────────────────────────
    adr     x0, str_mixed
    mov     w1, str_mixed_len
    bl      count_digits
    cmp     w0, #2                  // '4' and '2'
    b.ne    fail

    // ── Test 13: count alpha in "abc 42\n" ──────────────────────────
    adr     x0, str_mixed
    mov     w1, str_mixed_len
    bl      count_alpha
    cmp     w0, #3                  // 'a', 'b', 'c'
    b.ne    fail

    // ── Test 14: skip whitespace ────────────────────────────────────
    // "abc 42\n" — skip from index 3 (space) should land on '4'
    adr     x0, str_mixed
    add     x0, x0, #3             // point to ' '
    mov     w1, #4                  // remaining length
    bl      skip_whitespace
    ldrb    w2, [x0]               // should be '4'
    cmp     w2, #'4'
    b.ne    fail

    // ── Print success ────────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    ldp     x29, x30, [sp], #16
    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── is_digit(w0=char) -> w0=1 if '0'-'9', else 0 ───────────────────
is_digit:
    sub     w1, w0, #'0'           // w1 = char - '0'
    cmp     w1, #9                 // unsigned compare: 0..9
    cset    w0, ls                 // w0 = 1 if w1 <= 9
    ret

// ── is_alpha(w0=char) -> w0=1 if letter, else 0 ────────────────────
// Check both ranges: 'A'-'Z' (65-90) and 'a'-'z' (97-122)
is_alpha:
    orr     w1, w0, #0x20          // lowercase: 'A'|0x20 = 'a'
    sub     w1, w1, #'a'           // w1 = lowered - 'a'
    cmp     w1, #25                // 0..25 = valid letter
    cset    w0, ls
    ret

// ── is_whitespace(w0=char) -> w0=1 if space/tab/newline/cr ──────────
is_whitespace:
    cmp     w0, #' '
    b.eq    .Lws_yes
    cmp     w0, #'\t'
    b.eq    .Lws_yes
    cmp     w0, #'\n'
    b.eq    .Lws_yes
    cmp     w0, #'\r'
    b.eq    .Lws_yes
    mov     w0, #0
    ret
.Lws_yes:
    mov     w0, #1
    ret

// ── parse_number(x0=str, w1=len) -> w0=value ───────────────────────
// result = 0; for each digit: result = result * 10 + (ch - '0')
parse_number:
    mov     w2, #0                  // result = 0
    mov     w5, #10
.Lparse_loop:
    cbz     w1, .Lparse_done
    ldrb    w3, [x0], #1           // load byte, advance pointer
    sub     w3, w3, #'0'           // convert ASCII to digit
    mul     w2, w2, w5             // result *= 10
    add     w2, w2, w3             // result += digit
    sub     w1, w1, #1
    b       .Lparse_loop
.Lparse_done:
    mov     w0, w2
    ret

// ── count_digits(x0=str, w1=len) -> w0=count ───────────────────────
count_digits:
    stp     x29, x30, [sp, #-16]!
    mov     w4, #0                  // count
    mov     x2, x0                 // save str ptr
    mov     w3, w1                 // save len
.Lcd_loop:
    cbz     w3, .Lcd_done
    ldrb    w0, [x2], #1
    sub     w3, w3, #1
    sub     w5, w0, #'0'
    cmp     w5, #9
    b.hi    .Lcd_loop              // not a digit
    add     w4, w4, #1
    b       .Lcd_loop
.Lcd_done:
    mov     w0, w4
    ldp     x29, x30, [sp], #16
    ret

// ── count_alpha(x0=str, w1=len) -> w0=count ────────────────────────
count_alpha:
    stp     x29, x30, [sp, #-16]!
    mov     w4, #0
    mov     x2, x0
    mov     w3, w1
.Lca_loop:
    cbz     w3, .Lca_done
    ldrb    w0, [x2], #1
    sub     w3, w3, #1
    orr     w5, w0, #0x20          // lowercase
    sub     w5, w5, #'a'
    cmp     w5, #25
    b.hi    .Lca_loop
    add     w4, w4, #1
    b       .Lca_loop
.Lca_done:
    mov     w0, w4
    ldp     x29, x30, [sp], #16
    ret

// ── skip_whitespace(x0=ptr, w1=remaining) -> x0=new_ptr ────────────
skip_whitespace:
.Lsw_loop:
    cbz     w1, .Lsw_done
    ldrb    w2, [x0]
    cmp     w2, #' '
    b.eq    .Lsw_skip
    cmp     w2, #'\t'
    b.eq    .Lsw_skip
    cmp     w2, #'\n'
    b.eq    .Lsw_skip
    b       .Lsw_done
.Lsw_skip:
    add     x0, x0, #1
    sub     w1, w1, #1
    b       .Lsw_loop
.Lsw_done:
    ret
