// Vidya — 2D Collision Detection in C
//
// All coordinates in 16.16 fixed-point on int64_t. The Cyrius
// reference pre-shifts deltas by 4 before squaring so the squared
// sum fits in a signed 64-bit register; we mirror that pattern. For
// fully precise products without precision loss, widen to C23's
// _BitInt(128) (see dist_sq_wide) — standard C23, unlike the GNU
// __int128 extension, though C23 only guarantees widths up to
// BITINT_MAXWIDTH (>= 64). C's >> on a negative signed value is still
// implementation-defined in C23 (6.5.7), and it rounds toward
// -infinity on gcc/clang, so dist_sq shifts |delta|: shifting the raw
// delta made dist_sq(a, b) and dist_sq(b, a) disagree.

#include <assert.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define FX_SHIFT 16
#define FX_ONE   ((int64_t)1 << FX_SHIFT)

static int64_t fx(int64_t n) { return n << FX_SHIFT; }

static int64_t dist_sq(int64_t x1, int64_t y1, int64_t x2, int64_t y2) {
    int64_t dx = (x2 > x1 ? x2 - x1 : x1 - x2) >> 4;
    int64_t dy = (y2 > y1 ? y2 - y1 : y1 - y2) >> 4;
    return dx * dx + dy * dy;
}

// Demonstration of the 128-bit widened form for callers that need full
// precision. Unused in the test set (kept inline for the comment).
static_assert(BITINT_MAXWIDTH >= 128, "dist_sq_wide needs _BitInt(128)");
[[maybe_unused]]
static int64_t dist_sq_wide(int64_t x1, int64_t y1, int64_t x2, int64_t y2) {
    _BitInt(128) dx = x2 - x1;
    _BitInt(128) dy = y2 - y1;
    return (int64_t)(((dx * dx) + (dy * dy)) >> 8);
}

static bool circle_circle(int64_t x1, int64_t y1, int64_t r1,
                          int64_t x2, int64_t y2, int64_t r2) {
    int64_t d2 = dist_sq(x1, y1, x2, y2);
    int64_t sum_r = (r1 + r2) >> 4;
    return d2 <= sum_r * sum_r;
}

static bool aabb_overlap(int64_t l1, int64_t t1, int64_t r1, int64_t b1,
                         int64_t l2, int64_t t2, int64_t r2, int64_t b2) {
    if (l1 >= r2) return false;
    if (r1 <= l2) return false;
    if (t1 >= b2) return false;
    if (b1 <= t2) return false;
    return true;
}

static bool point_in_rect(int64_t px, int64_t py,
                          int64_t left, int64_t top,
                          int64_t right, int64_t bottom) {
    return px >= left && px < right && py >= top && py < bottom;
}

static int64_t clampll(int64_t v, int64_t lo, int64_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

static bool circle_aabb(int64_t cx, int64_t cy, int64_t cr,
                        int64_t left, int64_t top,
                        int64_t right, int64_t bottom) {
    int64_t closest_x = clampll(cx, left, right);
    int64_t closest_y = clampll(cy, top, bottom);
    int64_t d2 = dist_sq(cx, cy, closest_x, closest_y);
    int64_t r = cr >> 4;
    return d2 <= r * r;
}

static bool point_in_circle(int64_t px, int64_t py,
                            int64_t cx, int64_t cy, int64_t cr) {
    int64_t d2 = dist_sq(px, py, cx, cy);
    int64_t r = cr >> 4;
    return d2 <= r * r;
}

static int64_t push_apart_x(int64_t x1, int64_t x2, int64_t overlap) {
    int64_t dx = x2 - x1;
    int64_t half = overlap >> 1;
    return (dx > 0) ? -half : half;
}

static int64_t swept_aabb_x(int64_t al, int64_t ar, int64_t vx,
                            int64_t bl, int64_t br) {
    if (vx == 0) return FX_ONE;
    int64_t enter_dist, exit_dist;
    if (vx > 0) { enter_dist = bl - ar; exit_dist = br - al; }
    else        { enter_dist = br - al; exit_dist = bl - ar; }
    // Keep the signs: enter < 0 means already overlapping at t=0, and
    // exit < 0 means the boxes are separating. abs() would turn an
    // existing overlap into a future hit (or a miss).
    int64_t enter = enter_dist * FX_ONE / vx;
    int64_t exit_ = exit_dist  * FX_ONE / vx;
    if (exit_ < 0 || enter > exit_ || enter > FX_ONE) return FX_ONE;
    return enter < 0 ? 0 : enter;
}

// ── Tests ─────────────────────────────────────────────────────────────

int main(void) {
    assert(circle_circle(fx(10), fx(10), fx(5), fx(13), fx(10), fx(5)));
    assert(!circle_circle(fx(0), fx(0), fx(1), fx(100), fx(100), fx(1)));
    assert(circle_circle(fx(0), fx(0), fx(5), fx(10), fx(0), fx(5)));

    assert(aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                        fx(5), fx(5), fx(15), fx(15)));
    assert(!aabb_overlap(fx(0), fx(0), fx(5), fx(5),
                         fx(10), fx(10), fx(20), fx(20)));
    assert(!aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                         fx(10), fx(0), fx(20), fx(10)));

    assert(point_in_rect(fx(5), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(!point_in_rect(fx(15), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(point_in_rect(fx(0), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(!point_in_rect(fx(10), fx(5), fx(0), fx(0), fx(10), fx(10)));

    assert(circle_aabb(fx(5), fx(5), fx(3), fx(0), fx(0), fx(10), fx(10)));
    assert(!circle_aabb(fx(20), fx(20), fx(3), fx(0), fx(0), fx(10), fx(10)));

    assert(point_in_circle(fx(1), fx(1), fx(0), fx(0), fx(5)));
    assert(!point_in_circle(fx(100), fx(100), fx(0), fx(0), fx(5)));

    assert(dist_sq(fx(0), fx(0), fx(3), fx(4)) == 25 * (FX_ONE * FX_ONE >> 8));
    // Symmetric even when the delta is not a multiple of 16 raw units
    assert(dist_sq(0, 0, 65537, 0) == dist_sq(65537, 0, 0, 0));
    assert(circle_circle(0, 0, FX_ONE / 2, FX_ONE + 1, 0, FX_ONE / 2) ==
           circle_circle(FX_ONE + 1, 0, FX_ONE / 2, 0, 0, FX_ONE / 2));

    assert(push_apart_x(fx(0), fx(4), fx(2)) < 0);

    int64_t toi = swept_aabb_x(fx(0), fx(2), fx(8), fx(6), fx(10));
    assert(toi > 0 && toi < FX_ONE);
    int64_t toi2 = swept_aabb_x(fx(0), fx(2), -fx(1), fx(6), fx(10));
    assert(toi2 == FX_ONE);
    // Already overlapping at t=0 → contact time 0, not a later hit
    assert(swept_aabb_x(fx(0), fx(4), fx(8), fx(2), fx(6)) == 0);
    assert(swept_aabb_x(fx(3), fx(5), fx(8), fx(0), fx(4)) == 0);
    // Moving left onto a box on the left: 6 units at 8/frame → t = 0.75
    assert(swept_aabb_x(fx(10), fx(12), -fx(8), fx(0), fx(4)) == FX_ONE * 3 / 4);

    puts("All collision_detection_2d examples passed.");
    return 0;
}
