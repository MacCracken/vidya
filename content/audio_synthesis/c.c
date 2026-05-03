/* Vidya — Audio Synthesis — C port. Q15 fixed-point. */

#include <stdio.h>

#define SCALE      15
#define ONE        32768
#define PHASE_MASK 65535
#define PHASE_HALF 32768

static long long q_mul(long long a, long long b) {
    long long p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

static long long phase_advance(long long current, long long inc) {
    return (current + inc) & PHASE_MASK;
}

static const long long sine_table[16] = {
    0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
    0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
};

static long long osc_sine(long long phase)   { return sine_table[phase >> 12]; }
static long long osc_saw(long long phase)    { return phase - PHASE_HALF; }
static long long osc_square(long long phase) { return phase < PHASE_HALF ? 32767 : -32767; }

enum { ENV_IDLE = 0, ENV_ATTACK = 1, ENV_DECAY = 2, ENV_SUSTAIN = 3, ENV_RELEASE = 4 };

typedef struct {
    int state;
    long long level;
    long long stage_samples;
    long long release_start;
    long long attack_samples;
    long long decay_samples;
    long long sustain_level;
    long long release_samples;
} Adsr;

static void adsr_init(Adsr *a) {
    a->state = ENV_IDLE; a->level = 0; a->stage_samples = 0; a->release_start = 0;
    a->attack_samples = 0; a->decay_samples = 0; a->sustain_level = 0; a->release_samples = 0;
}

static void adsr_set_params(Adsr *a, long long attack, long long decay,
                            long long sustain, long long release) {
    a->attack_samples = attack;
    a->decay_samples = decay;
    a->sustain_level = sustain;
    a->release_samples = release;
}

static void adsr_gate_on(Adsr *a) {
    a->state = ENV_ATTACK;
    a->stage_samples = 0;
}

static int adsr_gate_off(Adsr *a) {
    if (a->state == ENV_IDLE) return 0;
    a->release_start = a->level;
    a->state = ENV_RELEASE;
    a->stage_samples = 0;
    return 1;
}

static long long adsr_step(Adsr *a) {
    if (a->state == ENV_IDLE) { a->level = 0; return 0; }
    if (a->state == ENV_ATTACK) {
        long long inc = ONE / a->attack_samples;
        a->level += inc;
        a->stage_samples += 1;
        if (a->stage_samples >= a->attack_samples) {
            a->level = ONE;
            a->state = ENV_DECAY;
            a->stage_samples = 0;
        }
        return a->level;
    }
    if (a->state == ENV_DECAY) {
        long long dec = (ONE - a->sustain_level) / a->decay_samples;
        a->level -= dec;
        a->stage_samples += 1;
        if (a->stage_samples >= a->decay_samples) {
            a->level = a->sustain_level;
            a->state = ENV_SUSTAIN;
            a->stage_samples = 0;
        }
        return a->level;
    }
    if (a->state == ENV_SUSTAIN) {
        a->level = a->sustain_level;
        return a->level;
    }
    if (a->state == ENV_RELEASE) {
        long long dec = a->release_start / a->release_samples;
        a->level -= dec;
        a->stage_samples += 1;
        if (a->stage_samples >= a->release_samples) {
            a->level = 0;
            a->state = ENV_IDLE;
            a->stage_samples = 0;
        }
        return a->level;
    }
    return 0;
}

enum { WAVE_SINE = 0, WAVE_SAW = 1, WAVE_SQUARE = 2 };

typedef struct {
    int waveform;
    long long phase;
    long long phase_inc;
} Voice;

static long long voice_oscillator(int waveform, long long phase) {
    if (waveform == WAVE_SINE)   return osc_sine(phase);
    if (waveform == WAVE_SAW)    return osc_saw(phase);
    if (waveform == WAVE_SQUARE) return osc_square(phase);
    return 0;
}

static long long voice_step(Voice *v, Adsr *env) {
    long long osc = voice_oscillator(v->waveform, v->phase);
    v->phase = phase_advance(v->phase, v->phase_inc);
    long long e = adsr_step(env);
    return q_mul(osc, e);
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    check(phase_advance(60000, 10000) == 4464, "phase wraps");
    check(phase_advance(0, 1000) == 1000, "phase advances");

    check(osc_sine(0) == 0, "sin(0) = 0");
    check(osc_sine(16384) == 32767, "sin(π/2) = ONE");
    check(osc_sine(32768) == 0, "sin(π) = 0");
    check(osc_sine(49152) == -32767, "sin(3π/2) = -ONE");

    check(osc_saw(0) == -PHASE_HALF, "saw(0) = -ONE");
    check(osc_saw(PHASE_HALF) == 0, "saw(π) = 0");
    check(osc_saw(65535) == 32767, "saw(near max)");

    check(osc_square(0) == 32767, "square first half");
    check(osc_square(PHASE_HALF) == -32767, "square second half");
    check(osc_square(32767) == 32767, "square just before half");
    check(osc_square(65535) == -32767, "square at end");

    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4); adsr_gate_on(&e);
        for (int i = 0; i < 4; i++) adsr_step(&e);
        check(e.state == ENV_DECAY, "attack → decay");
        check(e.level == ONE, "level = ONE");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4); adsr_gate_on(&e);
        for (int i = 0; i < 8; i++) adsr_step(&e);
        check(e.state == ENV_SUSTAIN, "decay → sustain");
        check(e.level == 16384, "level = sustain");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4); adsr_gate_on(&e);
        for (int i = 0; i < 8; i++) adsr_step(&e);
        for (int i = 0; i < 100; i++) adsr_step(&e);
        check(e.state == ENV_SUSTAIN, "sustain holds");
        check(e.level == 16384, "level held");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4); adsr_gate_on(&e);
        for (int i = 0; i < 8; i++) adsr_step(&e);
        adsr_gate_off(&e);
        check(e.release_start == 16384, "release_start captured");
        for (int i = 0; i < 4; i++) adsr_step(&e);
        check(e.state == ENV_IDLE, "release → idle");
        check(e.level == 0, "level = 0");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 8, 4, 16384, 4); adsr_gate_on(&e);
        adsr_step(&e); adsr_step(&e);
        adsr_gate_off(&e);
        check(e.release_start == 8192, "release captures partial-attack level");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4);
        Voice v = {WAVE_SINE, 0, 8192};
        check(voice_step(&v, &e) == 0, "voice silent when idle");
    }
    {
        Adsr e; adsr_init(&e); adsr_set_params(&e, 4, 4, 16384, 4);
        Voice v = {WAVE_SINE, 0, 8192};
        adsr_gate_on(&e);
        int any_nonzero = 0;
        for (int i = 0; i < 16; i++) {
            if (voice_step(&v, &e) != 0) any_nonzero = 1;
        }
        check(any_nonzero, "voice audible when gated");
    }

    printf("=== audio_synthesis ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
