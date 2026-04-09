// Vidya — Code Generation in AArch64 Assembly
//
// This file shows what a compiler's code generator produces for AArch64:
// function prologues/epilogues using stp/ldp, stack frame layout, local
// variables, parameter passing via x0-x7, arithmetic lowered to machine
// instructions, and control flow. Each function demonstrates a pattern
// a compiler emits — this IS the output of a code generator, annotated
// for learning.
//
// AArch64 prologue/epilogue pattern:
//   stp x29, x30, [sp, #-N]!   // save FP and LR, allocate frame
//   mov x29, sp                 // establish frame pointer
//   ...
//   ldp x29, x30, [sp], #N     // restore FP and LR, deallocate
//   ret                         // return via LR (x30)

.global _start

.section .rodata
msg_pass:   .ascii "All code generation examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Test 1: Simple function with stack frame ──────────────────
    // Equivalent source: fn add(a: i64, b: i64) -> i64 { a + b }
    mov     x0, #30
    mov     x1, #12
    bl      generated_add
    cmp     x0, #42
    b.ne    fail

    // ── Test 2: Function with local variables ─────────────────────
    // Equivalent source:
    //   fn quadratic(x: i64) -> i64 {
    //       let a = x * x;
    //       let b = 2 * x;
    //       let c = 1;
    //       a + b + c
    //   }
    mov     x0, #5              // x = 5
    bl      generated_quadratic // 25 + 10 + 1 = 36
    cmp     x0, #36
    b.ne    fail

    // ── Test 3: Conditional (if/else lowered to branches) ─────────
    // Equivalent source:
    //   fn abs_val(x: i64) -> i64 {
    //       if x < 0 { -x } else { x }
    //   }
    mov     x0, #7
    neg     x0, x0              // x0 = -7
    bl      generated_abs
    cmp     x0, #7
    b.ne    fail

    mov     x0, #13
    bl      generated_abs
    cmp     x0, #13
    b.ne    fail

    // ── Test 4: Loop lowered to branch-back ───────────────────────
    // Equivalent source:
    //   fn sum_to_n(n: i64) -> i64 {
    //       let mut total = 0;
    //       let mut i = 1;
    //       while i <= n { total += i; i += 1; }
    //       total
    //   }
    mov     x0, #10
    bl      generated_sum_to_n  // 1+2+...+10 = 55
    cmp     x0, #55
    b.ne    fail

    // ── Test 5: Struct-like register passing ──────────────────────
    // Equivalent source:
    //   struct Point { x: i64, y: i64 }
    //   fn manhattan(p: Point) -> i64 { abs(p.x) + abs(p.y) }
    // Compiler passes small structs in registers (x0=x, x1=y)
    mov     x0, #3
    neg     x0, x0              // point.x = -3
    mov     x1, #4              // point.y = 4
    bl      generated_manhattan // |-3| + |4| = 7
    cmp     x0, #7
    b.ne    fail

    // ── Test 6: Callee-saved register spill ───────────────────────
    // When a function needs more values than volatile registers,
    // the compiler spills callee-saved registers to the stack.
    mov     x0, #3
    bl      generated_polynomial    // 3^4 + 2*3^3 + 3*3^2 + 4*3 + 5
    // = 81 + 54 + 27 + 12 + 5 = 179
    cmp     x0, #179
    b.ne    fail

    // ── Print success ─────────────────────────────────────────────
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

// ════════════════════════════════════════════════════════════════════
// Generated function: add(a: i64, b: i64) -> i64
// Demonstrates: prologue with stp/ldp, parameter spill to stack
// ════════════════════════════════════════════════════════════════════
generated_add:
    // ── Prologue ──────────────────────────────────────────────────
    stp     x29, x30, [sp, #-32]!   // save FP + LR, allocate 32 bytes
    mov     x29, sp                  // establish frame pointer

    // ── Parameter spill (unoptimized codegen stores args to stack)
    str     x0, [x29, #16]          // spill arg1 (a)
    str     x1, [x29, #24]          // spill arg2 (b)

    // ── Body ──────────────────────────────────────────────────────
    ldr     x0, [x29, #16]          // reload a
    ldr     x1, [x29, #24]          // reload b
    add     x0, x0, x1              // a + b

    // ── Epilogue ──────────────────────────────────────────────────
    ldp     x29, x30, [sp], #32     // restore FP + LR, deallocate
    ret

// ════════════════════════════════════════════════════════════════════
// Generated function: quadratic(x: i64) -> i64
// Stack layout (relative to x29):
//   [x29, #16] = x (parameter)
//   [x29, #24] = a (local: x*x)
//   [x29, #32] = b (local: 2*x)
//   [x29, #40] = c (local: 1)
// ════════════════════════════════════════════════════════════════════
generated_quadratic:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    // Spill parameter
    str     x0, [x29, #16]          // x

    // let a = x * x
    ldr     x0, [x29, #16]
    mul     x0, x0, x0
    str     x0, [x29, #24]          // a = x*x

    // let b = 2 * x
    ldr     x0, [x29, #16]
    lsl     x0, x0, #1              // compiler strength-reduces 2*x to shift
    str     x0, [x29, #32]          // b = 2*x

    // let c = 1
    mov     x0, #1
    str     x0, [x29, #40]          // c = 1

    // return a + b + c
    ldr     x0, [x29, #24]
    ldr     x1, [x29, #32]
    add     x0, x0, x1
    ldr     x1, [x29, #40]
    add     x0, x0, x1

    ldp     x29, x30, [sp], #48
    ret

// ════════════════════════════════════════════════════════════════════
// Generated function: abs_val(x: i64) -> i64
// Demonstrates: conditional branch lowering (if/else -> cmp + b.cond)
// ════════════════════════════════════════════════════════════════════
generated_abs:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cmp     x0, #0                  // compare x with 0
    b.ge    .abs_positive            // if x >= 0, skip negation

    // x < 0 path: return -x
    neg     x0, x0
    b       .abs_done

.abs_positive:
    // x >= 0 path: return x (already in x0)

.abs_done:
    ldp     x29, x30, [sp], #16
    ret

// ════════════════════════════════════════════════════════════════════
// Generated function: sum_to_n(n: i64) -> i64
// Demonstrates: loop lowering (while -> cmp + conditional jump back)
// Stack layout:
//   [x29, #16] = n
//   [x29, #24] = total
//   [x29, #32] = i
// ════════════════════════════════════════════════════════════════════
generated_sum_to_n:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    str     x0, [x29, #16]          // n
    str     xzr, [x29, #24]         // total = 0
    mov     x0, #1
    str     x0, [x29, #32]          // i = 1

.sum_loop_header:
    // while i <= n
    ldr     x0, [x29, #32]          // load i
    ldr     x1, [x29, #16]          // load n
    cmp     x0, x1                  // i <= n?
    b.gt    .sum_loop_exit           // if i > n, exit loop

    // Loop body: total += i
    ldr     x0, [x29, #32]          // load i
    ldr     x1, [x29, #24]          // load total
    add     x1, x1, x0              // total += i
    str     x1, [x29, #24]          // store total

    // i += 1
    ldr     x0, [x29, #32]
    add     x0, x0, #1
    str     x0, [x29, #32]
    b       .sum_loop_header         // back to loop header

.sum_loop_exit:
    ldr     x0, [x29, #24]          // return total
    ldp     x29, x30, [sp], #48
    ret

// ════════════════════════════════════════════════════════════════════
// Generated function: manhattan(x: i64, y: i64) -> i64
// Demonstrates: inlined abs using conditional negate (CSNEG)
// AArch64 has CSNEG: conditional select negate — branchless abs
// ════════════════════════════════════════════════════════════════════
generated_manhattan:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Branchless abs(x): cmp + csneg
    // AArch64 has a dedicated conditional negate instruction
    cmp     x0, #0
    cneg    x0, x0, lt              // x0 = (x0 < 0) ? -x0 : x0
    mov     x2, x0                  // save abs(x)

    // Branchless abs(y)
    cmp     x1, #0
    cneg    x1, x1, lt
    add     x0, x2, x1              // abs(x) + abs(y)

    ldp     x29, x30, [sp], #16
    ret

// ════════════════════════════════════════════════════════════════════
// Generated function: polynomial(x: i64) -> i64
// Computes: x^4 + 2*x^3 + 3*x^2 + 4*x + 5
// Demonstrates: callee-saved register spill when intermediates
// exceed available volatile registers (unoptimized codegen pattern)
// ════════════════════════════════════════════════════════════════════
generated_polynomial:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [x29, #16]    // save callee-saved regs
    stp     x21, x22, [x29, #32]

    mov     x19, x0                  // x

    // x^2
    mul     x20, x19, x19           // x20 = x*x

    // x^3
    mul     x21, x20, x19           // x21 = x^2 * x

    // x^4
    mul     x22, x21, x19           // x22 = x^3 * x

    // Accumulate: x^4 + 2*x^3 + 3*x^2 + 4*x + 5
    mov     x0, x22                  // acc = x^4

    mov     x1, #2
    madd    x0, x21, x1, x0         // acc += 2*x^3

    mov     x1, #3
    madd    x0, x20, x1, x0         // acc += 3*x^2

    mov     x1, #4
    madd    x0, x19, x1, x0         // acc += 4*x

    add     x0, x0, #5              // acc += 5

    ldp     x21, x22, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #48
    ret
