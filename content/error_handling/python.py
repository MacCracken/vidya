# Vidya — Error Handling in Python
#
# Python uses exceptions for error handling. try/except catches errors,
# raise throws them. Custom exception classes enable callers to handle
# specific failure modes. Context managers ensure cleanup.

def main():
    # ── Basic try/except ────────────────────────────────────────────
    try:
        result = int("not_a_number")
        assert False, "should have raised"
    except ValueError as e:
        assert "invalid literal" in str(e)

    # ── Catch specific exceptions, not broad ones ───────────────────
    # BAD: except Exception catches everything including bugs
    # GOOD: catch only what you expect
    def safe_divide(a, b):
        try:
            return a / b
        except ZeroDivisionError:
            return None

    assert safe_divide(10, 2) == 5.0
    assert safe_divide(10, 0) is None

    # ── Custom exception classes ────────────────────────────────────
    class ConfigError(Exception):
        """Base for configuration errors."""
        pass

    class MissingKeyError(ConfigError):
        def __init__(self, key):
            self.key = key
            super().__init__(f"missing key: {key}")

    class ParseError(ConfigError):
        def __init__(self, key, value, reason):
            self.key = key
            self.value = value
            super().__init__(f"cannot parse '{key}={value}': {reason}")

    def read_port(config_text):
        for line in config_text.strip().splitlines():
            if line.startswith("port="):
                value = line.split("=", 1)[1].strip()
                try:
                    port = int(value)
                except ValueError as e:
                    raise ParseError("port", value, str(e)) from e
                return port
        raise MissingKeyError("port")

    # Success case
    assert read_port("host=localhost\nport=3000\n") == 3000

    # Missing key
    try:
        read_port("host=localhost\n")
        assert False, "should have raised"
    except MissingKeyError as e:
        assert e.key == "port"

    # Parse error with chained cause
    try:
        read_port("port=abc\n")
        assert False, "should have raised"
    except ParseError as e:
        assert e.key == "port"
        assert e.__cause__ is not None  # chained from ValueError

    # ── else and finally ────────────────────────────────────────────
    cleanup_ran = False
    try:
        value = int("42")
    except ValueError:
        assert False, "should not reach"
    else:
        # runs only if no exception
        assert value == 42
    finally:
        # always runs — use for cleanup
        cleanup_ran = True

    assert cleanup_ran

    # ── Context managers for resource cleanup ───────────────────────
    class ManagedResource:
        def __init__(self):
            self.opened = True
            self.closed = False

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            self.closed = True
            return False  # don't suppress exceptions

    with ManagedResource() as r:
        assert r.opened
    assert r.closed  # cleanup happened automatically

    # ── Re-raising with context ─────────────────────────────────────
    def process_config(text):
        try:
            return read_port(text)
        except ConfigError as e:
            raise RuntimeError(f"failed to process config") from e

    try:
        process_config("port=bad\n")
    except RuntimeError as e:
        assert "failed to process config" in str(e)
        assert isinstance(e.__cause__, ParseError)

    # ── EAFP vs LBYL ───────────────────────────────────────────────
    # Python prefers "Easier to Ask Forgiveness than Permission"
    data = {"key": "value"}

    # LBYL (Look Before You Leap) — check first
    if "key" in data:
        _ = data["key"]

    # EAFP (Easier to Ask Forgiveness) — try and catch
    try:
        _ = data["key"]
    except KeyError:
        pass

    # Both work, but EAFP is more Pythonic and avoids race conditions

    # ── Using None vs exceptions for expected absence ───────────────
    def find_user(user_id):
        users = {1: "alice", 2: "bob"}
        return users.get(user_id)  # returns None if missing

    assert find_user(1) == "alice"
    assert find_user(999) is None  # absence, not error

    print("All error handling examples passed.")


if __name__ == "__main__":
    main()
