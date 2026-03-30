# Vidya — Testing in x86_64 Assembly
#
# Assembly testing is manual: compare expected vs actual in registers
# or memory, branch to failure on mismatch. There's no assert macro
# or test framework — every check is an explicit cmp + jcc pair.
# This file demonstrates a structured testing pattern with pass/fail
# counting.

.intel_syntax noprefix
.global _start

.section .data
tests_run:      .long 0
tests_passed:   .long 0

.section .rodata
msg_pass:   .ascii "All testing examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Test: addition ──────────────────────────────────────────────
    mov     edi, 3
    mov     esi, 4
    call    add_ints
    mov     edi, eax
    mov     esi, 7
    call    check_eq            # expect 3+4 = 7

    # ── Test: subtraction ───────────────────────────────────────────
    mov     edi, 10
    mov     esi, 3
    call    sub_ints
    mov     edi, eax
    mov     esi, 7
    call    check_eq            # expect 10-3 = 7

    # ── Test: multiply ──────────────────────────────────────────────
    mov     edi, 6
    mov     esi, 7
    call    mul_ints
    mov     edi, eax
    mov     esi, 42
    call    check_eq            # expect 6*7 = 42

    # ── Test: clamp in range ────────────────────────────────────────
    mov     edi, 5              # value
    mov     esi, 0              # min
    mov     edx, 10             # max
    call    clamp
    mov     edi, eax
    mov     esi, 5
    call    check_eq

    # ── Test: clamp below min ───────────────────────────────────────
    mov     edi, -5
    mov     esi, 0
    mov     edx, 10
    call    clamp
    mov     edi, eax
    mov     esi, 0
    call    check_eq

    # ── Test: clamp above max ───────────────────────────────────────
    mov     edi, 100
    mov     esi, 0
    mov     edx, 10
    call    clamp
    mov     edi, eax
    mov     esi, 10
    call    check_eq

    # ── Test: abs positive ──────────────────────────────────────────
    mov     edi, 42
    call    abs_int
    mov     edi, eax
    mov     esi, 42
    call    check_eq

    # ── Test: abs negative ──────────────────────────────────────────
    mov     edi, -42
    call    abs_int
    mov     edi, eax
    mov     esi, 42
    call    check_eq

    # ── Test: abs zero ──────────────────────────────────────────────
    mov     edi, 0
    call    abs_int
    mov     edi, eax
    mov     esi, 0
    call    check_eq

    # ── Test: is_even ───────────────────────────────────────────────
    mov     edi, 4
    call    is_even
    mov     edi, eax
    mov     esi, 1              # true
    call    check_eq

    mov     edi, 7
    call    is_even
    mov     edi, eax
    mov     esi, 0              # false
    call    check_eq

    # ── Test: max ───────────────────────────────────────────────────
    mov     edi, 3
    mov     esi, 7
    call    max_int
    mov     edi, eax
    mov     esi, 7
    call    check_eq

    mov     edi, 10
    mov     esi, 2
    call    max_int
    mov     edi, eax
    mov     esi, 10
    call    check_eq

    # ── Verify all tests passed ─────────────────────────────────────
    mov     eax, [tests_run]
    cmp     eax, [tests_passed]
    jne     test_failure

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

test_failure:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── check_eq: compare edi (got) with esi (expected) ─────────────────
check_eq:
    inc     dword ptr [tests_run]
    cmp     edi, esi
    jne     .check_fail
    inc     dword ptr [tests_passed]
    ret
.check_fail:
    ret

# ── Code under test ─────────────────────────────────────────────────

add_ints:
    lea     eax, [edi + esi]
    ret

sub_ints:
    mov     eax, edi
    sub     eax, esi
    ret

mul_ints:
    mov     eax, edi
    imul    eax, esi
    ret

# clamp(value=edi, min=esi, max=edx) -> eax
clamp:
    mov     eax, edi
    cmp     eax, esi
    cmovl   eax, esi            # if value < min, value = min
    cmp     eax, edx
    cmovg   eax, edx            # if value > max, value = max
    ret

# abs_int(value=edi) -> eax
abs_int:
    mov     eax, edi
    cdq                         # edx = sign extension of eax
    xor     eax, edx            # flip bits if negative
    sub     eax, edx            # add 1 if was negative
    ret

# is_even(value=edi) -> eax (1=true, 0=false)
is_even:
    mov     eax, edi
    and     eax, 1
    xor     eax, 1              # flip: 0→1, 1→0
    ret

# max_int(a=edi, b=esi) -> eax
max_int:
    cmp     edi, esi
    cmovge  eax, edi
    cmovl   eax, esi
    ret
