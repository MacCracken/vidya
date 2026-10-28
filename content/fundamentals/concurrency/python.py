# Vidya — Concurrency in Python
#
# The default CPython build has the GIL (Global Interpreter Lock), which
# means threads don't run Python code in parallel. (The separate
# free-threaded build, supported since 3.14 per PEP 779, has no GIL and
# its threads do run in parallel.) On the default build, use threading
# for I/O-bound work, multiprocessing for CPU-bound work, and asyncio for
# high-concurrency I/O (thousands of connections).

import threading
import queue
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

def main():
    # ── Threading: concurrent I/O, not parallel CPU ─────────────────
    results = []
    lock = threading.Lock()

    def worker(n):
        value = n * n
        with lock:
            results.append(value)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sorted(results) == [0, 1, 4, 9, 16]

    # ── Thread-safe communication with Queue ────────────────────────
    q = queue.Queue()

    def producer():
        for i in range(5):
            q.put(i * i)
        q.put(None)  # sentinel

    def consumer():
        items = []
        while True:
            item = q.get()
            if item is None:
                break
            items.append(item)
        return items

    t = threading.Thread(target=producer)
    t.start()
    consumed = consumer()
    t.join()
    assert consumed == [0, 1, 4, 9, 16]

    # ── ThreadPoolExecutor: high-level thread management ────────────
    def compute(x):
        return x * x

    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(compute, i): i for i in range(10)}
        results = {}
        for future in as_completed(futures):
            i = futures[future]
            results[i] = future.result()

    assert results[5] == 25
    assert len(results) == 10

    # map() for simpler cases
    with ThreadPoolExecutor(max_workers=4) as executor:
        squares = list(executor.map(compute, range(5)))
    assert squares == [0, 1, 4, 9, 16]

    # ── Lock: mutual exclusion ──────────────────────────────────────
    counter = 0
    counter_lock = threading.Lock()

    def increment(n):
        nonlocal counter
        for _ in range(n):
            with counter_lock:  # context manager handles acquire/release
                # Read, yield, write: the sleep(0) hands the GIL to another
                # thread mid-update, so without the lock this loses updates
                # (measured: ~1000 of 4000 survive). A bare `counter += 1`
                # almost never races under the GIL, so it would pass with
                # the lock deleted and prove nothing.
                current = counter
                time.sleep(0)
                counter = current + 1

    threads = [threading.Thread(target=increment, args=(1000,)) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert counter == 4000

    # ── Event: signaling between threads ────────────────────────────
    ready = threading.Event()
    result_holder = [None]

    def waiter():
        ready.wait()  # blocks until set
        result_holder[0] = "done"

    t = threading.Thread(target=waiter)
    t.start()
    assert result_holder[0] is None  # not done yet
    ready.set()  # signal the waiter
    t.join()
    assert result_holder[0] == "done"

    # ── Barrier: synchronize N threads at a point ───────────────────
    barrier = threading.Barrier(3)
    arrival_order = []
    order_lock = threading.Lock()
    arrived = [0]
    seen_after_barrier = []

    def sync_worker(worker_id):
        with order_lock:
            arrived[0] += 1
        # All threads must reach the barrier before any proceed
        barrier.wait()
        with order_lock:
            seen_after_barrier.append(arrived[0])
            arrival_order.append(worker_id)

    threads = [threading.Thread(target=sync_worker, args=(i,)) for i in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(arrival_order) == 3
    # Every thread got past wait() only after all 3 had arrived
    assert seen_after_barrier == [3, 3, 3]

    # ── Thread-local data ───────────────────────────────────────────
    local = threading.local()
    all_set = threading.Barrier(3)

    def set_and_get(value):
        local.data = value
        # Wait until EVERY thread has written before reading back. Without
        # this, a plain shared object also passes (each thread reads its own
        # write before anyone else writes); with it, a shared object would
        # make all three read the last writer's value.
        all_set.wait()
        return local.data

    results = {}
    results_lock = threading.Lock()

    def thread_fn(tid):
        val = set_and_get(tid * 10)
        with results_lock:
            results[tid] = val

    threads = [threading.Thread(target=thread_fn, args=(i,)) for i in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    # Each thread saw its own value
    assert results[0] == 0
    assert results[1] == 10
    assert results[2] == 20

    # ── The GIL: what it means in practice ──────────────────────────
    # The GIL prevents parallel execution of Python bytecode.
    # CPU-bound threads don't speed up — use multiprocessing instead.
    #
    # I/O-bound threads DO run concurrently because the GIL is released
    # during I/O operations (file, network, sleep).
    #
    # For CPU parallelism, reach for processes. The `if __name__ ==
    # "__main__":` guard below is MANDATORY, not decoration: as of
    # Python 3.14 the default start method on Linux is `forkserver`
    # (it was `fork` through 3.13). forkserver and spawn re-IMPORT the
    # main module inside every child, so unguarded top-level Pool()
    # code runs again in the child, which then aborts. On 3.14 the
    # parent died with `ConnectionResetError: [Errno 104] Connection
    # reset by peer` from the forkserver handshake, a symptom that names
    # nothing. On 3.15 each child prints "RuntimeError: An attempt has
    # been made to start a new process before the current process has
    # finished its bootstrapping phase" and the Pool keeps respawning
    # the dying workers, so the parent HANGS instead of exiting. The
    # worker must also live at module scope so it can be pickled by
    # qualified name; a closure or nested def is not picklable.
    #
    #   from multiprocessing import Pool
    #
    #   def cpu_heavy_fn(x):        # module scope — picklable by name
    #       return x * x
    #
    #   if __name__ == "__main__":  # required under forkserver/spawn
    #       with Pool(4) as p:
    #           results = p.map(cpu_heavy_fn, data)

    print("All concurrency examples passed.")


if __name__ == "__main__":
    main()
