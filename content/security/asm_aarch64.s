// Vidya — Security Practices in AArch64 Assembly
//
// AArch64 security primitives: constant-time comparison (no data-
// dependent branches), secure memory zeroing (no compiler elision),
// bounds-checked copy, and input validation. These are the building
// blocks for higher-level cryptographic and security functions.

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
    // ── Test 1: constant-time comparison (equal) ──────────────────────
    adr     x0, secret_a
    adr     x1, secret_b
    mov     x2, secret_len
    bl      constant_time_eq
    cbz     w0, fail                // should be equal (w0=1)

    // ── Test 2: constant-time comparison (different) ──────────────────
    adr     x0, secret_a
    adr     x1, secret_c
    mov     x2, secret_len
    bl      constant_time_eq
    cbnz    w0, fail                // should NOT be equal (w0=0)

    // ── Test 3: constant-time comparison (empty) ──────────────────────
    adr     x0, secret_a
    adr     x1, secret_a
    mov     x2, #0
    bl      constant_time_eq
    cbz     w0, fail                // empty == empty (w0=1)

    // ── Test 4: secure memory zeroing ─────────────────────────────────
    // Fill with 0xAA pattern
    adr     x0, zero_buf
    mov     w1, #0xAA
    mov     x2, #32
fill_pattern:
    strb    w1, [x0], #1
    subs    x2, x2, #1
    b.ne    fill_pattern

    // Verify 0xAA pattern
    adr     x0, zero_buf
    mov     x2, #32
verify_aa:
    ldrb    w3, [x0], #1
    cmp     w3, #0xAA
    b.ne    fail
    subs    x2, x2, #1
    b.ne    verify_aa

    // Secure zero the buffer
    adr     x0, zero_buf
    mov     x1, #32
    bl      secure_zero

    // Verify all zeros
    adr     x0, zero_buf
    mov     x2, #32
verify_zero:
    ldrb    w3, [x0], #1
    cbnz    w3, fail
    subs    x2, x2, #1
    b.ne    verify_zero

    // ── Test 5: bounds-checked copy ───────────────────────────────────
    adr     x0, scratch             // dst
    mov     x1, #64                 // dst_size
    adr     x2, secret_a            // src
    mov     x3, secret_len          // src_len
    bl      safe_copy
    cbnz    w0, fail                // should succeed (0)

    // Verify copied content
    adr     x0, scratch
    adr     x1, secret_a
    mov     x2, secret_len
    bl      constant_time_eq
    cbz     w0, fail                // should match

    // Overflow: src_len > dst_size
    adr     x0, scratch
    mov     x1, #4                  // dst_size too small
    adr     x2, secret_a
    mov     x3, secret_len
    bl      safe_copy
    cmn     w0, #1                  // compare with -1
    b.ne    fail                    // should return -1

    // ── Test 6: input validation ──────────────────────────────────────
    adr     x0, secret_a
    mov     x1, secret_len
    bl      validate_alnum
    cbz     w0, fail                // "secret_token_24" is valid

    // ── All passed ────────────────────────────────────────────────────
    mov     x8, #64                 // sys_write
    mov     x0, #1                  // stdout
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93                 // sys_exit
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── constant_time_eq(x0=a, x1=b, x2=len) → w0 (1=equal, 0=not) ──
// No data-dependent branches. Only loop counter drives control flow.
constant_time_eq:
    mov     w3, #0                  // accumulator
    cbz     x2, .cte_done
    mov     x4, #0                  // index
.cte_loop:
    ldrb    w5, [x0, x4]
    ldrb    w6, [x1, x4]
    eor     w5, w5, w6
    orr     w3, w3, w5
    add     x4, x4, #1
    cmp     x4, x2
    b.lo    .cte_loop
.cte_done:
    cmp     w3, #0
    cset    w0, eq                  // w0 = 1 if equal, 0 if not
    ret

// ── secure_zero(x0=buf, x1=len) ──────────────────────────────────────
// Byte-by-byte zero. Cannot be elided by any compiler.
secure_zero:
    cbz     x1, .sz_done
    mov     x2, #0
.sz_loop:
    strb    wzr, [x0, x2]
    add     x2, x2, #1
    cmp     x2, x1
    b.lo    .sz_loop
.sz_done:
    ret

// ── safe_copy(x0=dst, x1=dst_size, x2=src, x3=src_len) → w0 ─────
// Returns 0 on success, -1 if src_len > dst_size.
safe_copy:
    cmp     x3, x1
    b.hi    .sc_overflow
    mov     x4, #0
.sc_loop:
    cmp     x4, x3
    b.hs    .sc_done
    ldrb    w5, [x2, x4]
    strb    w5, [x0, x4]
    add     x4, x4, #1
    b       .sc_loop
.sc_done:
    mov     w0, #0
    ret
.sc_overflow:
    mov     w0, #-1
    ret

// ── validate_alnum(x0=buf, x1=len) → w0 (1=valid, 0=invalid) ────
// Checks each byte is [a-zA-Z0-9_]
validate_alnum:
    cbz     x1, .va_invalid         // empty = invalid
    mov     x2, #0
.va_loop:
    ldrb    w3, [x0, x2]
    // Check a-z
    cmp     w3, #'a'
    b.lo    .va_not_lower
    cmp     w3, #'z'
    b.ls    .va_next
.va_not_lower:
    // Check A-Z
    cmp     w3, #'A'
    b.lo    .va_not_upper
    cmp     w3, #'Z'
    b.ls    .va_next
.va_not_upper:
    // Check 0-9
    cmp     w3, #'0'
    b.lo    .va_not_digit
    cmp     w3, #'9'
    b.ls    .va_next
.va_not_digit:
    // Check underscore
    cmp     w3, #'_'
    b.ne    .va_invalid
.va_next:
    add     x2, x2, #1
    cmp     x2, x1
    b.lo    .va_loop
    mov     w0, #1
    ret
.va_invalid:
    mov     w0, #0
    ret
