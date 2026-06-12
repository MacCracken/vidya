/* Vidya — Reproducible Builds — C port (C17). Fixed arrays mirror the
 * Cyrius reference.
 *
 * A reproducible build is a pure function of its inputs: the same sources
 * produce a byte-identical artifact, on any machine, at any time. Three
 * classic sources of non-determinism, and their fixes:
 *
 *   1. Embedded wall-clock timestamps  -> clamp every timestamp to
 *      SOURCE_DATE_EPOCH so "now" never leaks in.
 *   2. Filesystem iteration order      -> SORT filenames before processing
 *      so output doesn't depend on directory layout.
 *   3. Non-deterministic artifact names -> name artifacts by the HASH of
 *      their content (content-addressing), so identical inputs map to
 *      identical paths — the build becomes idempotent.
 *
 * Verification: build twice and compare digests. This models that pipeline
 * over an in-memory set of files and shows a deterministic build staying
 * identical across runs that differ in input order AND wall-clock time,
 * while a naive build drifts.
 */

#include <assert.h>
#include <stdio.h>

#define HB    131L
#define HM    1000003L
#define HSEED 7L
#define MAX_FILES 128

static long fold(long h, long v) { return (h * HB + v) % HM; }

/* --- 1. Deterministic timestamps: clamp "now" to SOURCE_DATE_EPOCH --- */
static long normalize_ts(long now, long sde) { return now > sde ? sde : now; }

/* --- 3. Content-addressed artifact path: a pure function of content --- */
static long cas_path(long content) { return (content * HB + 7L) % HM; }

/* --- File set: parallel arrays (name sort-key, content signature) --- */
static long f_name[MAX_FILES];
static long f_content[MAX_FILES];
static int  f_n = 0;

static void file_set(int i, long name, long content) {
    f_name[i] = name;
    f_content[i] = content;
}

/* --- 2. Sorted iteration: insertion-sort files by name key, ascending,
 *     reordering content alongside so the pairing is preserved. --- */
static void files_sort(void) {
    for (int i = 1; i < f_n; i++) {
        long kn = f_name[i];
        long kc = f_content[i];
        int j = i - 1;
        while (j >= 0 && f_name[j] > kn) {
            f_name[j + 1] = f_name[j];
            f_content[j + 1] = f_content[j];
            j--;
        }
        f_name[j + 1] = kn;
        f_content[j + 1] = kc;
    }
}

/* --- The build: fold the (normalized) timestamp and every file's
 *     (name, content) into one artifact digest. Flags toggle the two
 *     determinism fixes so we can contrast a correct vs naive pipeline. --- */
static long build_digest(int do_sort, int do_norm, long now, long sde) {
    if (do_sort) files_sort();
    long ts = do_norm ? normalize_ts(now, sde) : now;
    long h = fold(HSEED, ts);
    for (int i = 0; i < f_n; i++) {
        h = fold(h, f_name[i]);
        h = fold(h, f_content[i]);
    }
    return h;
}

/* Same SET of three files, presented in two different input orders. */
static void setup_order_a(void) {
    f_n = 3;
    file_set(0, 30, 111);
    file_set(1, 10, 222);
    file_set(2, 20, 333);
}
static void setup_order_b(void) {
    f_n = 3;
    file_set(0, 20, 333);
    file_set(1, 30, 111);
    file_set(2, 10, 222);
}

int main(void) {
    /* 1. Deterministic timestamps. */
    assert(normalize_ts(9999, 5000) == 5000);
    assert(normalize_ts(3000, 5000) == 3000);

    /* 2. Sorted iteration keeps content paired with its name. */
    setup_order_a();
    files_sort();
    assert(f_name[0] == 10);
    assert(f_name[1] == 20);
    assert(f_name[2] == 30);
    assert(f_content[0] == 222);

    /* 3. Content-addressed paths are a pure function of content. */
    assert(cas_path(111) == cas_path(111));
    assert(cas_path(111) != cas_path(222));

    /* Deterministic pipeline: two builds differing in BOTH input order and
     * wall-clock "now" produce equal digests. */
    setup_order_a();
    long d1 = build_digest(1, 1, 9999, 5000);
    setup_order_b();
    long d2 = build_digest(1, 1, 8888, 5000);
    assert(d1 == d2);

    /* Naive pipeline drifts with order + timestamp. */
    setup_order_a();
    long n1 = build_digest(0, 0, 9999, 5000);
    setup_order_b();
    long n2 = build_digest(0, 0, 8888, 5000);
    assert(n1 != n2);

    /* Normalization alone kills clock drift (sorting on, only clock differs). */
    setup_order_a();
    long norm1 = build_digest(1, 1, 9999, 5000);
    setup_order_a();
    long norm2 = build_digest(1, 1, 7777, 5000);
    assert(norm1 == norm2);

    printf("All reproducible_builds examples passed.\n");
    return 0;
}
