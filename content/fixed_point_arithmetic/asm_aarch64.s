// Vidya — Fixed-Point Arithmetic in AArch64 Assembly
//
// 16.16 fixed-point on x-registers (64-bit). AArch64's ASR (arithmetic
// shift right) is sign-preserving on negatives, and SMULH gives the
// upper 64 bits of a 64×64 multiply — together they make the 16.16
// product cheaper than the x86_64 form (which needs IMUL + RDX:RAX).
//
// The sine table is the same 256-entry quarter-wave table as the x86
// version; values verified to match. Linux Aarch64 syscall ABI: x8
// holds the syscall number, args in x0–x5, return in x0.

.global _start

.section .rodata

// 256-entry quarter-wave sine table (16.16 fixed-point)
// sin(i * π/512) * 65536 for i = 0..255
.align 4
sine_table:
    .quad 0, 402, 804, 1206, 1608, 2010, 2412, 2814
    .quad 3216, 3617, 4019, 4420, 4821, 5222, 5623, 6023
    .quad 6424, 6824, 7224, 7623, 8022, 8421, 8820, 9218
    .quad 9616, 10014, 10411, 10808, 11204, 11600, 11996, 12391
    .quad 12785, 13179, 13573, 13966, 14359, 14751, 15143, 15534
    .quad 15924, 16314, 16703, 17091, 17479, 17867, 18253, 18639
    .quad 19024, 19409, 19793, 20176, 20558, 20939, 21320, 21699
    .quad 22078, 22456, 22834, 23210, 23586, 23960, 24334, 24707
    .quad 25079, 25450, 25821, 26190, 26558, 26925, 27291, 27656
    .quad 28020, 28383, 28745, 29106, 29466, 29824, 30182, 30538
    .quad 30893, 31248, 31600, 31952, 32303, 32652, 33000, 33347
    .quad 33692, 34036, 34379, 34721, 35062, 35401, 35738, 36075
    .quad 36410, 36744, 37076, 37407, 37736, 38064, 38391, 38716
    .quad 39040, 39362, 39683, 40002, 40320, 40636, 40951, 41264
    .quad 41576, 41886, 42194, 42501, 42806, 43110, 43412, 43713
    .quad 44011, 44308, 44604, 44898, 45190, 45481, 45769, 46056
    .quad 46341, 46624, 46906, 47186, 47464, 47740, 48015, 48287
    .quad 48558, 48828, 49095, 49361, 49624, 49886, 50146, 50404
    .quad 50660, 50914, 51166, 51416, 51665, 51911, 52155, 52398
    .quad 52639, 52877, 53114, 53348, 53581, 53811, 54040, 54266
    .quad 54491, 54713, 54933, 55152, 55368, 55582, 55794, 56003
    .quad 56211, 56417, 56620, 56822, 57021, 57218, 57413, 57606
    .quad 57797, 57986, 58172, 58356, 58538, 58718, 58895, 59070
    .quad 59243, 59414, 59582, 59749, 59913, 60074, 60234, 60391
    .quad 60546, 60698, 60849, 60997, 61142, 61286, 61427, 61565
    .quad 61702, 61836, 61967, 62097, 62224, 62348, 62470, 62590
    .quad 62707, 62822, 62935, 63045, 63152, 63258, 63360, 63461
    .quad 63559, 63655, 63748, 63838, 63927, 64012, 64096, 64176
    .quad 64255, 64331, 64404, 64475, 64543, 64609, 64673, 64734
    .quad 64792, 64848, 64902, 64953, 65001, 65047, 65091, 65132
    .quad 65170, 65206, 65240, 65271, 65299, 65325, 65349, 65370
    .quad 65389, 65405, 65419, 65430, 65439, 65445, 65449, 65451

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
    // q4: -table[1023 - a]
    mov     x10, #1023
    sub     x0, x10, x0
    ldr     x0, [x9, x0, lsl #3]
    neg     x0, x0
    ret
.Ls_q1:
    ldr     x0, [x9, x0, lsl #3]
    ret
.Ls_q2:
    mov     x10, #511
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

    // Test 7: sin_lookup(256) ≈ 1.0  (table[255] = 65451 — within tolerance)
    mov     x0, #256
    bl      sin_lookup
    ldr     x10, =60000
    cmp     x0, x10
    b.le    fail

    // Test 8: sin_lookup(512) == 0
    ldr     x0, =512
    bl      sin_lookup
    cbnz    x0, fail

    // Test 9: sin_lookup(768) ≈ -1.0
    ldr     x0, =768
    bl      sin_lookup
    ldr     x10, =-60000
    cmp     x0, x10
    b.ge    fail

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
