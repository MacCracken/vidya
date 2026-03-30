// Vidya — Error Handling in AArch64 Assembly
//
// AArch64 error handling uses return values in registers and condition
// flags. System calls return negative values on error in x0. Functions
// follow the AAPCS64 calling convention: x0 for return value, condition
// flags for boolean outcomes.

.global _start

.section .rodata
msg_pass:   .ascii "All error handling examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Syscall error checking ─────────────────────────────────────
    // sys_write to stdout (should succeed)
    mov     x8, #64             // sys_write
    mov     x0, #1              // fd = stdout
    adr     x1, msg_pass
    mov     x2, #1              // write 1 byte
    svc     #0
    cmp     x0, #1              // should return 1
    b.ne    fail

    // sys_write to invalid fd (should fail)
    mov     x8, #64
    mov     x0, #999            // invalid fd
    adr     x1, msg_pass
    mov     x2, #1
    svc     #0
    cmn     x0, #9              // -EBADF = -9, cmn adds: x0 + 9 == 0?
    b.ne    fail

    // ── Function return codes ──────────────────────────────────────
    // safe_divide: x0=dividend, x1=divisor -> x0=result, x1=error
    mov     x0, #42
    mov     x1, #2
    bl      safe_divide
    cbnz    w1, fail            // error flag should be 0
    cmp     x0, #21             // 42 / 2 = 21
    b.ne    fail

    // Division by zero
    mov     x0, #42
    mov     x1, #0
    bl      safe_divide
    cbz     w1, fail            // error flag should be nonzero

    // ── Bounds checking ────────────────────────────────────────────
    mov     x0, #3              // index
    mov     x1, #10             // length
    bl      check_bounds
    cbnz    w0, fail            // should be in bounds (0)

    mov     x0, #15             // out of bounds
    mov     x1, #10
    bl      check_bounds
    cbz     w0, fail            // should be out of bounds (1)

    // ── Flags-based error: subtraction overflow ────────────────────
    mov     x0, #100
    mov     x1, #50
    subs    x0, x0, x1          // 100 - 50, sets flags
    b.lo    fail                // carry clear = no underflow, good

    mov     x0, #50
    mov     x1, #100
    subs    x0, x0, x1          // 50 - 100, sets flags
    b.hs    fail                // carry set = underflow expected

    // ── Conditional select for error handling ──────────────────────
    // CSEL: branchless error result selection
    mov     x0, #42
    mov     x1, #-1             // error sentinel
    cmp     x0, #0
    csel    x2, x0, x1, gt     // x2 = x0 if > 0, else x1
    cmp     x2, #42
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

// safe_divide: x0/x1 -> x0=quotient, x1=0(ok) or 1(error)
safe_divide:
    cbz     x1, .Ldiv_err
    udiv    x0, x0, x1
    mov     x1, #0
    ret
.Ldiv_err:
    mov     x0, #0
    mov     x1, #1
    ret

// check_bounds: is x0 < x1?
// returns w0 = 0 (in bounds) or 1 (out of bounds)
check_bounds:
    cmp     x0, x1
    cset    w0, hs              // w0 = 1 if x0 >= x1 (out of bounds)
    ret
