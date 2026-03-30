// Vidya — Pattern Matching in AArch64 Assembly
//
// AArch64 matching uses CMP+B.cond chains, TBZ/TBNZ (test bit and
// branch), CSEL/CSINC (conditional select), and branch tables via
// ADR+BR. The conditional execution model is flag-based, not
// predicated (unlike ARMv7's IT blocks).

.global _start

.section .rodata
msg_pass:   .ascii "All pattern matching examples passed.\n"
msg_len = . - msg_pass

// Branch table
.align 3
branch_table:
    .quad .Lcase_0
    .quad .Lcase_1
    .quad .Lcase_2
    .quad .Lcase_3
bt_size = 4

.section .text

_start:
    // ── Compare chain (if-else) ────────────────────────────────────
    mov     w0, #-5
    bl      classify_number
    cmp     w0, #1              // negative
    b.ne    fail

    mov     w0, #0
    bl      classify_number
    cmp     w0, #2              // zero
    b.ne    fail

    mov     w0, #7
    bl      classify_number
    cmp     w0, #3              // small
    b.ne    fail

    mov     w0, #100
    bl      classify_number
    cmp     w0, #4              // large
    b.ne    fail

    // ── Branch table dispatch ──────────────────────────────────────
    mov     w0, #0
    bl      dispatch_table
    cmp     w0, #10
    b.ne    fail

    mov     w0, #2
    bl      dispatch_table
    cmp     w0, #30
    b.ne    fail

    mov     w0, #99
    bl      dispatch_table
    cmn     w0, #1              // -1 = default
    b.ne    fail

    // ── Character classification ───────────────────────────────────
    mov     w0, #'5'
    bl      classify_char
    cmp     w0, #1              // digit
    b.ne    fail

    mov     w0, #'a'
    bl      classify_char
    cmp     w0, #2              // lowercase
    b.ne    fail

    mov     w0, #'Z'
    bl      classify_char
    cmp     w0, #3              // uppercase
    b.ne    fail

    mov     w0, #'@'
    bl      classify_char
    cmp     w0, #0              // other
    b.ne    fail

    // ── CSEL: branchless select ────────────────────────────────────
    mov     w0, #42
    mov     w1, #99
    cmp     w0, #50
    csel    w2, w1, w0, lt      // w2 = w1 if 42<50, else w0
    cmp     w2, #99
    b.ne    fail

    mov     w0, #100
    mov     w1, #0
    cmp     w0, #50
    csel    w2, w1, w0, lt      // w2 = w1 if 100<50 (false), else w0
    cmp     w2, #100
    b.ne    fail

    // ── TBZ/TBNZ: test single bit and branch ──────────────────────
    // Test bit 0 to check even/odd
    mov     w0, #4
    tbz     w0, #0, .Leven      // branch if bit 0 is zero (even)
    b       fail
.Leven:

    mov     w0, #7
    tbnz    w0, #0, .Lodd      // branch if bit 0 is set (odd)
    b       fail
.Lodd:

    // ── CSINC: conditional increment ───────────────────────────────
    // Useful for boolean results: w0 = (condition) ? 0 : 1
    mov     w0, #5
    cmp     w0, #10
    csinc   w1, wzr, wzr, ge    // w1 = 0 if 5>=10 (false), else 0+1=1
    cmp     w1, #1              // 5 < 10, so w1 = 1
    b.ne    fail

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// classify_number: w0 -> w0 (1=neg, 2=zero, 3=small, 4=large)
classify_number:
    cmp     w0, #0
    b.lt    .Lcn_neg
    b.eq    .Lcn_zero
    cmp     w0, #10
    b.le    .Lcn_small
    mov     w0, #4
    ret
.Lcn_neg:
    mov     w0, #1
    ret
.Lcn_zero:
    mov     w0, #2
    ret
.Lcn_small:
    mov     w0, #3
    ret

// dispatch_table: w0 = index -> w0 = result
dispatch_table:
    cmp     w0, bt_size
    b.ge    .Ldt_default
    adr     x1, branch_table
    ldr     x1, [x1, w0, uxtw #3]
    br      x1
.Lcase_0:
    mov     w0, #10
    ret
.Lcase_1:
    mov     w0, #20
    ret
.Lcase_2:
    mov     w0, #30
    ret
.Lcase_3:
    mov     w0, #40
    ret
.Ldt_default:
    mov     w0, #-1
    ret

// classify_char: w0 = ascii -> w0 (0=other, 1=digit, 2=lower, 3=upper)
classify_char:
    cmp     w0, #'0'
    b.lo    .Lcc_upper
    cmp     w0, #'9'
    b.ls    .Lcc_digit
.Lcc_upper:
    cmp     w0, #'A'
    b.lo    .Lcc_lower
    cmp     w0, #'Z'
    b.ls    .Lcc_up_ret
.Lcc_lower:
    cmp     w0, #'a'
    b.lo    .Lcc_other
    cmp     w0, #'z'
    b.ls    .Lcc_lo_ret
.Lcc_other:
    mov     w0, #0
    ret
.Lcc_digit:
    mov     w0, #1
    ret
.Lcc_lo_ret:
    mov     w0, #2
    ret
.Lcc_up_ret:
    mov     w0, #3
    ret
