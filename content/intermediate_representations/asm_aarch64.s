// Vidya — Intermediate Representations in AArch64 Assembly
//
// Three-address code (TAC) is the classic IR: t1 = a op b. Each TAC
// instruction maps cleanly to AArch64 because AArch64 is itself a
// three-address architecture: ADD Xd, Xn, Xm. This file shows IR
// lowered to AArch64: every instruction has a TAC comment showing the
// IR it came from.
//
// TAC operators -> AArch64:
//   t = a + b   -> ADD Xd, Xn, Xm
//   t = a - b   -> SUB Xd, Xn, Xm
//   t = a * b   -> MUL Xd, Xn, Xm
//   t = a / b   -> UDIV/SDIV Xd, Xn, Xm
//   t = a       -> MOV Xd, Xn
//   if a cmp b goto L -> CMP Xn, Xm; B.cond L
//   t = const   -> MOV Xd, #imm

.global _start

.section .rodata
msg_pass:   .ascii "All intermediate representations examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Example 1: arithmetic expression ────────────────────────────
    // Source:  result = (a + b) * (c - d)
    // IR:     t1 = a + b
    //         t2 = c - d
    //         t3 = t1 * t2
    //
    // Register allocation: a=w0, b=w1, c=w2, d=w3
    //                      t1=w4, t2=w5, t3=w6

    mov     w0, #10                 // a = 10
    mov     w1, #5                  // b = 5
    mov     w2, #8                  // c = 8
    mov     w3, #3                  // d = 3

    add     w4, w0, w1             // t1 = a + b        -> 15
    sub     w5, w2, w3             // t2 = c - d        -> 5
    mul     w6, w4, w5             // t3 = t1 * t2      -> 75

    cmp     w6, #75
    b.ne    fail

    // ── Example 2: conditional (if-else lowered to branches) ────────
    // Source:  if (x > 10) { y = x * 2 } else { y = x + 1 }
    // IR:     t1 = x > 10
    //         if_false t1 goto else_branch
    //         y = x * 2
    //         goto end
    //       else_branch:
    //         y = x + 1
    //       end:

    mov     w0, #15                 // x = 15

    // t1 = x > 10; if_false t1 goto else
    cmp     w0, #10                // CMP x, 10
    b.le    .Lelse1                // B.LE else_branch

    // y = x * 2
    lsl     w1, w0, #1             // t2 = x << 1 (same as x*2)
    b       .Lend1                 // goto end

.Lelse1:
    // y = x + 1
    add     w1, w0, #1             // t2 = x + 1

.Lend1:
    cmp     w1, #30                 // 15 * 2 = 30
    b.ne    fail

    // ── Example 3: else branch taken ────────────────────────────────
    mov     w0, #5                  // x = 5

    cmp     w0, #10
    b.le    .Lelse2

    lsl     w1, w0, #1
    b       .Lend2

.Lelse2:
    add     w1, w0, #1             // 5 + 1 = 6

.Lend2:
    cmp     w1, #6
    b.ne    fail

    // ── Example 4: loop lowered from IR ─────────────────────────────
    // Source:  sum = 0; for i in 1..=5 { sum += i }
    // IR:     sum = 0
    //         i = 1
    //       loop_top:
    //         if i > 5 goto loop_end
    //         sum = sum + i
    //         i = i + 1
    //         goto loop_top
    //       loop_end:

    mov     w0, #0                  // sum = 0
    mov     w1, #1                  // i = 1

.Lloop_top:
    cmp     w1, #5                 // if i > 5 goto loop_end
    b.gt    .Lloop_end
    add     w0, w0, w1             // sum = sum + i
    add     w1, w1, #1             // i = i + 1
    b       .Lloop_top             // goto loop_top

.Lloop_end:
    cmp     w0, #15                 // 1+2+3+4+5 = 15
    b.ne    fail

    // ── Example 5: function call in IR ──────────────────────────────
    // Source:  result = add(3, 4) + add(10, 20)
    // IR:     t1 = call add(3, 4)
    //         t2 = call add(10, 20)
    //         t3 = t1 + t2

    mov     w0, #3                  // arg1 = 3
    mov     w1, #4                  // arg2 = 4
    bl      ir_add                  // t1 = call add(3, 4)
    mov     w4, w0                  // save t1

    mov     w0, #10                 // arg1 = 10
    mov     w1, #20                 // arg2 = 20
    bl      ir_add                  // t2 = call add(10, 20)

    add     w0, w4, w0             // t3 = t1 + t2 = 7 + 30 = 37
    cmp     w0, #37
    b.ne    fail

    // ── Example 6: phi-node elimination via MOV ─────────────────────
    // SSA phi: y3 = phi(y1, y2) is eliminated by inserting MOVs
    // at the end of each predecessor block.
    // Source:  y = (x > 0) ? x : -x   (absolute value)
    // IR SSA: if x > 0 goto pos
    //         y2 = 0 - x
    //         goto join
    //       pos: y1 = x
    //       join: y3 = phi(y1, y2)
    // After phi elimination:
    //         y = 0 - x; goto join
    //       pos: y = x
    //       join: (y is ready)

    mov     w0, #-7                 // x = -7
    cmp     w0, #0
    b.gt    .Lpos

    neg     w1, w0                  // y = 0 - x (phi predecessor 1)
    b       .Ljoin

.Lpos:
    mov     w1, w0                  // y = x (phi predecessor 2)

.Ljoin:
    cmp     w1, #7                  // abs(-7) = 7
    b.ne    fail

    // ── Example 7: strength reduction in IR ─────────────────────────
    // IR before:  t1 = i * 4  (array index scaling)
    // IR after:   t1 = i << 2 (strength-reduced)
    mov     w0, #7
    lsl     w1, w0, #2             // t1 = i << 2 (was i * 4)
    cmp     w1, #28
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

// ── ir_add(w0, w1) -> w0 ────────────────────────────────────────────
// Simple two-argument add — the kind of function IR call nodes target.
ir_add:
    add     w0, w0, w1
    ret
