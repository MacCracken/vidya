# Vidya — Concurrency in Python
#
# Python has the GIL (Global Interpreter Lock), which means threads
# don't run Python code in parallel. Use threading for I/O-bound work,
# multiprocessing for CPU-bound work, and asyncio for high-concurrency
# I/O (thousands of connections).

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
                counter += 1

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

    def sync_worker(worker_id):
        # All threads must reach the barrier before any proceed
        barrier.wait()
        with order_lock:
            arrival_order.append(worker_id)

    threads = [threading.Thread(target=sync_worker, args=(i,)) for i in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert len(arrival_order) == 3

    # ── Thread-local data ───────────────────────────────────────────
    local = threading.local()

    def set_and_get(value):
        local.data = value
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
    # For CPU parallelism:
    #   from multiprocessing import Pool
    #   with Pool(4) as p:
    #       results = p.map(cpu_heavy_fn, data)

    print("All concurrency examples passed.")


if __name__ == "__main__":
    main()
