/* Vidya — Transactions and ACID — C port.
 * OCC store with read-set version snapshots. Fixed-capacity arrays
 * mirror the Cyrius reference. */

#include <assert.h>
#include <stdio.h>
#include <string.h>

#define N_ACCOUNTS 8
#define N_TX 2
#define TX_CAP 4

enum { TX_FREE = 0, TX_ACTIVE = 1, TX_COMMITTED = 2, TX_ABORTED = 3 };

typedef struct {
    long long accounts[N_ACCOUNTS];
    long long version[N_ACCOUNTS];
    int status[N_TX];
    int wcount[N_TX];
    int wkeys[N_TX][TX_CAP];
    long long wvals[N_TX][TX_CAP];
    int rcount[N_TX];
    int rkeys[N_TX][TX_CAP];
    long long rsnaps[N_TX][TX_CAP];
} Store;

static void store_init(Store *s) { memset(s, 0, sizeof(*s)); }

static void account_set_raw(Store *s, int k, long long v) {
    s->accounts[k] = v;
    s->version[k] += 1;
}

static long long account_get_raw(Store *s, int k) { return s->accounts[k]; }

static long long account_total(Store *s) {
    long long sum = 0;
    for (int i = 0; i < N_ACCOUNTS; i++) sum += s->accounts[i];
    return sum;
}

static int tx_begin(Store *s) {
    for (int t = 0; t < N_TX; t++) {
        if (s->status[t] == TX_FREE) {
            s->status[t] = TX_ACTIVE;
            s->wcount[t] = 0;
            s->rcount[t] = 0;
            return t;
        }
    }
    return -1;
}

static int tx_find_write(Store *s, int tx, int k) {
    for (int i = 0; i < s->wcount[tx]; i++) {
        if (s->wkeys[tx][i] == k) return i;
    }
    return -1;
}

static int tx_has_read(Store *s, int tx, int k) {
    for (int i = 0; i < s->rcount[tx]; i++) {
        if (s->rkeys[tx][i] == k) return 1;
    }
    return 0;
}

static long long tx_read(Store *s, int tx, int k) {
    assert(s->status[tx] == TX_ACTIVE);
    int widx = tx_find_write(s, tx, k);
    if (widx >= 0) return s->wvals[tx][widx];
    if (!tx_has_read(s, tx, k) && s->rcount[tx] < TX_CAP) {
        s->rkeys[tx][s->rcount[tx]] = k;
        s->rsnaps[tx][s->rcount[tx]] = s->version[k];
        s->rcount[tx] += 1;
    }
    return s->accounts[k];
}

static int tx_write(Store *s, int tx, int k, long long v) {
    if (s->status[tx] != TX_ACTIVE) return 0;
    int widx = tx_find_write(s, tx, k);
    if (widx >= 0) {
        s->wvals[tx][widx] = v;
        return 1;
    }
    if (s->wcount[tx] >= TX_CAP) return 0;
    s->wkeys[tx][s->wcount[tx]] = k;
    s->wvals[tx][s->wcount[tx]] = v;
    s->wcount[tx] += 1;
    return 1;
}

static int tx_validate(Store *s, int tx) {
    for (int i = 0; i < s->rcount[tx]; i++) {
        int k = s->rkeys[tx][i];
        if (s->version[k] != s->rsnaps[tx][i]) return 0;
    }
    return 1;
}

static int tx_commit(Store *s, int tx) {
    if (s->status[tx] != TX_ACTIVE) return 0;
    if (!tx_validate(s, tx)) {
        s->status[tx] = TX_ABORTED;
        return 0;
    }
    for (int i = 0; i < s->wcount[tx]; i++) {
        int k = s->wkeys[tx][i];
        s->accounts[k] = s->wvals[tx][i];
        s->version[k] += 1;
    }
    s->status[tx] = TX_COMMITTED;
    return 1;
}

static int tx_abort(Store *s, int tx) {
    if (s->status[tx] != TX_ACTIVE) return 0;
    s->status[tx] = TX_ABORTED;
    return 1;
}

static void crash_recovery(Store *s) {
    for (int t = 0; t < N_TX; t++) {
        s->status[t] = TX_FREE;
        s->wcount[t] = 0;
        s->rcount[t] = 0;
    }
}

static void seed(Store *s) {
    store_init(s);
    account_set_raw(s, 0, 1000);
    account_set_raw(s, 1, 500);
    account_set_raw(s, 2, 200);
}

static int pass_count = 0;
static int fail_count = 0;

static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    Store s;

    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 9999);
        tx_write(&s, tx, 1, 8888);
        tx_write(&s, tx, 2, 7777);
        tx_abort(&s, tx);
        check(account_get_raw(&s, 0) == 1000, "abort: key 0 unchanged");
        check(account_get_raw(&s, 1) == 500, "abort: key 1 unchanged");
        check(account_get_raw(&s, 2) == 200, "abort: key 2 unchanged");
        check(s.status[tx] == TX_ABORTED, "tx status = ABORTED");
    }
    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 100);
        tx_write(&s, tx, 1, 200);
        tx_write(&s, tx, 2, 300);
        check(tx_commit(&s, tx) == 1, "commit succeeded");
        check(account_get_raw(&s, 0) == 100, "commit: key 0 installed");
        check(account_get_raw(&s, 1) == 200, "commit: key 1 installed");
        check(account_get_raw(&s, 2) == 300, "commit: key 2 installed");
        check(s.status[tx] == TX_COMMITTED, "tx status = COMMITTED");
    }
    seed(&s);
    {
        long long initial = account_total(&s);
        int tx = tx_begin(&s);
        long long src = tx_read(&s, tx, 0);
        long long dst = tx_read(&s, tx, 1);
        tx_write(&s, tx, 0, src - 100);
        tx_write(&s, tx, 1, dst + 100);
        tx_commit(&s, tx);
        check(account_get_raw(&s, 0) == 900, "src debited");
        check(account_get_raw(&s, 1) == 600, "dst credited");
        check(account_total(&s) == initial, "total preserved");
    }
    seed(&s);
    {
        int tx1 = tx_begin(&s);
        int tx2 = tx_begin(&s);
        tx_write(&s, tx1, 0, 9999);
        check(tx_read(&s, tx2, 0) == 1000, "tx2 sees committed, not pending");
    }
    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 4242);
        check(tx_read(&s, tx, 0) == 4242, "tx sees own write");
        check(account_get_raw(&s, 0) == 1000, "durable unchanged before commit");
    }
    seed(&s);
    {
        int tx1 = tx_begin(&s);
        int tx2 = tx_begin(&s);
        long long v1 = tx_read(&s, tx1, 0);
        tx_write(&s, tx1, 0, v1 + 50);
        long long v2 = tx_read(&s, tx2, 0);
        tx_write(&s, tx2, 0, v2 + 100);
        int ok1 = tx_commit(&s, tx1);
        int ok2 = tx_commit(&s, tx2);
        check(ok1 == 1, "tx1 commits");
        check(ok2 == 0, "tx2 conflicts and aborts");
        check(s.status[tx2] == TX_ABORTED, "tx2 status = ABORTED");
        check(account_get_raw(&s, 0) == 1050, "tx1 durable; tx2 lost");
    }
    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 12345);
        tx_commit(&s, tx);
        crash_recovery(&s);
        check(account_get_raw(&s, 0) == 12345, "committed survives crash");
    }
    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 7);
        int ok1 = tx_commit(&s, tx);
        int ok2 = tx_commit(&s, tx);
        check(ok1 == 1, "first commit ok");
        check(ok2 == 0, "second commit rejected");
    }
    seed(&s);
    {
        int tx = tx_begin(&s);
        tx_write(&s, tx, 0, 1);
        tx_write(&s, tx, 1, 2);
        tx_write(&s, tx, 2, 3);
        tx_write(&s, tx, 3, 4);
        int fifth = tx_write(&s, tx, 4, 5);
        check(fifth == 0, "5th write rejected (cap=4)");
    }

    printf("=== transactions_and_acid ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
