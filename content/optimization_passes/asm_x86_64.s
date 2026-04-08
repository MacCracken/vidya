# Vidya — Optimization Passes in x86_64 Assembly
#
# Optimized vs unoptimized patterns side by side. Each test shows
# what a naive compiler emits, then what an optimizing compiler produces.
# The optimized version computes the same result with fewer or cheaper
# instructions.
#
# Patterns demonstrated:
# - Strength reduction: imul → shl/lea
# - Constant folding: computed at assemble time with .equ
# - Dead code elimination: unreachable code after unconditional jump
# - Common subexpression elimination: compute once, reuse
# - Algebraic identity: x * 1 = x, x + 0 = x
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

# ── Constant folding: evaluated at assemble time ─────────────────────
# An optimizing compiler folds constant expressions at compile time.
# The assembler does the same with .equ — no runtime cost.
.equ UNOPT_A,       6
.equ UNOPT_B,       7
.equ FOLDED_RESULT, UNOPT_A * UNOPT_B             # 42, computed at assembly
.equ FOLDED_SHIFT,  1 << 10                        # 1024
.equ FOLDED_MASK,   0xFF00 & 0x0F00                # 0x0F00
.equ FOLDED_EXPR,   (10 + 20) * 3 - 5             # 85

_start:
    # ══════════════════════════════════════════════════════════════════
    # Test 1: Strength reduction — multiply by power of 2
    # ══════════════════════════════════════════════════════════════════
    # Unoptimized: x * 8
    mov     $13, %rax
    mov     %rax, %rbx             # save for comparison
    imul    $8, %rax, %rcx         # unoptimized: imul (3-cycle latency)

    # Optimized: x << 3  (1-cycle latency, same result)
    mov     %rbx, %rax
    shl     $3, %rax               # strength reduction: mul → shift

    cmp     %rcx, %rax             # must produce same result
    jne     fail                   # 13 * 8 = 13 << 3 = 104

    # ══════════════════════════════════════════════════════════════════
    # Test 2: Strength reduction — multiply by non-power-of-2
    # ══════════════════════════════════════════════════════════════════
    # Unoptimized: x * 5
    mov     $20, %rax
    imul    $5, %rax, %rcx         # unoptimized: imul

    # Optimized: lea (x, x*4) — single instruction, 1-cycle latency
    mov     $20, %rax
    lea     (%rax, %rax, 4), %rax  # rax = rax + rax*4 = rax*5

    cmp     %rcx, %rax
    jne     fail                   # 20 * 5 = 100

    # ══════════════════════════════════════════════════════════════════
    # Test 3: Strength reduction — multiply by 3
    # ══════════════════════════════════════════════════════════════════
    # Unoptimized: x * 3
    mov     $15, %rax
    imul    $3, %rax, %rcx         # unoptimized

    # Optimized: lea (x, x*2) — x + 2*x = 3*x
    mov     $15, %rax
    lea     (%rax, %rax, 2), %rax  # optimized: lea

    cmp     %rcx, %rax
    jne     fail                   # 15 * 3 = 45

    # ══════════════════════════════════════════════════════════════════
    # Test 4: Constant folding — verified at assemble time
    # ══════════════════════════════════════════════════════════════════
    # Without folding, the compiler would emit:
    #   mov $6, %rax
    #   mov $7, %rbx
    #   imul %rbx, %rax
    # With folding, it becomes a single immediate load:

    mov     $FOLDED_RESULT, %rax   # just loads 42 — no runtime multiply
    cmp     $42, %rax
    jne     fail

    mov     $FOLDED_SHIFT, %rax    # 1024, no runtime shift
    cmp     $1024, %rax
    jne     fail

    mov     $FOLDED_MASK, %rax     # 0x0F00, no runtime AND
    cmp     $0x0F00, %rax
    jne     fail

    mov     $FOLDED_EXPR, %rax     # 85, entire expression folded
    cmp     $85, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 5: Dead code elimination
    # ══════════════════════════════════════════════════════════════════
    # After an unconditional jump, code is unreachable (dead).
    # An optimizer removes it entirely. Here we show the pattern:
    # the dead code exists in source but is never executed.

    mov     $99, %rax
    jmp     t5_alive               # unconditional jump

    # ── Dead code below: never executed ──────────────────────────────
    # An optimizing compiler would remove these entirely.
    # They waste code cache and binary size.
    mov     $0, %rax               # dead: overwritten value
    mov     $666, %rbx             # dead: unused result
    add     %rbx, %rax             # dead: depends on dead values

t5_alive:
    # rax should still be 99 (dead code was not reached)
    cmp     $99, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 6: Common subexpression elimination (CSE)
    # ══════════════════════════════════════════════════════════════════
    # Unoptimized: computes (a + b) twice
    #   t1 = a + b
    #   t2 = t1 * 2
    #   t3 = a + b      ← redundant, same as t1
    #   t4 = t3 + 10
    #
    # Optimized: reuses t1

    mov     $30, %rax              # a = 30
    mov     $12, %rbx              # b = 12

    # CSE: compute (a + b) once, reuse
    add     %rbx, %rax             # t1 = a + b = 42 (computed once)
    mov     %rax, %rcx             # save t1

    shl     $1, %rax               # t2 = t1 * 2 = 84
    cmp     $84, %rax
    jne     fail

    # Reuse t1 instead of recomputing a + b
    lea     10(%rcx), %rax         # t4 = t1 + 10 = 52 (reused, not recomputed)
    cmp     $52, %rax
    jne     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 7: Algebraic identity simplification
    # ══════════════════════════════════════════════════════════════════
    # x * 1 = x  → remove the multiply entirely
    # x + 0 = x  → remove the add entirely
    # x * 0 = 0  → replace with xor (zero idiom)

    mov     $77, %rax

    # Unoptimized:
    #   imul $1, %rax, %rbx       # x * 1
    #   add  $0, %rbx             # x + 0
    # Optimized: both are identity ops, just use x directly
    mov     %rax, %rbx             # optimized: x * 1 + 0 = x

    cmp     $77, %rbx
    jne     fail

    # x * 0 → xor (cheaper than imul, and a zero idiom that CPUs optimize)
    xor     %rcx, %rcx             # optimized form of x * 0
    test    %rcx, %rcx
    jnz     fail

    # ══════════════════════════════════════════════════════════════════
    # Test 8: Strength reduction — division by power of 2
    # ══════════════════════════════════════════════════════════════════
    # Unoptimized: unsigned x / 4
    #   xor %rdx, %rdx
    #   mov $4, %rcx
    #   div %rcx                   # ~35 cycles on modern CPUs
    #
    # Optimized: x >> 2            # 1 cycle

    mov     $200, %rax
    shr     $2, %rax               # 200 / 4 = 50

    cmp     $50, %rax
    jne     fail

    # ── All passed ───────────────────────────────────────────────────
    mov     $1, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $60, %rax
    xor     %rdi, %rdi
    syscall

fail:
    mov     $60, %rax
    mov     $1, %rdi
    syscall

.section .rodata
msg_pass:
    .ascii  "All optimization passes examples passed.\n"
    msg_len = . - msg_pass
