// Vidya — Projectile Physics in AArch64 Assembly
//
// Semi-implicit Euler integration in 16.16 fixed-point on 64-bit
// x-registers. The bounce-restitution multiply uses the SMULH+MUL
// pair to form a 128-bit product, then concatenates (high<<48) |
// (low>>16) to perform the fixed-point shift without losing bits if
// the product ever exceeds 2^63 — same idiom as the AArch64 fx_mul
// in fixed_point_arithmetic. Constants > 16 bits use `ldr xN, =N`
// (literal-pool load) since `mov` only takes 16-bit immediates.
//
// Linux Aarch64 syscall ABI: x8 = syscall number, x0–x5 = args,
// return in x0. Functions calling other functions save x29/x30.

.global _start

.section .data
.align 3
ball_x:   .quad 0
ball_y:   .quad 0
ball_vx:  .quad 0
ball_vy:  .quad 0

.section .rodata
msg_pass:    .ascii "All projectile_physics examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// ── physics_step: one frame of semi-implicit Euler ───────────────────
// vy += GRAVITY ; y += vy ; x += vx
physics_step:
    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x

    // vy += GRAVITY
    ldr     x10, [x9, #24]              // ball_vy
    ldr     x11, =6554                  // GRAVITY
    add     x10, x10, x11
    str     x10, [x9, #24]

    // y += vy (use NEW vy)
    ldr     x11, [x9, #8]               // ball_y
    add     x11, x11, x10
    str     x11, [x9, #8]

    // x += vx (horizontal — unaffected by gravity)
    ldr     x10, [x9, #16]              // ball_vx
    ldr     x11, [x9]                   // ball_x
    add     x11, x11, x10
    str     x11, [x9]
    ret

// ── bounce_check: if y > FLOOR_Y, clamp + reflect with restitution ───
bounce_check:
    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x

    ldr     x10, [x9, #8]               // ball_y
    ldr     x11, =14745600              // FLOOR_Y
    cmp     x10, x11
    b.le    .Lbounce_done

    // y = FLOOR_Y
    str     x11, [x9, #8]

    // vy = -(vy * RESTITUTION) >> 16
    // Use SMULH + MUL to get the full 128-bit product, then concatenate
    // (high << 48) | (low >> 16) — same form as fx_mul in fixed_point.
    ldr     x10, [x9, #24]              // vy
    ldr     x11, =45875                 // RESTITUTION
    smulh   x12, x10, x11               // high 64
    mul     x13, x10, x11               // low  64
    lsr     x13, x13, #16
    lsl     x12, x12, #48
    orr     x10, x12, x13
    neg     x10, x10
    str     x10, [x9, #24]

.Lbounce_done:
    ret

// ── reset_ball: zero all four slots, then set from x0..x3 ────────────
// Helper not strictly required but keeps tests readable.
//   x0 = x, x1 = y, x2 = vx, x3 = vy
ball_set:
    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    str     x0, [x9]
    str     x1, [x9, #8]
    str     x2, [x9, #16]
    str     x3, [x9, #24]
    ret

// ── _start: run all tests ────────────────────────────────────────────
_start:
    // -------- Test 1: gravity increases vy; semi-implicit y == vy ----
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    bl      ball_set
    bl      physics_step
    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #24]               // vy
    ldr     x10, =6554                  // GRAVITY
    cmp     x0, x10
    b.ne    fail
    ldr     x0, [x9, #8]                // y
    cmp     x0, x10
    b.ne    fail

    // -------- Test 2: parabolic arc — rises then falls ---------------
    mov     x0, #0
    ldr     x1, =6553600                // y = 100.0
    mov     x2, #0
    ldr     x3, =-1310720               // vy = -20.0 upward
    bl      ball_set

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x19, [x9, #8]               // initial_y (callee-saved scratch)

    mov     x20, #50
.Larc_rise:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      physics_step
    ldp     x29, x30, [sp], #16
    sub     x20, x20, #1
    cbnz    x20, .Larc_rise

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #8]                // mid_y
    cmp     x0, x19
    b.ge    fail                         // must be < initial_y (rising)

    mov     x20, #400
.Larc_fall:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      physics_step
    ldp     x29, x30, [sp], #16
    sub     x20, x20, #1
    cbnz    x20, .Larc_fall

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #8]                // final_y
    cmp     x0, x19
    b.le    fail                         // must be > initial_y

    // -------- Test 3: bounce reverses + reduces velocity -------------
    mov     x0, #0
    ldr     x1, =14745601               // FLOOR_Y + 1 (just past)
    mov     x2, #0
    ldr     x3, =655360                 // vy = 10.0 down
    bl      ball_set

    bl      bounce_check

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #24]               // post-bounce vy
    cmp     x0, #0
    b.ge    fail                         // must be negative
    neg     x0, x0
    ldr     x10, =655360
    cmp     x0, x10
    b.ge    fail                         // |vy| must be < initial 655360
    ldr     x0, [x9, #8]                // ball_y
    ldr     x10, =14745600
    cmp     x0, x10
    b.ne    fail                         // y reset to FLOOR_Y

    // -------- Test 4: horizontal velocity unchanged by gravity -------
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =131072                 // vx = 2.0
    mov     x3, #0
    bl      ball_set

    bl      physics_step
    bl      physics_step
    bl      physics_step

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #16]               // vx
    ldr     x10, =131072
    cmp     x0, x10
    b.ne    fail
    ldr     x0, [x9]                    // x
    ldr     x10, =393216                // 3 * 131072
    cmp     x0, x10
    b.ne    fail

    // -------- Test 5: energy decay — 1000 frames -> |vy| < 2*G -------
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    ldr     x3, =655360                 // vy = 10.0 down
    bl      ball_set

    mov     x20, #1000
.Ldecay_loop:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      physics_step
    bl      bounce_check
    ldp     x29, x30, [sp], #16
    sub     x20, x20, #1
    cbnz    x20, .Ldecay_loop

    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #24]               // vy
    // abs(vy)
    cmp     x0, #0
    b.ge    .Ldecay_pos
    neg     x0, x0
.Ldecay_pos:
    ldr     x10, =13108                 // 2 * GRAVITY
    cmp     x0, x10
    b.ge    fail

    // -------- Test 6: semi-implicit stability — bounded rise --------
    mov     x0, #0
    ldr     x1, =14090240               // FLOOR_Y - 655360
    mov     x2, #0
    ldr     x3, =-655360                // vy = -10.0 upward
    bl      ball_set

    ldr     x19, =14090240              // start_y (also tracks min_y)
    mov     x20, #500
.Lstable_loop:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      physics_step
    bl      bounce_check
    ldp     x29, x30, [sp], #16
    adrp    x9, ball_x
    add     x9, x9, :lo12:ball_x
    ldr     x0, [x9, #8]                // current y
    cmp     x0, x19
    b.ge    .Lstable_skip
    mov     x19, x0                      // min_y = y
.Lstable_skip:
    sub     x20, x20, #1
    cbnz    x20, .Lstable_loop

    // min_y > start_y - max_rise   (max_rise = 1000 * 65536 = 65536000)
    ldr     x10, =14090240              // start_y
    ldr     x11, =65536000              // max_rise
    sub     x10, x10, x11
    cmp     x19, x10
    b.le    fail

    // -------- All tests passed — exit 0 -----------------------------
    mov     x0, #1                      // stdout
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64                     // SYS_write
    svc     #0
    mov     x0, #0
    mov     x8, #93                     // SYS_exit
    svc     #0

fail:
    mov     x0, #2                      // stderr
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
