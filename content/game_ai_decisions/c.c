// Vidya — Game AI Decision Making in C
//
// Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting, and
// weighted action selection. C's `uint64_t` arithmetic is defined to wrap
// modulo 2^64 — which is exactly what the PCG state update needs. The
// signed `int64_t` for scores keeps the negative-distance-penalty path
// well-defined without resorting to __int128.

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

typedef enum {
    ACT_SHOOT = 0, ACT_DUNK, ACT_PASS, ACT_DRIVE, ACT_STEAL,
} Action;

typedef struct {
    int64_t speed;
    int64_t shooting;
    int64_t dunking;
    int64_t passing;
    int64_t stealing;
    int64_t blocking;
    int64_t clutch;
    int64_t rebounding;
} Stats;

static uint64_t rng_state = 12345;

static const uint64_t PCG_MULT = 6364136223846793005ULL;
static const uint64_t PCG_INC  = 1442695040888963407ULL;

static void rng_seed(uint64_t s) { rng_state = s; }

static int64_t rng_next(void) {
    rng_state = rng_state * PCG_MULT + PCG_INC;     // unsigned wrap is defined
    return (int64_t)((rng_state >> 33) & 0x7fffffffULL);
}

static int64_t rng_range(int64_t max) {
    if (max <= 0) return 0;
    return rng_next() % max;
}

static bool prob_check(int64_t stat) {
    int64_t threshold = stat * 10;
    return rng_range(100) < threshold;
}

static int64_t evaluate_shoot(int64_t shooting, int64_t distance_fx) {
    int64_t base = shooting * 10;
    int64_t dist_units = distance_fx >> 16;
    int64_t score = base - dist_units;
    return score < 0 ? 0 : score;
}

static int64_t evaluate_dunk(int64_t dunking, int64_t distance_fx) {
    if ((distance_fx >> 16) > 3) return 0;
    return dunking * 15;
}

static int64_t evaluate_pass(int64_t passing) { return passing * 8; }
static int64_t evaluate_drive(int64_t speed) { return speed * 6; }

static int64_t apply_urgency(int64_t score, int64_t shot_clock) {
    int64_t urgency = (24 - shot_clock) / 4;
    if (urgency < 1) urgency = 1;
    return score * urgency;
}

static int64_t add_noise(int64_t score) {
    int64_t noise = rng_range(21) - 10;
    int64_t result = score + noise;
    return result < 0 ? 0 : result;
}

static Action ai_decide_offense(const Stats *s, int64_t distance_fx, int64_t shot_clock) {
    int64_t shoot_score = add_noise(apply_urgency(evaluate_shoot(s->shooting, distance_fx), shot_clock));
    int64_t dunk_score  = add_noise(evaluate_dunk(s->dunking, distance_fx));
    int64_t pass_score  = add_noise(evaluate_pass(s->passing));
    int64_t drive_score = add_noise(evaluate_drive(s->speed));

    Action best = ACT_SHOOT;
    int64_t best_score = shoot_score;
    if (dunk_score  > best_score) { best = ACT_DUNK;  best_score = dunk_score; }
    if (pass_score  > best_score) { best = ACT_PASS;  best_score = pass_score; }
    if (drive_score > best_score) { best = ACT_DRIVE; best_score = drive_score; }
    (void)best_score;
    return best;
}

int main(void) {
    // evaluate_shoot
    assert(evaluate_shoot(9, 3LL << 16) == 87);
    assert(evaluate_shoot(1, 20LL << 16) == 0);
    assert(evaluate_shoot(10, 0) == 100);

    // evaluate_dunk
    assert(evaluate_dunk(8, 2LL << 16) == 120);
    assert(evaluate_dunk(10, 10LL << 16) == 0);

    // urgency
    assert(apply_urgency(50, 24) == 50);
    assert(apply_urgency(50, 2) == 250);
    assert(apply_urgency(50, 0) == 300);

    // prob_check
    rng_seed(42);
    for (int i = 0; i < 20; i++) assert(prob_check(10));
    rng_seed(99);
    for (int i = 0; i < 20; i++) assert(!prob_check(0));

    // PRNG determinism
    rng_seed(77777);
    int64_t a1 = rng_next(); int64_t a2 = rng_next();
    rng_seed(77777);
    int64_t b1 = rng_next(); int64_t b2 = rng_next();
    assert(a1 == b1);
    assert(a2 == b2);

    // PRNG variation
    rng_seed(42);
    int64_t v1 = rng_next();
    int64_t v2 = rng_next();
    assert(v1 != v2);

    // Difficulty scaling
    assert(evaluate_shoot(9, 5LL << 16) > evaluate_shoot(3, 5LL << 16));
    assert(evaluate_dunk(9, 2LL << 16) > evaluate_dunk(2, 2LL << 16));

    // ai_decide_offense: high dunk stat at close range -> DUNK
    rng_seed(100);
    Stats s = { .speed = 5, .shooting = 5, .dunking = 10, .passing = 3,
                .stealing = 3, .blocking = 3, .clutch = 3, .rebounding = 3 };
    Action act = ai_decide_offense(&s, 1LL << 16, 20);
    assert(act == ACT_DUNK);

    puts("All game_ai_decisions examples passed.");
    return 0;
}
