/* Vidya — Package Resolution — C port (C17). Mirrors the Cyrius
 * reference: semver-as-integer, caret ranges, range intersection for
 * diamond dependencies, highest-version selection, bounded backtracking,
 * and Kahn-scan dependency-cycle detection.
 *
 * A semver major.minor.patch is encoded as one integer
 *   enc = major*1000000 + minor*1000 + patch
 * so version comparison IS integer comparison. A constraint is a
 * half-open range [lo, hi). A caret ^X.Y.Z = [X.Y.Z, (X+1).0.0). */

#include <assert.h>
#include <stdio.h>
#include <string.h>

#define VMAJ 1000000L
#define VMIN 1000L

/* --- Semver encode / inspect --- */
static long sv(long maj, long min, long pat) { return maj * VMAJ + min * VMIN + pat; }
static long sv_major(long v) { return v / VMAJ; }

/* --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) --- */
static long caret_lo(long v) { return v; }
static long caret_hi(long v) { return (sv_major(v) + 1) * VMAJ; }

/* --- Constraint satisfaction over a half-open range --- */
static int satisfies(long v, long lo, long hi) {
    if (v < lo) return 0;
    if (v >= hi) return 0;
    return 1;
}

/* --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi --- */
static long range_lo_max(long a, long b) { return a > b ? a : b; }
static long range_hi_min(long a, long b) { return a < b ? a : b; }
static int range_empty(long lo, long hi) { return lo >= hi ? 1 : 0; }

/* --- Highest version in vers[0..n) that lies in [lo, hi); -1 if none --- */
static long best_match(const long *vers, int n, long lo, long hi) {
    long best = -1;
    for (int i = 0; i < n; i++) {
        long v = vers[i];
        if (satisfies(v, lo, hi) && v > best) best = v;
    }
    return best;
}

/* --- Available versions of the shared dependency C --- */
static long c_vers[3];
static int c_n = 0;
static void setup_c(void) {
    c_n = 3;
    c_vers[0] = sv(1, 0, 0);
    c_vers[1] = sv(1, 5, 0);
    c_vers[2] = sv(2, 0, 0);
}

/* --- Diamond resolution: A requires C ^a_base, B requires C ^b_base.
 *     Intersect the two carets and pick the highest C that fits.
 *     Returns chosen C version, or -1 if the constraints conflict. --- */
static long resolve_shared(long a_base, long b_base) {
    long lo = range_lo_max(caret_lo(a_base), caret_lo(b_base));
    long hi = range_hi_min(caret_hi(a_base), caret_hi(b_base));
    if (range_empty(lo, hi)) return -1;
    return best_match(c_vers, c_n, lo, hi);
}

/* --- Bounded backtracking: A has candidate versions (a_vers), each
 *     requiring a different caret on C (a_creq). B requires C ^b_base.
 *     Choose the HIGHEST A for which some C still satisfies both;
 *     record the chosen C in *chosen_c. -1 if none. --- */
static long resolve_backtrack(const long *a_vers, const long *a_creq, int an,
                              long b_base, long *chosen_c) {
    long bestA = -1;
    long bestC = -1;
    for (int i = 0; i < an; i++) {
        long aver = a_vers[i];
        long creq = a_creq[i];
        long lo = range_lo_max(caret_lo(creq), caret_lo(b_base));
        long hi = range_hi_min(caret_hi(creq), caret_hi(b_base));
        if (!range_empty(lo, hi)) {
            long c = best_match(c_vers, c_n, lo, hi);
            if (c != -1 && aver > bestA) { bestA = aver; bestC = c; }
        }
    }
    *chosen_c = bestC;
    return bestA;
}

/* --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
 *     some package permanently unplaceable). --- */
#define MAX_PKG 128
#define MAXD    8

static int p_depcnt[MAX_PKG];
static int p_deps[MAX_PKG][MAXD];
static int p_placed[MAX_PKG];
static int p_n = 0;

static void pkg_reset(int n) {
    p_n = n;
    memset(p_depcnt, 0, sizeof(p_depcnt));
}
static void pkg_add_dep(int p, int d) {
    int c = p_depcnt[p];
    p_deps[p][c] = d;
    p_depcnt[p] = c + 1;
}
static int pkg_has_cycle(void) {
    memset(p_placed, 0, sizeof(p_placed));
    int placed = 0;
    while (placed < p_n) {
        int progress = 0;
        for (int p = 0; p < p_n; p++) {
            if (p_placed[p] == 0) {
                int ready = 1;
                for (int k = 0; k < p_depcnt[p]; k++) {
                    if (p_placed[p_deps[p][k]] == 0) ready = 0;
                }
                if (ready) {
                    p_placed[p] = 1;
                    placed++;
                    progress = 1;
                }
            }
        }
        if (progress == 0) return 1;   /* stuck => cycle */
    }
    return 0;
}

int main(void) {
    /* semver */
    assert(sv(1, 2, 3) > sv(1, 2, 0));
    assert(sv(2, 0, 0) > sv(1, 9, 9));
    assert(sv_major(sv(1, 5, 2)) == 1);

    /* caret */
    assert(caret_lo(sv(1, 2, 0)) == sv(1, 2, 0));
    assert(caret_hi(sv(1, 2, 0)) == sv(2, 0, 0));
    assert(satisfies(sv(1, 4, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))) == 1);
    assert(satisfies(sv(2, 0, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))) == 0);
    assert(satisfies(sv(1, 1, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))) == 0);

    /* intersection */
    assert(range_lo_max(sv(1, 0, 0), sv(1, 3, 0)) == sv(1, 3, 0));
    assert(range_hi_min(sv(2, 0, 0), sv(3, 0, 0)) == sv(2, 0, 0));
    {
        long lo = range_lo_max(caret_lo(sv(1, 0, 0)), caret_lo(sv(2, 0, 0)));
        long hi = range_hi_min(caret_hi(sv(1, 0, 0)), caret_hi(sv(2, 0, 0)));
        assert(range_empty(lo, hi) == 1);
    }

    /* best_match */
    setup_c();
    assert(best_match(c_vers, c_n, caret_lo(sv(1, 0, 0)), caret_hi(sv(1, 0, 0))) == sv(1, 5, 0));
    assert(best_match(c_vers, c_n, caret_lo(sv(3, 0, 0)), caret_hi(sv(3, 0, 0))) == -1);

    /* diamond resolution */
    assert(resolve_shared(sv(1, 0, 0), sv(1, 0, 0)) == sv(1, 5, 0));
    assert(resolve_shared(sv(1, 0, 0), sv(2, 0, 0)) == -1);

    /* bounded backtracking: highest A (1.1.0) forces C ^2 which conflicts
     * with B ^1 — backtrack to A 1.0.0 (requires C ^1), resolving C 1.5.0 */
    {
        long a_vers[2] = { sv(1, 1, 0), sv(1, 0, 0) };
        long a_creq[2] = { sv(2, 0, 0), sv(1, 0, 0) };
        long chosen_c = -1;
        long chosenA = resolve_backtrack(a_vers, a_creq, 2, sv(1, 0, 0), &chosen_c);
        assert(chosenA == sv(1, 0, 0));
        assert(chosen_c == sv(1, 5, 0));
    }

    /* cycle detection */
    pkg_reset(2);
    pkg_add_dep(0, 1);
    pkg_add_dep(1, 0);
    assert(pkg_has_cycle() == 1);   /* A<->B is a cycle */

    pkg_reset(3);
    pkg_add_dep(2, 0);
    pkg_add_dep(2, 1);              /* app -> A, B (diamond, acyclic) */
    assert(pkg_has_cycle() == 0);

    printf("All package_resolution examples passed.\n");
    return 0;
}
