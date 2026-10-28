// Vidya — LLM Inference (Decoding) — C port.

#include <limits.h>
#include <stdio.h>
#include <string.h>

#define VOCAB_SIZE 8
#define TOK_EOS 1
/* "Removed" logit. Masking to 0 is wrong: logits are unnormalized and can
 * be negative, so a 0 can OUTRANK every survivor, and softmax gives a
 * 0 logit weight e^0 = 1, not 0. Mask to -infinity (here: the minimum). */
#define LOGIT_NEG_INF LLONG_MIN

static long long bigram[VOCAB_SIZE][VOCAB_SIZE];

static void init_bigram(void) {
    memset(bigram, 0, sizeof(bigram));
    bigram[2][3] = 1000;
    bigram[2][4] = 100;
    bigram[3][6] = 800;
    bigram[3][5] = 200;
    bigram[4][5] = 700;
    bigram[5][1] = 600;
    bigram[6][7] = 900;
    bigram[6][3] = 100;
    bigram[7][1] = 950;
}

static int argmax_logits(const long long *logits, int n) {
    int best_idx = 0;
    long long best_val = logits[0];
    for (int i = 1; i < n; i++) {
        if (logits[i] > best_val) {
            best_val = logits[i];
            best_idx = i;
        }
    }
    return best_idx;
}

static int topk_filter(long long *logits, int n, int k) {
    int marks[VOCAB_SIZE] = {0};
    int picked = 0;
    while (picked < k) {
        int best_idx = -1;
        long long best_val = 0;
        int first = 1;
        for (int j = 0; j < n; j++) {
            if (!marks[j]) {
                if (first) { best_idx = j; best_val = logits[j]; first = 0; }
                else if (logits[j] > best_val) { best_idx = j; best_val = logits[j]; }
            }
        }
        if (best_idx < 0) return picked;
        marks[best_idx] = 1;
        picked++;
    }
    for (int m = 0; m < n; m++) if (!marks[m]) logits[m] = LOGIT_NEG_INF;
    return picked;
}

static void bigram_logits(int prev, long long *out) {
    for (int i = 0; i < VOCAB_SIZE; i++) out[i] = bigram[prev][i];
}

static int decode_sequence(int start, long long *output, int max_len) {
    long long buf[VOCAB_SIZE];
    int current = start;
    int count = 0;
    while (count < max_len) {
        bigram_logits(current, buf);
        int next_tok = argmax_logits(buf, VOCAB_SIZE);
        output[count++] = next_tok;
        if (next_tok == TOK_EOS) return count;
        current = next_tok;
    }
    return count;
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    init_bigram();

    {
        long long l[4] = {100, 500, 200, 300};
        check(argmax_logits(l, 4) == 1, "argmax picks 1");
    }
    {
        long long l[3] = {100, 500, 500};
        check(argmax_logits(l, 3) == 1, "first-found wins");
    }
    {
        long long l[3] = {-100, -50, -200};
        check(argmax_logits(l, 3) == 1, "argmax over negatives");
    }

    {
        long long l[8] = {10, 50, 30, 20, 40, 5, 60, 25};
        check(topk_filter(l, 8, 3) == 3, "topk picked 3");
        check(l[6] == 60 && l[1] == 50 && l[4] == 40, "top 3 kept");
        check(l[0] == LOGIT_NEG_INF, "idx 0 masked");
        check(l[2] == LOGIT_NEG_INF, "idx 2 masked");
        check(l[3] == LOGIT_NEG_INF, "idx 3 masked");
        check(l[5] == LOGIT_NEG_INF, "idx 5 masked");
        check(l[7] == LOGIT_NEG_INF, "idx 7 masked");
    }
    {
        /* All-negative logits: a masked token must not become the argmax */
        long long l[4] = {-100, -50, -200, -10};
        topk_filter(l, 4, 2);
        check(argmax_logits(l, 4) == 3, "masked tokens never win argmax");
    }
    {
        long long l[3] = {1, 2, 3};
        check(topk_filter(l, 3, 3) == 3, "topk(3,3) keeps all");
        check(l[0] == 1 && l[1] == 2 && l[2] == 3, "all preserved");
    }

    {
        long long buf[VOCAB_SIZE];
        bigram_logits(2, buf);
        check(argmax_logits(buf, VOCAB_SIZE) == 3, "after hello → world");
    }

    {
        long long out[16];
        int n = decode_sequence(2, out, 10);
        check(n == 4, "produced 4 tokens");
        check(out[0] == 3 && out[1] == 6 && out[2] == 7 && out[3] == 1,
              "hello → world,the,end,EOS");
    }
    {
        long long out[16];
        int n = decode_sequence(5, out, 10);
        check(n == 1, "produced 1 token");
        check(out[0] == 1, "bar → EOS");
    }
    {
        long long out[16];
        int n = decode_sequence(2, out, 2);
        check(n == 2, "capped at 2");
        check(out[0] == 3 && out[1] == 6, "first 2 of decode");
    }
    {
        /* Greedy decoding over a bigram model depends only on the previous
         * token, so restarting from the first emitted token must reproduce
         * the rest of the sequence. (Decoding the same start twice and
         * comparing can never fail: nothing here is random.) */
        long long o1[16], o2[16];
        int n1 = decode_sequence(2, o1, 10);
        int n2 = decode_sequence((int)o1[0], o2, 10);
        check(n2 == n1 - 1, "suffix length");
        int eq = 1;
        for (int i = 0; i < n2; i++) if (o2[i] != o1[i + 1]) eq = 0;
        check(eq, "bigram decode depends only on prev token (suffix matches)");
    }

    printf("=== inference ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
