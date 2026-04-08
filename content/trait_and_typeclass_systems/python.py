# Vidya — Trait and Typeclass Systems in Python
#
# Python has no traits or typeclasses. Instead it achieves polymorphism
# through three mechanisms:
#   1. Duck typing — if it has the method, call it (no declaration needed)
#   2. Abstract Base Classes (ABC) — nominal "trait" with enforcement
#   3. Protocols (PEP 544) — structural typing, like Rust traits
#   4. Dunder methods — implicit "trait impls" for operators/builtins
#
# This maps to Rust concepts:
#   ABC       ≈ trait with required methods (nominal, must inherit)
#   Protocol  ≈ trait bounds checked structurally (no inheritance needed)
#   __len__   ≈ impl Len for T
#   __iter__  ≈ impl Iterator for T
#   __add__   ≈ impl Add for T

from abc import ABC, abstractmethod
from typing import Protocol, runtime_checkable


def main():
    # ── Duck typing: implicit trait satisfaction ────────────────────
    # No interface declared. Any object with .speak() works.
    # This is like Rust without trait bounds — maximum flexibility,
    # zero compile-time checking.

    class Dog:
        def speak(self):
            return "woof"

    class Cat:
        def speak(self):
            return "meow"

    class Robot:
        def speak(self):
            return "beep"

    def make_speak(thing):
        return thing.speak()  # duck typing: no type annotation needed

    assert make_speak(Dog()) == "woof"
    assert make_speak(Cat()) == "meow"
    assert make_speak(Robot()) == "beep"

    # Failure is at RUNTIME, not compile time:
    try:
        make_speak(42)
        assert False, "should have raised"
    except AttributeError as e:
        assert "speak" in str(e)

    # ── ABC: nominal trait with enforcement ─────────────────────────
    # Abstract Base Class = Rust trait with required methods.
    # You MUST inherit and implement all abstract methods.
    # This is nominal typing: the class must declare the relationship.

    class Drawable(ABC):
        @abstractmethod
        def draw(self) -> str:
            """Render this object as a string."""
            pass

        @abstractmethod
        def bounding_box(self) -> tuple:
            """Return (x, y, width, height)."""
            pass

        # Concrete method — like a default method in a Rust trait
        def describe(self) -> str:
            x, y, w, h = self.bounding_box()
            return f"{self.draw()} at ({x},{y}) size {w}x{h}"

    class Circle(Drawable):
        def __init__(self, cx, cy, r):
            self.cx = cx
            self.cy = cy
            self.r = r

        def draw(self) -> str:
            return f"Circle(r={self.r})"

        def bounding_box(self) -> tuple:
            return (self.cx - self.r, self.cy - self.r,
                    self.r * 2, self.r * 2)

    class Rect(Drawable):
        def __init__(self, x, y, w, h):
            self.x = x
            self.y = y
            self.w = w
            self.h = h

        def draw(self) -> str:
            return f"Rect({self.w}x{self.h})"

        def bounding_box(self) -> tuple:
            return (self.x, self.y, self.w, self.h)

    # Can't instantiate abstract class — like Rust's "trait is not a type"
    try:
        Drawable()
        assert False, "should have raised"
    except TypeError:
        pass

    # Must implement ALL abstract methods
    class Incomplete(Drawable):
        def draw(self) -> str:
            return "half"
        # Missing bounding_box!

    try:
        Incomplete()
        assert False, "should have raised"
    except TypeError:
        pass

    # Polymorphic dispatch through ABC — like dyn Drawable in Rust
    shapes: list[Drawable] = [Circle(5, 5, 3), Rect(0, 0, 10, 20)]
    descriptions = [s.describe() for s in shapes]
    assert "Circle" in descriptions[0]
    assert "Rect" in descriptions[1]

    # isinstance works — nominal check
    assert isinstance(shapes[0], Drawable)
    assert isinstance(shapes[1], Drawable)

    # ── Protocol: structural trait (no inheritance) ─────────────────
    # Protocols are like Rust traits checked structurally: any type
    # with the right methods satisfies the protocol, without inheriting.

    @runtime_checkable
    class Serializable(Protocol):
        def serialize(self) -> str: ...

    class User:
        def __init__(self, name, age):
            self.name = name
            self.age = age

        def serialize(self) -> str:
            return f"{self.name}:{self.age}"

    class Config:
        def __init__(self, entries):
            self.entries = entries

        def serialize(self) -> str:
            return ";".join(f"{k}={v}" for k, v in self.entries.items())

    # Neither User nor Config inherits from Serializable.
    # They satisfy it structurally — just by having serialize().
    def save_all(items: list[Serializable]) -> list[str]:
        return [item.serialize() for item in items]

    results = save_all([
        User("alice", 30),
        Config({"debug": "true", "port": "8080"})
    ])
    assert results[0] == "alice:30"
    assert "debug=true" in results[1]

    # runtime_checkable allows isinstance checks
    assert isinstance(User("test", 1), Serializable)
    assert not isinstance(42, Serializable)

    # ── Dunder methods: implicit trait implementations ──────────────
    # Python's dunder methods are like Rust's standard traits:
    #   __len__     → len(x)     ≈ impl Len
    #   __iter__    → iter(x)    ≈ impl IntoIterator
    #   __add__     → x + y      ≈ impl Add
    #   __eq__      → x == y     ≈ impl PartialEq
    #   __str__     → str(x)     ≈ impl Display
    #   __repr__    → repr(x)    ≈ impl Debug
    #   __hash__    → hash(x)    ≈ impl Hash
    #   __enter__   → with x     ≈ (no direct Rust equivalent)

    class Vec2:
        def __init__(self, x, y):
            self.x = x
            self.y = y

        # impl Display
        def __str__(self):
            return f"({self.x}, {self.y})"

        # impl Debug
        def __repr__(self):
            return f"Vec2({self.x}, {self.y})"

        # impl PartialEq
        def __eq__(self, other):
            if not isinstance(other, Vec2):
                return NotImplemented
            return self.x == other.x and self.y == other.y

        # impl Hash (required if __eq__ is defined and you want dict keys)
        def __hash__(self):
            return hash((self.x, self.y))

        # impl Add
        def __add__(self, other):
            return Vec2(self.x + other.x, self.y + other.y)

        # impl Mul<scalar>
        def __mul__(self, scalar):
            return Vec2(self.x * scalar, self.y * scalar)

        # impl Len (for abs/magnitude as integer)
        def __abs__(self):
            return (self.x ** 2 + self.y ** 2) ** 0.5

    v1 = Vec2(1, 2)
    v2 = Vec2(3, 4)

    assert str(v1) == "(1, 2)"
    assert repr(v1) == "Vec2(1, 2)"
    assert v1 + v2 == Vec2(4, 6)
    assert v1 * 3 == Vec2(3, 6)
    assert v1 == Vec2(1, 2)
    assert v1 != v2
    assert abs(Vec2(3, 4)) == 5.0

    # Hashable — can be used as dict key
    d = {v1: "first", v2: "second"}
    assert d[Vec2(1, 2)] == "first"

    # ── Iterable protocol: __iter__ + __next__ ─────────────────────
    # Like implementing Iterator for a Rust type.

    class Countdown:
        def __init__(self, start):
            self.current = start

        def __iter__(self):
            return self

        def __next__(self):
            if self.current <= 0:
                raise StopIteration
            val = self.current
            self.current -= 1
            return val

    assert list(Countdown(5)) == [5, 4, 3, 2, 1]

    # Works with for loops, sum(), list comprehensions — all generic
    assert sum(Countdown(3)) == 6

    # ── Multiple dispatch: Python doesn't have it ──────────────────
    # Rust's trait system supports static dispatch (monomorphization)
    # and dynamic dispatch (dyn Trait). Python only has dynamic dispatch.
    # There's no monomorphization — method lookup happens at runtime.

    # functools.singledispatch provides limited dispatch on first arg type:
    from functools import singledispatch

    @singledispatch
    def process(data):
        return f"unknown: {data}"

    @process.register(int)
    def _(data):
        return f"int: {data * 2}"

    @process.register(str)
    def _(data):
        return f"str: {data.upper()}"

    assert process(5) == "int: 10"
    assert process("hello") == "str: HELLO"
    assert process(3.14) == "unknown: 3.14"

    # ── Mixin classes: trait composition ────────────────────────────
    # Python's multiple inheritance serves as trait composition.
    # Mixins add behavior without requiring a specific base class.

    class JsonMixin:
        def to_json(self) -> str:
            import json
            return json.dumps(self.__dict__)

    class LogMixin:
        def log_repr(self) -> str:
            return f"[LOG] {self.__class__.__name__}: {self.__dict__}"

    class Server(JsonMixin, LogMixin):
        def __init__(self, host, port):
            self.host = host
            self.port = port

    srv = Server("localhost", 8080)
    assert '"host": "localhost"' in srv.to_json()
    assert "[LOG] Server" in srv.log_repr()

    print("All trait and typeclass system examples passed.")


if __name__ == "__main__":
    main()
