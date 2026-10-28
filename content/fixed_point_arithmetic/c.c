// Vidya — Fixed-Point Arithmetic in C
//
// 16.16 fixed-point on int64_t. Two shift rules matter, and C23 kept
// both (6.5.7): `>>` of a negative signed value is implementation-
// defined (gcc and clang define it as an arithmetic shift), and `<<`
// of a negative signed value is undefined behaviour. So fx_from_int
// and fx_div scale up by multiplying by FX_ONE rather than shifting
// left, and fx_to_int handles negative truncation explicitly so it
// matches Rust / Python / Cyrius across compilers. fx_mul and
// fx_mul_safe do shift negative products right, so they rely on the
// gcc/clang arithmetic shift (rounding toward -infinity).
//
// fx_mul widens the intermediate product to C23's _BitInt(128) so
// 16.16 × 16.16 doesn't wrap. _BitInt is standard C23 (GNU __int128
// is an extension that -Wpedantic rejects), but a width above 64 is
// optional: C23 only guarantees BITINT_MAXWIDTH >= 64, hence the
// static_assert. fx_mul_safe demonstrates the pre-shift pattern for
// targets without 128-bit integers.

#include <assert.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

// M_PI is a POSIX/GNU extension, not in strict C23 — define inline.
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define FX_SHIFT 16
#define FX_ONE   ((int64_t)1 << FX_SHIFT)
#define FX_HALF  ((int64_t)1 << (FX_SHIFT - 1))

static_assert(BITINT_MAXWIDTH >= 128, "fx_mul needs _BitInt(128)");
typedef _BitInt(128) fx_wide;

static int64_t fx_from_int(int64_t n) {
    return n * FX_ONE;   // n << FX_SHIFT is UB for negative n
}

static int64_t fx_to_int(int64_t v) {
    return (v < 0) ? -(int64_t)(((uint64_t)-v) >> FX_SHIFT)
                   :  (int64_t)(((uint64_t)v) >> FX_SHIFT);
}

static int64_t fx_to_int_round(int64_t v) {
    return (v < 0) ? -(int64_t)(((uint64_t)(-v + FX_HALF)) >> FX_SHIFT)
                   :  (int64_t)(((uint64_t)(v + FX_HALF)) >> FX_SHIFT);
}

static int64_t fx_mul(int64_t a, int64_t b) {
    return (int64_t)(((fx_wide)a * b) >> FX_SHIFT);
}

static int64_t fx_mul_safe(int64_t a, int64_t b) {
    return (a >> 8) * (b >> 8);
}

static int64_t fx_div(int64_t a, int64_t b) {
    if (b == 0) return 0;
    return (int64_t)(((fx_wide)a * FX_ONE) / b);
}

// ── Sine table — quarter-wave, 256 steps (257 entries, 0..π/2 inclusive) ─
// The mirror of step a in quadrant 2 is 512 - a, so the table needs the
// π/2 endpoint; mirroring with 511 - a instead is off by one step and
// costs ~400x accuracy in quadrants 2 and 4 (sin(511) would read as 0).
static int64_t sin_table[257];

static void build_sin_table(void) {
    for (int i = 0; i <= 256; i++) {
        double angle = (double)i * (M_PI / 2.0) / 256.0;
        sin_table[i] = (int64_t)(sin(angle) * (double)FX_ONE);
    }
}

static int64_t sin_lookup(int64_t angle) {
    int a = (int)(angle & 1023);
    if (a < 256) return sin_table[a];
    if (a < 512) return sin_table[512 - a];
    if (a < 768) return -sin_table[a - 512];
    return -sin_table[1024 - a];
}

// ── Tests ─────────────────────────────────────────────────────────────

int main(void) {
    assert(fx_from_int(1) == 65536);
    assert(fx_from_int(10) == 655360);
    assert(fx_from_int(0) == 0);

    int64_t three = fx_from_int(3);
    int64_t two_half = 163840; // 2.5 in 16.16
    assert(fx_mul(three, two_half) == 491520);   // 3.0 * 2.5 == 7.5
    assert(fx_mul(FX_ONE, FX_ONE) == FX_ONE);
    assert(fx_mul(FX_HALF, FX_HALF) == 16384);   // 0.5 * 0.5 == 0.25

    assert(fx_mul(fx_from_int(-3), two_half) == -491520);  // -3.0 * 2.5

    int64_t big = fx_from_int(1000);
    assert(fx_mul_safe(big, big) == fx_from_int(1000000));
    assert(fx_mul(1, FX_ONE) == 1);         // full precision
    assert(fx_mul_safe(1, FX_ONE) == 0);    // pre-shift drops the low 8 bits

    assert(fx_div(fx_from_int(10), fx_from_int(4)) == 163840);
    assert(fx_div(fx_from_int(-10), fx_from_int(4)) == -163840);  // -2.5
    assert(fx_div(FX_ONE, 0) == 0);

    assert(fx_from_int(-3) == -196608);
    assert(fx_to_int(fx_from_int(-3)) == -3);
    assert(fx_to_int(-(FX_ONE + FX_HALF)) == -1);
    assert(fx_to_int_round(-(FX_ONE + FX_HALF)) == -2);

    build_sin_table();
    assert(sin_lookup(0) == 0);
    assert(sin_lookup(256) > 60000);
    assert(sin_lookup(512) == 0);
    assert(sin_lookup(768) < -60000);
    assert(sin_lookup(511) == sin_lookup(1));     // sin(π - x) == sin(x)
    assert(sin_lookup(1023) == -sin_lookup(1));   // sin(2π - x) == -sin(x)

    for (int i = 0; i < 100; i++) {
        assert(fx_to_int(fx_from_int(i)) == i);
    }

    puts("All fixed_point_arithmetic examples passed.");
    return 0;
}
