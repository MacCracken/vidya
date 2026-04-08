# Vidya — Ownership and Borrowing Concepts in Python
#
# Python has no ownership system — it uses reference counting + cycle
# collection. This file shows what ownership WOULD prevent:
#   1. Dangling references — weakref detects objects collected by GC
#   2. Aliasing mutations — mutable shared state leads to surprises
#   3. Use-after-delete — del removes a name, but other refs keep the object alive
#   4. Resource leaks — without RAII, you need context managers
#
# Every bug demonstrated here is prevented at compile time in Rust.

import weakref
import gc
import sys


def main():
    # ── Reference counting: Python's primary memory strategy ───────
    # Every object has a reference count. When it drops to zero, the
    # object is immediately deallocated. sys.getrefcount() shows it
    # (adds 1 for the function argument itself).

    a = [1, 2, 3]
    base = sys.getrefcount(a)  # typically 2: 'a' + getrefcount arg
    b = a                       # alias — refcount increases
    assert sys.getrefcount(a) == base + 1
    del b                       # refcount decreases
    assert sys.getrefcount(a) == base

    # ── Aliasing: the problem ownership prevents ───────────────────
    # Two names pointing to the same mutable list. Mutation through
    # one alias is visible through the other. In Rust, you can't have
    # &mut and & to the same data simultaneously.

    original = [1, 2, 3]
    alias = original          # both point to the SAME list
    alias.append(4)           # mutate through alias
    assert original == [1, 2, 3, 4]  # original is changed!
    # Rust would reject this: can't have two mutable references.

    # Safe pattern: explicit copy
    original2 = [1, 2, 3]
    independent = original2.copy()  # like Rust's .clone()
    independent.append(4)
    assert original2 == [1, 2, 3]   # original unchanged
    assert independent == [1, 2, 3, 4]

    # ── Dangling references via weakref ────────────────────────────
    # weakref doesn't prevent collection — it lets you DETECT it.
    # This is the Python equivalent of a dangling pointer: the referent
    # is gone, but you still hold a reference.

    class Resource:
        def __init__(self, name):
            self.name = name

        def describe(self):
            return f"Resource({self.name})"

    obj = Resource("important")
    weak = weakref.ref(obj)

    # While the object lives, the weak reference works
    assert weak() is not None
    assert weak().describe() == "Resource(important)"

    # Delete the strong reference — object may be collected
    del obj
    gc.collect()

    # Now the weak reference returns None — the object is gone.
    # In C, this would be a dangling pointer. In Rust, the compiler
    # prevents this entirely. In Python, weakref makes it detectable.
    assert weak() is None

    # ── Weakref callbacks: notification on collection ──────────────
    collected = []

    def on_collect(ref):
        collected.append("collected")

    obj2 = Resource("tracked")
    weak2 = weakref.ref(obj2, on_collect)
    del obj2
    gc.collect()
    assert len(collected) == 1
    assert collected[0] == "collected"

    # ── Move semantics simulation ──────────────────────────────────
    # Python has no moves. But you can simulate the pattern:
    # after "moving" a value, set the source to None.

    class OwnedBuffer:
        """Simulates an owned resource that can be moved."""

        def __init__(self, data):
            self._data = data

        def take(self):
            """Move semantics: consume self, return data, invalidate."""
            if self._data is None:
                raise RuntimeError("use after move!")
            data = self._data
            self._data = None  # invalidate — simulates Rust's move
            return data

        def is_valid(self):
            return self._data is not None

    buf = OwnedBuffer([1, 2, 3])
    assert buf.is_valid()

    moved_data = buf.take()
    assert moved_data == [1, 2, 3]
    assert not buf.is_valid()

    # Second take raises — like Rust's compile error on use-after-move
    try:
        buf.take()
        assert False, "should have raised"
    except RuntimeError as e:
        assert "use after move" in str(e)

    # ── Borrowing simulation: read-only views ──────────────────────
    # memoryview provides a read-only view (shared borrow) without copy.
    # The underlying buffer must stay alive while the view exists.

    data = bytearray(b"hello world")
    view = memoryview(data)  # shared borrow — no copy

    assert bytes(view[0:5]) == b"hello"

    # Mutation through the original is visible through the view
    data[0:5] = b"HELLO"
    assert bytes(view[0:5]) == b"HELLO"

    view.release()  # explicit "end borrow"

    # ── Resource cleanup: RAII equivalent ──────────────────────────
    # Python has no destructors that run at scope exit (like Rust's Drop).
    # Context managers (__enter__/__exit__) are the closest equivalent.

    class Connection:
        def __init__(self, addr):
            self.addr = addr
            self.open = True
            self.queries = 0

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            self.open = False  # cleanup runs even on exception
            return False

        def query(self, sql):
            if not self.open:
                raise RuntimeError("connection closed")
            self.queries += 1
            return f"result-{self.queries}"

    # RAII pattern: resource lifetime tied to scope
    with Connection("localhost:5432") as conn:
        assert conn.open
        result = conn.query("SELECT 1")
        assert result == "result-1"

    # After the with block, cleanup has run
    assert not conn.open

    # Forgetting the context manager = resource leak
    leaked = Connection("localhost:5432")
    assert leaked.open  # no cleanup unless you call __exit__ manually
    leaked.open = False  # manual cleanup — error-prone

    # ── Cycle collection ───────────────────────────────────────────
    # Reference counting can't handle cycles. Python's GC detects them.
    # Rust's ownership prevents cycles entirely (or uses Rc<RefCell<T>>
    # with explicit weak references).

    class Node:
        def __init__(self, value):
            self.value = value
            self.next = None

    a_node = Node("a")
    b_node = Node("b")
    a_node.next = b_node
    b_node.next = a_node  # cycle! refcount never reaches zero

    weak_a = weakref.ref(a_node)
    weak_b = weakref.ref(b_node)

    del a_node
    del b_node
    gc.collect()  # cycle collector breaks the cycle

    assert weak_a() is None  # collected despite the cycle
    assert weak_b() is None

    # ── Iterator invalidation ──────────────────────────────────────
    # Rust prevents mutating a collection while iterating.
    # Python allows it, leading to subtle bugs.

    items = [1, 2, 3, 4, 5]
    # BAD: modifying while iterating skips elements
    result_bad = []
    for item in items[:]:  # use a copy to avoid the bug
        result_bad.append(item * 2)
    assert result_bad == [2, 4, 6, 8, 10]

    # Dict raises RuntimeError if modified during iteration (Python 3.x)
    d = {"a": 1, "b": 2}
    try:
        for key in d:
            if key == "a":
                d["c"] = 3  # modify during iteration
                break
    except RuntimeError:
        pass  # some Python implementations catch this

    print("All ownership and borrowing examples passed.")


if __name__ == "__main__":
    main()
