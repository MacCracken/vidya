// Vidya — Optimization Passes in AArch64 Assembly
//
// Compiler optimizations visible at the instruction level. AArch64's
// fixed-width encoding and rich instruction set enable clean patterns:
// MUL by power-of-2 becomes LSL, constant expressions fold at assembly
// time via .equ, dead stores are eliminated, and conditional select
// (CSEL) replaces branches for branchless code.

.global _start

.section .rodata
msg_pass:   .ascii "All optimization passes examples passed.\n"
msg_len = . - msg_pass

// ── Constant folding at assembly time ───────────────────────────────
// The assembler evaluates these — zero runtime cost.
.equ ARRAY_SIZE, 16
.equ ELEMENT_SIZE, 4
.equ TOTAL_BYTES, ARRAY_SIZE * ELEMENT_SIZE     // 64, folded
.equ HEADER_SIZE, 8
.equ PAYLOAD_OFFSET, HEADER_SIZE + 4            // 12, folded
.equ MASK_LOW4, (1 << 4) - 1                    // 0xF, folded

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: constant folding verification ───────────────────────
    // .equ expressions are evaluated at assemble time, not runtime.
    mov     w0, TOTAL_BYTES
    cmp     w0, #64
    b.ne    fail

    mov     w0, PAYLOAD_OFFSET
    cmp     w0, #12
    b.ne    fail

    mov     w0, MASK_LOW4
    cmp     w0, #15
    b.ne    fail

    // ── Test 2: strength reduction — multiply to shift ──────────────
    // Unoptimized: MUL w0, w0, #8
    // Optimized:   LSL w0, w0, #3  (same result, single-cycle)
    mov     w0, #5
    lsl     w1, w0, #3             // 5 * 8 = 40 via shift
    mov     w2, #8
    mul     w3, w0, w2             // 5 * 8 = 40 via multiply
    cmp     w1, w3                 // both should be 40
    b.ne    fail
    cmp     w1, #40
    b.ne    fail

    // ── Test 3: strength reduction — multiply by 3 ──────────────────
    // x * 3 = x + (x << 1) — one ADD instead of MUL
    mov     w0, #7
    add     w1, w0, w0, lsl #1    // 7 + 14 = 21 = 7 * 3
    cmp     w1, #21
    b.ne    fail

    // ── Test 4: strength reduction — multiply by 5 ──────────────────
    // x * 5 = x + (x << 2)
    mov     w0, #6
    add     w1, w0, w0, lsl #2    // 6 + 24 = 30 = 6 * 5
    cmp     w1, #30
    b.ne    fail

    // ── Test 5: dead code elimination ───────────────────────────────
    // An optimizer removes code after unconditional branches and
    // stores to variables that are never read. Here we show the
    // OPTIMIZED version — the dead code is simply absent.
    mov     w0, #42
    b       .Lskip_dead
    // Dead: these would be here in unoptimized code
    // mov w0, #99       // dead store (overwritten before use)
    // add w0, w0, #1    // dead computation
.Lskip_dead:
    cmp     w0, #42                 // w0 is still 42
    b.ne    fail

    // ── Test 6: common subexpression elimination ────────────────────
    // Unoptimized:  a = x + y;  b = x + y;  (computed twice)
    // Optimized:    t = x + y;  a = t;  b = t;
    mov     w0, #10                 // x
    mov     w1, #7                  // y
    add     w2, w0, w1             // t = x + y (computed once)
    mov     w3, w2                  // a = t
    mov     w4, w2                  // b = t (reuses t, no recompute)
    cmp     w3, #17
    b.ne    fail
    cmp     w4, #17
    b.ne    fail

    // ── Test 7: branchless via CSEL (branch elimination) ────────────
    // Unoptimized:  if (x > 0) y = x; else y = -x;
    //               CMP, B.LE, MOV, B, NEG  (branch, possible mispredict)
    // Optimized:    CMP, NEG, CSEL  (branchless, predictable)
    mov     w0, #-8
    neg     w1, w0                  // w1 = -(-8) = 8
    cmp     w0, #0
    csel    w2, w0, w1, gt         // w2 = w0 if > 0, else w1
    cmp     w2, #8                  // abs(-8) = 8
    b.ne    fail

    // ── Test 8: branchless min/max ──────────────────────────────────
    // min(a, b) without branching
    mov     w0, #20
    mov     w1, #13
    cmp     w0, w1
    csel    w2, w0, w1, lt         // w2 = min(20, 13) = 13
    cmp     w2, #13
    b.ne    fail

    // max(a, b) without branching
    cmp     w0, w1
    csel    w3, w0, w1, gt         // w3 = max(20, 13) = 20
    cmp     w3, #20
    b.ne    fail

    // ── Test 9: loop-invariant code motion ──────────────────────────
    // Unoptimized: for i in 0..4 { result += base * scale }
    //              MUL inside loop (redundant, same every iteration)
    // Optimized:   t = base * scale (hoisted out of loop)
    //              for i in 0..4 { result += t }
    mov     w0, #3                  // base
    mov     w1, #7                  // scale
    mul     w2, w0, w1             // t = base * scale = 21 (hoisted)
    mov     w3, #0                  // result = 0
    mov     w4, #0                  // i = 0
.Llicm_loop:
    cmp     w4, #4
    b.ge    .Llicm_done
    add     w3, w3, w2             // result += t (no MUL in loop)
    add     w4, w4, #1
    b       .Llicm_loop
.Llicm_done:
    cmp     w3, #84                 // 21 * 4 = 84
    b.ne    fail

    // ── Test 10: peephole — replace MOV+ADD with single ADD ─────────
    // Unoptimized:  MOV w1, w0; ADD w1, w1, #5
    // Optimized:    ADD w1, w0, #5
    mov     w0, #10
    add     w1, w0, #5             // single instruction, no temp MOV
    cmp     w1, #15
    b.ne    fail

    // ── Test 11: algebraic simplification ───────────────────────────
    // x * 1 = x (identity); x + 0 = x; x - x = 0
    mov     w0, #42
    // x * 1 optimizes to just x — no MUL emitted
    mov     w1, w0                  // "x * 1" -> MOV
    cmp     w1, #42
    b.ne    fail

    // x - x optimizes to MOV Xd, #0
    mov     w2, #0                  // "x - x" -> MOV #0
    cmp     w2, #0
    b.ne    fail

    // ── Print success ────────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    ldp     x29, x30, [sp], #16
    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0
