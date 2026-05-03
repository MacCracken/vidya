/* Vidya — Audio DSP — C port. Q15 fixed-point throughout. */

#include <stdio.h>

#define SCALE 15
#define ONE   32768
#define SMAX  32767
#define SMIN  (-32767)

static long long q_mul(long long a, long long b) {
    long long p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

static long long abs_i(long long x) { return x < 0 ? -x : x; }

static long long clip(long long s) {
    if (s > SMAX) return SMAX;
    if (s < SMIN) return SMIN;
    return s;
}

typedef struct {
    long long b0, b1, b2, a1, a2;
    long long x1, x2, y1, y2;
} Biquad;

static void biquad_set(Biquad *b, long long b0, long long b1, long long b2,
                       long long a1, long long a2) {
    b->b0=b0; b->b1=b1; b->b2=b2; b->a1=a1; b->a2=a2;
    b->x1=0; b->x2=0; b->y1=0; b->y2=0;
}

static void biquad_lowpass_1pole(Biquad *b, long long a_q15) {
    biquad_set(b, a_q15, 0, 0, a_q15 - ONE, 0);
}

static long long biquad_step(Biquad *b, long long x) {
    long long y = q_mul(b->b0, x) + q_mul(b->b1, b->x1) + q_mul(b->b2, b->x2)
                - q_mul(b->a1, b->y1) - q_mul(b->a2, b->y2);
    b->x2 = b->x1; b->x1 = x;
    b->y2 = b->y1; b->y1 = y;
    return y;
}

static long long fir_step(const long long *taps, long long *history,
                          int n_taps, long long x_new) {
    for (int i = n_taps - 1; i > 0; i--) history[i] = history[i - 1];
    history[0] = x_new;
    long long acc = 0;
    for (int j = 0; j < n_taps; j++) acc += q_mul(taps[j], history[j]);
    return acc;
}

static long long peak(const long long *buf, int n) {
    long long p = 0;
    for (int i = 0; i < n; i++) {
        long long a = abs_i(buf[i]);
        if (a > p) p = a;
    }
    return p;
}

static long long mean_absolute(const long long *buf, int n) {
    long long sum = 0;
    for (int i = 0; i < n; i++) sum += abs_i(buf[i]);
    return sum / n;
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    check(q_mul(ONE, 100) == 100, "ONE * 100 = 100");
    check(q_mul(ONE/2, ONE/2) == ONE/4, "0.5 * 0.5 = 0.25");
    long long r = q_mul(ONE/2, SMAX);
    check(r >= 16383 && r <= 16384, "0.5 * SMAX in [16383,16384]");

    check(clip(50000) == SMAX, "clip(50000) = SMAX");
    check(clip(-50000) == SMIN, "clip(-50000) = SMIN");
    check(clip(1234) == 1234, "clip(1234) unchanged");

    {
        Biquad b;
        biquad_lowpass_1pole(&b, 3277);
        for (int i = 0; i < 200; i++) biquad_step(&b, 30000);
        check(b.y1 >= 29900 && b.y1 <= 30100, "DC settled near 30000");
    }
    {
        Biquad b;
        biquad_lowpass_1pole(&b, 3277);
        for (int i = 0; i < 200; i++) {
            long long x = (i & 1) == 0 ? 20000 : -20000;
            biquad_step(&b, x);
        }
        check(abs_i(b.y1) < 2000, "Nyquist heavily attenuated");
    }
    {
        long long taps[3] = {ONE, 0, 0};
        long long history[3] = {0, 0, 0};
        check(fir_step(taps, history, 3, 1234) == 1234, "identity passes 1234");
        check(fir_step(taps, history, 3, 5678) == 5678, "identity passes 5678");
    }
    {
        long long third = ONE / 3;
        long long taps[3] = {third, third, third};
        long long history[3] = {0, 0, 0};
        fir_step(taps, history, 3, 9000);
        fir_step(taps, history, 3, 9000);
        long long y = fir_step(taps, history, 3, 9000);
        check(y >= 8990 && y <= 9010, "moving avg converges to 9000");
    }
    {
        long long buf[5] = {100, -5000, 200, 3000, -1500};
        check(peak(buf, 5) == 5000, "peak = 5000");
    }
    {
        long long buf[8];
        for (int i = 0; i < 8; i++) buf[i] = 4000;
        check(mean_absolute(buf, 8) == 4000, "mean-abs constant = constant");
    }
    {
        long long buf[8];
        for (int i = 0; i < 8; i++) buf[i] = (i & 1) == 0 ? 4000 : -4000;
        check(mean_absolute(buf, 8) == 4000, "mean-abs alternating = 4000");
    }

    printf("=== audio_dsp ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
