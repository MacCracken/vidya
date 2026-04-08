# Vidya — Code Generation in x86_64 Assembly
#
# This file shows what a compiler's code generator produces: function
# prologues/epilogues, local variable layout on the stack, parameter
# passing, arithmetic lowered to machine instructions, and control flow.
# Each function demonstrates a pattern a compiler emits — this IS the
# output of a code generator, annotated for learning.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All code generation examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Test 1: Simple function with stack frame ────────────────────
    # Equivalent source: fn add(a: i64, b: i64) -> i64 { a + b }
    mov     rdi, 30
    mov     rsi, 12
    call    generated_add
    cmp     rax, 42
    jne     fail

    # ── Test 2: Function with local variables ───────────────────────
    # Equivalent source:
    #   fn quadratic(x: i64) -> i64 {
    #       let a = x * x;
    #       let b = 2 * x;
    #       let c = 1;
    #       a + b + c
    #   }
    mov     rdi, 5              # x = 5
    call    generated_quadratic # 25 + 10 + 1 = 36
    cmp     rax, 36
    jne     fail

    # ── Test 3: Conditional (if/else lowered to branches) ───────────
    # Equivalent source:
    #   fn abs_val(x: i64) -> i64 {
    #       if x < 0 { -x } else { x }
    #   }
    mov     rdi, -7
    call    generated_abs
    cmp     rax, 7
    jne     fail

    mov     rdi, 13
    call    generated_abs
    cmp     rax, 13
    jne     fail

    # ── Test 4: Loop lowered to branch-back ─────────────────────────
    # Equivalent source:
    #   fn sum_to_n(n: i64) -> i64 {
    #       let mut total = 0;
    #       let mut i = 1;
    #       while i <= n { total += i; i += 1; }
    #       total
    #   }
    mov     rdi, 10
    call    generated_sum_to_n  # 1+2+...+10 = 55
    cmp     rax, 55
    jne     fail

    # ── Test 5: Struct-like stack layout ────────────────────────────
    # Equivalent source:
    #   struct Point { x: i64, y: i64 }
    #   fn manhattan(p: Point) -> i64 { abs(p.x) + abs(p.y) }
    # Compiler passes small structs in registers (rdi=x, rsi=y)
    mov     rdi, -3             # point.x
    mov     rsi, 4              # point.y
    call    generated_manhattan # |−3| + |4| = 7
    cmp     rax, 7
    jne     fail

    # ── Test 6: Caller-saved register spill ─────────────────────────
    # When a function needs more values than registers, the compiler
    # spills to the stack. This function uses many intermediates.
    mov     rdi, 3
    call    generated_polynomial    # 3^4 + 2*3^3 + 3*3^2 + 4*3 + 5
    # = 81 + 54 + 27 + 12 + 5 = 179
    cmp     rax, 179
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ════════════════════════════════════════════════════════════════════
# Generated function: add(a: i64, b: i64) -> i64
# Demonstrates: prologue, epilogue, parameter access
# ════════════════════════════════════════════════════════════════════
generated_add:
    # ── Prologue ────────────────────────────────────────────────────
    push    rbp                 # save caller's frame pointer
    mov     rbp, rsp            # establish our frame pointer
    sub     rsp, 16             # reserve space for locals (16-byte aligned)

    # ── Parameter spill (unoptimized codegen stores args to stack) ──
    mov     [rbp - 8], rdi      # spill arg1 (a)
    mov     [rbp - 16], rsi     # spill arg2 (b)

    # ── Body ────────────────────────────────────────────────────────
    mov     rax, [rbp - 8]      # reload a
    add     rax, [rbp - 16]     # a + b

    # ── Epilogue ────────────────────────────────────────────────────
    leave                       # mov rsp, rbp; pop rbp
    ret

# ════════════════════════════════════════════════════════════════════
# Generated function: quadratic(x: i64) -> i64
# Stack layout:
#   [rbp - 8]  = x (parameter)
#   [rbp - 16] = a (local: x*x)
#   [rbp - 24] = b (local: 2*x)
#   [rbp - 32] = c (local: 1)
# ════════════════════════════════════════════════════════════════════
generated_quadratic:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32             # 4 locals × 8 bytes = 32

    # Spill parameter
    mov     [rbp - 8], rdi      # x

    # let a = x * x
    mov     rax, [rbp - 8]
    imul    rax, rax
    mov     [rbp - 16], rax     # a = x*x

    # let b = 2 * x
    mov     rax, [rbp - 8]
    shl     rax, 1              # compiler strength-reduces 2*x to shift
    mov     [rbp - 24], rax     # b = 2*x

    # let c = 1
    mov     qword ptr [rbp - 32], 1

    # return a + b + c
    mov     rax, [rbp - 16]
    add     rax, [rbp - 24]
    add     rax, [rbp - 32]

    leave
    ret

# ════════════════════════════════════════════════════════════════════
# Generated function: abs_val(x: i64) -> i64
# Demonstrates: conditional branch lowering (if/else → cmp + jcc)
# ════════════════════════════════════════════════════════════════════
generated_abs:
    push    rbp
    mov     rbp, rsp

    mov     rax, rdi            # x
    test    rax, rax            # compare x with 0
    jns     .abs_positive       # if x >= 0, skip negation

    # x < 0 path: return -x
    neg     rax
    jmp     .abs_done

.abs_positive:
    # x >= 0 path: return x (already in rax)

.abs_done:
    leave
    ret

# ════════════════════════════════════════════════════════════════════
# Generated function: sum_to_n(n: i64) -> i64
# Demonstrates: loop lowering (while → cmp + conditional jump back)
# Stack layout:
#   [rbp - 8]  = n
#   [rbp - 16] = total
#   [rbp - 24] = i
# ════════════════════════════════════════════════════════════════════
generated_sum_to_n:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32

    mov     [rbp - 8], rdi          # n
    mov     qword ptr [rbp - 16], 0 # total = 0
    mov     qword ptr [rbp - 24], 1 # i = 1

.sum_loop_header:
    # while i <= n
    mov     rax, [rbp - 24]     # load i
    cmp     rax, [rbp - 8]      # i <= n?
    jg      .sum_loop_exit      # if i > n, exit loop

    # Loop body: total += i
    mov     rax, [rbp - 24]     # load i
    add     [rbp - 16], rax     # total += i

    # i += 1
    inc     qword ptr [rbp - 24]
    jmp     .sum_loop_header    # back to loop header

.sum_loop_exit:
    mov     rax, [rbp - 16]     # return total
    leave
    ret

# ════════════════════════════════════════════════════════════════════
# Generated function: manhattan(x: i64, y: i64) -> i64
# Demonstrates: inlined abs (compiler inlines small functions)
# ════════════════════════════════════════════════════════════════════
generated_manhattan:
    push    rbp
    mov     rbp, rsp

    # Inline abs(x): use branchless abs via cdq pattern
    # abs(x) = (x ^ (x >> 63)) - (x >> 63)
    mov     rax, rdi
    mov     rcx, rdi
    sar     rcx, 63             # arithmetic shift: 0 if positive, -1 if negative
    xor     rax, rcx            # conditional bitflip
    sub     rax, rcx            # +1 if was negative
    mov     rdx, rax            # save abs(x)

    # Inline abs(y)
    mov     rax, rsi
    mov     rcx, rsi
    sar     rcx, 63
    xor     rax, rcx
    sub     rax, rcx

    add     rax, rdx            # abs(x) + abs(y)

    leave
    ret

# ════════════════════════════════════════════════════════════════════
# Generated function: polynomial(x: i64) -> i64
# Computes: x^4 + 2*x^3 + 3*x^2 + 4*x + 5
# Demonstrates: register spill to stack when intermediates exceed
# available registers (unoptimized codegen pattern)
# Stack layout:
#   [rbp - 8]  = x
#   [rbp - 16] = x^2
#   [rbp - 24] = x^3
#   [rbp - 32] = x^4
#   [rbp - 40] = accumulator
# ════════════════════════════════════════════════════════════════════
generated_polynomial:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48             # 5 locals + alignment

    mov     [rbp - 8], rdi      # spill x

    # x^2
    mov     rax, [rbp - 8]
    imul    rax, [rbp - 8]
    mov     [rbp - 16], rax     # x^2

    # x^3
    mov     rax, [rbp - 16]
    imul    rax, [rbp - 8]
    mov     [rbp - 24], rax     # x^3

    # x^4
    mov     rax, [rbp - 24]
    imul    rax, [rbp - 8]
    mov     [rbp - 32], rax     # x^4

    # Accumulate: x^4 + 2*x^3 + 3*x^2 + 4*x + 5
    mov     rax, [rbp - 32]     # x^4
    mov     [rbp - 40], rax     # acc = x^4

    mov     rax, [rbp - 24]     # x^3
    imul    rax, 2              # 2*x^3
    add     [rbp - 40], rax

    mov     rax, [rbp - 16]     # x^2
    imul    rax, 3              # 3*x^2
    add     [rbp - 40], rax

    mov     rax, [rbp - 8]      # x
    imul    rax, 4              # 4*x
    add     [rbp - 40], rax

    add     qword ptr [rbp - 40], 5  # + 5

    mov     rax, [rbp - 40]     # return accumulator
    leave
    ret
