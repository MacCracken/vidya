// Vidya — Game Loop Architecture in AArch64 Assembly
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loop_step` takes an elapsed-microsecond delta in x0 and returns the
// number of fixed-step updates fired this frame in x0. AArch64's
// CNTVCT_EL0 virtual counter would normally feed deltas to a real
// engine; tests use deterministic deltas so the exit code is portable
// across host hardware. Constants like 16667/83335/50000/1000000
// exceed the 12-bit `add` immediate, so they are loaded via the
// assembler's literal-pool form `ldr xN, =literal`.

.global _start

.section .data
.align 3
g_accum:        .quad 0
g_update_count: .quad 0
g_render_count: .quad 0

.section .rodata
msg_pass:    .ascii "All game_loop_architecture examples passed.\n"
msg_pass_len = . - msg_pass

msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// ── loop_reset: zero all three GameLoop fields ────────────────────────
loop_reset:
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    str     xzr, [x9]
    str     xzr, [x9, #8]
    str     xzr, [x9, #16]
    ret

// ── loop_step: x0 = elapsed_us, returns x0 = updates this frame ───────
loop_step:
    // accum = g_accum + elapsed_us
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    ldr     x10, [x9]
    add     x10, x10, x0          // x10 = accum + elapsed

    // spiral-of-death cap: if accum > MAX_ACCUM, accum = MAX_ACCUM
    ldr     x11, =83335           // MAX_ACCUM = 5 * DT_US
    cmp     x10, x11
    csel    x10, x11, x10, gt

    // drain the accumulator in DT_US chunks
    ldr     x12, =16667           // DT_US
    mov     x13, #0               // updates = 0
.Ldrain:
    cmp     x10, x12
    b.lt    .Ldrain_done
    sub     x10, x10, x12
    add     x13, x13, #1
    b       .Ldrain
.Ldrain_done:

    // store accum, bump update_count, bump render_count
    str     x10, [x9]
    ldr     x14, [x9, #8]
    add     x14, x14, x13
    str     x14, [x9, #8]
    ldr     x14, [x9, #16]
    add     x14, x14, #1
    str     x14, [x9, #16]

    mov     x0, x13
    ret

// ── _start: run all tests ─────────────────────────────────────────────
// Calls loop_reset / loop_step via `bl`, so we must save FP+LR in the
// prologue. Using a fresh stack frame keeps the test sequence linear.
_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test 1: exact dt fires exactly one update; update_count = 1
    bl      loop_reset
    ldr     x0, =16667
    bl      loop_step
    cmp     x0, #1
    b.ne    fail
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    ldr     x0, [x9, #8]
    cmp     x0, #1
    b.ne    fail

    // Test 2: under dt fires zero updates (DT_US/2 = 8333 fits 12-bit imm)
    bl      loop_reset
    mov     x0, #8333
    bl      loop_step
    cbnz    x0, fail

    // Test 3: 50ms catchup fires exactly 2 updates
    bl      loop_reset
    ldr     x0, =50000
    bl      loop_step
    cmp     x0, #2
    b.ne    fail

    // Test 4: spiral-of-death cap — 1s hang fires exactly 5 updates
    bl      loop_reset
    ldr     x0, =1000000
    bl      loop_step
    cmp     x0, #5
    b.ne    fail

    // Test 5: 3 frames at exact dt → 3 renders, 3 updates
    bl      loop_reset
    ldr     x0, =16667
    bl      loop_step
    ldr     x0, =16667
    bl      loop_step
    ldr     x0, =16667
    bl      loop_step
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    ldr     x0, [x9, #16]
    cmp     x0, #3
    b.ne    fail
    ldr     x0, [x9, #8]
    cmp     x0, #3
    b.ne    fail

    // Test 6: 1.5*dt = 25000 → 1 update, remainder positive and < dt
    bl      loop_reset
    ldr     x0, =25000            // DT_US + DT_US/2 = 16667 + 8333
    bl      loop_step
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    ldr     x0, [x9]
    // accum should be > DT_US/4 (4166) and < DT_US (16667)
    ldr     x10, =4166
    cmp     x0, x10
    b.le    fail
    ldr     x10, =16667
    cmp     x0, x10
    b.ge    fail

    // Test 7: 30000 + 5000 + 30000 → 3 updates, 3 renders
    bl      loop_reset
    ldr     x0, =30000
    bl      loop_step
    ldr     x0, =5000
    bl      loop_step
    ldr     x0, =30000
    bl      loop_step
    adrp    x9, g_accum
    add     x9, x9, :lo12:g_accum
    ldr     x0, [x9, #8]
    cmp     x0, #3
    b.ne    fail
    ldr     x0, [x9, #16]
    cmp     x0, #3
    b.ne    fail

    // All passed — print and exit 0
    ldp     x29, x30, [sp], #16
    mov     x0, #1                  // stdout
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64                 // SYS_write
    svc     #0
    mov     x0, #0
    mov     x8, #93                 // SYS_exit
    svc     #0

fail:
    ldp     x29, x30, [sp], #16
    mov     x0, #2                  // stderr
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
