# Vidya — Memory Management in Python
#
# Python uses reference counting with a cycle-detecting garbage collector.
# Objects are allocated on the heap; there is no stack allocation for Python
# objects. Understanding object identity, mutability, and the GC helps
# avoid subtle bugs and memory leaks.

import sys
import gc
import weakref

def main():
    # ── Reference counting ──────────────────────────────────────────
    # Python tracks how many references point to each object
    a = [1, 2, 3]
    # Before 3.14 this was one higher (getrefcount's argument held its own
    # temporary reference). Since 3.14 the interpreter passes a BORROWED
    # reference where it can, so a fresh local now reports 1, not 2.
    ref_before = sys.getrefcount(a)

    b = a  # b points to the same object — refcount increases
    assert a is b  # same object identity
    assert sys.getrefcount(a) > ref_before  # one more reference

    b = None  # refcount decreases; object freed when it hits zero

    # ── Identity vs equality ────────────────────────────────────────
    x = [1, 2, 3]
    y = [1, 2, 3]
    assert x == y      # equal values
    assert x is not y  # different objects in memory

    # Small integers are cached: CPython keeps one object per value in
    # -5..1024 since 3.15 (-5..256 before). Build them at RUNTIME to see it:
    # two equal literals in one function share a single constant object, so
    # `a = 5000; b = 5000; a is b` is True with no cache involved at all.
    a = int("42")
    b = int("42")
    assert a is b  # same cached object

    # ── Mutability matters for memory ───────────────────────────────
    # Mutable objects: list, dict, set — modified in place
    lst = [1, 2, 3]
    lst.append(4)  # modifies the same object
    assert lst == [1, 2, 3, 4]

    # Immutable objects: int, str, tuple — create new objects
    s = "hello"
    t = s + " world"  # creates a NEW string object
    assert s == "hello"  # original unchanged

    # ── Copy vs reference ───────────────────────────────────────────
    import copy

    original = [[1, 2], [3, 4]]

    # Shallow copy: new outer list, same inner lists
    shallow = copy.copy(original)
    shallow[0].append(99)
    assert original[0] == [1, 2, 99]  # inner list shared!

    # Deep copy: fully independent
    original = [[1, 2], [3, 4]]
    deep = copy.deepcopy(original)
    deep[0].append(99)
    assert original[0] == [1, 2]  # original untouched

    # ── Garbage collector for reference cycles ──────────────────────
    # Reference counting alone can't free cycles
    class Node:
        def __init__(self):
            self.ref = None

    a = Node()
    b = Node()
    a.ref = b
    b.ref = a  # cycle! refcount never reaches zero
    probe = weakref.ref(a)

    gc.disable()  # keep the automatic collector from running in between
    del a, b
    assert probe() is not None  # refcounting alone did NOT free the cycle

    # Python's GC detects and collects cycles
    collected = gc.collect()
    gc.enable()
    assert collected >= 2 and probe() is None  # the cycle collector did

    # ── Weak references: break reference cycles ─────────────────────
    class Resource:
        def __init__(self, name):
            self.name = name

    obj = Resource("test")
    weak = weakref.ref(obj)
    assert weak() is obj  # dereference the weak ref

    del obj
    assert weak() is None  # object was freed — weak ref returns None

    # ── __slots__: memory-efficient classes ─────────────────────────
    class PointDict:
        """Regular class — each instance has a __dict__ (heavy)."""
        def __init__(self, x, y):
            self.x = x
            self.y = y

    class PointSlots:
        """Slotted class — fixed attributes, no __dict__ (light)."""
        __slots__ = ("x", "y")
        def __init__(self, x, y):
            self.x = x
            self.y = y

    p1 = PointDict(1, 2)
    p2 = PointSlots(1, 2)
    assert p2.x == 1 and p2.y == 2
    # PointSlots uses ~40-60% less memory per instance than PointDict

    # ── Generators: lazy allocation ─────────────────────────────────
    # List: all elements in memory at once
    eager = [x * x for x in range(10)]
    assert len(eager) == 10  # 10 ints allocated

    # Generator: one element at a time
    lazy = (x * x for x in range(1_000_000))
    first = next(lazy)
    assert first == 0
    # Only one int in memory at a time, not 1M

    # ── Context managers for deterministic cleanup ──────────────────
    class TempBuffer:
        def __init__(self, size):
            self.data = bytearray(size)

        def __enter__(self):
            return self

        def __exit__(self, *args):
            self.data = bytearray()  # release memory immediately
            return False

    with TempBuffer(1024) as buf:
        assert len(buf.data) == 1024
    assert len(buf.data) == 0  # cleaned up

    # ── String interning ────────────────────────────────────────────
    # Python automatically interns some strings (identifier-like literals).
    # Comparing two "hello" literals would not show it: equal literals in one
    # function are one constant object, interned or not. Build one at runtime:
    a = "hello"
    b = "".join(["hel", "lo"])
    assert a == b and a is not b  # equal value, separate object
    assert sys.intern(b) is a     # interning maps it to the canonical copy

    # Dynamic strings may not be interned
    a = "hello" + " " + "world"
    b = "hello world"
    # a is b may or may not be True — don't rely on it
    assert a == b  # always use == for string comparison

    # ── sys.getsizeof: measure object memory ────────────────────────
    assert sys.getsizeof([]) < sys.getsizeof([1, 2, 3, 4, 5])
    assert sys.getsizeof("") < sys.getsizeof("hello world")

    print("All memory management examples passed.")


if __name__ == "__main__":
    main()
