#!/usr/bin/env python3
"""Vidya — Distributed Systems Foundations — Python port.

Vector clocks + quorum reads/writes + partition handling.
"""

N_NODES = 3
W = 2
R = 2

VC_LESS, VC_EQUAL, VC_GREATER, VC_CONCURRENT = 1, 2, 3, 4


def vc_init():
    return [0] * N_NODES


def vc_tick(vc, node):
    vc[node] += 1


def vc_merge(into, from_):
    for i in range(N_NODES):
        if from_[i] > into[i]:
            into[i] = from_[i]


def vc_compare(a, b):
    any_lt = any(a[i] < b[i] for i in range(N_NODES))
    any_gt = any(a[i] > b[i] for i in range(N_NODES))
    if not any_lt:
        return VC_EQUAL if not any_gt else VC_GREATER
    return VC_LESS if not any_gt else VC_CONCURRENT


class QCluster:
    def __init__(self):
        self.accounts = [0] * N_NODES
        self.write_seq = [0] * N_NODES
        self.alive = [1] * N_NODES
        self.global_seq = 0

    def partition(self, node): self.alive[node] = 0
    def heal(self, node):      self.alive[node] = 1
    def alive_count(self):     return sum(self.alive)

    def write(self, value):
        if self.alive_count() < W:
            return 0
        self.global_seq += 1
        for i in range(N_NODES):
            if self.alive[i]:
                self.accounts[i] = value
                self.write_seq[i] = self.global_seq
        return 1

    def read(self):
        if self.alive_count() < R:
            return -1
        best_seq, best_value = 0, 0
        for i in range(N_NODES):
            if self.alive[i] and self.write_seq[i] > best_seq:
                best_seq = self.write_seq[i]
                best_value = self.accounts[i]
        return best_value


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_vc_init():
    vc = vc_init()
    check(vc == [0, 0, 0], "vc init zero")


def test_vc_tick():
    vc = vc_init()
    vc_tick(vc, 1); vc_tick(vc, 1); vc_tick(vc, 2)
    check(vc == [0, 2, 1], "tick increments own component")


def test_vc_merge():
    a = vc_init(); b = vc_init()
    vc_tick(a, 0); vc_tick(a, 0)
    vc_tick(b, 1); vc_tick(b, 2)
    vc_merge(a, b)
    check(a == [2, 1, 1], "merge takes element-wise max")


def test_vc_compare_less():
    a = vc_init(); b = vc_init()
    vc_tick(b, 0)
    check(vc_compare(a, b) == VC_LESS, "[0,0,0] < [1,0,0]")


def test_vc_compare_greater():
    a = vc_init(); b = vc_init()
    vc_tick(a, 0); vc_tick(a, 0); vc_tick(b, 0)
    check(vc_compare(a, b) == VC_GREATER, "[2,0,0] > [1,0,0]")


def test_vc_compare_equal():
    a = vc_init(); b = vc_init()
    vc_tick(a, 1); vc_tick(b, 1)
    check(vc_compare(a, b) == VC_EQUAL, "equal")


def test_vc_compare_concurrent():
    a = vc_init(); b = vc_init()
    vc_tick(a, 0); vc_tick(b, 1)
    check(vc_compare(a, b) == VC_CONCURRENT, "[1,0,0] || [0,1,0]")
    check(vc_compare(b, a) == VC_CONCURRENT, "concurrent symmetric")


def test_quorum_write_succeeds_full_cluster():
    c = QCluster()
    check(c.write(100) == 1, "qwrite ok with 3 alive")
    check(c.accounts == [100, 100, 100], "all replicas wrote")


def test_quorum_write_succeeds_with_one_partitioned():
    c = QCluster()
    c.partition(2)
    check(c.write(200) == 1, "qwrite ok with 2 alive")
    check(c.accounts[0] == 200 and c.accounts[1] == 200, "0 and 1 wrote")
    check(c.accounts[2] == 0, "2 (partitioned) untouched")


def test_quorum_write_fails_with_two_partitioned():
    c = QCluster()
    c.partition(1); c.partition(2)
    check(c.write(300) == 0, "qwrite fails when only 1 alive")
    check(c.accounts[0] == 0, "no replica wrote")


def test_intersection_guarantees_latest_read():
    c = QCluster()
    c.partition(2); c.write(500); c.heal(2)
    c.partition(0)
    v = c.read()
    check(v == 500, "intersection: read sees latest")


def test_quorum_read_fails_when_below_R():
    c = QCluster()
    c.write(700)
    c.partition(0); c.partition(1)
    check(c.read() == -1, "qread sentinel when alive < R")


if __name__ == "__main__":
    test_vc_init()
    test_vc_tick()
    test_vc_merge()
    test_vc_compare_less()
    test_vc_compare_greater()
    test_vc_compare_equal()
    test_vc_compare_concurrent()
    test_quorum_write_succeeds_full_cluster()
    test_quorum_write_succeeds_with_one_partitioned()
    test_quorum_write_fails_with_two_partitioned()
    test_intersection_guarantees_latest_read()
    test_quorum_read_fails_when_below_R()
    print("=== distributed_systems ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
