/* Vidya — Write-Ahead Logging in C
 *
 * In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
 * mutating the data store, then replay the durable prefix on recovery.
 * The log buffer is a flat `uint8_t[6144]` — exactly the cyrius
 * reference shape — and we use memcpy for the load64/store64 primitives
 * so the byte ordering is platform-defined but consistent within the
 * binary. The 256-record cap and the OP_INVALID/SET/DEL constants match
 * the cyrius reference. No real fsync — `log_committed` snapshots the
 * durable prefix.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REC_SZ 24
#define LOG_CAP_BYTES 6144
#define OP_INVALID 0
#define OP_SET 1
#define OP_DEL 2
#define STORE_KEYS 16

static uint8_t log_buf[LOG_CAP_BYTES];
static int64_t log_offset = 0;
static int64_t log_committed = 0;

static int64_t data_vals[STORE_KEYS];
static uint8_t data_present[STORE_KEYS];

static void log_reset(void) {
    log_offset = 0;
    log_committed = 0;
}

static void store_clear(void) {
    memset(data_vals, 0, sizeof data_vals);
    memset(data_present, 0, sizeof data_present);
}

static void reset_all(void) {
    log_reset();
    store_clear();
    /* Wipe the buffer so leftover bytes from a prior test don't ghost
     * into a fresh replay. */
    memset(log_buf, 0, sizeof log_buf);
}

static void store64(uint8_t *p, int64_t v) {
    memcpy(p, &v, sizeof v);
}

static int64_t load64(const uint8_t *p) {
    int64_t v;
    memcpy(&v, p, sizeof v);
    return v;
}

static int64_t log_append(int64_t op, int64_t key, int64_t val) {
    /* Returns 1 on success, 0 if buffer is full — matches cyrius. */
    if (log_offset + REC_SZ > LOG_CAP_BYTES) return 0;
    store64(&log_buf[log_offset + 0],  op);
    store64(&log_buf[log_offset + 8],  key);
    store64(&log_buf[log_offset + 16], val);
    log_offset += REC_SZ;
    return 1;
}

static int64_t log_commit(void) {
    /* Real implementations call fsync(wal_fd); we model durability with
     * an offset snapshot — every byte up to log_committed survives. */
    log_committed = log_offset;
    return log_committed;
}

static int64_t store_set(int64_t key, int64_t val) {
    if (key < 0 || key >= STORE_KEYS) return 0;
    /* WAL rule: log BEFORE data. */
    if (log_append(OP_SET, key, val) == 0) return 0;
    data_vals[key] = val;
    data_present[key] = 1;
    return 1;
}

static int64_t store_del(int64_t key) {
    if (key < 0 || key >= STORE_KEYS) return 0;
    if (log_append(OP_DEL, key, 0) == 0) return 0;
    data_vals[key] = 0;
    data_present[key] = 0;
    return 1;
}

static int64_t store_get(int64_t key) {
    if (key < 0 || key >= STORE_KEYS) return -1;
    if (data_present[key] == 0) return -1;
    return data_vals[key];
}

static int64_t replay(void) {
    store_clear();
    int64_t pos = 0, applied = 0;
    while (pos < log_committed) {
        int64_t op  = load64(&log_buf[pos + 0]);
        int64_t key = load64(&log_buf[pos + 8]);
        int64_t val = load64(&log_buf[pos + 16]);
        if (op == OP_SET) {
            data_vals[key] = val;
            data_present[key] = 1;
            applied++;
        } else if (op == OP_DEL) {
            data_vals[key] = 0;
            data_present[key] = 0;
            applied++;
        }
        pos += REC_SZ;
    }
    return applied;
}

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); exit(1); } \
} while (0)

static void test_append_and_replay(void) {
    reset_all();
    store_set(0, 100);
    store_set(1, 200);
    store_set(2, 300);
    log_commit();
    store_clear();
    int64_t n = replay();
    CHECK(n == 3, "replayed 3 records");
    CHECK(store_get(0) == 100, "key 0 = 100");
    CHECK(store_get(1) == 200, "key 1 = 200");
    CHECK(store_get(2) == 300, "key 2 = 300");
}

static void test_log_before_data_invariant(void) {
    reset_all();
    int64_t ok = store_set(5, 42);
    CHECK(ok == 1, "first set succeeds");
    CHECK(load64(&log_buf[0])  == OP_SET, "log[0].op = SET");
    CHECK(load64(&log_buf[8])  == 5,      "log[0].key = 5");
    CHECK(load64(&log_buf[16]) == 42,     "log[0].val = 42");
    CHECK(store_get(5) == 42, "data has key 5 = 42");
}

static void test_uncommitted_writes_lost_on_crash(void) {
    reset_all();
    store_set(0, 1);
    store_set(1, 2);
    log_commit();
    store_set(2, 3);
    store_set(3, 4);
    store_clear();
    int64_t n = replay();
    CHECK(n == 2, "only 2 committed records replayed");
    CHECK(store_get(0) == 1,  "committed key 0 survived");
    CHECK(store_get(1) == 2,  "committed key 1 survived");
    CHECK(store_get(2) == -1, "uncommitted key 2 lost");
    CHECK(store_get(3) == -1, "uncommitted key 3 lost");
}

static void test_delete_replays_correctly(void) {
    reset_all();
    store_set(0, 100);
    store_set(1, 200);
    store_del(0);
    log_commit();
    store_clear();
    replay();
    CHECK(store_get(0) == -1, "key 0 deleted");
    CHECK(store_get(1) == 200, "key 1 = 200");
}

static void test_overwrite_uses_last_record(void) {
    reset_all();
    store_set(7, 100);
    store_set(7, 200);
    store_set(7, 300);
    log_commit();
    store_clear();
    replay();
    CHECK(store_get(7) == 300, "last write wins on replay");
}

static void test_sequential_offsets_monotonic(void) {
    reset_all();
    int64_t prev = log_offset;
    for (int i = 0; i < 5; i++) {
        store_set(i, i * 10);
        int64_t now = log_offset;
        CHECK(now > prev, "log offset advances monotonically");
        prev = now;
    }
}

static void test_log_capacity_limit(void) {
    reset_all();
    int failures = 0;
    for (int i = 0; i < 300; i++) {
        int64_t ok = store_set(0, i);
        if (ok == 0) failures++;
    }
    CHECK(failures > 0, "log capacity is bounded");
}

int main(void) {
    (void)OP_INVALID; /* referenced by spec */
    test_append_and_replay();
    test_log_before_data_invariant();
    test_uncommitted_writes_lost_on_crash();
    test_delete_replays_correctly();
    test_overwrite_uses_last_record();
    test_sequential_offsets_monotonic();
    test_log_capacity_limit();
    printf("All write_ahead_logging examples passed.\n");
    return 0;
}
