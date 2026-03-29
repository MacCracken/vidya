# Vidya — Performance in Python
#
# Python is not fast by default — but it can be fast enough with the
# right techniques. Use built-in functions (C-implemented), avoid
# unnecessary allocation, prefer generators over lists, and know when
# to reach for C extensions or specialized libraries.

import time
import sys
from collections import deque

def main():
    # ── Built-in functions are C-fast ───────────────────────────────
    numbers = list(range(10_000))

    # GOOD: sum() is implemented in C — fast
    total = sum(numbers)
    assert total == 49_995_000

    # BAD: manual loop in Python — slow
    # total = 0
    # for n in numbers: total += n

    # Same principle: min(), max(), sorted(), any(), all() are C-speed
    assert min(numbers) == 0
    assert max(numbers) == 9999

    # ── List comprehensions vs map/filter ───────────────────────────
    # Comprehensions are bytecode-optimized and typically 20-30% faster

    # GOOD: comprehension
    squares = [x * x for x in range(1000)]

    # Slower: map with lambda (function call overhead per element)
    squares_map = list(map(lambda x: x * x, range(1000)))

    assert squares == squares_map

    # ── Generators: avoid materializing large sequences ─────────────
    # List: all elements in memory
    big_list = [x * x for x in range(100_000)]
    list_size = sys.getsizeof(big_list)

    # Generator: one element at a time
    big_gen = (x * x for x in range(100_000))
    gen_size = sys.getsizeof(big_gen)

    assert gen_size < list_size  # generator is tiny regardless of N

    # Use generators in pipelines
    total = sum(x * x for x in range(100_000))  # no intermediate list
    assert total == 333328333350000

    # ── String concatenation: join vs += ────────────────────────────
    # join() is O(n) — one allocation
    parts = [str(i) for i in range(1000)]
    result = ",".join(parts)
    assert result.startswith("0,1,2")

    # BAD: += in a loop is O(n²)
    # result = ""
    # for p in parts: result += "," + p

    # ── dict lookups are O(1) ───────────────────────────────────────
    lookup = {i: i * i for i in range(10_000)}
    assert lookup[5000] == 25_000_000

    # vs list linear search O(n)
    items = list(range(10_000))
    assert 5000 in items  # linear scan

    # For membership testing, use sets
    item_set = set(range(10_000))
    assert 5000 in item_set  # O(1)

    # ── deque for O(1) append/pop on both ends ──────────────────────
    # list.insert(0, x) is O(n) — shifts all elements
    # deque.appendleft(x) is O(1)

    d = deque(maxlen=5)
    for i in range(10):
        d.append(i)
    assert list(d) == [5, 6, 7, 8, 9]  # oldest items dropped

    # ── Local variables are faster than global ──────────────────────
    # Python looks up local variables by index, global by name (dict lookup)

    global_list = list(range(100))

    def sum_local():
        local_list = global_list  # bind to local name
        total = 0
        for x in local_list:
            total += x
        return total

    assert sum_local() == 4950

    # ── __slots__ for memory-efficient objects ──────────────────────
    class PointRegular:
        def __init__(self, x, y):
            self.x = x
            self.y = y

    class PointSlots:
        __slots__ = ("x", "y")
        def __init__(self, x, y):
            self.x = x
            self.y = y

    regular = PointRegular(1, 2)
    slotted = PointSlots(1, 2)

    regular_size = sys.getsizeof(regular) + sys.getsizeof(regular.__dict__)
    slotted_size = sys.getsizeof(slotted)
    # Slotted is typically 40-60% smaller
    assert slotted.x == 1 and slotted.y == 2

    # ── Avoid repeated attribute lookups in loops ───────────────────
    data = []
    append = data.append  # cache the method lookup
    for i in range(100):
        append(i)  # faster than data.append(i) in tight loops
    assert len(data) == 100

    # ── Use appropriate data structures ─────────────────────────────
    # bisect for sorted list operations
    import bisect
    sorted_data = [1, 3, 5, 7, 9]
    bisect.insort(sorted_data, 4)
    assert sorted_data == [1, 3, 4, 5, 7, 9]

    # Counter for frequency counting
    from collections import Counter
    words = "the cat sat on the mat the cat".split()
    freq = Counter(words)
    assert freq["the"] == 3
    assert freq.most_common(1) == [("the", 3)]

    # defaultdict to avoid key checking
    from collections import defaultdict
    groups = defaultdict(list)
    for word in words:
        groups[len(word)].append(word)
    assert len(groups[3]) > 0  # 3-letter words

    # ── Measuring performance ───────────────────────────────────────
    # time.perf_counter for precise timing
    start = time.perf_counter()
    _ = sum(range(100_000))
    elapsed = time.perf_counter() - start
    assert elapsed >= 0  # just verifying it works

    # For proper benchmarking, use timeit:
    # import timeit
    # timeit.timeit("sum(range(1000))", number=10000)

    print("All performance examples passed.")


if __name__ == "__main__":
    main()
