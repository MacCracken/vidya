/* Vidya — Neural Network Forward Pass — C port. Q15 fixed-point. */

#include <stdio.h>

#define SCALE    15
#define ONE      32768
#define N_IN     2
#define N_HIDDEN 3
#define N_OUT    2

static long long q_mul(long long a, long long b) {
    long long p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

static const long long W_HIDDEN[N_HIDDEN * N_IN] = {
    16384, -16384,
    -16384, 16384,
    16384, 16384,
};
static const long long B_HIDDEN[N_HIDDEN] = {0, 0, 0};

static const long long W_OUTPUT[N_OUT * N_HIDDEN] = {
    16384, 0, 0,
    0, 16384, 0,
};
static const long long B_OUTPUT[N_OUT] = {0, 0};

static long long last_hidden[N_HIDDEN];
static long long last_output[N_OUT];

static void dense(const long long *W, const long long *b,
                  const long long *x, long long *out, int n_in, int n_out) {
    for (int j = 0; j < n_out; j++) {
        long long acc = b[j];
        for (int i = 0; i < n_in; i++) {
            acc += q_mul(W[j * n_in + i], x[i]);
        }
        out[j] = acc;
    }
}

static void relu(long long *x, int n) {
    for (int i = 0; i < n; i++) {
        if (x[i] < 0) x[i] = 0;
    }
}

static int argmax(const long long *x, int n) {
    int best_idx = 0;
    long long best_val = x[0];
    for (int i = 1; i < n; i++) {
        if (x[i] > best_val) {
            best_val = x[i];
            best_idx = i;
        }
    }
    return best_idx;
}

static int forward(const long long *input) {
    dense(W_HIDDEN, B_HIDDEN, input, last_hidden, N_IN, N_HIDDEN);
    relu(last_hidden, N_HIDDEN);
    dense(W_OUTPUT, B_OUTPUT, last_hidden, last_output, N_HIDDEN, N_OUT);
    return argmax(last_output, N_OUT);
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    check(q_mul(ONE, 100) == 100, "ONE * 100 = 100");
    check(q_mul(16384, 16384) == 8192, "0.5 * 0.5 = 0.25");
    check(q_mul(-16384, 16384) == -8192, "-0.5 * 0.5 = -0.25");

    {
        long long w[4] = {16384, 16384, 8192, 24576};
        long long b[2] = {0, 0};
        long long x[2] = {32767, 32767};
        long long y[2];
        dense(w, b, x, y, 2, 2);
        check(y[0] >= 32765 && y[0] <= 32769, "dense y[0] ~= 1.0");
        check(y[1] >= 32765 && y[1] <= 32769, "dense y[1] ~= 1.0");
    }
    {
        long long w[2] = {0, 0};
        long long b[1] = {12345};
        long long x[2] = {32767, 32767};
        long long y[1];
        dense(w, b, x, y, 2, 1);
        check(y[0] == 12345, "bias passes through");
    }
    {
        long long y[4] = {-100, 200, -300, 400};
        relu(y, 4);
        check(y[0] == 0 && y[1] == 200 && y[2] == 0 && y[3] == 400, "relu clips");
    }
    {
        long long y[1] = {0};
        relu(y, 1);
        check(y[0] == 0, "relu(0) = 0");
    }
    {
        long long y[4] = {100, 500, 200, 300};
        check(argmax(y, 4) == 1, "argmax picks 1");
    }
    {
        long long y[3] = {100, 500, 500};
        check(argmax(y, 3) == 1, "first-found wins");
    }

    {
        long long x[2] = {26214, 6553};
        check(forward(x) == 0, "x=[0.8,0.2] → class 0");
    }
    {
        long long x[2] = {6553, 26214};
        check(forward(x) == 1, "x=[0.2,0.8] → class 1");
    }
    {
        long long x[2] = {32767, 0};
        check(forward(x) == 0, "x=[1.0,0.0] → class 0");
    }
    {
        long long x[2] = {0, 32767};
        check(forward(x) == 1, "x=[0.0,1.0] → class 1");
    }
    {
        long long x[2] = {32767, 0};
        forward(x);
        check(last_hidden[1] == 0, "relu zeroed hidden[1]");
        check(last_hidden[0] > 0, "hidden[0] passed through");
    }

    printf("=== neural_networks ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
