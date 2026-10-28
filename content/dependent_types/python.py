#!/usr/bin/env python3
# Vidya — Dependent Types — Python port.
#
# A dependent type depends on a VALUE: Vec n a is a vector whose length n
# is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
# v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
# values computed at run time; none of vidya's 11 languages can.
#
# Python is runtime-checked refinement only. Classes are values, so a
# function can build a type from a number (Vec(3) below), but nothing is
# checked before the code runs: a wrong length is an exception, the
# interpreter ignores annotations, and typing.NewType is erased. Type
# checkers (mypy, pyright) are not part of this gate.

import functools
from dataclasses import FrozenInstanceError, dataclass
from typing import NewType


def check(cond, name):
    if not cond:
        raise SystemExit(f"FAIL: {name}")


def refused(make, *args):
    """True when the checked constructor refuses its arguments."""
    try:
        make(*args)
    except ValueError:
        return True
    return False


# --- 1. Length-indexed vector ---
# Vec(n) is the class of tuples of exactly n ints, built from the number n
# when the code runs (cached, so Vec(3) is Vec(3)). Its length is a class
# attribute, so it is read from the TYPE. The check is in __new__, at run
# time: a Vec2 of three items is an exception, not a compile error.
@functools.cache
def Vec(n):
    class _Vec(tuple):
        __slots__ = ()
        N = n

        def __new__(cls, items=()):
            items = tuple(items)
            if len(items) != n:
                raise ValueError(f"Vec{n} needs {n} items, got {len(items)}")
            return super().__new__(cls, items)

    _Vec.__name__ = _Vec.__qualname__ = f"Vec{n}"
    return _Vec


Vec0, Vec2, Vec3 = Vec(0), Vec(2), Vec(3)


# The length, read from the TYPE of the argument, for any vector type.
def vlen(v):
    return type(v).N


# head refuses the empty vector type when it is called; nothing refuses
# it sooner.
def head(v):
    if type(v).N == 0:
        raise TypeError("head of an empty vector")
    return v[0]


# append computes its result TYPE from its arguments' types: Vec(n + m).
def append(a, b):
    return Vec(type(a).N + type(b).N)(a + b)


# A length known only at run time: a list carries it as a value, so head
# checks it and returns (ok, value).
def vec_head(v):
    if len(v) == 0:
        return False, None
    return True, v[0]


# The static way to put a length in a type is an annotation. The
# interpreter ignores it: a type checker would refuse head3((1, 2)),
# Python runs it.
def head3(v: tuple[int, int, int]) -> int:
    return v[0]


# --- 2. Fin n: an index proven in range ---
# Fin(n) is the class of ints proven in 0..n-1. A Fin is an int, so it
# indexes a tuple directly; index3 adds no check of its own (the tuple
# still checks, as every Python index does). Refusing negatives matters
# here: a plain -1 does not fail in Python, it reads from the end.
# Fin3's bound is Vec3.N, the same number as Vec3's length.
@functools.cache
def Fin(n):
    class _Fin(int):
        __slots__ = ()
        N = n

        def __new__(cls, i):
            if not 0 <= i < n:
                raise ValueError(f"Fin{n} needs 0 <= i < {n}, got {i}")
            return super().__new__(cls, i)

    _Fin.__name__ = _Fin.__qualname__ = f"Fin{n}"
    return _Fin


Fin2, Fin3 = Fin(Vec2.N), Fin(Vec3.N)


def index2(v, k):
    return v[k]


def index3(v, k):
    return v[k]


# --- 3. Refinement at the boundary (parse, don't validate) ---
# Percent's __post_init__ is the one place the range is checked. Everything
# downstream takes a Percent and trusts it: discount never looks at the
# range. frozen=True makes plain assignment raise; percent_checks counts
# validations, so a check can see that.
percent_checks = 0


@dataclass(frozen=True, slots=True)
class Percent:
    v: int

    def __post_init__(self):
        global percent_checks
        percent_checks += 1
        if not 0 <= self.v <= 100:
            raise ValueError(f"percent out of range 0..100: {self.v}")


def discount(price, p: Percent):
    return price - price * p.v // 100


# --- 4. Σ type (dependent pair) ---
# Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
# the first. Python can state that only at run time, so Sized checks the
# dependency once, in __post_init__, and refuses a pair whose data does
# not really hold n elements. data is a tuple, so its length cannot change
# afterwards. sized_sum takes its loop bound from n alone.
@dataclass(frozen=True, slots=True)
class Sized:
    n: int
    data: tuple[int, ...]

    def __post_init__(self):
        if len(self.data) != self.n:
            raise ValueError(f"Sized needs {self.n} items, got {len(self.data)}")


def sized_sum(s: Sized):
    total = 0
    for i in range(s.n):
        total += s.data[i]
    return total


# --- 5. The escape hatch ---
# Python has no private fields and no constructor it cannot skip.
# object.__new__ makes an instance without running __post_init__, and
# object.__setattr__ writes past frozen=True. typing.NewType is weaker
# still: PercentN(150) is the int 150, validated by nothing. What keeps a
# refinement honest is convention and review (grep for object.__new__,
# object.__setattr__), plus a type checker for the annotations.
PercentN = NewType("PercentN", int)


# === Tests ===

def test_length_indexed():
    empty, a, b = Vec0(), Vec2((1, 2)), Vec3((3, 4, 5))
    check(vlen(empty) == 0, "Vec0's type says length 0")
    check(vlen(a) == 2, "Vec2's type says length 2")
    check(vlen(b) == 3, "Vec3's type says length 3")
    check(head(a) == 1, "head([1, 2]) = 1")
    check(head(b) == 3, "head([3, 4, 5]) = 3")
    try:
        head(empty)
        check(False, "head of an empty vector must be refused")
    except TypeError:
        pass
    check(refused(Vec2, (1, 2, 3)), "a Vec2 of three items is refused")

    c = append(a, b)
    check(type(c) is Vec(5), "append(Vec2, Vec3) has type Vec5")
    check(vlen(c) == vlen(a) + vlen(b), "append(Vec2, Vec3) has length 2 + 3 = 5")
    check(c == (1, 2, 3, 4, 5), "append(Vec2, Vec3) reads [1, 2, 3, 4, 5]")

    # The run-time-length list: the empty case is refused when it happens.
    check(vec_head([]) == (False, None), "run-time head of an empty list is refused")
    check(vec_head([7]) == (True, 7), "run-time head of [7] is allowed and = 7")
    check(head3((1, 2)) == 1, "the interpreter ignores tuple[int, int, int]: head3((1, 2)) runs")


def test_fin():
    a, b = Vec2((1, 2)), Vec3((3, 4, 5))
    check(refused(Fin3, -1), "fin3(-1) is refused")
    check(refused(Fin3, 3), "fin3(3) is refused: 3 is not < 3")
    check(b[-1] == 5, "a plain -1 is no error: it reads from the end")

    accepted = 0
    reads = True
    for i in range(-1, 4):
        try:
            k = Fin3(i)
        except ValueError:
            continue
        accepted += 1
        if index3(b, k) != 3 + i:
            reads = False
    check(accepted == 3, "fin3 accepts exactly 0, 1, 2 out of -1..3")
    check(reads, "index3 with each Fin3 reads [3, 4, 5] in order")

    check(refused(Fin2, 2), "fin2(2) is refused: 2 is not < 2")
    check(index2(a, Fin2(1)) == 2, "index2([1, 2], fin2(1)) = 2")
    # Nothing ties a Fin2 to a Vec2 when the code runs: to the tuple it is an int.
    check(index3(b, Fin2(1)) == 4, "index3 accepts a Fin2 at run time: reads 4")


def test_refinement():
    global percent_checks
    percent_checks = 0
    check(refused(Percent, -1), "percent(-1) is refused")
    check(refused(Percent, 101), "percent(101) is refused")
    p0, p100, p25 = Percent(0), Percent(100), Percent(25)
    check(percent_checks == 5, "5 constructions, 5 validations")

    check(discount(200, p25) == 150, "discount(200, 25%) = 150")
    check(discount(200, p0) == 200, "discount(200, 0%) = 200")
    check(discount(200, p100) == 0, "discount(200, 100%) = 0")
    check(percent_checks == 5, "discount never re-validated: still 5 checks after 3 calls")


def test_sigma():
    check(refused(Sized, 3, (1, 2)), "(3, [1, 2]) is refused: the length is 2")
    check(refused(Sized, 2, (1, 2, 3)), "(2, [1, 2, 3]) is refused: the length is 3")
    s = Sized(3, (1, 2, 3))
    check(s.n == 3, "(3, [1, 2, 3]) is built and its n is 3")
    check(sized_sum(s) == 6, "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6")


def test_escape_hatch():
    check(refused(Percent, 150), "the API refuses 150")
    before = percent_checks
    forged = object.__new__(Percent)          # skips __init__ and __post_init__
    object.__setattr__(forged, "v", 150)
    check(percent_checks == before, "object.__new__ ran no validation")
    check(forged.v == 150, "object.__new__ makes a Percent of 150 anyway")
    check(discount(200, forged) == -100, "and discount trusts it: 200 - 300 = -100")

    p = Percent(30)
    try:
        p.v = 250
        check(False, "frozen=True must refuse a plain assignment")
    except FrozenInstanceError:
        pass
    object.__setattr__(p, "v", 250)           # rewrites a validated Percent in place
    check(discount(100, p) == -150, "object.__setattr__ into a checked Percent breaks it too: -150")

    n = PercentN(150)
    check(type(n) is int and n == 150, "NewType is erased: PercentN(150) is the int 150")


if __name__ == "__main__":
    test_length_indexed()
    test_fin()
    test_refinement()
    test_sigma()
    test_escape_hatch()
    print("All dependent type examples passed.")
