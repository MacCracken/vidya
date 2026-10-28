// Vidya — Fixed-Point Arithmetic in AArch64 Assembly
//
// 16.16 fixed-point on x-registers (64-bit). AArch64's ASR (arithmetic
// shift right) is sign-preserving on negatives, and SMULH gives the
// upper 64 bits of a 64×64 multiply. Paired with MUL for the low 64
// bits it builds the full 128-bit 16.16 product — two multiplies, where
// x86_64's one-operand IMUL yields both halves in RDX:RAX at once.
//
// The sine table holds trunc(sin(i·π/512)·65536), the same values the
// C/Python/Rust ports compute at startup. Linux Aarch64 syscall ABI: x8
// holds the syscall number, args in x0–x5, return in x0.

.global _start

.section .rodata

// 257-entry quarter-wave sine table (16.16 fixed-point)
// trunc(sin(i * π/512) * 65536) for i = 0..256 — 0 .. π/2 INCLUSIVE.
// The mirror sin(π - x) = sin(x) reads index 512 - a, which reaches 256,
// so the table needs its π/2 endpoint. Mirroring with 511 - a instead (to
// fit 256 entries) puts quadrants 2 and 4 one step out of phase:
// sin(511) would read 0 where the true value is 402/65536.
.align 4
sine_table:
    .quad 0, 402, 804, 1206, 1608, 2010, 2412, 2814
    .quad 3215, 3617, 4018, 4420, 4821, 5222, 5622, 6023
    .quad 6423, 6823, 7223, 7623, 8022, 8421, 8819, 9218
    .quad 9616, 10013, 10410, 10807, 11204, 11600, 11995, 12390
    .quad 12785, 13179, 13573, 13966, 14359, 14751, 15142, 15533
    .quad 15923, 16313, 16702, 17091, 17479, 17866, 18253, 18638
    .quad 19024, 19408, 19792, 20175, 20557, 20938, 21319, 21699
    .quad 22078, 22456, 22833, 23210, 23586, 23960, 24334, 24707
    .quad 25079, 25450, 25820, 26189, 26557, 26925, 27291, 27656
    .quad 28020, 28383, 28745, 29105, 29465, 29824, 30181, 30538
    .quad 30893, 31247, 31600, 31952, 32302, 32651, 32999, 33346
    .quad 33692, 34036, 34379, 34721, 35061, 35400, 35738, 36074
    .quad 36409, 36743, 37075, 37406, 37736, 38064, 38390, 38716
    .quad 39039, 39362, 39682, 40002, 40319, 40636, 40950, 41263
    .quad 41575, 41885, 42194, 42501, 42806, 43110, 43412, 43712
    .quad 44011, 44308, 44603, 44897, 45189, 45480, 45768, 46055
    .quad 46340, 46624, 46906, 47186, 47464, 47740, 48015, 48288
    .quad 48558, 48828, 49095, 49360, 49624, 49886, 50146, 50403
    .quad 50660, 50914, 51166, 51416, 51665, 51911, 52155, 52398
    .quad 52639, 52877, 53114, 53348, 53581, 53811, 54040, 54266
    .quad 54491, 54713, 54933, 55152, 55368, 55582, 55794, 56004
    .quad 56212, 56417, 56621, 56822, 57022, 57219, 57414, 57606
    .quad 57797, 57986, 58172, 58356, 58538, 58718, 58895, 59070
    .quad 59243, 59414, 59583, 59749, 59913, 60075, 60235, 60392
    .quad 60547, 60700, 60850, 60998, 61144, 61288, 61429, 61568
    .quad 61705, 61839, 61971, 62100, 62228, 62353, 62475, 62596
    .quad 62714, 62829, 62942, 63053, 63162, 63268, 63371, 63473
    .quad 63571, 63668, 63762, 63854, 63943, 64030, 64115, 64197
    .quad 64276, 64353, 64428, 64501, 64571, 64638, 64703, 64766
    .quad 64826, 64884, 64939, 64992, 65043, 65091, 65136, 65179
    .quad 65220, 65258, 65294, 65327, 65358, 65386, 65412, 65436
    .quad 65457, 65475, 65491, 65505, 65516, 65524, 65531, 65534
    .quad 65536                      // i = 256: sin(π/2) = 1.0 exactly

msg_pass:    .ascii "All fixed_point_arithmetic examples passed.\n"
msg_pass_len = . - msg_pass

msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// ── fx_mul: x0 = (x0 * x1) >> 16 ─────────────────────────────────────
// Uses MUL for the low 64 bits + SMULH for the high 64 bits, then
// concatenates into a 128-bit product and shifts right by 16.
fx_mul:
    // low 64 = x0 * x1 ; high 64 = SMULH x0, x1
    smulh   x2, x0, x1          // x2 = high 64 of product
    mul     x3, x0, x1          // x3 = low  64 of product
    // result = (high << 48) | (low >> 16)
    lsr     x3, x3, #16
    lsl     x2, x2, #48
    orr     x0, x2, x3
    ret

// ── fx_div: x0 = (x0 << 16) / x1 ─────────────────────────────────────
// Returns 0 when x1 == 0.
fx_div:
    cbz     x1, .Lfx_div_zero
    lsl     x0, x0, #16
    sdiv    x0, x0, x1
    ret
.Lfx_div_zero:
    mov     x0, #0
    ret

// ── asr: arithmetic shift right by x1 of value x0 ────────────────────
// Sign-preserving — the ASR mnemonic does exactly this. Wrapping the
// instruction in a labelled function so callers can branch to it like
// the Cyrius reference does.
asr:
    asr     x0, x0, x1
    ret

// ── sin_lookup: x0 = sin_lookup(x0) ──────────────────────────────────
// angle in x0 (low 10 bits significant), result in x0.
sin_lookup:
    and     x0, x0, #1023
    adrp    x9, sine_table
    add     x9, x9, :lo12:sine_table
    cmp     x0, #256
    b.lt    .Ls_q1
    cmp     x0, #512
    b.lt    .Ls_q2
    cmp     x0, #768
    b.lt    .Ls_q3
    // q4: -table[1024 - a]   (sin(2π - x) = -sin(x))
    mov     x10, #1024
    sub     x0, x10, x0
    ldr     x0, [x9, x0, lsl #3]
    neg     x0, x0
    ret
.Ls_q1:
    ldr     x0, [x9, x0, lsl #3]
    ret
.Ls_q2:
    // q2: table[512 - a]   (sin(π - x) = sin(x))
    mov     x10, #512
    sub     x0, x10, x0
    ldr     x0, [x9, x0, lsl #3]
    ret
.Ls_q3:
    sub     x0, x0, #512
    ldr     x0, [x9, x0, lsl #3]
    neg     x0, x0
    ret

// ── _start: run all tests ────────────────────────────────────────────
// Note on `ldr xN, =imm` form: AArch64 `mov` accepts only 16-bit
// immediate fields with optional 16-bit shifts. Constants like 163840
// (0x28000) span bit positions that don't align to a single movz, so
// we use the assembler's literal-pool load form `ldr x10, =N` which
// handles any 64-bit constant uniformly.
_start:
    // Test 1: fx_mul(FX_ONE, FX_ONE) == FX_ONE
    ldr     x0, =65536
    ldr     x1, =65536
    bl      fx_mul
    ldr     x10, =65536
    cmp     x0, x10
    b.ne    fail

    // Test 2: fx_mul(0.5, 0.5) == 0.25  (16384)
    ldr     x0, =32768
    ldr     x1, =32768
    bl      fx_mul
    ldr     x10, =16384
    cmp     x0, x10
    b.ne    fail

    // Test 3: fx_div(FX_ONE * 10, FX_ONE * 4) == 163840  (2.5)
    ldr     x0, =655360
    ldr     x1, =262144
    bl      fx_div
    ldr     x10, =163840
    cmp     x0, x10
    b.ne    fail

    // Test 4: fx_div(FX_ONE, 0) == 0
    ldr     x0, =65536
    mov     x1, #0
    bl      fx_div
    cbnz    x0, fail

    // Test 5: asr(-256, 1) == -128
    mov     x0, #-256
    mov     x1, #1
    bl      asr
    mov     x10, #-128
    cmp     x0, x10
    b.ne    fail

    // Test 6: sin_lookup(0) == 0
    mov     x0, #0
    bl      sin_lookup
    cbnz    x0, fail

    // Test 7: sin_lookup(256) == 1.0 exactly (table[256] = 65536)
    mov     x0, #256
    bl      sin_lookup
    ldr     x10, =65536
    cmp     x0, x10
    b.ne    fail

    // Test 8: sin_lookup(512) == 0
    ldr     x0, =512
    bl      sin_lookup
    cbnz    x0, fail

    // Test 9: sin_lookup(768) == -1.0 exactly
    ldr     x0, =768
    bl      sin_lookup
    ldr     x10, =-65536
    cmp     x0, x10
    b.ne    fail

    // Test 10: the mirrors line up with quadrant 1:
    // sin(511) == sin(1) and sin(1023) == -sin(1) (402 = trunc(sin(π/512)·65536)),
    // sin(384) == sin(128) (46340 = trunc(sin(π/4)·65536)).
    ldr     x0, =511
    bl      sin_lookup
    mov     x10, #402
    cmp     x0, x10
    b.ne    fail
    ldr     x0, =1023
    bl      sin_lookup
    mov     x10, #-402
    cmp     x0, x10
    b.ne    fail
    ldr     x0, =384
    bl      sin_lookup
    ldr     x10, =46340
    cmp     x0, x10
    b.ne    fail

    // All passed — print and exit 0
    mov     x0, #1                  // stdout
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64                 // SYS_write
    svc     #0
    mov     x0, #0
    mov     x8, #93                 // SYS_exit
    svc     #0

fail:
    mov     x0, #2                  // stderr
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
