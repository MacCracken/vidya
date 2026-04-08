# Vidya — Macro Systems in x86_64 Assembly
#
# GNU as (GAS) has its own macro system: .macro/.endm, .rept for
# repetition, .irp for iteration over a list, .if/.endif for
# conditional assembly, and .equ for named constants. These are
# assembler-time code generation — the macro expands before any
# machine code is emitted. This is the lowest-level macro system:
# textual substitution that produces instructions.

.intel_syntax noprefix
.global _start

# ── .equ: named constants (like #define for numbers) ───────────────
# These are assembler-time substitutions — no runtime cost.
.equ SYS_WRITE, 1
.equ SYS_EXIT, 60
.equ STDOUT, 1
.equ EXIT_SUCCESS, 0
.equ EXIT_FAILURE, 1

# ── .macro/.endm: define reusable instruction sequences ────────────
# Parameters are substituted at assembly time. This is the assembler's
# version of functions, but with zero call overhead — pure inlining.

# Macro: assert_eq reg, immediate — fail if not equal
.macro assert_eq reg, value
    cmp     \reg, \value
    jne     fail
.endm

# Macro: syscall_exit code — exit with given status
.macro syscall_exit code
    mov     rax, SYS_EXIT
    mov     rdi, \code
    syscall
.endm

# Macro: syscall_write fd, buf, len — write to file descriptor
.macro syscall_write fd, buf, len
    mov     rax, SYS_WRITE
    mov     rdi, \fd
    lea     rsi, [\buf]
    mov     rdx, \len
    syscall
.endm

# Macro: load_pair reg1, val1, reg2, val2 — load two registers
.macro load_pair reg1, val1, reg2, val2
    mov     \reg1, \val1
    mov     \reg2, \val2
.endm

.section .rodata
msg_pass:   .ascii "All macro systems examples passed.\n"
msg_len = . - msg_pass

.section .data

# ── .rept: repeat a block N times ──────────────────────────────────
# Generates N copies of the enclosed instructions.
# Here we build a lookup table of squares: 0, 1, 4, 9, 16, ...
.align 4
squares_table:
.set _i, 0
.rept 8
    .long _i * _i
    .set _i, _i + 1
.endr
squares_count = 8

# ── .irp: iterate over a list ─────────────────────────────────────
# Generates one copy per list element. Here we build a table of
# specific values.
.align 4
primes_table:
.irp val, 2, 3, 5, 7, 11, 13
    .long \val
.endr
primes_count = 6

.section .text

_start:
    # ── Test .equ constants ────────────────────────────────────────
    # Verify constants are substituted correctly
    mov     eax, SYS_EXIT
    assert_eq eax, 60

    mov     eax, SYS_WRITE
    assert_eq eax, 1

    # ── Test .macro: assert_eq itself ──────────────────────────────
    mov     eax, 42
    assert_eq eax, 42

    mov     eax, 0
    assert_eq eax, 0

    # ── Test .macro: load_pair ─────────────────────────────────────
    load_pair eax, 100, ecx, 200
    assert_eq eax, 100
    assert_eq ecx, 200

    # ── Test .rept: squares table ──────────────────────────────────
    # Verify the table built by .rept contains correct squares
    lea     rsi, [squares_table]
    mov     eax, dword ptr [rsi + 0*4]      # 0^2 = 0
    assert_eq eax, 0

    mov     eax, dword ptr [rsi + 1*4]      # 1^2 = 1
    assert_eq eax, 1

    mov     eax, dword ptr [rsi + 2*4]      # 2^2 = 4
    assert_eq eax, 4

    mov     eax, dword ptr [rsi + 3*4]      # 3^2 = 9
    assert_eq eax, 9

    mov     eax, dword ptr [rsi + 4*4]      # 4^2 = 16
    assert_eq eax, 16

    mov     eax, dword ptr [rsi + 7*4]      # 7^2 = 49
    assert_eq eax, 49

    # ── Test .irp: primes table ────────────────────────────────────
    lea     rsi, [primes_table]
    mov     eax, dword ptr [rsi + 0*4]
    assert_eq eax, 2

    mov     eax, dword ptr [rsi + 1*4]
    assert_eq eax, 3

    mov     eax, dword ptr [rsi + 2*4]
    assert_eq eax, 5

    mov     eax, dword ptr [rsi + 3*4]
    assert_eq eax, 7

    mov     eax, dword ptr [rsi + 4*4]
    assert_eq eax, 11

    mov     eax, dword ptr [rsi + 5*4]
    assert_eq eax, 13

    # ── Test .if/.endif: conditional assembly ──────────────────────
    # The .if block below generates code only if the condition is true.
    # This is compile-time branching — no runtime cost.

.equ FEATURE_EXTRA_CHECK, 1

.if FEATURE_EXTRA_CHECK
    # This code is assembled because FEATURE_EXTRA_CHECK == 1
    mov     eax, 999
    assert_eq eax, 999
.endif

.equ FEATURE_DISABLED, 0

.if FEATURE_DISABLED
    # This code is NOT assembled — skipped entirely by the assembler.
    # If it were included it would fail.
    jmp     fail
.endif

    # ── Test nested macro usage ────────────────────────────────────
    # Macros can invoke other macros — composition at assembly time.
    load_pair eax, 7, ecx, 7
    assert_eq eax, 7
    assert_eq ecx, 7

    # ── Verify .rept-generated table via loop ──────────────────────
    # Walk the squares table and verify each entry programmatically
    lea     rsi, [squares_table]
    xor     ecx, ecx            # index = 0
.verify_squares:
    cmp     ecx, squares_count
    jge     .squares_ok
    mov     eax, ecx
    imul    eax, ecx            # expected = index * index
    cmp     eax, dword ptr [rsi + rcx*4]
    jne     fail
    inc     ecx
    jmp     .verify_squares
.squares_ok:

    # ── Print success using macro ──────────────────────────────────
    syscall_write STDOUT, msg_pass, msg_len

    # ── Exit using macro ───────────────────────────────────────────
    syscall_exit EXIT_SUCCESS

fail:
    syscall_exit EXIT_FAILURE
