# Vidya — Concurrent File Access (flock) in Python
#
# Single-process exercise of the file-lock state machine via two
# distinct OPENs of the same path. flock is per-OPEN; the two fds
# have independent lock state and contend with each other in one
# process. fcntl.flock raises BlockingIOError on LOCK_NB conflict.

import fcntl
import os
import struct

PATH = "/tmp/vidya_cfa_python.bin"


def main():
    try:
        os.remove(PATH)
    except FileNotFoundError:
        pass

    # --- Test 1: exclusive write ---
    f1 = open(PATH, "w+b")
    fcntl.flock(f1.fileno(), fcntl.LOCK_EX)
    f1.seek(0)
    f1.write(struct.pack("<Q", 0xDEADBEEF12345678))
    f1.flush()
    fcntl.flock(f1.fileno(), fcntl.LOCK_UN)

    # --- Test 2: shared read with roundtrip ---
    fcntl.flock(f1.fileno(), fcntl.LOCK_SH)
    f1.seek(0)
    got = struct.unpack("<Q", f1.read(8))[0]
    assert got == 0xDEADBEEF12345678, "data roundtrip"
    fcntl.flock(f1.fileno(), fcntl.LOCK_UN)

    # --- Test 3: exclusive contention ---
    f2 = open(PATH, "r+b")
    fcntl.flock(f1.fileno(), fcntl.LOCK_EX)
    blocked = False
    try:
        fcntl.flock(f2.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        blocked = True
    assert blocked, "fd2 non-blocking exclusive blocked while fd1 holds"

    # --- Test 4: release fd1, fd2 can acquire ---
    fcntl.flock(f1.fileno(), fcntl.LOCK_UN)
    fcntl.flock(f2.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(f2.fileno(), fcntl.LOCK_UN)

    # --- Test 5: shared locks coexist ---
    fcntl.flock(f1.fileno(), fcntl.LOCK_SH | fcntl.LOCK_NB)
    fcntl.flock(f2.fileno(), fcntl.LOCK_SH | fcntl.LOCK_NB)
    fcntl.flock(f1.fileno(), fcntl.LOCK_UN)
    fcntl.flock(f2.fileno(), fcntl.LOCK_UN)

    f1.close()
    f2.close()
    os.remove(PATH)
    print("concurrent_file_access: 12/12 ok")


main()
