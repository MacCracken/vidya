# Vidya — Macro Systems in Python
#
# Python has no macro system. Instead, it achieves compile-time (or
# import-time) code generation through:
#   1. Decorators — wrap or replace functions/classes at definition time
#   2. Metaclasses — intercept class creation, modify or generate methods
#   3. __init_subclass__ — hook into subclass creation (simpler than metaclasses)
#   4. Class decorators — modify classes after creation
#   5. exec/eval — runtime code generation (dangerous, rarely appropriate)
#
# Compared to Rust macros:
#   Decorator     ≈ attribute macro (#[derive], #[test])
#   Metaclass     ≈ procedural macro (full AST manipulation)
#   __init_subclass__ ≈ derive macro with trait bounds


def main():
    # ── Decorators: function transformation at definition time ─────
    # A decorator takes a function and returns a (possibly different)
    # function. It runs once, when the function is defined — not on
    # every call. This is like Rust's attribute macros.

    # Simple decorator: add logging
    def trace(func):
        call_log = []

        def wrapper(*args, **kwargs):
            call_log.append(func.__name__)
            return func(*args, **kwargs)

        wrapper.call_log = call_log
        wrapper.__name__ = func.__name__
        return wrapper

    @trace
    def add(a, b):
        return a + b

    assert add(2, 3) == 5
    assert add(10, 20) == 30
    assert add.call_log == ["add", "add"]

    # ── Decorator with arguments ───────────────────────────────────
    # A decorator factory: returns a decorator. The outer function
    # takes the decorator's arguments.

    def repeat(n):
        def decorator(func):
            def wrapper(*args, **kwargs):
                results = []
                for _ in range(n):
                    results.append(func(*args, **kwargs))
                return results
            wrapper.__name__ = func.__name__
            return wrapper
        return decorator

    @repeat(3)
    def greet(name):
        return f"hello, {name}"

    assert greet("world") == ["hello, world"] * 3

    # ── Stacking decorators ────────────────────────────────────────
    # Multiple decorators compose. Applied bottom-up (inner first).
    # Like stacking #[attr] macros in Rust.

    def uppercase_result(func):
        def wrapper(*args, **kwargs):
            result = func(*args, **kwargs)
            return result.upper() if isinstance(result, str) else result
        wrapper.__name__ = func.__name__
        return wrapper

    def add_exclaim(func):
        def wrapper(*args, **kwargs):
            result = func(*args, **kwargs)
            return result + "!" if isinstance(result, str) else result
        wrapper.__name__ = func.__name__
        return wrapper

    @add_exclaim       # applied second (outer)
    @uppercase_result  # applied first (inner)
    def say(msg):
        return msg

    # "hello" → uppercase → "HELLO" → add_exclaim → "HELLO!"
    assert say("hello") == "HELLO!"

    # ── Class decorators: modifying classes after creation ──────────
    # Like derive macros — add methods or behavior to a class.

    def auto_repr(cls):
        """Add a __repr__ based on __init__ parameters."""
        import inspect
        params = list(inspect.signature(cls.__init__).parameters.keys())
        params = [p for p in params if p != "self"]

        def __repr__(self):
            values = ", ".join(f"{p}={getattr(self, p)!r}" for p in params)
            return f"{cls.__name__}({values})"

        cls.__repr__ = __repr__
        return cls

    @auto_repr
    class Point:
        def __init__(self, x, y):
            self.x = x
            self.y = y

    p = Point(3, 4)
    assert repr(p) == "Point(x=3, y=4)"

    # ── Metaclasses: intercept class creation ──────────────────────
    # A metaclass controls HOW a class is created. It can:
    #   - Add/remove/modify methods
    #   - Validate the class definition
    #   - Register the class in a global registry
    #
    # This is the Python equivalent of procedural macros: full control
    # over the generated code (class body).

    class ValidatedMeta(type):
        """Metaclass that enforces all methods have docstrings."""
        def __new__(mcs, name, bases, namespace):
            # Skip validation for the base class itself
            if bases:
                for key, value in namespace.items():
                    if callable(value) and not key.startswith("_"):
                        if not getattr(value, "__doc__", None):
                            raise TypeError(
                                f"{name}.{key}() must have a docstring"
                            )
            return super().__new__(mcs, name, bases, namespace)

    class Service(metaclass=ValidatedMeta):
        pass

    class GoodService(Service):
        def process(self):
            """Process the request."""
            return "processed"

    assert GoodService().process() == "processed"

    # Missing docstring — caught at class definition time
    try:
        class BadService(Service):
            def handle(self):
                return "no docs"  # no docstring!
        assert False, "should have raised"
    except TypeError as e:
        assert "docstring" in str(e)

    # ── Registry metaclass: auto-registration ──────────────────────
    # Like a proc macro that registers implementations of a trait.

    class PluginMeta(type):
        registry = {}

        def __new__(mcs, name, bases, namespace):
            cls = super().__new__(mcs, name, bases, namespace)
            if bases:  # don't register the base class itself
                PluginMeta.registry[name] = cls
            return cls

    class Plugin(metaclass=PluginMeta):
        def execute(self):
            raise NotImplementedError

    class LogPlugin(Plugin):
        def execute(self):
            return "logging"

    class CachePlugin(Plugin):
        def execute(self):
            return "caching"

    assert "LogPlugin" in PluginMeta.registry
    assert "CachePlugin" in PluginMeta.registry
    assert PluginMeta.registry["LogPlugin"]().execute() == "logging"

    # ── __init_subclass__: simpler subclass hook ───────────────────
    # Added in Python 3.6 as a simpler alternative to metaclasses.
    # Runs when a subclass is created.

    class Configurable:
        _defaults = {}

        def __init_subclass__(cls, default=None, **kwargs):
            super().__init_subclass__(**kwargs)
            if default is not None:
                cls._defaults[cls.__name__] = default

    class DebugMode(Configurable, default=True):
        pass

    class ReleaseMode(Configurable, default=False):
        pass

    assert Configurable._defaults["DebugMode"] is True
    assert Configurable._defaults["ReleaseMode"] is False

    # ── Property decorator: computed attributes ────────────────────
    # @property is a built-in decorator that turns a method into a
    # computed attribute. Like a getter/setter in other languages.

    class Temperature:
        def __init__(self, celsius):
            self._celsius = celsius

        @property
        def celsius(self):
            return self._celsius

        @celsius.setter
        def celsius(self, value):
            if value < -273.15:
                raise ValueError("below absolute zero")
            self._celsius = value

        @property
        def fahrenheit(self):
            return self._celsius * 9 / 5 + 32

    t = Temperature(100)
    assert t.celsius == 100
    assert t.fahrenheit == 212.0
    t.celsius = 0
    assert t.fahrenheit == 32.0

    try:
        t.celsius = -300
        assert False, "should have raised"
    except ValueError:
        pass

    # ── functools.wraps: preserving function metadata ──────────────
    # Without @wraps, the decorated function loses its name and docs.
    # This is like Rust macro hygiene — the transformation should not
    # destroy the original identity.

    import functools

    def timed(func):
        @functools.wraps(func)  # preserves __name__, __doc__
        def wrapper(*args, **kwargs):
            return func(*args, **kwargs)
        return wrapper

    @timed
    def compute(x):
        """Compute something important."""
        return x * 2

    assert compute.__name__ == "compute"
    assert compute.__doc__ == "Compute something important."
    assert compute(21) == 42

    # ── Compile-time code generation comparison ────────────────────
    # Rust: macro_rules! generates code at compile time
    # Python: decorators/metaclasses run at import time (class definition)
    # Both happen before the first "real" function call.
    #
    # Key difference: Rust macros operate on token trees (syntax).
    # Python decorators operate on live objects (functions, classes).
    # Rust macros are hygienic. Python decorators are not — they can
    # freely access and modify the caller's namespace.

    print("All macro system examples passed.")


if __name__ == "__main__":
    main()
