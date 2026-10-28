#!/usr/bin/env python3
"""Vidya — Transactions and ACID — Python port.

OCC store with read-set version snapshots. Mirrors the Cyrius
reference: same accounts, same tests, same expected outcomes.
"""

N_ACCOUNTS = 8
N_TX = 2
TX_CAP = 4

TX_FREE, TX_ACTIVE, TX_COMMITTED, TX_ABORTED = 0, 1, 2, 3


class Store:
    def __init__(self):
        self.accounts = [0] * N_ACCOUNTS
        self.version = [0] * N_ACCOUNTS
        self.tx_status = [TX_FREE] * N_TX
        self.tx_writes = [{} for _ in range(N_TX)]
        self.tx_reads = [{} for _ in range(N_TX)]
        # Set when a read could not be recorded (read-set full). Validation
        # cannot check a key it never snapshotted, so such a tx must not
        # commit — otherwise a stale read of that key commits silently.
        self.read_overflow = [False] * N_TX

    def account_set_raw(self, k, v):
        self.accounts[k] = v
        self.version[k] += 1

    def account_get_raw(self, k):
        return self.accounts[k]

    def total(self):
        return sum(self.accounts)

    def begin(self):
        for t in range(N_TX):
            if self.tx_status[t] == TX_FREE:
                self.tx_status[t] = TX_ACTIVE
                self.tx_writes[t] = {}
                self.tx_reads[t] = {}
                self.read_overflow[t] = False
                return t
        return -1

    def read(self, tx, k):
        assert self.tx_status[tx] == TX_ACTIVE
        if k in self.tx_writes[tx]:
            return self.tx_writes[tx][k]
        if k not in self.tx_reads[tx]:
            if len(self.tx_reads[tx]) < TX_CAP:
                self.tx_reads[tx][k] = self.version[k]
            else:
                self.read_overflow[tx] = True  # untracked read: cannot validate
        return self.accounts[k]

    def write(self, tx, k, v):
        if self.tx_status[tx] != TX_ACTIVE:
            return 0
        if k in self.tx_writes[tx]:
            self.tx_writes[tx][k] = v
            return 1
        if len(self.tx_writes[tx]) >= TX_CAP:
            return 0
        self.tx_writes[tx][k] = v
        return 1

    def validate(self, tx):
        if self.read_overflow[tx]:
            return False
        for k, snap in self.tx_reads[tx].items():
            if self.version[k] != snap:
                return False
        return True

    def commit(self, tx):
        if self.tx_status[tx] != TX_ACTIVE:
            return 0
        if not self.validate(tx):
            self.tx_status[tx] = TX_ABORTED
            return 0
        for k, v in self.tx_writes[tx].items():
            self.accounts[k] = v
            self.version[k] += 1
        self.tx_status[tx] = TX_COMMITTED
        return 1

    def abort(self, tx):
        if self.tx_status[tx] != TX_ACTIVE:
            return 0
        self.tx_status[tx] = TX_ABORTED
        return 1

    def crash_recovery(self):
        for t in range(N_TX):
            self.tx_status[t] = TX_FREE
            self.tx_writes[t] = {}
            self.tx_reads[t] = {}
            self.read_overflow[t] = False


def seed():
    s = Store()
    s.account_set_raw(0, 1000)
    s.account_set_raw(1, 500)
    s.account_set_raw(2, 200)
    return s


PASS, FAIL = 0, 0


def check(cond, name):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL: {name}")


def test_atomicity_abort():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 9999)
    s.write(tx, 1, 8888)
    s.write(tx, 2, 7777)
    s.abort(tx)
    check(s.account_get_raw(0) == 1000, "abort: key 0 unchanged")
    check(s.account_get_raw(1) == 500, "abort: key 1 unchanged")
    check(s.account_get_raw(2) == 200, "abort: key 2 unchanged")
    check(s.tx_status[tx] == TX_ABORTED, "tx status = ABORTED")


def test_atomicity_commit():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 100)
    s.write(tx, 1, 200)
    s.write(tx, 2, 300)
    check(s.commit(tx) == 1, "commit succeeded")
    check(s.account_get_raw(0) == 100, "commit: key 0 installed")
    check(s.account_get_raw(1) == 200, "commit: key 1 installed")
    check(s.account_get_raw(2) == 300, "commit: key 2 installed")
    check(s.tx_status[tx] == TX_COMMITTED, "tx status = COMMITTED")


def test_consistency_transfer():
    s = seed()
    initial = s.total()
    tx = s.begin()
    src = s.read(tx, 0)
    dst = s.read(tx, 1)
    s.write(tx, 0, src - 100)
    s.write(tx, 1, dst + 100)
    s.commit(tx)
    check(s.account_get_raw(0) == 900, "src debited")
    check(s.account_get_raw(1) == 600, "dst credited")
    check(s.total() == initial, "total preserved")


def test_isolation_no_dirty_read():
    s = seed()
    tx1 = s.begin()
    tx2 = s.begin()
    s.write(tx1, 0, 9999)
    check(s.read(tx2, 0) == 1000, "tx2 sees committed, not tx1's pending")


def test_isolation_read_your_own_writes():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 4242)
    check(s.read(tx, 0) == 4242, "tx sees own write")
    check(s.account_get_raw(0) == 1000, "durable store unchanged before commit")


def test_isolation_write_write_conflict():
    s = seed()
    tx1 = s.begin()
    tx2 = s.begin()
    v1 = s.read(tx1, 0)
    s.write(tx1, 0, v1 + 50)
    v2 = s.read(tx2, 0)
    s.write(tx2, 0, v2 + 100)
    ok1 = s.commit(tx1)
    ok2 = s.commit(tx2)
    check(ok1 == 1, "tx1 commits")
    check(ok2 == 0, "tx2 conflicts and aborts")
    check(s.tx_status[tx2] == TX_ABORTED, "tx2 status = ABORTED")
    check(s.account_get_raw(0) == 1050, "tx1's write durable; tx2 lost")


def test_durability_survives_crash():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 12345)
    s.commit(tx)
    in_flight = s.begin()
    s.write(in_flight, 1, 777)  # never committed
    s.crash_recovery()
    # Durability is half the property; the other half is that a crash must
    # not let uncommitted work leak in (atomicity across the crash).
    check(s.account_get_raw(0) == 12345, "committed value survives crash")
    check(s.account_get_raw(1) == 500, "in-flight write discarded by crash")
    check(s.begin() == 0, "tx slots free after recovery")


def test_readset_overflow_aborts():
    s = seed()
    s.account_set_raw(4, 50)
    tx1 = s.begin()
    for k in range(TX_CAP):
        s.read(tx1, k)
    stale = s.read(tx1, 4)        # 5th key: read-set full, not snapshotted
    tx2 = s.begin()
    s.write(tx2, 4, 999)
    s.commit(tx2)                 # key 4 changes under tx1
    s.write(tx1, 4, stale + 1)
    check(s.commit(tx1) == 0, "untracked read aborts commit (no lost update)")
    check(s.account_get_raw(4) == 999, "tx2's write survives")


def test_no_double_commit():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 7)
    ok1 = s.commit(tx)
    ok2 = s.commit(tx)
    check(ok1 == 1, "first commit ok")
    check(ok2 == 0, "second commit rejected")


def test_writeset_capacity():
    s = seed()
    tx = s.begin()
    s.write(tx, 0, 1)
    s.write(tx, 1, 2)
    s.write(tx, 2, 3)
    s.write(tx, 3, 4)
    fifth = s.write(tx, 4, 5)
    check(fifth == 0, "5th write rejected (cap=4)")


if __name__ == "__main__":
    test_atomicity_abort()
    test_atomicity_commit()
    test_consistency_transfer()
    test_isolation_no_dirty_read()
    test_isolation_read_your_own_writes()
    test_isolation_write_write_conflict()
    test_durability_survives_crash()
    test_no_double_commit()
    test_writeset_capacity()
    test_readset_overflow_aborts()
    print(f"=== transactions_and_acid ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
