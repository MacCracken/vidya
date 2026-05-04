/* Vidya — Embeddings and Vector Search — C port. Q15 fixed-point. */

#include <stdio.h>

#define SCALE    15
#define ONE      32768
#define DIM      4
#define N_CORPUS 4

static long long q_mul(long long a, long long b) {
    long long p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

static const long long CORPUS[N_CORPUS][DIM] = {
    {32767, 0, 0, 0},
    {0, 32767, 0, 0},
    {16384, 16384, 16384, 16384},
    {-32767, 0, 0, 0},
};

static long long dot(const long long *a, const long long *b, int n) {
    long long acc = 0;
    for (int i = 0; i < n; i++) acc += q_mul(a[i], b[i]);
    return acc;
}

static long long corpus_sim(const long long *query, int idx) {
    return dot(query, CORPUS[idx], DIM);
}

static int nearest(const long long *query) {
    int best_idx = 0;
    long long best_sim = corpus_sim(query, 0);
    for (int i = 1; i < N_CORPUS; i++) {
        long long s = corpus_sim(query, i);
        if (s > best_sim) { best_sim = s; best_idx = i; }
    }
    return best_idx;
}

static int top_k_neighbors(const long long *query, int k, int *out) {
    int marks[N_CORPUS] = {0};
    int picked = 0;
    while (picked < k) {
        int best_idx = -1;
        long long best_sim = 0;
        int first = 1;
        for (int j = 0; j < N_CORPUS; j++) {
            if (!marks[j]) {
                long long s = corpus_sim(query, j);
                if (first) { best_idx = j; best_sim = s; first = 0; }
                else if (s > best_sim) { best_idx = j; best_sim = s; }
            }
        }
        if (best_idx < 0) return picked;
        marks[best_idx] = 1;
        out[picked++] = best_idx;
    }
    return picked;
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    for (int i = 0; i < N_CORPUS; i++) {
        long long s = corpus_sim(CORPUS[i], i);
        check(s >= 32760, "self-sim ≈ ONE");
    }

    check(corpus_sim(CORPUS[0], 1) == 0, "v0·v1 = 0");
    {
        long long s = corpus_sim(CORPUS[0], 3);
        check(s >= -ONE && s <= -32760, "v0·v3 ≈ -ONE");
    }
    check(corpus_sim(CORPUS[2], 2) == ONE, "v2 self-sim = ONE");
    {
        long long s = corpus_sim(CORPUS[0], 2);
        check(s >= 16380 && s <= 16384, "v0·v2 ≈ 0.5");
    }
    check(dot(CORPUS[0], CORPUS[2], DIM) == dot(CORPUS[2], CORPUS[0], DIM), "dot symmetric");

    {
        long long q[4] = {29490, 0, 0, 0};
        check(nearest(q) == 0, "near-x → v0");
    }
    {
        long long q[4] = {0, 32767, 0, 0};
        check(nearest(q) == 1, "y-axis → v1");
    }
    {
        long long q[4] = {16384, 16384, 16384, 16384};
        check(nearest(q) == 2, "diagonal → v2");
    }
    {
        long long q[4] = {-29490, 0, 0, 0};
        check(nearest(q) == 3, "negative-x → v3");
    }

    {
        long long q[4] = {32767, 0, 0, 0};
        int out[N_CORPUS];
        int n = top_k_neighbors(q, 3, out);
        check(n == 3 && out[0] == 0 && out[1] == 2 && out[2] == 1, "top-3 ranked v0,v2,v1");
    }
    {
        long long q[4] = {32767, 0, 0, 0};
        int out[N_CORPUS];
        int n = top_k_neighbors(q, 10, out);
        check(n == 4, "top_k caps at corpus size");
    }
    {
        long long q[4] = {29490, 0, 0, 0};
        check(nearest(q) == nearest(q), "deterministic");
    }

    printf("=== embeddings ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
