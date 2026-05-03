#!/usr/bin/env python3
"""Vidya — Consensus and Raft — Python port.

3-node Raft cluster as in-memory state machines. Mirrors the Cyrius
reference: same node API, same tests, same expected outcomes.
"""

N_NODES = 3
MAX_LOG = 8
QUORUM = 2

ROLE_FOLLOWER, ROLE_CANDIDATE, ROLE_LEADER = 0, 1, 2


class Cluster:
    def __init__(self):
        self.role = [ROLE_FOLLOWER] * N_NODES
        self.term = [0] * N_NODES
        self.voted_for = [-1] * N_NODES
        # log[node] = list of (term, value)
        self.log = [[] for _ in range(N_NODES)]
        self.commit_idx = [-1] * N_NODES

    def last_log_index(self, n): return len(self.log[n]) - 1
    def last_log_term(self, n):
        return self.log[n][-1][0] if self.log[n] else 0

    def log_up_to_date(self, c_term, c_idx, v_term, v_idx):
        if c_term > v_term: return True
        if c_term < v_term: return False
        return c_idx >= v_idx

    def start_election(self, node):
        self.term[node] += 1
        self.voted_for[node] = node
        self.role[node] = ROLE_CANDIDATE
        return self.term[node]

    def request_vote(self, voter, candidate, c_term, c_last_term, c_last_idx):
        if c_term < self.term[voter]:
            return False
        if c_term > self.term[voter]:
            self.term[voter] = c_term
            self.voted_for[voter] = -1
            self.role[voter] = ROLE_FOLLOWER
        if self.voted_for[voter] != -1 and self.voted_for[voter] != candidate:
            return False
        if not self.log_up_to_date(c_last_term, c_last_idx,
                                   self.last_log_term(voter),
                                   self.last_log_index(voter)):
            return False
        self.voted_for[voter] = candidate
        return True

    def run_election(self, candidate):
        votes = 1
        c_term = self.term[candidate]
        c_last_term = self.last_log_term(candidate)
        c_last_idx = self.last_log_index(candidate)
        for v in range(N_NODES):
            if v == candidate: continue
            if self.request_vote(v, candidate, c_term, c_last_term, c_last_idx):
                votes += 1
        if votes >= QUORUM:
            self.role[candidate] = ROLE_LEADER
        return votes

    def append_entry(self, leader, value):
        if len(self.log[leader]) >= MAX_LOG:
            return -1
        idx = len(self.log[leader])
        self.log[leader].append((self.term[leader], value))
        return idx

    def replicate(self, leader, follower):
        i = 0
        while i < len(self.log[leader]):
            le = self.log[leader][i]
            if i < len(self.log[follower]):
                if self.log[follower][i][0] != le[0]:
                    self.log[follower] = self.log[follower][:i]
            if i >= len(self.log[follower]):
                self.log[follower].append(le)
            i += 1
        return len(self.log[follower])

    def count_matching(self, leader, idx):
        leader_term = self.log[leader][idx][0]
        c = 0
        for n in range(N_NODES):
            if len(self.log[n]) > idx and self.log[n][idx][0] == leader_term:
                c += 1
        return c

    def advance_commit(self, leader):
        cur = self.term[leader]
        for idx in range(self.commit_idx[leader] + 1, len(self.log[leader])):
            if self.log[leader][idx][0] == cur:
                if self.count_matching(leader, idx) >= QUORUM:
                    self.commit_idx[leader] = idx
        return self.commit_idx[leader]


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_init_state():
    c = Cluster()
    for n in range(N_NODES):
        check(c.role[n] == ROLE_FOLLOWER, f"node {n} follower")
    check(c.term[0] == 0, "node 0 term=0")
    check(c.voted_for[0] == -1, "node 0 voted_for=-1")
    check(len(c.log[0]) == 0, "node 0 empty log")
    check(c.commit_idx[0] == -1, "node 0 nothing committed")


def test_single_node_election():
    c = Cluster()
    t = c.start_election(0)
    check(t == 1, "election bumps term to 1")
    votes = c.run_election(0)
    check(votes == 3, "3 votes")
    check(c.role[0] == ROLE_LEADER, "node 0 LEADER")
    check(c.term[1] == 1, "follower 1 term updated")
    check(c.voted_for[1] == 0, "follower 1 voted for 0")


def test_stale_request_rejected():
    c = Cluster()
    c.term[1] = 5
    ok = c.request_vote(1, 0, 1, 0, -1)
    check(ok is False, "stale-term RPC rejected")
    check(c.term[1] == 5, "voter term unchanged")


def test_higher_term_steps_down():
    c = Cluster()
    c.start_election(0)
    c.run_election(0)
    check(c.role[0] == ROLE_LEADER, "node 0 leader")
    ok = c.request_vote(0, 2, 5, 0, -1)
    check(ok is True, "higher-term granted")
    check(c.term[0] == 5, "term=5")
    check(c.role[0] == ROLE_FOLLOWER, "stepped down")


def test_vote_uniqueness():
    c = Cluster()
    a = c.request_vote(2, 0, 1, 0, -1)
    check(a is True, "first vote granted")
    b = c.request_vote(2, 1, 1, 0, -1)
    check(b is False, "second denied")
    check(c.voted_for[2] == 0, "voted_for unchanged")


def test_log_replication_and_match():
    c = Cluster()
    c.start_election(0); c.run_election(0)
    c.append_entry(0, 100)
    c.append_entry(0, 200)
    c.append_entry(0, 300)
    n = c.replicate(0, 1)
    check(n == 3, "follower 1 has 3 entries")
    for i in range(3):
        check(c.log[0][i] == c.log[1][i], f"match @{i}")


def test_commit_on_majority():
    c = Cluster()
    c.start_election(0); c.run_election(0)
    c.append_entry(0, 42)
    c.replicate(0, 1)
    check(c.advance_commit(0) == 0, "commit_idx → 0")
    c.append_entry(0, 99)
    check(c.advance_commit(0) == 0, "stays at 0 without majority for idx 1")
    c.replicate(0, 2)
    check(c.advance_commit(0) == 1, "commit_idx → 1 once majority")


def test_log_up_to_date_blocks_stale_candidate():
    c = Cluster()
    c.start_election(0); c.run_election(0)
    c.append_entry(0, 10)
    c.append_entry(0, 20)
    c.term[1] = 4
    t = c.start_election(1)
    ok = c.request_vote(0, 1, t, 0, -1)
    check(ok is False, "shorter-log candidate denied")
    check(c.term[0] == t, "term advanced via step-down")
    check(c.role[0] == ROLE_FOLLOWER, "stepped down")


def test_indirect_commit_of_prior_term():
    c = Cluster()
    c.start_election(0); c.run_election(0)
    c.append_entry(0, 100)
    c.replicate(0, 1)
    c.advance_commit(0)
    check(c.commit_idx[0] == 0, "term-1 entry committed")

    t2 = c.start_election(1)
    check(t2 == 2, "node 1 term=2")
    votes = c.run_election(1)
    check(votes >= QUORUM, "node 1 wins")
    check(c.role[1] == ROLE_LEADER, "leader")

    c.append_entry(1, 200)
    c.replicate(1, 2)
    c.advance_commit(1)
    check(c.commit_idx[1] == 1, "term-2 commit drags term-1 forward")
    check(c.log[1][0][0] == 1, "idx 0 term-1")
    check(c.log[1][1][0] == 2, "idx 1 term-2")


def test_term_monotonicity():
    c = Cluster()
    c.start_election(0); t1 = c.term[0]
    c.start_election(0); t2 = c.term[0]
    check(t2 > t1, "term increases")
    ok = c.request_vote(0, 1, 1, 0, -1)
    check(ok is False, "stale denied")
    check(c.term[0] == t2, "term not decremented")


if __name__ == "__main__":
    test_init_state()
    test_single_node_election()
    test_stale_request_rejected()
    test_higher_term_steps_down()
    test_vote_uniqueness()
    test_log_replication_and_match()
    test_commit_on_majority()
    test_log_up_to_date_blocks_stale_candidate()
    test_indirect_commit_of_prior_term()
    test_term_monotonicity()
    print("=== consensus ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
