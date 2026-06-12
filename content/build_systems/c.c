/* Vidya — Build Systems — C port. A minimal build-system core: a DAG of
 * targets, topological build order, content-signature dirty-tracking, and
 * ninja-style incremental rebuild (only dirty targets run), plus cycle
 * detection. Fixed parallel arrays mirror the Cyrius reference.
 *
 * No real files or compilers: each target carries a source "content
 * signature" (an integer). A target's INPUT signature mixes its own source
 * with the OUTPUT signatures of its dependencies; if that differs from the
 * signature it was last built against, the target is dirty and rebuilds.
 * Editing a source re-dirties everything downstream — exactly how
 * mtime/hash-based tools (make, ninja, bazel) decide what to redo. */

#include <stdio.h>
#include <assert.h>

#define MAXN 16   /* max targets */
#define MAXD 8    /* max deps per target */
#define HB   131  /* signature polynomial base */
#define HM   1000003 /* signature modulus (prime; keeps values < 2^53) */

typedef struct {
    long src[MAXN];            /* source content signature */
    int  depcnt[MAXN];         /* number of dependencies */
    int  deps[MAXN][MAXD];     /* dependency target ids */
    long built[MAXN];          /* signature last built against (-1 = never) */
    long out[MAXN];            /* current output signature */
    int  order[MAXN];          /* topological order (target ids) */
    int  placed[MAXN];         /* topo scratch: placed flag */
    int  n;                    /* number of targets */
} Builder;

static void bs_reset(Builder *b, int n) {
    b->n = n;
    for (int i = 0; i < n; i++) {
        b->src[i] = 0;
        b->depcnt[i] = 0;
        b->built[i] = -1;      /* never built */
        b->out[i] = 0;
    }
}

static void bs_set_src(Builder *b, int t, long sig) { b->src[t] = sig; }

static void bs_add_dep(Builder *b, int t, int d) {
    b->deps[t][b->depcnt[t]] = d;
    b->depcnt[t] += 1;
}

/* Topological sort (Kahn-style ready-scan). Writes target ids into order and
 * returns how many were ordered; < n ⇒ a cycle left some unreachable. */
static int bs_topo(Builder *b) {
    for (int i = 0; i < b->n; i++) b->placed[i] = 0;
    int placed = 0;
    while (placed < b->n) {
        int progress = 0;
        for (int t = 0; t < b->n; t++) {
            if (b->placed[t] == 0) {
                int ready = 1;
                for (int k = 0; k < b->depcnt[t]; k++) {
                    if (b->placed[b->deps[t][k]] == 0) ready = 0;
                }
                if (ready) {
                    b->order[placed] = t;
                    b->placed[t] = 1;
                    placed += 1;
                    progress = 1;
                }
            }
        }
        if (progress == 0) return placed;   /* stuck ⇒ cycle */
    }
    return placed;
}

/* Input signature: mix this target's source with deps' outputs. */
static long bs_sig(const Builder *b, int t) {
    long sig = b->src[t] % HM;
    for (int k = 0; k < b->depcnt[t]; k++) {
        int d = b->deps[t][k];
        sig = (sig * HB + b->out[d]) % HM;
    }
    return sig;
}

/* Incremental build: walk topo order, rebuild only dirty targets. Output is
 * content-addressed (out == input signature), so a target whose inputs are
 * unchanged keeps its output and its dependents stay clean. Returns the
 * number of targets rebuilt. */
static int bs_build(Builder *b) {
    int ordered = bs_topo(b);
    int rebuilt = 0;
    for (int i = 0; i < ordered; i++) {
        int t = b->order[i];
        long sig = bs_sig(b, t);
        if (sig != b->built[t]) {
            b->out[t] = sig;      /* produce output */
            b->built[t] = sig;    /* remember what we built */
            rebuilt += 1;
        }
    }
    return rebuilt;
}

/* Classic C build graph: app(2) <- util.o(0), main.o(1) */
static void build_graph(Builder *b) {
    bs_reset(b, 3);
    bs_set_src(b, 0, 1001);   /* util.c */
    bs_set_src(b, 1, 2002);   /* main.c */
    bs_set_src(b, 2, 3003);   /* link recipe */
    bs_add_dep(b, 2, 0);
    bs_add_dep(b, 2, 1);
}

static int order_pos(const Builder *b, int target) {
    for (int i = 0; i < b->n; i++) {
        if (b->order[i] == target) return i;
    }
    return -1;
}

int main(void) {
    Builder b;

    /* topo orders all 3; app after util.o AND main.o */
    build_graph(&b);
    assert(bs_topo(&b) == 3);
    assert(order_pos(&b, 2) > order_pos(&b, 0));
    assert(order_pos(&b, 2) > order_pos(&b, 1));

    /* cold build rebuilds all 3 */
    build_graph(&b);
    assert(bs_build(&b) == 3);

    /* second build, no edits, rebuilds nothing */
    build_graph(&b);
    bs_build(&b);
    assert(bs_build(&b) == 0);

    /* edit main.c → rebuilds main.o + app = 2 */
    build_graph(&b);
    bs_build(&b);
    bs_set_src(&b, 1, 2999);
    assert(bs_build(&b) == 2);

    /* edit util.c → rebuilds util.o + app = 2, main.o left untouched */
    build_graph(&b);
    bs_build(&b);
    long main_built = b.built[1];
    bs_set_src(&b, 0, 1999);
    assert(bs_build(&b) == 2);
    assert(b.built[1] == main_built);

    /* 0 <-> 1 cycle leaves targets unordered */
    bs_reset(&b, 2);
    bs_add_dep(&b, 0, 1);
    bs_add_dep(&b, 1, 0);
    assert(bs_topo(&b) < 2);

    printf("All build_systems examples passed.\n");
    return 0;
}
