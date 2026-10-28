# Vidya — Pattern Matching in Python
#
# Python 3.10+ introduced structural pattern matching with match/case.
# It destructures sequences, mappings, and objects — similar to Rust's
# match but with Python's dynamic typing. For older Python, if/elif
# chains and dictionary dispatch are the alternatives.

def main():
    # ── Basic match/case (Python 3.10+) ─────────────────────────────
    def classify_status(code):
        match code:
            case 200:
                return "ok"
            case 301 | 302:
                return "redirect"
            case 404:
                return "not found"
            case 500:
                return "server error"
            case _:
                return "unknown"

    assert classify_status(200) == "ok"
    assert classify_status(301) == "redirect"
    assert classify_status(302) == "redirect"
    assert classify_status(404) == "not found"
    assert classify_status(999) == "unknown"

    # ── Destructuring sequences ─────────────────────────────────────
    def describe_point(point):
        match point:
            case (0, 0):
                return "origin"
            case (x, 0):
                return f"on x-axis at {x}"
            case (0, y):
                return f"on y-axis at {y}"
            case (x, y):
                return f"({x}, {y})"

    assert describe_point((0, 0)) == "origin"
    assert describe_point((3, 0)) == "on x-axis at 3"
    assert describe_point((0, 5)) == "on y-axis at 5"
    assert describe_point((3, 4)) == "(3, 4)"

    # ── Matching with guards ────────────────────────────────────────
    def classify_number(n):
        match n:
            case x if x < 0:
                return "negative"
            case 0:
                return "zero"
            case x if x <= 10:
                return "small"
            case _:
                return "large"

    assert classify_number(-5) == "negative"
    assert classify_number(0) == "zero"
    assert classify_number(7) == "small"
    assert classify_number(100) == "large"

    # ── Matching mappings (dicts) ───────────────────────────────────
    def process_event(event):
        match event:
            case {"type": "click", "x": x, "y": y}:
                return f"click at ({x}, {y})"
            case {"type": "keypress", "key": key}:
                return f"pressed {key}"
            case {"type": t}:
                return f"unknown event: {t}"

    assert process_event({"type": "click", "x": 10, "y": 20}) == "click at (10, 20)"
    assert process_event({"type": "keypress", "key": "Enter"}) == "pressed Enter"
    assert process_event({"type": "scroll"}) == "unknown event: scroll"

    # ── Matching class instances ─────────────────────────────────────
    class Circle:
        def __init__(self, radius):
            self.radius = radius

    class Rectangle:
        def __init__(self, width, height):
            self.width = width
            self.height = height

    # __match_args__ enables positional matching
    Circle.__match_args__ = ("radius",)
    Rectangle.__match_args__ = ("width", "height")

    def area(shape):
        import math
        match shape:
            case Circle(r):
                return math.pi * r * r
            case Rectangle(w, h):
                return w * h
            case _:
                raise ValueError(f"unknown shape: {shape}")

    import math
    assert abs(area(Circle(1.0)) - math.pi) < 1e-10
    assert area(Rectangle(3.0, 4.0)) == 12.0

    # ── Star patterns: capture rest ─────────────────────────────────
    def head_tail(items):
        match items:
            case []:
                return "empty"
            case [only]:
                return f"single: {only}"
            case [first, *rest]:
                return f"head={first}, tail_len={len(rest)}"

    assert head_tail([]) == "empty"
    assert head_tail([1]) == "single: 1"
    assert head_tail([1, 2, 3, 4]) == "head=1, tail_len=3"

    # ── Nested patterns ─────────────────────────────────────────────
    def process_response(resp):
        match resp:
            case {"status": 200, "data": {"items": [first, *_]}}:
                return f"first item: {first}"
            case {"status": 200, "data": {"items": []}}:
                return "no items"
            case {"status": code}:
                return f"error: {code}"

    assert process_response({"status": 200, "data": {"items": [1, 2, 3]}}) == "first item: 1"
    assert process_response({"status": 200, "data": {"items": []}}) == "no items"
    assert process_response({"status": 404}) == "error: 404"

    # ── Pre-3.10 alternatives ───────────────────────────────────────
    # Dictionary dispatch (works in any Python version)
    dispatch = {
        "add": lambda a, b: a + b,
        "sub": lambda a, b: a - b,
        "mul": lambda a, b: a * b,
    }

    op = "add"
    result = dispatch.get(op, lambda a, b: None)(3, 4)
    assert result == 7

    # Tuple unpacking (always available)
    point = (3, 4)
    x, y = point
    assert x == 3 and y == 4

    # Multiple assignment with *
    first, *middle, last = [1, 2, 3, 4, 5]
    assert first == 1
    assert middle == [2, 3, 4]
    assert last == 5

    print("All pattern matching examples passed.")


if __name__ == "__main__":
    main()
