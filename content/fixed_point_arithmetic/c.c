// Vidya — Fixed-Point Arithmetic in C
//
// 16.16 fixed-point on int64_t. C's >> on signed integers is
// implementation-defined for negative values (gcc and clang emit
// arithmetic shift, MSVC ditto in practice), but we don't rely on
// that — fx_to_int handles negative truncation explicitly so the
// behaviour matches Rust / Python / Cyrius across compilers.
//
// fx_mul uses __int128 for the intermediate product so 16.16 ×
// 16.16 doesn't wrap. fx_mul_safe demonstrates the pre-shift pattern
// for environments without 128-bit integers.

#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

// M_PI is a POSIX/GNU extension, not in strict C17 — define inline.
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define FX_SHIFT 16
#define FX_ONE   ((int64_t)1 << FX_SHIFT)
#define FX_HALF  ((int64_t)1 << (FX_SHIFT - 1))

static int64_t fx_from_int(int64_t n) {
    return n << FX_SHIFT;
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
    return (int64_t)(((__int128)a * (__int128)b) >> FX_SHIFT);
}

static int64_t fx_mul_safe(int64_t a, int64_t b) {
    return (a >> 8) * (b >> 8);
}

static int64_t fx_div(int64_t a, int64_t b) {
    if (b == 0) return 0;
    return (int64_t)(((__int128)a << FX_SHIFT) / b);
}

// ── Sine table — quarter-wave, 256 entries ────────────────────────────
static int64_t sin_table[256];

static void build_sin_table(void) {
    for (int i = 0; i < 256; i++) {
        double angle = (double)i * (M_PI / 2.0) / 256.0;
        sin_table[i] = (int64_t)(sin(angle) * (double)FX_ONE);
    }
}

static int64_t sin_lookup(int64_t angle) {
    int a = (int)(angle & 1023);
    if (a < 256) return sin_table[a];
    if (a < 512) return sin_table[511 - a];
    if (a < 768) return -sin_table[a - 512];
    return -sin_table[1023 - a];
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

    int64_t big = fx_from_int(1000);
    assert(fx_mul_safe(big, big) > 0);

    assert(fx_div(fx_from_int(10), fx_from_int(4)) == 163840);
    assert(fx_div(FX_ONE, 0) == 0);

    assert(fx_to_int(-fx_from_int(3)) == -3);
    assert(fx_to_int(-(FX_ONE + FX_HALF)) == -1);
    assert(fx_to_int_round(-(FX_ONE + FX_HALF)) == -2);

    build_sin_table();
    assert(sin_lookup(0) == 0);
    assert(sin_lookup(256) > 60000);
    assert(sin_lookup(512) == 0);
    assert(sin_lookup(768) < -60000);

    for (int i = 0; i < 100; i++) {
        assert(fx_to_int(fx_from_int(i)) == i);
    }

    puts("All fixed_point_arithmetic examples passed.");
    return 0;
}
