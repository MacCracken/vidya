# Vidya — Iterators in Python
#
# Python iterators are the backbone of for-loops, comprehensions, and
# generators. The iterator protocol (__iter__ + __next__) is simple but
# powerful. Generators (yield) create lazy sequences without classes.

def main():
    # ── Basic iteration ─────────────────────────────────────────────
    numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    # List comprehension — the Pythonic way
    even_squares = [x * x for x in numbers if x % 2 == 0]
    assert even_squares == [4, 16, 36, 64, 100]

    # ── Generator expressions: lazy evaluation ──────────────────────
    # Generators produce values one at a time — no list in memory
    gen = (x * x for x in range(1_000_000))
    first = next(gen)
    assert first == 0
    second = next(gen)
    assert second == 1

    # GOTCHA: generators can only be iterated once!
    small_gen = (x for x in range(3))
    first_pass = list(small_gen)
    second_pass = list(small_gen)  # empty — generator exhausted
    assert first_pass == [0, 1, 2]
    assert second_pass == []

    # ── Generator functions with yield ──────────────────────────────
    def countdown(n):
        while n > 0:
            yield n
            n -= 1

    assert list(countdown(3)) == [3, 2, 1]

    # Infinite generators
    def naturals():
        n = 0
        while True:
            yield n
            n += 1

    from itertools import islice
    first_five = list(islice(naturals(), 5))
    assert first_five == [0, 1, 2, 3, 4]

    # ── Built-in functions that work with iterators ─────────────────
    assert sum(numbers) == 55
    assert min(numbers) == 1
    assert max(numbers) == 10
    assert any(x > 5 for x in numbers)
    assert not all(x > 5 for x in numbers)
    assert len(list(filter(lambda x: x % 2 == 0, numbers))) == 5

    # ── map, filter, zip, enumerate ─────────────────────────────────
    doubled = list(map(lambda x: x * 2, [1, 2, 3]))
    assert doubled == [2, 4, 6]

    evens = list(filter(lambda x: x % 2 == 0, numbers))
    assert evens == [2, 4, 6, 8, 10]

    pairs = list(zip([1, 2, 3], ["a", "b", "c"]))
    assert pairs == [(1, "a"), (2, "b"), (3, "c")]

    for i, word in enumerate(["hello", "world"]):
        assert isinstance(i, int)
        assert isinstance(word, str)

    # ── itertools: the power tools ──────────────────────────────────
    import itertools

    # chain: concatenate iterables
    combined = list(itertools.chain([1, 2], [3, 4], [5]))
    assert combined == [1, 2, 3, 4, 5]

    # groupby: group consecutive equal elements
    data = [("a", 1), ("a", 2), ("b", 3), ("b", 4)]
    groups = {k: list(v) for k, v in itertools.groupby(data, key=lambda x: x[0])}
    assert len(groups["a"]) == 2
    assert len(groups["b"]) == 2

    # product: cartesian product
    combos = list(itertools.product([1, 2], ["a", "b"]))
    assert combos == [(1, "a"), (1, "b"), (2, "a"), (2, "b")]

    # accumulate: running totals
    running_sum = list(itertools.accumulate([1, 2, 3, 4]))
    assert running_sum == [1, 3, 6, 10]

    # ── The iterator protocol ───────────────────────────────────────
    class Squares:
        """Custom iterator: squares from 0 to n-1."""
        def __init__(self, n):
            self.n = n
            self.i = 0

        def __iter__(self):
            return self

        def __next__(self):
            if self.i >= self.n:
                raise StopIteration
            result = self.i * self.i
            self.i += 1
            return result

    assert list(Squares(4)) == [0, 1, 4, 9]

    # ── Comprehensions: list, dict, set ─────────────────────────────
    squares_list = [x * x for x in range(5)]
    assert squares_list == [0, 1, 4, 9, 16]

    squares_dict = {x: x * x for x in range(5)}
    assert squares_dict[3] == 9

    squares_set = {x % 3 for x in range(10)}
    assert squares_set == {0, 1, 2}

    # Nested comprehension
    flat = [x for row in [[1, 2], [3, 4], [5]] for x in row]
    assert flat == [1, 2, 3, 4, 5]

    # ── reduce (functools) ──────────────────────────────────────────
    from functools import reduce
    product = reduce(lambda a, b: a * b, [1, 2, 3, 4])
    assert product == 24

    # ── sorted with key ─────────────────────────────────────────────
    words = ["banana", "apple", "cherry"]
    by_length = sorted(words, key=len)
    assert by_length == ["apple", "banana", "cherry"]

    # Stable sort — equal elements keep original order
    data = [(1, "b"), (2, "a"), (1, "a")]
    by_first = sorted(data, key=lambda x: x[0])
    assert by_first == [(1, "b"), (1, "a"), (2, "a")]

    print("All iterator examples passed.")


if __name__ == "__main__":
    main()
