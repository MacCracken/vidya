/* Vidya — Consensus and Raft — C port. Fixed arrays mirror the
 * Cyrius reference. */

#include <stdio.h>
#include <string.h>

#define N_NODES 3
#define MAX_LOG 8
#define QUORUM  2

enum { ROLE_FOLLOWER = 0, ROLE_CANDIDATE = 1, ROLE_LEADER = 2 };

typedef struct {
    int role[N_NODES];
    long long term[N_NODES];
    int voted_for[N_NODES];
    int log_count[N_NODES];
    long long log_terms[N_NODES][MAX_LOG];
    long long log_values[N_NODES][MAX_LOG];
    int commit_idx[N_NODES];
} Cluster;

static void cluster_init(Cluster *c) {
    memset(c, 0, sizeof(*c));
    for (int i = 0; i < N_NODES; i++) {
        c->voted_for[i] = -1;
        c->commit_idx[i] = -1;
    }
}

static int last_log_index(const Cluster *c, int n) { return c->log_count[n] - 1; }
static long long last_log_term(const Cluster *c, int n) {
    int idx = last_log_index(c, n);
    return idx < 0 ? 0 : c->log_terms[n][idx];
}

static int log_up_to_date(long long c_term, int c_idx, long long v_term, int v_idx) {
    if (c_term > v_term) return 1;
    if (c_term < v_term) return 0;
    return c_idx >= v_idx ? 1 : 0;
}

static long long start_election(Cluster *c, int n) {
    c->term[n] += 1;
    c->voted_for[n] = n;
    c->role[n] = ROLE_CANDIDATE;
    return c->term[n];
}

static int request_vote(Cluster *c, int voter, int candidate, long long c_term,
                        long long c_last_term, int c_last_idx) {
    if (c_term < c->term[voter]) return 0;
    if (c_term > c->term[voter]) {
        c->term[voter] = c_term;
        c->voted_for[voter] = -1;
        c->role[voter] = ROLE_FOLLOWER;
    }
    if (c->voted_for[voter] != -1 && c->voted_for[voter] != candidate) return 0;
    if (!log_up_to_date(c_last_term, c_last_idx,
                        last_log_term(c, voter), last_log_index(c, voter))) return 0;
    c->voted_for[voter] = candidate;
    return 1;
}

static int run_election(Cluster *c, int candidate) {
    int votes = 1;
    long long c_term = c->term[candidate];
    long long c_last_term = last_log_term(c, candidate);
    int c_last_idx = last_log_index(c, candidate);
    for (int v = 0; v < N_NODES; v++) {
        if (v == candidate) continue;
        if (request_vote(c, v, candidate, c_term, c_last_term, c_last_idx)) votes++;
    }
    if (votes >= QUORUM) c->role[candidate] = ROLE_LEADER;
    return votes;
}

static int append_entry(Cluster *c, int leader, long long value) {
    if (c->log_count[leader] >= MAX_LOG) return -1;
    int idx = c->log_count[leader];
    c->log_terms[leader][idx] = c->term[leader];
    c->log_values[leader][idx] = value;
    c->log_count[leader] += 1;
    return idx;
}

static int replicate(Cluster *c, int leader, int follower) {
    int leader_count = c->log_count[leader];
    for (int i = 0; i < leader_count; i++) {
        long long lt = c->log_terms[leader][i];
        long long lv = c->log_values[leader][i];
        if (i < c->log_count[follower] && c->log_terms[follower][i] != lt) {
            c->log_count[follower] = i;
        }
        if (i >= c->log_count[follower]) {
            c->log_terms[follower][i] = lt;
            c->log_values[follower][i] = lv;
            c->log_count[follower] = i + 1;
        }
    }
    return c->log_count[follower];
}

static int count_matching(const Cluster *c, int leader, int idx) {
    long long leader_term = c->log_terms[leader][idx];
    int count = 0;
    for (int n = 0; n < N_NODES; n++) {
        if (c->log_count[n] > idx && c->log_terms[n][idx] == leader_term) count++;
    }
    return count;
}

static int advance_commit(Cluster *c, int leader) {
    long long cur = c->term[leader];
    for (int idx = c->commit_idx[leader] + 1; idx < c->log_count[leader]; idx++) {
        if (c->log_terms[leader][idx] == cur &&
            count_matching(c, leader, idx) >= QUORUM) {
            c->commit_idx[leader] = idx;
        }
    }
    return c->commit_idx[leader];
}

static int pass_count = 0, fail_count = 0;
static void check(int cond, const char *name) {
    if (cond) pass_count++;
    else { fail_count++; fprintf(stderr, "  FAIL: %s\n", name); }
}

int main(void) {
    Cluster c;

    cluster_init(&c);
    for (int n = 0; n < N_NODES; n++) check(c.role[n] == ROLE_FOLLOWER, "follower");
    check(c.term[0] == 0, "term=0");
    check(c.voted_for[0] == -1, "voted_for=-1");
    check(c.log_count[0] == 0, "empty log");
    check(c.commit_idx[0] == -1, "nothing committed");

    cluster_init(&c);
    {
        long long t = start_election(&c, 0);
        check(t == 1, "term=1");
        int v = run_election(&c, 0);
        check(v == 3, "3 votes");
        check(c.role[0] == ROLE_LEADER, "leader");
        check(c.term[1] == 1, "follower term");
        check(c.voted_for[1] == 0, "follower voted 0");
    }

    cluster_init(&c);
    c.term[1] = 5;
    check(!request_vote(&c, 1, 0, 1, 0, -1), "stale rejected");
    check(c.term[1] == 5, "term unchanged");

    cluster_init(&c);
    start_election(&c, 0);
    run_election(&c, 0);
    check(c.role[0] == ROLE_LEADER, "leader");
    check(request_vote(&c, 0, 2, 5, 0, -1), "higher-term granted");
    check(c.term[0] == 5, "term=5");
    check(c.role[0] == ROLE_FOLLOWER, "stepped down");

    cluster_init(&c);
    check(request_vote(&c, 2, 0, 1, 0, -1), "first vote");
    check(!request_vote(&c, 2, 1, 1, 0, -1), "second denied");
    check(c.voted_for[2] == 0, "voted_for unchanged");

    cluster_init(&c);
    start_election(&c, 0); run_election(&c, 0);
    append_entry(&c, 0, 100);
    append_entry(&c, 0, 200);
    append_entry(&c, 0, 300);
    check(replicate(&c, 0, 1) == 3, "3 replicated");
    for (int i = 0; i < 3; i++) {
        check(c.log_terms[0][i] == c.log_terms[1][i] &&
              c.log_values[0][i] == c.log_values[1][i], "match");
    }

    cluster_init(&c);
    start_election(&c, 0); run_election(&c, 0);
    append_entry(&c, 0, 42);
    replicate(&c, 0, 1);
    check(advance_commit(&c, 0) == 0, "commit_idx → 0");
    append_entry(&c, 0, 99);
    check(advance_commit(&c, 0) == 0, "stays at 0");
    replicate(&c, 0, 2);
    check(advance_commit(&c, 0) == 1, "commit_idx → 1");

    cluster_init(&c);
    start_election(&c, 0); run_election(&c, 0);
    append_entry(&c, 0, 10);
    append_entry(&c, 0, 20);
    c.term[1] = 4;
    long long t = start_election(&c, 1);
    check(!request_vote(&c, 0, 1, t, 0, -1), "shorter-log denied");
    check(c.term[0] == t, "term advanced");
    check(c.role[0] == ROLE_FOLLOWER, "stepped down");

    cluster_init(&c);
    start_election(&c, 0); run_election(&c, 0);
    append_entry(&c, 0, 100);
    replicate(&c, 0, 1);
    advance_commit(&c, 0);
    check(c.commit_idx[0] == 0, "term-1 committed");
    long long t2 = start_election(&c, 1);
    check(t2 == 2, "term=2");
    int votes = run_election(&c, 1);
    check(votes >= QUORUM, "node 1 wins");
    check(c.role[1] == ROLE_LEADER, "leader");
    append_entry(&c, 1, 200);
    replicate(&c, 1, 2);
    advance_commit(&c, 1);
    check(c.commit_idx[1] == 1, "term-2 commits and drags term-1 forward");
    check(c.log_terms[1][0] == 1, "idx 0 term-1");
    check(c.log_terms[1][1] == 2, "idx 1 term-2");

    cluster_init(&c);
    start_election(&c, 0);
    long long t1 = c.term[0];
    start_election(&c, 0);
    long long t2b = c.term[0];
    check(t2b > t1, "term increases");
    check(!request_vote(&c, 0, 1, 1, 0, -1), "stale denied");
    check(c.term[0] == t2b, "term not decremented");

    printf("=== consensus ===\n");
    printf("%d passed, %d failed (%d total)\n", pass_count, fail_count, pass_count + fail_count);
    return fail_count > 0 ? 1 : 0;
}
