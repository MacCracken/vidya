// Vidya — Error Handling in Rust
//
// Rust uses Result<T, E> for recoverable errors and panic! for bugs.
// The ? operator propagates errors ergonomically. Custom error types
// give callers the ability to match on specific failure modes.

use std::fmt;
use std::fs;
use std::io;
use std::num::ParseIntError;

// ── Custom error type ──────────────────────────────────────────────
// Define a domain-specific error enum per module/crate.

#[derive(Debug)]
enum ConfigError {
    Io(io::Error),
    Parse(ParseIntError),
    Missing(String),
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => write!(f, "I/O error: {e}"),
            Self::Parse(e) => write!(f, "parse error: {e}"),
            Self::Missing(key) => write!(f, "missing key: {key}"),
        }
    }
}

// From impls enable the ? operator to convert automatically
impl From<io::Error> for ConfigError {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<ParseIntError> for ConfigError {
    fn from(e: ParseIntError) -> Self {
        Self::Parse(e)
    }
}

// ── The ? operator ─────────────────────────────────────────────────
// Propagates errors up the call stack with automatic From conversion.

fn read_port(config_text: &str) -> Result<u16, ConfigError> {
    for line in config_text.lines() {
        if let Some(value) = line.strip_prefix("port=") {
            return Ok(value.trim().parse()?); // ParseIntError → ConfigError via From
        }
    }
    Err(ConfigError::Missing("port".into()))
}

// ── Result combinators ─────────────────────────────────────────────
// map, and_then, unwrap_or, unwrap_or_else — transform without unwrapping

fn parse_or_default(s: &str) -> u16 {
    s.parse::<u16>().unwrap_or(8080)
}

fn parse_with_context(s: &str) -> Result<u16, String> {
    s.parse::<u16>()
        .map_err(|e| format!("invalid port '{s}': {e}"))
}

// ── Option for absence (not errors) ────────────────────────────────
// Option<T> represents "might not exist" — different from "something went wrong"

fn find_key<'a>(config: &'a str, key: &str) -> Option<&'a str> {
    config
        .lines()
        .find(|line| line.starts_with(key))
        .and_then(|line| line.split('=').nth(1))
        .map(|v| v.trim())
}

// ── Panic for bugs, not errors ─────────────────────────────────────
// panic! is for invariant violations — things that should never happen.

fn divide(a: f64, b: f64) -> f64 {
    assert!(b != 0.0, "division by zero is a bug, not an error");
    a / b
}

fn main() {
    // Custom error type with ?
    let config = "host=localhost\nport=3000\n";
    let port = read_port(config).expect("test config should parse");
    assert_eq!(port, 3000);

    // Missing key error
    let bad_config = "host=localhost\n";
    let err = read_port(bad_config).unwrap_err();
    assert!(matches!(err, ConfigError::Missing(_)));

    // Parse error propagation
    let corrupt_config = "port=abc\n";
    let err = read_port(corrupt_config).unwrap_err();
    assert!(matches!(err, ConfigError::Parse(_)));

    // Result combinators
    assert_eq!(parse_or_default("9090"), 9090);
    assert_eq!(parse_or_default("bad"), 8080);
    assert!(parse_with_context("bad").is_err());

    // Option for absence
    assert_eq!(find_key(config, "host"), Some("localhost"));
    assert_eq!(find_key(config, "missing"), None);

    // Panic for invariant violations
    assert_eq!(divide(10.0, 2.0), 5.0);

    println!("All error handling examples passed.");
}
