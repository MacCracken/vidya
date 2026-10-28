#!/usr/bin/env python3
# Vidya — Functional Patterns — Python port.
#
# Pure functions and memoization, compose and pipe, closures and partial
# application, what a closure captures, a persistent cons list that
# shares structure instead of copying, folds as its recursion scheme, and
# the stack depth a missing tail-call guarantee costs.
#
# Python closures capture VARIABLES, not values: a free variable is looked
# up when the closure is called (late binding), so a loop of lambdas
# traps the unwary and a default argument binds early. functools has
# cache, partial and reduce built in. Nothing is immutable by force.

import functools
import operator
import sys
from dataclasses import FrozenInstanceError, dataclass


# --- 1. Purity ---
# A pure function's result depends only on its arguments, and calling it
# changes nothing. Python has no way to check that: there is no const fn
# and nothing runs a function at compile time, so purity is a discipline.
def pure_add(a, b):
    return a + b


_counter = 0  # hidden state impure_next reads and bumps


def impure_next():
    global _counter
    _counter += 1
    return _counter


# counted_add is pure_add plus a call counter, so a check can see whether
# the underlying function ran (the counter is the test's probe; the value
# is still pure_add's).
_add_calls = 0


def counted_add(a, b):
    global _add_calls
    _add_calls += 1
    return pure_add(a, b)


# Memoization: cache results by argument. Sound only for a pure function,
# since a cached result must be what a fresh call would return. The key is
# BOTH arguments; a key of `a` alone would hand (2, 4) the result cached
# for (2, 3). functools.cache does the same, keyed on every argument.
def memoize2(f):
    table = {}

    def memo(a, b):
        key = (a, b)
        if key not in table:
            table[key] = f(a, b)
        return table[key]

    return memo


# --- 2. Higher-order functions and composition ---
# compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
# pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
def add_three(x):
    return x + 3


def times_two(x):
    return x * 2


def compose(f, g):
    return lambda x: f(g(x))


def pipe(f, g):
    return lambda x: g(f(x))


# --- 3. Closures and partial application ---
# make_adder(n) returns a function that remembers n in a closure cell.
def make_adder(n):
    return lambda x: x + n


# A closure can READ an enclosing variable freely, but assigning to it
# would make it a new local; `nonlocal` rebinds the enclosing one. Each
# make_counter() call makes a new n, so two counters never share a count.
def make_counter():
    n = 0

    def next_count():
        nonlocal n
        n += 1
        return n

    return next_count


# Partial application is functools.partial: partial(add3, 1, 2) is a
# one-argument callable that supplies 1 and 2 first.
def add3(a, b, c):
    return a + b + c


# --- 4. The capture gotcha: see test_capture ---
# A lambda stores where to find i, not i's value, and looks it up when
# called. Every lambda built by one comprehension shares that one i, and
# by the time any is called the loop has left it at its last value.


# --- 5. Persistent (immutable) list with structural sharing ---
# A cons cell holds a head and a tail; None is the empty list. cons never
# copies its tail, so prepending is O(1) and the old list is still whole
# and unchanged. frozen=True makes `node.head = 99` raise, but it is a
# guard in __setattr__, not a property of memory: object.__setattr__
# gets straight past it (the gotcha in test_persistent_list).
@dataclass(frozen=True, slots=True)
class Cons:
    head: int
    tail: Cons | None


NIL = None
_cons_allocs = 0  # nodes allocated, so checks can count copying


def cons(h, t):
    global _cons_allocs
    _cons_allocs += 1
    return Cons(h, t)


def head(xs):
    return xs.head


def tail(xs):
    return xs.tail


def list_of(*values):
    xs = NIL
    for v in reversed(values):
        xs = cons(v, xs)
    return xs


def nth(xs, i):
    for _ in range(i):
        xs = xs.tail
    return xs.head


# Structural equality: same values in the same order (not the same
# nodes). The dataclass's own == would do this too, recursively, which
# is O(n) stack; this loop is not.
def list_eq(a, b):
    while a is not NIL and b is not NIL:
        if a.head != b.head:
            return False
        a, b = a.tail, b.tail
    return a is NIL and b is NIL


# Functional update: a new list with element i replaced. It copies the i
# cells in front of i plus the replaced cell (i + 1 allocations) and
# shares everything after it. The original list is not touched.
def update_at(xs, i, v):
    if xs is NIL:
        return NIL
    if i == 0:
        return cons(v, xs.tail)
    return cons(xs.head, update_at(xs.tail, i - 1, v))


# --- 6. Fold as the recursion scheme ---
# foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
# foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
# functools.reduce is foldl over any iterable.
def foldr(f, z, xs):
    if xs is NIL:
        return z
    return f(xs.head, foldr(f, z, xs.tail))


def foldl(f, z, xs):
    acc = z
    while xs is not NIL:
        acc = f(acc, xs.head)
        xs = xs.tail
    return acc


def list_length(xs):
    return foldl(lambda acc, _x: acc + 1, 0, xs)


def list_sum(xs):
    return foldl(operator.add, 0, xs)


def list_reverse(xs):
    return foldl(lambda acc, x: cons(x, acc), NIL, xs)


def list_map(g, xs):
    return foldr(lambda x, acc: cons(g(x), acc), NIL, xs)


# --- 7. Tail recursion and stack depth ---
# Python does not eliminate tail calls, and says so: CPython keeps every
# frame for the traceback and caps the depth at sys.getrecursionlimit(),
# 1000 by default, so total(n) below raises RecursionError long before
# 100,000 (on 3.15.2, depth 998 works as a script's top-level call and
# 999 raises). Raising the limit only moves the cliff: since 3.11 a
# Python-to-Python call uses no C stack, so after
# sys.setrecursionlimit(10**7) total(3_000_000) finished here, every
# level a frame in heap memory. CPython 3.14's "tail-calling
# interpreter" is about how the C interpreter dispatches bytecodes;
# Python calls still use a frame each. The accumulator loop needs no
# frames. Python ints do not overflow, so 5000050000 needs no 64-bit care.
def sum_to_loop(n):
    acc = 0
    for i in range(1, n + 1):
        acc += i
    return acc


def total(n):
    return 0 if n == 0 else n + total(n - 1)  # n + ... runs after the call


# === Tests ===

def test_purity():
    global _counter
    r1 = pure_add(2, 3)
    r2 = pure_add(2, 3)
    assert r1 == r2, "pure_add: same arguments, same result"
    assert r1 == 5, "pure_add(2, 3) = 5"

    _counter = 0
    n1 = impure_next()
    n2 = impure_next()
    assert n1 != n2, "impure_next: same call, different results (1, then 2)"
    assert _counter == 2, "impure_next left a trace: hidden state bumped twice"


def test_memoize():
    global _add_calls
    _add_calls = 0
    madd = memoize2(counted_add)
    m1 = madd(2, 3)
    m2 = madd(2, 3)
    assert m1 == 5, "memo: first call computes 2 + 3 = 5"
    assert m2 == 5, "memo: second call returns the cached 5"
    assert _add_calls == 1, "memo: second call is a cache hit (1 call, not 2)"
    assert madd(2, 4) == 6, "memo: (2, 4) is a miss, the key is both arguments"
    assert _add_calls == 2, "memo: the miss ran the underlying function once more"

    # The built-in: functools.cache keys on every argument too.
    cached = functools.cache(counted_add)
    cached(2, 3)
    cached(2, 3)
    cached(2, 4)
    info = cached.cache_info()
    assert (info.hits, info.misses) == (1, 2), "functools.cache: 1 hit, 2 misses"


def test_composition():
    c = compose(add_three, times_two)
    p = pipe(add_three, times_two)
    assert c(1) == 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5"
    assert p(1) == 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8"
    assert c(1) != p(1), "order matters: compose != pipe at x = 1"

    # The laws, over a range of x: compose applies g first, and pipe is
    # compose with its arguments swapped.
    cgf = compose(times_two, add_three)
    xs = range(-2, 3)
    assert all(c(x) == add_three(times_two(x)) for x in xs), \
        "compose(f, g)(x) == f(g(x)) for x in -2..2"
    assert all(p(x) == cgf(x) for x in xs), \
        "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2"


def test_closures():
    add5 = make_adder(5)
    add10 = make_adder(10)
    assert add5(1) == 6, "make_adder(5)(1) = 6"
    assert add10(1) == 11, "make_adder(10)(1) = 11: each adder keeps its own n"

    c1 = make_counter()
    c2 = make_counter()
    c1()
    c1()
    assert c1() == 3, "counter 1 counted 1, 2, 3"
    assert c2() == 1, "counter 2 starts at 1: its state is its own"
    assert c1() == 4, "counter 1 carries on at 4, untouched by counter 2"

    add_1_2 = functools.partial(add3, 1, 2)
    assert add_1_2(3) == 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6"


def test_capture():
    # Late binding: all three lambdas share the comprehension's one i,
    # which the range loop left at 2.
    late = [lambda: i for i in range(3)]
    assert [f() for f in late] == [2, 2, 2], "late binding: every lambda sees the last i"

    # The fix: a default argument is evaluated when the lambda is built.
    bound = [lambda i=i: i for i in range(3)]
    assert [f() for f in bound] == [0, 1, 2], "default argument binds each i early"

    # A C-style loop leaves its variable one PAST the end, so here the
    # result is JavaScript's `var` answer, [3, 3, 3], not [2, 2, 2].
    refs = []
    j = 0
    while j < 3:
        refs.append(lambda: j)
        j += 1
    assert [r() for r in refs] == [3, 3, 3], "while loop: every lambda sees j's final 3"

    # After the fact: a later assignment IS seen, unless bound early.
    base = 1
    g = lambda: base
    g_early = lambda base=base: base
    base = 99
    assert g() == 99, "late binding: g sees the later base = 99"
    assert g_early() == 1, "bound early: g_early kept the 1 it was built with"


def test_persistent_list():
    xs = list_of(1, 2, 3)
    ys = cons(0, xs)
    assert tail(ys) is xs, "cons shares: tail(ys) IS xs, the same node"
    assert list_eq(ys, list_of(0, 1, 2, 3)), "ys reads [0, 1, 2, 3]"
    assert list_eq(xs, list_of(1, 2, 3)), "xs still reads [1, 2, 3] after the cons"

    before = _cons_allocs
    zs = update_at(xs, 1, 20)
    assert _cons_allocs - before == 2, "update at index 1 allocates i + 1 = 2 nodes, not 3"
    assert list_eq(zs, list_of(1, 20, 3)), "zs reads [1, 20, 3]"
    assert tail(tail(zs)) is tail(tail(xs)), "the suffix after the updated cell is shared"
    assert tail(zs) is not tail(xs), "the updated cell is new, not xs's"
    assert list_eq(xs, list_of(1, 2, 3)), "xs still reads [1, 2, 3] after the update"

    # The gotcha: write through a node two versions share and both change.
    # frozen=True refuses the plain write; object.__setattr__ does not.
    vs = list_of(1, 2, 3)
    ws = update_at(vs, 0, 7)  # ws = [7, 2, 3], shares vs's [2, 3]
    try:
        tail(vs).head = 99
        refused = False
    except FrozenInstanceError:
        refused = True
    assert refused, "frozen dataclass refuses node.head = 99"
    object.__setattr__(tail(vs), "head", 99)  # in-place write to the shared cell
    assert nth(ws, 1) == 99, "a write through a shared node changes the other version too"


def test_folds():
    xs = list_of(1, 2, 3)
    assert list_length(xs) == 3, "length via foldl = 3"
    assert list_length(NIL) == 0, "length of the empty list = 0"
    assert list_sum(xs) == 6, "sum via foldl = 1 + 2 + 3 = 6"
    assert list_eq(list_reverse(xs), list_of(3, 2, 1)), "reverse via foldl = [3, 2, 1]"
    assert list_eq(list_map(lambda x: x * 10, xs), list_of(10, 20, 30)), \
        "map via foldr keeps order: [10, 20, 30]"
    assert list_eq(xs, list_of(1, 2, 3)), "the folds left xs as [1, 2, 3]"

    # Subtraction is not associative, so the fold's direction shows.
    assert foldl(operator.sub, 0, xs) == -6, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6"
    assert foldr(operator.sub, 0, xs) == 2, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2"
    assert functools.reduce(operator.sub, [1, 2, 3], 0) == foldl(operator.sub, 0, xs), \
        "functools.reduce is foldl"


def test_tail_calls():
    assert sum_to_loop(100_000) == 5_000_050_000, "accumulator loop: sum 1..100000 = 5000050000"
    assert total(500) == 125_250, "naive recursion is fine well under the limit"
    assert sys.getrecursionlimit() == 1000, "CPython's default recursion limit is 1000"
    try:
        total(100_000)
        raised = False
    except RecursionError:
        raised = True
    assert raised, "naive recursion 100,000 deep raises RecursionError"


if __name__ == "__main__":
    test_purity()
    test_memoize()
    test_composition()
    test_closures()
    test_capture()
    test_persistent_list()
    test_folds()
    test_tail_calls()
    print("All functional pattern examples passed.")
    raise SystemExit(0)
