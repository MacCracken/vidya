// Vidya — Game AI Decision Making in AArch64 Assembly
//
// Stat-driven AI scoring with PCG PRNG. AArch64 has no single 64x64→128
// instruction in one form: we use the MUL/UMULH pair to get the low and
// high halves of an unsigned multiply. For PCG, we only need the low 64
// bits of state*MULT, so a plain MUL suffices and the wraparound is the
// natural modulo-2^64 behavior of MUL on x-registers. Constants larger
// than a 16-bit immediate (PCG_MULT, PCG_INC) must be loaded via the
// assembler's literal-pool form: `ldr xN, =literal`.

.global _start

.equ ACT_SHOOT,   0
.equ ACT_DUNK,    1
.equ ACT_PASS,    2
.equ ACT_DRIVE,   3
.equ ACT_STEAL,   4

.section .data
.align 3
rng_state:   .quad 12345

.section .rodata
msg_pass:    .ascii "All game_ai_decisions examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// rng_seed: x0 = new state
rng_seed:
    adrp    x9, rng_state
    add     x9, x9, :lo12:rng_state
    str     x0, [x9]
    ret

// rng_next: returns next pseudo-random value in x0
// state = state * PCG_MULT + PCG_INC (mod 2^64)
// return = (state >> 33) & 0x7fffffff
rng_next:
    adrp    x9, rng_state
    add     x9, x9, :lo12:rng_state
    ldr     x10, [x9]                   // x10 = state
    ldr     x11, =6364136223846793005   // PCG_MULT
    mul     x10, x10, x11               // state *= MULT (low 64 — wraps)
    ldr     x11, =1442695040888963407   // PCG_INC
    add     x10, x10, x11               // state += INC (wraps in u64 sense)
    str     x10, [x9]                   // store new state
    lsr     x10, x10, #33               // upper bits
    ldr     x11, =2147483647            // 0x7fffffff
    and     x0, x10, x11
    ret

// rng_range: x0 = max ; returns x0 in [0, max)
// Uses udiv + msub to compute the modulo.
rng_range:
    cmp     x0, #0
    b.le    .Lrng_range_zero
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0                     // save max
    bl      rng_next                    // x0 = random
    udiv    x10, x0, x19                // q = r / max
    msub    x0, x10, x19, x0            // r - q*max
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lrng_range_zero:
    mov     x0, #0
    ret

// evaluate_shoot: x0 = shooting, x1 = distance_fx ; returns score in x0
// score = max(0, shooting * 10 - (dist_fx >> 16))
evaluate_shoot:
    mov     x9, #10
    mul     x0, x0, x9                  // base = shooting * 10
    asr     x1, x1, #16                 // dist_units
    sub     x0, x0, x1
    cmp     x0, #0
    b.ge    .Les_done
    mov     x0, #0
.Les_done:
    ret

// evaluate_dunk: x0 = dunking, x1 = distance_fx ; returns score
// if (dist_fx >> 16) > 3 -> 0 else dunking * 15
evaluate_dunk:
    asr     x1, x1, #16
    cmp     x1, #3
    b.gt    .Led_far
    mov     x9, #15
    mul     x0, x0, x9
    ret
.Led_far:
    mov     x0, #0
    ret

// apply_urgency: x0 = score, x1 = shot_clock ; returns urgency-adjusted score
// urgency = max(1, (24 - clock) / 4); return score * urgency
apply_urgency:
    mov     x9, #24
    sub     x1, x9, x1                  // 24 - clock
    asr     x1, x1, #2                  // /4 (signed)
    cmp     x1, #1
    b.ge    .Lau_ok
    mov     x1, #1
.Lau_ok:
    mul     x0, x0, x1
    ret

// _start: run all tests
_start:
    // Test 1: evaluate_shoot(9, 3<<16) == 87
    mov     x0, #9
    mov     x1, #3
    lsl     x1, x1, #16
    bl      evaluate_shoot
    cmp     x0, #87
    b.ne    fail

    // Test 2: evaluate_shoot(1, 20<<16) == 0
    mov     x0, #1
    mov     x1, #20
    lsl     x1, x1, #16
    bl      evaluate_shoot
    cbnz    x0, fail

    // Test 3: evaluate_shoot(10, 0) == 100
    mov     x0, #10
    mov     x1, #0
    bl      evaluate_shoot
    cmp     x0, #100
    b.ne    fail

    // Test 4: evaluate_dunk(8, 2<<16) == 120
    mov     x0, #8
    mov     x1, #2
    lsl     x1, x1, #16
    bl      evaluate_dunk
    cmp     x0, #120
    b.ne    fail

    // Test 5: evaluate_dunk(10, 10<<16) == 0 (too far)
    mov     x0, #10
    mov     x1, #10
    lsl     x1, x1, #16
    bl      evaluate_dunk
    cbnz    x0, fail

    // Test 6: apply_urgency(50, 24) == 50
    mov     x0, #50
    mov     x1, #24
    bl      apply_urgency
    cmp     x0, #50
    b.ne    fail

    // Test 7: apply_urgency(50, 2) == 250
    mov     x0, #50
    mov     x1, #2
    bl      apply_urgency
    cmp     x0, #250
    b.ne    fail

    // Test 8: PRNG determinism (same seed produces same first value)
    ldr     x0, =77777
    bl      rng_seed
    bl      rng_next
    mov     x19, x0                     // save value

    ldr     x0, =77777
    bl      rng_seed
    bl      rng_next
    cmp     x0, x19
    b.ne    fail

    // Test 9: PRNG variation (consecutive values differ)
    mov     x0, #42
    bl      rng_seed
    bl      rng_next
    mov     x19, x0
    bl      rng_next
    cmp     x0, x19
    b.eq    fail

    // Test 10: rng_range(100) returns value in [0, 100)
    mov     x0, #1234
    bl      rng_seed
    mov     x0, #100
    bl      rng_range
    cmp     x0, #0
    b.lt    fail
    cmp     x0, #100
    b.ge    fail

    // All passed
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
