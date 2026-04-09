// Vidya — Macro Systems in AArch64 Assembly
//
// GNU as (GAS) has its own macro system: .macro/.endm for reusable
// instruction sequences, .rept for repetition, .irp for iteration
// over a list, .if/.endif for conditional assembly, and .equ for
// named constants. These expand at assembly time — zero runtime cost.
// This is the lowest-level macro system: textual substitution that
// produces instructions.

.global _start

// ── .equ: named constants (like #define for numbers) ────────────────
// Assembler-time substitutions — no runtime cost.
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93
.equ STDOUT, 1
.equ EXIT_SUCCESS, 0
.equ EXIT_FAILURE, 1

// ── .macro/.endm: reusable instruction sequences ────────────────────
// Parameters are substituted at assembly time. Pure inlining.

// Macro: assert_eq reg, immediate — fail if not equal
.macro assert_eq reg, value
    cmp     \reg, \value
    b.ne    fail
.endm

// Macro: syscall_exit code — exit with given status
.macro syscall_exit code
    mov     x8, #SYS_EXIT
    mov     x0, \code
    svc     #0
.endm

// Macro: syscall_write fd, buf, len — write to file descriptor
.macro syscall_write fd, buf, len
    mov     x8, #SYS_WRITE
    mov     x0, \fd
    adr     x1, \buf
    mov     x2, \len
    svc     #0
.endm

// Macro: load_pair reg1, val1, reg2, val2 — load two registers
.macro load_pair reg1, val1, reg2, val2
    mov     \reg1, \val1
    mov     \reg2, \val2
.endm

.section .rodata
msg_pass:   .ascii "All macro systems examples passed.\n"
msg_len = . - msg_pass

.section .data

// ── .rept: repeat a block N times ───────────────────────────────────
// Generates N copies of the enclosed instructions/data.
// Build a lookup table of squares: 0, 1, 4, 9, 16, ...
.align 2
squares_table:
.set _i, 0
.rept 8
    .word _i * _i
    .set _i, _i + 1
.endr
squares_count = 8

// ── .irp: iterate over a list ───────────────────────────────────────
// Generates one copy per list element.
.align 2
primes_table:
.irp val, 2, 3, 5, 7, 11, 13
    .word \val
.endr
primes_count = 6

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test .equ constants ─────────────────────────────────────────
    mov     w0, SYS_EXIT
    assert_eq w0, #93

    mov     w0, SYS_WRITE
    assert_eq w0, #64

    // ── Test .macro: assert_eq itself ───────────────────────────────
    mov     w0, #42
    assert_eq w0, #42

    mov     w0, #0
    assert_eq w0, #0

    // ── Test .macro: load_pair ──────────────────────────────────────
    load_pair w0, #100, w1, #200
    assert_eq w0, #100
    assert_eq w1, #200

    // ── Test .rept: squares table ───────────────────────────────────
    adr     x5, squares_table

    ldr     w0, [x5, #0]           // 0^2 = 0
    assert_eq w0, #0

    ldr     w0, [x5, #4]           // 1^2 = 1
    assert_eq w0, #1

    ldr     w0, [x5, #8]           // 2^2 = 4
    assert_eq w0, #4

    ldr     w0, [x5, #12]          // 3^2 = 9
    assert_eq w0, #9

    ldr     w0, [x5, #16]          // 4^2 = 16
    assert_eq w0, #16

    ldr     w0, [x5, #28]          // 7^2 = 49
    assert_eq w0, #49

    // ── Test .irp: primes table ─────────────────────────────────────
    adr     x5, primes_table

    ldr     w0, [x5, #0]
    assert_eq w0, #2

    ldr     w0, [x5, #4]
    assert_eq w0, #3

    ldr     w0, [x5, #8]
    assert_eq w0, #5

    ldr     w0, [x5, #12]
    assert_eq w0, #7

    ldr     w0, [x5, #16]
    assert_eq w0, #11

    ldr     w0, [x5, #20]
    assert_eq w0, #13

    // ── Test .if/.endif: conditional assembly ────────────────────────
    // The .if block generates code only when the condition is true.
    // Assembly-time branching — zero runtime cost.

.equ FEATURE_EXTRA_CHECK, 1

.if FEATURE_EXTRA_CHECK
    // This code is assembled because FEATURE_EXTRA_CHECK == 1
    mov     w0, #999
    assert_eq w0, #999
.endif

.equ FEATURE_DISABLED, 0

.if FEATURE_DISABLED
    // NOT assembled — skipped entirely by the assembler.
    b       fail
.endif

    // ── Test nested macro usage ─────────────────────────────────────
    // Macros can invoke other macros — composition at assembly time.
    load_pair w0, #7, w1, #7
    assert_eq w0, #7
    assert_eq w1, #7

    // ── Verify .rept-generated table via loop ───────────────────────
    // Walk the squares table and verify each entry programmatically
    adr     x5, squares_table
    mov     w6, #0                  // index = 0
.Lverify_squares:
    cmp     w6, squares_count
    b.ge    .Lsquares_ok
    mul     w0, w6, w6             // expected = index * index
    ldr     w1, [x5, w6, uxtw #2] // actual = table[index]
    cmp     w0, w1
    b.ne    fail
    add     w6, w6, #1
    b       .Lverify_squares
.Lsquares_ok:

    // ── Test macro with computed values ──────────────────────────────
    // Show that macro parameters can be registers with computed values
    mov     w0, #10
    add     w0, w0, #5             // w0 = 15
    mov     w1, #3
    mul     w1, w1, w1             // w1 = 9
    load_pair w2, w0, w3, w1
    assert_eq w2, #15
    assert_eq w3, #9

    // ── Print success using macro ───────────────────────────────────
    syscall_write #STDOUT, msg_pass, msg_len

    // ── Exit using macro ────────────────────────────────────────────
    ldp     x29, x30, [sp], #16
    syscall_exit #EXIT_SUCCESS

fail:
    syscall_exit #EXIT_FAILURE
