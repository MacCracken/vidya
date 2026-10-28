// Vidya — Projectile Physics in C
//
// Semi-implicit Euler integration in 16.16 fixed-point on int64_t.
// The bounce-restitution multiply stays in int64_t: the worst-case
// `vy * RESTITUTION` in these tests (~3.6e10) is far below INT64_MAX
// (~9.2e18), so no 128-bit intermediate is needed (GNU __int128 is a
// non-portable extension anyway; C23's standard spelling is
// _BitInt(128)). Widening would not change the shift either: C23 6.5.7
// still leaves `>>` of a negative signed value implementation-defined,
// whatever its width. bounce_check runs after a step carried y past
// the floor, so vy > 0 there and the `>>` sees a non-negative product.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define FX_SHIFT     16
#define GRAVITY      ((int64_t)6554)
#define FLOOR_Y      ((int64_t)14745600)
#define RESTITUTION  ((int64_t)45875)

typedef struct {
    int64_t x;
    int64_t y;
    int64_t vx;
    int64_t vy;
} Ball;

static void physics_step(Ball *b) {
    // Semi-implicit Euler: velocity first, then position.
    b->vy += GRAVITY;
    b->y  += b->vy;
    b->x  += b->vx;
}

static void bounce_check(Ball *b) {
    if (b->y > FLOOR_Y) {
        b->y = FLOOR_Y;
        // vy = -(vy * restitution) >> 16 — fits int64_t (see header).
        b->vy = -((b->vy * RESTITUTION) >> FX_SHIFT);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

static void test_gravity(void) {
    Ball b = {0, 0, 0, 0};
    physics_step(&b);
    assert(b.vy == GRAVITY);
    assert(b.y  == GRAVITY);   // semi-implicit: position uses NEW velocity
}

static void test_parabolic_arc(void) {
    Ball b = {0, 6553600, 0, -1310720};  // y=100.0, vy=-20.0
    int64_t initial_y = b.y;

    for (int i = 0; i < 50; i++) physics_step(&b);
    assert(b.y < initial_y);   // rising

    for (int i = 0; i < 400; i++) physics_step(&b);
    assert(b.y > initial_y);   // fallen past start
}

static void test_bounce(void) {
    Ball b = {0, FLOOR_Y + 1, 0, 655360};  // vy=10.0 down, past floor
    bounce_check(&b);
    assert(b.vy < 0);                       // reflected
    assert(-b.vy < 655360);                 // damped
    assert(b.y == FLOOR_Y);                 // reset to surface
}

static void test_horizontal_unchanged(void) {
    int64_t vx_initial = 131072;            // 2.0
    Ball b = {0, 0, vx_initial, 0};
    physics_step(&b);
    physics_step(&b);
    physics_step(&b);
    assert(b.vx == vx_initial);
    assert(b.x  == 3 * vx_initial);
}

static void test_energy_decay(void) {
    Ball b = {0, 0, 0, 655360};             // vy=10.0 down

    // 1000 frames — |vy| plateaus around 2700, well under 2*GRAVITY=13108.
    for (int i = 0; i < 1000; i++) {
        physics_step(&b);
        bounce_check(&b);
    }

    int64_t abs_vy = b.vy < 0 ? -b.vy : b.vy;
    assert(abs_vy < GRAVITY * 2);
}

static void test_semi_implicit_stability(void) {
    int64_t start_y = FLOOR_Y - 655360;     // 10.0 above floor
    Ball b = {0, start_y, 0, -655360};      // vy=-10.0 upward
    int64_t min_y = start_y;

    for (int i = 0; i < 500; i++) {
        physics_step(&b);
        bounce_check(&b);
        if (b.y < min_y) min_y = b.y;
    }

    int64_t max_rise = (int64_t)1000 * 65536;
    assert(min_y > start_y - max_rise);
}

int main(void) {
    test_gravity();
    test_parabolic_arc();
    test_bounce();
    test_horizontal_unchanged();
    test_energy_decay();
    test_semi_implicit_stability();
    puts("All projectile_physics examples passed.");
    return 0;
}
