# Vidya — Testing in Python
#
# Python's unittest module is built-in; pytest is the community standard.
# This file demonstrates testing patterns using only the standard library
# (unittest and assert). Tests should be clear, focused, and independent.

import unittest

# ── Code under test ─────────────────────────────────────────────────

def parse_kv(line):
    """Parse a 'key=value' line into a (key, value) tuple."""
    if "=" not in line:
        raise ValueError(f"no '=' found in: {line}")
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if not key:
        raise ValueError("empty key")
    return (key, value)


def clamp(value, min_val, max_val):
    """Clamp a value to [min_val, max_val]."""
    if min_val > max_val:
        raise ValueError(f"min ({min_val}) must be <= max ({max_val})")
    return max(min_val, min(max_val, value))


class Counter:
    """A simple counter with a maximum value."""
    def __init__(self, max_val):
        self._count = 0
        self._max = max_val

    def increment(self):
        if self._count < self._max:
            self._count += 1
            return True
        return False

    @property
    def value(self):
        return self._count


# ── Unit tests ──────────────────────────────────────────────────────

class TestParseKV(unittest.TestCase):
    """Tests for parse_kv function."""

    def test_valid_input(self):
        assert parse_kv("host=localhost") == ("host", "localhost")

    def test_trims_whitespace(self):
        assert parse_kv("  port = 3000  ") == ("port", "3000")

    def test_empty_value_is_ok(self):
        assert parse_kv("key=") == ("key", "")

    def test_no_equals_raises(self):
        with self.assertRaises(ValueError) as ctx:
            parse_kv("no_equals_sign")
        assert "no '='" in str(ctx.exception)

    def test_empty_key_raises(self):
        with self.assertRaises(ValueError) as ctx:
            parse_kv("=value")
        assert "empty key" in str(ctx.exception)


class TestClamp(unittest.TestCase):
    """Tests for clamp function."""

    def test_in_range(self):
        assert clamp(5, 0, 10) == 5

    def test_below_min(self):
        assert clamp(-1, 0, 10) == 0

    def test_above_max(self):
        assert clamp(100, 0, 10) == 10

    def test_at_boundaries(self):
        assert clamp(0, 0, 10) == 0
        assert clamp(10, 0, 10) == 10

    def test_min_equals_max(self):
        assert clamp(5, 5, 5) == 5

    def test_invalid_range_raises(self):
        with self.assertRaises(ValueError):
            clamp(5, 10, 0)

    # Parameterized-style testing
    def test_boundary_cases(self):
        cases = [
            (0, 0, 10, 0),
            (10, 0, 10, 10),
            (5, 0, 10, 5),
            (-1, 0, 10, 0),
            (11, 0, 10, 10),
        ]
        for value, lo, hi, expected in cases:
            with self.subTest(value=value, lo=lo, hi=hi):
                assert clamp(value, lo, hi) == expected


class TestCounter(unittest.TestCase):
    """Tests for Counter class."""

    def test_initial_value(self):
        c = Counter(5)
        assert c.value == 0

    def test_increments(self):
        c = Counter(3)
        assert c.increment() is True
        assert c.value == 1

    def test_stops_at_max(self):
        c = Counter(2)
        c.increment()
        c.increment()
        assert c.increment() is False
        assert c.value == 2

    def test_zero_max(self):
        c = Counter(0)
        assert c.increment() is False
        assert c.value == 0


# ── Test helpers and fixtures ───────────────────────────────────────

class TestWithSetup(unittest.TestCase):
    """Demonstrates setUp/tearDown pattern."""

    def setUp(self):
        """Runs before each test method."""
        self.counter = Counter(10)
        for _ in range(5):
            self.counter.increment()

    def test_value_after_setup(self):
        assert self.counter.value == 5

    def test_can_still_increment(self):
        assert self.counter.increment() is True
        assert self.counter.value == 6


# ── Run examples and tests ──────────────────────────────────────────

def main():
    # Verify examples work
    assert parse_kv("host=localhost") == ("host", "localhost")
    assert clamp(5, 0, 10) == 5

    c = Counter(3)
    assert c.increment() is True
    assert c.increment() is True
    assert c.increment() is True
    assert c.increment() is False
    assert c.value == 3

    # Run the test suite programmatically
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    suite.addTests(loader.loadTestsFromTestCase(TestParseKV))
    suite.addTests(loader.loadTestsFromTestCase(TestClamp))
    suite.addTests(loader.loadTestsFromTestCase(TestCounter))
    suite.addTests(loader.loadTestsFromTestCase(TestWithSetup))

    runner = unittest.TextTestRunner(verbosity=0)
    result = runner.run(suite)
    assert result.wasSuccessful(), f"Tests failed: {result.failures + result.errors}"

    print("All testing examples passed.")


if __name__ == "__main__":
    main()
