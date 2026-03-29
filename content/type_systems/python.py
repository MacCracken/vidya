# Vidya — Type Systems in Python
#
# Python is dynamically typed — types are checked at runtime, not compile
# time. Type hints (PEP 484+) add optional static analysis without
# changing runtime behavior. Protocols and ABCs provide structural and
# nominal typing. Duck typing remains the Pythonic default.

from typing import Protocol, TypeVar, Generic
from abc import ABC, abstractmethod

def main():
    # ── Duck typing: "if it quacks like a duck..." ──────────────────
    class Duck:
        def quack(self):
            return "quack"

    class Person:
        def quack(self):
            return "I'm quacking"

    def make_it_quack(thing):
        return thing.quack()  # works on anything with .quack()

    assert make_it_quack(Duck()) == "quack"
    assert make_it_quack(Person()) == "I'm quacking"

    # ── Type hints: documentation + static analysis ─────────────────
    def greet(name: str, times: int = 1) -> str:
        return (f"hello, {name}! " * times).strip()

    assert greet("world") == "hello, world!"
    assert greet("world", 2) == "hello, world! hello, world!"
    # Type hints don't enforce at runtime — this still works:
    # greet(42)  # mypy would catch this, Python wouldn't

    # ── Union types and Optional ────────────────────────────────────
    def find_user(user_id: int) -> str | None:  # Python 3.10+ union syntax
        users = {1: "alice", 2: "bob"}
        return users.get(user_id)

    assert find_user(1) == "alice"
    assert find_user(999) is None

    # ── Protocols: structural typing (PEP 544) ──────────────────────
    class Renderable(Protocol):
        def render(self) -> str: ...

    class Button:
        def render(self) -> str:
            return "<button>Click</button>"

    class TextBox:
        def render(self) -> str:
            return "<input type='text'/>"

    def render_all(widgets: list[Renderable]) -> list[str]:
        return [w.render() for w in widgets]

    results = render_all([Button(), TextBox()])
    assert len(results) == 2
    assert "<button>" in results[0]

    # ── Abstract Base Classes: nominal typing ───────────────────────
    class Shape(ABC):
        @abstractmethod
        def area(self) -> float:
            pass

        def describe(self) -> str:
            return f"Shape with area {self.area():.2f}"

    class Circle(Shape):
        def __init__(self, radius: float):
            self.radius = radius

        def area(self) -> float:
            import math
            return math.pi * self.radius ** 2

    class Rectangle(Shape):
        def __init__(self, width: float, height: float):
            self.width = width
            self.height = height

        def area(self) -> float:
            return self.width * self.height

    # Can't instantiate Shape directly:
    try:
        Shape()
        assert False, "should have raised"
    except TypeError:
        pass  # expected — Shape is abstract

    c = Circle(1.0)
    import math
    assert abs(c.area() - math.pi) < 1e-10
    assert "3.14" in c.describe()

    # ── Generics with TypeVar ───────────────────────────────────────
    T = TypeVar("T")

    def first(items: list[T]) -> T | None:
        return items[0] if items else None

    assert first([1, 2, 3]) == 1
    assert first(["a", "b"]) == "a"
    assert first([]) is None

    # ── Generic classes ─────────────────────────────────────────────
    class Stack(Generic[T]):
        def __init__(self):
            self._items: list[T] = []

        def push(self, item: T) -> None:
            self._items.append(item)

        def pop(self) -> T:
            return self._items.pop()

        def peek(self) -> T | None:
            return self._items[-1] if self._items else None

        def __len__(self) -> int:
            return len(self._items)

    stack: Stack[int] = Stack()
    stack.push(1)
    stack.push(2)
    assert stack.peek() == 2
    assert stack.pop() == 2
    assert len(stack) == 1

    # ── NewType: lightweight type distinction ───────────────────────
    from typing import NewType

    UserId = NewType("UserId", int)
    OrderId = NewType("OrderId", int)

    def get_user(uid: UserId) -> str:
        return f"user-{uid}"

    uid = UserId(42)
    # oid = OrderId(42)
    # get_user(oid)  # mypy error! OrderId is not UserId
    assert get_user(uid) == "user-42"

    # ── dataclasses: typed records ──────────────────────────────────
    from dataclasses import dataclass

    @dataclass
    class Point:
        x: float
        y: float

        def distance(self) -> float:
            return (self.x ** 2 + self.y ** 2) ** 0.5

    p = Point(3.0, 4.0)
    assert p.distance() == 5.0
    assert p == Point(3.0, 4.0)  # structural equality by default

    # Frozen dataclass — immutable
    @dataclass(frozen=True)
    class Color:
        r: int
        g: int
        b: int

    red = Color(255, 0, 0)
    try:
        red.r = 128  # type: ignore
        assert False, "should have raised"
    except AttributeError:
        pass  # expected — frozen is immutable

    # ── isinstance and type checking at runtime ─────────────────────
    assert isinstance(42, int)
    assert isinstance("hello", str)
    assert isinstance(Circle(1.0), Shape)  # ABC check
    assert not isinstance(42, str)

    # issubclass for class relationships
    assert issubclass(Circle, Shape)
    assert issubclass(bool, int)  # bool is a subclass of int!

    print("All type system examples passed.")


if __name__ == "__main__":
    main()
