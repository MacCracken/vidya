// Vidya — Game Loop Architecture in C
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loop_step` takes an elapsed-microsecond delta and returns the number
// of fixed-step updates fired this frame. C's `int64_t` from <stdint.h>
// is the right choice for monotonic-time math (~292 years before wrap).
// A real game would feed deltas from clock_gettime(CLOCK_MONOTONIC),
// but tests use deterministic deltas so they behave identically on
// every machine.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define DT_US        ((int64_t)16667)
#define MAX_ACCUM    ((int64_t)83335)   // 5 * DT_US

typedef struct {
    int64_t accum;
    int64_t update_count;
    int64_t render_count;
} GameLoop;

static int64_t loop_step(GameLoop *g, int64_t elapsed_us) {
    int64_t accum = g->accum + elapsed_us;
    // Spiral-of-death cap: never let the accumulator exceed MAX_ACCUM.
    if (accum > MAX_ACCUM) accum = MAX_ACCUM;
    int64_t updates = 0;
    while (accum >= DT_US) {
        accum -= DT_US;
        updates++;
    }
    g->accum = accum;
    g->update_count += updates;
    g->render_count += 1;
    return updates;
}

static void test_exact_dt_fires_one_update(void) {
    GameLoop g = {0};
    int64_t u = loop_step(&g, DT_US);
    assert(u == 1);
    assert(g.update_count == 1);
}

static void test_under_dt_no_update(void) {
    GameLoop g = {0};
    int64_t u = loop_step(&g, DT_US / 2);
    assert(u == 0);
}

static void test_catchup_50ms(void) {
    GameLoop g = {0};
    int64_t u = loop_step(&g, 50000);
    assert(u == 2);
}

static void test_spiral_of_death_cap(void) {
    GameLoop g = {0};
    int64_t u = loop_step(&g, 1000000);
    assert(u == 5);
}

static void test_render_per_frame(void) {
    GameLoop g = {0};
    loop_step(&g, DT_US);
    loop_step(&g, DT_US);
    loop_step(&g, DT_US);
    assert(g.render_count == 3);
    assert(g.update_count == 3);
}

static void test_accumulator_remainder(void) {
    GameLoop g = {0};
    int64_t one_and_half = DT_US + (DT_US / 2);
    loop_step(&g, one_and_half);
    assert(g.accum > DT_US / 4);
    assert(g.accum < DT_US);
}

static void test_input_update_render_separation(void) {
    GameLoop g = {0};
    loop_step(&g, 30000);
    loop_step(&g, 5000);
    loop_step(&g, 30000);
    assert(g.update_count == 3);
    assert(g.render_count == 3);
}

int main(void) {
    test_exact_dt_fires_one_update();
    test_under_dt_no_update();
    test_catchup_50ms();
    test_spiral_of_death_cap();
    test_render_per_frame();
    test_accumulator_remainder();
    test_input_update_render_separation();
    puts("All game_loop_architecture examples passed.");
    return 0;
}
