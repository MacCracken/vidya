// Vidya — Testing in AArch64 Assembly
//
// Same pattern as x86_64: compare expected vs actual, branch on
// mismatch. AArch64's CSINC instruction makes pass/fail counting
// branchless. CBZ/CBNZ simplify zero-checks.

.global _start

.section .data
tests_run:      .word 0
tests_passed:   .word 0

.section .rodata
msg_pass:   .ascii "All testing examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Test: addition ─────────────────────────────────────────────
    mov     w0, #3
    mov     w1, #4
    add     w0, w0, w1
    mov     w1, #7
    bl      check_eq

    // ── Test: subtraction ──────────────────────────────────────────
    mov     w0, #10
    mov     w1, #3
    sub     w0, w0, w1
    mov     w1, #7
    bl      check_eq

    // ── Test: multiply ─────────────────────────────────────────────
    mov     w0, #6
    mov     w1, #7
    mul     w0, w0, w1
    mov     w1, #42
    bl      check_eq

    // ── Test: clamp in range ───────────────────────────────────────
    mov     w0, #5
    mov     w1, #0
    mov     w2, #10
    bl      clamp
    mov     w1, #5
    bl      check_eq

    // ── Test: clamp below min ──────────────────────────────────────
    mov     w0, #-5
    mov     w1, #0
    mov     w2, #10
    bl      clamp
    mov     w1, #0
    bl      check_eq

    // ── Test: clamp above max ──────────────────────────────────────
    mov     w0, #100
    mov     w1, #0
    mov     w2, #10
    bl      clamp
    mov     w1, #10
    bl      check_eq

    // ── Test: abs positive ─────────────────────────────────────────
    mov     w0, #42
    bl      abs_int
    mov     w1, #42
    bl      check_eq

    // ── Test: abs negative ─────────────────────────────────────────
    mov     w0, #-42
    bl      abs_int
    mov     w1, #42
    bl      check_eq

    // ── Test: abs zero ─────────────────────────────────────────────
    mov     w0, #0
    bl      abs_int
    mov     w1, #0
    bl      check_eq

    // ── Test: is_even ──────────────────────────────────────────────
    mov     w0, #4
    bl      is_even
    mov     w1, #1
    bl      check_eq

    mov     w0, #7
    bl      is_even
    mov     w1, #0
    bl      check_eq

    // ── Test: max ──────────────────────────────────────────────────
    mov     w0, #3
    mov     w1, #7
    bl      max_int
    mov     w1, #7
    bl      check_eq

    mov     w0, #10
    mov     w1, #2
    bl      max_int
    mov     w1, #10
    bl      check_eq

    // ── Verify all passed ──────────────────────────────────────────
    adr     x0, tests_run
    ldr     w1, [x0]
    adr     x0, tests_passed
    ldr     w2, [x0]
    cmp     w1, w2
    b.ne    test_failure

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

test_failure:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// check_eq: w0=got, w1=expected
check_eq:
    adr     x2, tests_run
    ldr     w3, [x2]
    add     w3, w3, #1
    str     w3, [x2]

    cmp     w0, w1
    b.ne    .Lce_fail
    adr     x2, tests_passed
    ldr     w3, [x2]
    add     w3, w3, #1
    str     w3, [x2]
.Lce_fail:
    ret

// clamp(value=w0, min=w1, max=w2) -> w0
clamp:
    cmp     w0, w1
    csel    w0, w1, w0, lt      // if value < min, value = min
    cmp     w0, w2
    csel    w0, w2, w0, gt      // if value > max, value = max
    ret

// abs_int(w0) -> w0
abs_int:
    cmp     w0, #0
    cneg    w0, w0, lt          // negate if negative
    ret

// is_even(w0) -> w0 (1=true, 0=false)
is_even:
    tst     w0, #1
    cset    w0, eq              // w0 = 1 if bit0==0 (even)
    ret

// max_int(w0, w1) -> w0
max_int:
    cmp     w0, w1
    csel    w0, w0, w1, ge
    ret
