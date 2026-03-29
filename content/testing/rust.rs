// Vidya — Testing in Rust
//
// Rust has first-class testing support: #[test] functions, assert macros,
// doc-tests, and integration tests in tests/. Tests compile as a separate
// binary and run in parallel by default.

// ── Code under test ────────────────────────────────────────────────

/// Parse a "key=value" line into a (key, value) pair.
fn parse_kv(line: &str) -> Result<(&str, &str), String> {
    let (key, value) = line
        .split_once('=')
        .ok_or_else(|| format!("no '=' found in: {line}"))?;

    let key = key.trim();
    let value = value.trim();

    if key.is_empty() {
        return Err("empty key".into());
    }

    Ok((key, value))
}

/// Clamp a value to a range.
fn clamp(value: i32, min: i32, max: i32) -> i32 {
    assert!(min <= max, "min ({min}) must be <= max ({max})");
    if value < min {
        min
    } else if value > max {
        max
    } else {
        value
    }
}

/// A simple accumulator to demonstrate stateful testing.
struct Counter {
    count: u64,
    max: u64,
}

impl Counter {
    fn new(max: u64) -> Self {
        Self { count: 0, max }
    }

    fn increment(&mut self) -> bool {
        if self.count < self.max {
            self.count += 1;
            true
        } else {
            false
        }
    }

    fn value(&self) -> u64 {
        self.count
    }
}

fn main() {
    // Run the same checks as the test suite to validate examples
    assert_eq!(parse_kv("host=localhost").unwrap(), ("host", "localhost"));
    assert_eq!(parse_kv("port = 3000").unwrap(), ("port", "3000"));
    assert!(parse_kv("no_equals").is_err());
    assert!(parse_kv("=no_key").is_err());

    assert_eq!(clamp(5, 0, 10), 5);
    assert_eq!(clamp(-1, 0, 10), 0);
    assert_eq!(clamp(100, 0, 10), 10);

    let mut c = Counter::new(3);
    assert!(c.increment());
    assert!(c.increment());
    assert!(c.increment());
    assert!(!c.increment()); // at max
    assert_eq!(c.value(), 3);

    println!("All testing examples passed.");
}

// ── Unit tests ─────────────────────────────────────────────────────
// #[cfg(test)] is only compiled during `cargo test`

#[cfg(test)]
mod tests {
    use super::*;

    // ── Basic assertions ───────────────────────────────────────────

    #[test]
    fn parse_kv_valid_input() {
        let (k, v) = parse_kv("host=localhost").unwrap();
        assert_eq!(k, "host");
        assert_eq!(v, "localhost");
    }

    #[test]
    fn parse_kv_trims_whitespace() {
        let (k, v) = parse_kv("  port = 3000  ").unwrap();
        assert_eq!(k, "port");
        assert_eq!(v, "3000");
    }

    #[test]
    fn parse_kv_empty_value_is_ok() {
        let (k, v) = parse_kv("key=").unwrap();
        assert_eq!(k, "key");
        assert_eq!(v, "");
    }

    // ── Error case tests ───────────────────────────────────────────

    #[test]
    fn parse_kv_no_equals() {
        let err = parse_kv("no_equals_sign").unwrap_err();
        assert!(err.contains("no '='"), "unexpected error: {err}");
    }

    #[test]
    fn parse_kv_empty_key() {
        let err = parse_kv("=value").unwrap_err();
        assert_eq!(err, "empty key");
    }

    // ── should_panic with expected message ─────────────────────────

    #[test]
    #[should_panic(expected = "min (10) must be <= max (5)")]
    fn clamp_panics_on_invalid_range() {
        clamp(7, 10, 5); // min > max is a bug
    }

    // ── Parameterized-style testing ────────────────────────────────

    #[test]
    fn clamp_boundary_values() {
        let cases = [
            // (value, min, max, expected)
            (0, 0, 10, 0),   // at min
            (10, 0, 10, 10), // at max
            (5, 0, 10, 5),   // in range
            (-1, 0, 10, 0),  // below min
            (11, 0, 10, 10), // above max
            (5, 5, 5, 5),    // min == max == value
        ];

        for (value, min, max, expected) in cases {
            assert_eq!(
                clamp(value, min, max),
                expected,
                "clamp({value}, {min}, {max}) should be {expected}"
            );
        }
    }

    // ── Stateful testing ───────────────────────────────────────────

    #[test]
    fn counter_increments_up_to_max() {
        let mut c = Counter::new(2);
        assert_eq!(c.value(), 0);
        assert!(c.increment());
        assert_eq!(c.value(), 1);
        assert!(c.increment());
        assert_eq!(c.value(), 2);
        assert!(!c.increment()); // returns false at max
        assert_eq!(c.value(), 2); // doesn't go past max
    }

    #[test]
    fn counter_zero_max() {
        let mut c = Counter::new(0);
        assert!(!c.increment()); // can't increment at all
        assert_eq!(c.value(), 0);
    }

    // ── Testing with helpers ───────────────────────────────────────

    /// Test helper: create a counter and increment it n times
    fn counter_after_n(max: u64, increments: u64) -> Counter {
        let mut c = Counter::new(max);
        for _ in 0..increments {
            c.increment();
        }
        c
    }

    #[test]
    fn counter_helper_usage() {
        let c = counter_after_n(10, 5);
        assert_eq!(c.value(), 5);
    }

    #[test]
    fn counter_helper_overcounted() {
        let c = counter_after_n(3, 100);
        assert_eq!(c.value(), 3); // capped at max
    }
}
