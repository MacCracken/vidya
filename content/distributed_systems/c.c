/* Vidya — Distributed Systems Foundations — C port. */

#include <stdio.h>
#include <string.h>

#define N_NODES 3
#define W 2
#define R 2

enum { VC_LESS = 1, VC_EQUAL = 2, VC_GREATER = 3, VC_CONCURRENT = 4 };

typedef struct { long long c[N_NODES]; } VClock;

static void vc_init(VClock *v) { memset(v, 0, sizeof(*v)); }
static void vc_tick(VClock *v, int node) { v->c[node] += 1; }
static void vc_merge(VClock *into, const VClock *from) {
    for (int i = 0; i < N_NODES; i++)
        if (from->c[i] > into->c[i]) into->c[i] = from->c[i];
}
static int vc_compare(const VClock *a, const VClock *b) {
    int any_lt = 0, any_gt = 0;
    for (int i = 0; i < N_NODES; i++) {
        if (a->c[i] < b->c[i]) any_lt = 1;
        if (a->c[i] > b->c[i]) any_gt = 1;
    }
    if (!any_lt && !any_gt) return VC_EQUAL;
    if (!any_lt) return VC_GREATER;
    if (!any_gt) return VC_LESS;
    return VC_CONCURRENT;
}

typedef struct {
    long long accounts[N_NODES];
    long long write_seq[N_NODES];
    int alive[N_NODES];
    long long global_seq;
} QCluster;

static void qc_init(QCluster *c) {
    memset(c, 0, sizeof(*c));
    for (int i = 0; i < N_NODES; i++) c->alive[i] = 1;
}
static void qc_partition(QCluster *c, int n) { c->alive[n] = 0; }
static void qc_heal(QCluster *c, int n)      { c->alive[n] = 1; }
static int qc_alive_count(const QCluster *c) {
    int n = 0;
    for (int i = 0; i < N_NODES; i++) n += c->alive[i];
    return n;
}
static int qc_write(QCluster *c, long long value) {
    if (qc_alive_count(c) < W) return 0;
    c->global_seq += 1;
    for (int i = 0; i < N_NODES; i++) {
        if (c->alive[i]) {
            c->accounts[i] = value;
            c->write_seq[i] = c->global_seq;
        }
    }
    return 1;
}
static long long qc_read(const QCluster *c) {
    if (qc_alive_count(c) < R) return -1;
    long long best_seq = 0, best_value = 0;
    for (int i = 0; i < N_NODES; i++) {
        if (c->alive[i] && c->write_seq[i] > best_seq) {
            best_seq = c->write_seq[i];
            best_value = c->accounts[i];
        }
    }
    return best_value;
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

static int vc_eq(const VClock *v, long long a, long long b, long long cv) {
    return v->c[0] == a && v->c[1] == b && v->c[2] == cv;
}

int main(void) {
    {
        VClock v; vc_init(&v);
        check(vc_eq(&v, 0, 0, 0), "vc init zero");
    }
    {
        VClock v; vc_init(&v);
        vc_tick(&v, 1); vc_tick(&v, 1); vc_tick(&v, 2);
        check(vc_eq(&v, 0, 2, 1), "tick");
    }
    {
        VClock a, b; vc_init(&a); vc_init(&b);
        vc_tick(&a, 0); vc_tick(&a, 0);
        vc_tick(&b, 1); vc_tick(&b, 2);
        vc_merge(&a, &b);
        check(vc_eq(&a, 2, 1, 1), "merge max");
    }
    {
        VClock a, b; vc_init(&a); vc_init(&b);
        vc_tick(&b, 0);
        check(vc_compare(&a, &b) == VC_LESS, "less");
    }
    {
        VClock a, b; vc_init(&a); vc_init(&b);
        vc_tick(&a, 0); vc_tick(&a, 0); vc_tick(&b, 0);
        check(vc_compare(&a, &b) == VC_GREATER, "greater");
    }
    {
        VClock a, b; vc_init(&a); vc_init(&b);
        vc_tick(&a, 1); vc_tick(&b, 1);
        check(vc_compare(&a, &b) == VC_EQUAL, "equal");
    }
    {
        VClock a, b; vc_init(&a); vc_init(&b);
        vc_tick(&a, 0); vc_tick(&b, 1);
        check(vc_compare(&a, &b) == VC_CONCURRENT, "concurrent");
        check(vc_compare(&b, &a) == VC_CONCURRENT, "concurrent symmetric");
    }
    {
        QCluster c; qc_init(&c);
        check(qc_write(&c, 100) == 1, "write ok full");
        check(c.accounts[0] == 100 && c.accounts[1] == 100 && c.accounts[2] == 100, "all wrote");
    }
    {
        QCluster c; qc_init(&c);
        qc_partition(&c, 2);
        check(qc_write(&c, 200) == 1, "write ok 2 alive");
        check(c.accounts[0] == 200 && c.accounts[1] == 200, "0,1 wrote");
        check(c.accounts[2] == 0, "2 untouched");
    }
    {
        QCluster c; qc_init(&c);
        qc_partition(&c, 1); qc_partition(&c, 2);
        check(qc_write(&c, 300) == 0, "write fails 1 alive");
        check(c.accounts[0] == 0, "no replica wrote");
    }
    {
        QCluster c; qc_init(&c);
        qc_partition(&c, 2); qc_write(&c, 500); qc_heal(&c, 2);
        qc_partition(&c, 0);
        check(qc_read(&c) == 500, "intersection: read sees latest");
    }
    {
        QCluster c; qc_init(&c);
        qc_write(&c, 700);
        qc_partition(&c, 0); qc_partition(&c, 1);
        check(qc_read(&c) == -1, "read sentinel below R");
    }

    printf("=== distributed_systems ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
