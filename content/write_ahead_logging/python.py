#!/usr/bin/env python3
"""Vidya — Write-Ahead Logging in Python

In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
mutating the data store, then replay the durable prefix on recovery.
Python's `bytearray` is the natural cousin of cyrius's flat byte buffer
— mutable, indexable, and fits cleanly with `int.to_bytes` /
`int.from_bytes` for the 64-bit fields. The 256-record cap and the
OP_INVALID/SET/DEL constants match the cyrius reference byte-for-byte.
No real fsync — `log_committed` snapshots the durable prefix.
"""

REC_SZ = 24
LOG_CAP_BYTES = 6144
OP_INVALID = 0
OP_SET = 1
OP_DEL = 2
STORE_KEYS = 16


class Wal:
    def __init__(self) -> None:
        self.log_buf = bytearray(LOG_CAP_BYTES)
        self.log_offset = 0
        self.log_committed = 0
        self.data_vals = [0] * STORE_KEYS
        self.data_present = [0] * STORE_KEYS

    def log_reset(self) -> None:
        self.log_offset = 0
        self.log_committed = 0

    def store_clear(self) -> None:
        for i in range(STORE_KEYS):
            self.data_vals[i] = 0
            self.data_present[i] = 0

    def reset_all(self) -> None:
        self.log_reset()
        self.store_clear()
        # Wipe the buffer so leftover bytes from a prior test don't ghost
        # into a fresh replay.
        for i in range(LOG_CAP_BYTES):
            self.log_buf[i] = 0

    def _store64(self, off: int, v: int) -> None:
        # Two's-complement little-endian, matching cyrius's store64.
        self.log_buf[off:off + 8] = int(v).to_bytes(8, "little", signed=True)

    def _load64(self, off: int) -> int:
        return int.from_bytes(self.log_buf[off:off + 8], "little", signed=True)

    def log_append(self, op: int, key: int, val: int) -> int:
        # Returns 1 on success, 0 if the buffer is full — matches cyrius.
        if self.log_offset + REC_SZ > LOG_CAP_BYTES:
            return 0
        off = self.log_offset
        self._store64(off, op)
        self._store64(off + 8, key)
        self._store64(off + 16, val)
        self.log_offset += REC_SZ
        return 1

    def log_commit(self) -> int:
        # Real implementations call fsync(wal_fd); we model durability
        # with an offset snapshot.
        self.log_committed = self.log_offset
        return self.log_committed

    def store_set(self, key: int, val: int) -> int:
        if key < 0 or key >= STORE_KEYS:
            return 0
        # WAL rule: log BEFORE data.
        if self.log_append(OP_SET, key, val) == 0:
            return 0
        self.data_vals[key] = val
        self.data_present[key] = 1
        return 1

    def store_del(self, key: int) -> int:
        if key < 0 or key >= STORE_KEYS:
            return 0
        if self.log_append(OP_DEL, key, 0) == 0:
            return 0
        self.data_vals[key] = 0
        self.data_present[key] = 0
        return 1

    def store_get(self, key: int) -> int:
        if key < 0 or key >= STORE_KEYS:
            return -1
        if self.data_present[key] == 0:
            return -1
        return self.data_vals[key]

    def replay(self) -> int:
        self.store_clear()
        pos = 0
        applied = 0
        while pos < self.log_committed:
            op = self._load64(pos)
            key = self._load64(pos + 8)
            val = self._load64(pos + 16)
            if op == OP_SET:
                self.data_vals[key] = val
                self.data_present[key] = 1
                applied += 1
            elif op == OP_DEL:
                self.data_vals[key] = 0
                self.data_present[key] = 0
                applied += 1
            pos += REC_SZ
        return applied


def test_append_and_replay() -> None:
    w = Wal()
    w.reset_all()
    w.store_set(0, 100)
    w.store_set(1, 200)
    w.store_set(2, 300)
    w.log_commit()
    w.store_clear()
    n = w.replay()
    assert n == 3, "replayed 3 records"
    assert w.store_get(0) == 100, "key 0 = 100"
    assert w.store_get(1) == 200, "key 1 = 200"
    assert w.store_get(2) == 300, "key 2 = 300"


def test_log_before_data_invariant() -> None:
    w = Wal()
    w.reset_all()
    ok = w.store_set(5, 42)
    assert ok == 1, "first set succeeds"
    assert w._load64(0) == OP_SET, "log[0].op = SET"
    assert w._load64(8) == 5, "log[0].key = 5"
    assert w._load64(16) == 42, "log[0].val = 42"
    assert w.store_get(5) == 42, "data has key 5 = 42"


def test_uncommitted_writes_lost_on_crash() -> None:
    w = Wal()
    w.reset_all()
    w.store_set(0, 1)
    w.store_set(1, 2)
    w.log_commit()
    w.store_set(2, 3)
    w.store_set(3, 4)
    w.store_clear()
    n = w.replay()
    assert n == 2, "only 2 committed records replayed"
    assert w.store_get(0) == 1, "committed key 0 survived"
    assert w.store_get(1) == 2, "committed key 1 survived"
    assert w.store_get(2) == -1, "uncommitted key 2 lost"
    assert w.store_get(3) == -1, "uncommitted key 3 lost"


def test_delete_replays_correctly() -> None:
    w = Wal()
    w.reset_all()
    w.store_set(0, 100)
    w.store_set(1, 200)
    w.store_del(0)
    w.log_commit()
    w.store_clear()
    w.replay()
    assert w.store_get(0) == -1, "key 0 deleted"
    assert w.store_get(1) == 200, "key 1 = 200"


def test_overwrite_uses_last_record() -> None:
    w = Wal()
    w.reset_all()
    w.store_set(7, 100)
    w.store_set(7, 200)
    w.store_set(7, 300)
    w.log_commit()
    w.store_clear()
    w.replay()
    assert w.store_get(7) == 300, "last write wins on replay"


def test_sequential_offsets_monotonic() -> None:
    w = Wal()
    w.reset_all()
    prev = w.log_offset
    for i in range(5):
        w.store_set(i, i * 10)
        now = w.log_offset
        assert now > prev, "log offset advances monotonically"
        prev = now


def test_log_capacity_limit() -> None:
    w = Wal()
    w.reset_all()
    failures = 0
    for i in range(300):
        ok = w.store_set(0, i)
        if ok == 0:
            failures += 1
    assert failures > 0, "log capacity is bounded"


def main() -> None:
    _ = OP_INVALID  # referenced by spec; unused at runtime
    test_append_and_replay()
    test_log_before_data_invariant()
    test_uncommitted_writes_lost_on_crash()
    test_delete_replays_correctly()
    test_overwrite_uses_last_record()
    test_sequential_offsets_monotonic()
    test_log_capacity_limit()
    print("All write_ahead_logging examples passed.")


if __name__ == "__main__":
    main()
