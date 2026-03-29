// Vidya — Strings in Rust
//
// Rust has two primary string types:
// - `String` — heap-allocated, owned, growable, UTF-8
// - `&str`   — borrowed slice into a String or static data, UTF-8
//
// This distinction (owned vs borrowed) is Rust's core string insight.
// Most functions should accept `&str` and return `String`.

fn main() {
    // ── Creation ───────────────────────────────────────────────────
    let owned = String::from("hello");
    let literal: &str = "world"; // &'static str
    let from_format = format!("{owned} {literal}");
    assert_eq!(from_format, "hello world");

    // ── Borrowing ──────────────────────────────────────────────────
    // Best practice: accept &str in function parameters
    fn greet(name: &str) -> String {
        format!("hello, {name}")
    }
    let result = greet(&owned); // String auto-derefs to &str
    assert_eq!(result, "hello, hello");

    // ── Pre-allocation ─────────────────────────────────────────────
    // When you know the approximate size, pre-allocate to avoid resizing
    let mut buf = String::with_capacity(64);
    for i in 0..10 {
        use std::fmt::Write;
        write!(buf, "{i} ").unwrap(); // write! avoids format! allocation
    }
    assert_eq!(buf.trim(), "0 1 2 3 4 5 6 7 8 9");

    // ── UTF-8 safety ───────────────────────────────────────────────
    let cafe = "café";
    assert_eq!(cafe.len(), 5); // 5 bytes (é is 2 bytes in UTF-8)
    assert_eq!(cafe.chars().count(), 4); // 4 characters

    // GOTCHA: you cannot index a String by byte position
    // let c = cafe[4]; // ← compile error!
    // Instead, iterate by character:
    let fourth = cafe.chars().nth(3);
    assert_eq!(fourth, Some('é'));

    // ── Slicing (byte boundaries only) ─────────────────────────────
    let hello = &cafe[0..3]; // "caf" — safe, all ASCII
    assert_eq!(hello, "caf");
    // let bad = &cafe[0..4]; // ← PANICS! byte 4 is middle of 'é'

    // ── Cow: borrow or own, decided at runtime ─────────────────────
    use std::borrow::Cow;

    fn maybe_uppercase(s: &str, shout: bool) -> Cow<'_, str> {
        if shout {
            Cow::Owned(s.to_uppercase()) // allocates only when needed
        } else {
            Cow::Borrowed(s) // zero-cost borrow
        }
    }
    let quiet = maybe_uppercase("hello", false);
    let loud = maybe_uppercase("hello", true);
    assert_eq!(&*quiet, "hello");
    assert_eq!(&*loud, "HELLO");

    // ── String comparison ──────────────────────────────────────────
    assert_eq!("hello", "hello"); // case-sensitive by default
    assert!("Hello".eq_ignore_ascii_case("hello")); // ASCII only
    // For full Unicode case-insensitive comparison, use the `unicase` crate

    // ── Common conversions ─────────────────────────────────────────
    let num: i32 = "42".parse().unwrap();
    let back = num.to_string();
    assert_eq!(back, "42");

    println!("All string examples passed.");
}
