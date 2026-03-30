# Vidya — Design Patterns in Python
#
# Python patterns: builder via keyword args and dataclasses, strategy
# via first-class functions, observer via callbacks, context managers
# for RAII, and duck typing for dependency injection.

from dataclasses import dataclass, field
from contextlib import contextmanager
from typing import Protocol, Callable


def main():
    test_builder_pattern()
    test_strategy_pattern()
    test_observer_pattern()
    test_state_machine()
    test_context_manager_raii()
    test_dependency_injection()
    test_factory_pattern()

    print("All design patterns examples passed.")


# ── Builder pattern ────────────────────────────────────────────────────
# In Python, keyword arguments and dataclasses often replace builders.
# Use a builder when validation or multi-step construction is needed.

@dataclass
class Server:
    host: str
    port: int
    max_connections: int = 100
    timeout_ms: int = 5000


class ServerBuilder:
    def __init__(self):
        self._host: str | None = None
        self._port: int | None = None
        self._max_connections = 100
        self._timeout_ms = 5000

    def host(self, h: str) -> "ServerBuilder":
        self._host = h
        return self

    def port(self, p: int) -> "ServerBuilder":
        self._port = p
        return self

    def max_connections(self, n: int) -> "ServerBuilder":
        self._max_connections = n
        return self

    def timeout_ms(self, ms: int) -> "ServerBuilder":
        self._timeout_ms = ms
        return self

    def build(self) -> Server:
        if self._host is None:
            raise ValueError("host is required")
        if self._port is None:
            raise ValueError("port is required")
        return Server(self._host, self._port, self._max_connections, self._timeout_ms)


def test_builder_pattern():
    server = ServerBuilder().host("localhost").port(8080).timeout_ms(3000).build()
    assert server.host == "localhost"
    assert server.port == 8080
    assert server.max_connections == 100
    assert server.timeout_ms == 3000

    try:
        ServerBuilder().host("localhost").build()
        assert False, "should fail without port"
    except ValueError:
        pass


# ── Strategy pattern ───────────────────────────────────────────────────
# First-class functions — no interface classes needed.

def apply_discount(price: float, strategy: Callable[[float], float]) -> float:
    return strategy(price)


def test_strategy_pattern():
    no_discount = lambda p: p
    ten_pct = lambda p: p * 0.9
    flat_five = lambda p: max(p - 5, 0)

    assert apply_discount(100, no_discount) == 100
    assert apply_discount(100, ten_pct) == 90
    assert apply_discount(100, flat_five) == 95
    assert apply_discount(3, flat_five) == 0


# ── Observer pattern ───────────────────────────────────────────────────

class EventEmitter:
    def __init__(self):
        self._listeners: list[Callable[[str], None]] = []

    def on(self, callback: Callable[[str], None]):
        self._listeners.append(callback)

    def emit(self, event: str):
        for listener in self._listeners:
            listener(event)


def test_observer_pattern():
    log: list[str] = []
    emitter = EventEmitter()
    emitter.on(lambda e: log.append(f"A:{e}"))
    emitter.on(lambda e: log.append(f"B:{e}"))

    emitter.emit("click")
    emitter.emit("hover")

    assert log == ["A:click", "B:click", "A:hover", "B:hover"]


# ── State machine as enum ─────────────────────────────────────────────

class DoorState:
    LOCKED = "locked"
    CLOSED = "closed"
    OPEN = "open"

    _transitions = {
        ("locked", "unlock"): "closed",
        ("closed", "open"):   "open",
        ("open", "close"):    "closed",
        ("closed", "lock"):   "locked",
    }

    def __init__(self, state: str = "locked"):
        self.state = state

    def transition(self, action: str) -> "DoorState":
        key = (self.state, action)
        if key not in self._transitions:
            raise ValueError(f"cannot {action} when {self.state}")
        return DoorState(self._transitions[key])


def test_state_machine():
    door = DoorState("locked")
    door = door.transition("unlock")
    assert door.state == "closed"
    door = door.transition("open")
    assert door.state == "open"
    door = door.transition("close")
    door = door.transition("lock")
    assert door.state == "locked"

    try:
        DoorState("locked").transition("open")
        assert False
    except ValueError:
        pass


# ── RAII via context managers ──────────────────────────────────────────

@contextmanager
def managed_resource(name: str, log: list[str]):
    log.append(f"acquire:{name}")
    try:
        yield name
    finally:
        log.append(f"release:{name}")


def test_context_manager_raii():
    log: list[str] = []
    with managed_resource("db", log) as r1:
        with managed_resource("file", log) as r2:
            assert r1 == "db"
            assert r2 == "file"
            assert len(log) == 2

    assert log == ["acquire:db", "acquire:file", "release:file", "release:db"]


# ── Dependency injection ──────────────────────────────────────────────

class Logger(Protocol):
    def log(self, msg: str) -> str: ...


class StdoutLogger:
    def log(self, msg: str) -> str:
        return f"[stdout] {msg}"


class TestLogger:
    def __init__(self):
        self.entries: list[str] = []

    def log(self, msg: str) -> str:
        entry = f"[test] {msg}"
        self.entries.append(entry)
        return entry


class Service:
    def __init__(self, logger: Logger):
        self.logger = logger

    def process(self, item: str) -> str:
        return self.logger.log(f"processing {item}")


def test_dependency_injection():
    svc = Service(StdoutLogger())
    assert svc.process("order") == "[stdout] processing order"

    test_log = TestLogger()
    svc = Service(test_log)
    svc.process("order-1")
    svc.process("order-2")
    assert len(test_log.entries) == 2
    assert test_log.entries[0] == "[test] processing order-1"


# ── Factory pattern ────────────────────────────────────────────────────

import math

def shape_factory(name: str, **kwargs) -> dict:
    factories = {
        "circle":    lambda: {"type": "circle", "area": math.pi * kwargs["radius"] ** 2},
        "rectangle": lambda: {"type": "rectangle", "area": kwargs["width"] * kwargs["height"]},
        "triangle":  lambda: {"type": "triangle", "area": 0.5 * kwargs["base"] * kwargs["height"]},
    }
    if name not in factories:
        raise ValueError(f"unknown shape: {name}")
    return factories[name]()


def test_factory_pattern():
    c = shape_factory("circle", radius=5)
    assert abs(c["area"] - 78.539) < 0.001

    r = shape_factory("rectangle", width=3, height=4)
    assert r["area"] == 12

    t = shape_factory("triangle", base=6, height=4)
    assert t["area"] == 12

    try:
        shape_factory("hexagon")
        assert False
    except ValueError:
        pass


if __name__ == "__main__":
    main()
