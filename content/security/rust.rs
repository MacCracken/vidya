// Vidya — Security Practices in Rust
//
// Rust's ownership model prevents many memory-safety bugs at compile
// time, but security requires more: input validation, constant-time
// comparison, secret zeroing, and injection prevention. Rust's type
// system helps encode security invariants as types.

use std::path::{Path, PathBuf};

fn main() {
    test_input_validation();
    test_allowlist_regex();
    test_constant_time_comparison();
    test_secret_zeroing();
    test_path_traversal_prevention();
    test_parameterized_query_pattern();
    test_integer_overflow_checks();
    test_type_driven_validation();

    println!("All security examples passed.");
}

// ── Input validation at the boundary ──────────────────────────────────
fn validate_username(input: &str) -> Result<&str, &'static str> {
    if input.is_empty() {
        return Err("username cannot be empty");
    }
    if input.len() > 32 {
        return Err("username too long");
    }
    // Allowlist: only alphanumeric and underscores
    if !input.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return Err("username contains invalid characters");
    }
    Ok(input)
}

fn test_input_validation() {
    assert!(validate_username("alice_42").is_ok());
    assert!(validate_username("").is_err());
    assert!(validate_username("a".repeat(33).as_str()).is_err());
    assert!(validate_username("alice; DROP TABLE").is_err());
    assert!(validate_username("../etc/passwd").is_err());
    assert!(validate_username("<script>").is_err());
}

// ── Allowlist via regex pattern ───────────────────────────────────────
fn matches_allowlist(input: &str, pattern: &str) -> bool {
    // Simple anchored pattern matcher for [a-zA-Z0-9_]{1,32}
    // In production, use the `regex` crate with anchored patterns
    if pattern == "^[a-zA-Z0-9_]{1,32}$" {
        !input.is_empty()
            && input.len() <= 32
            && input.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    } else {
        false
    }
}

fn test_allowlist_regex() {
    let pat = "^[a-zA-Z0-9_]{1,32}$";
    assert!(matches_allowlist("valid_name", pat));
    assert!(!matches_allowlist("", pat));
    assert!(!matches_allowlist("has spaces", pat));
    assert!(!matches_allowlist("<script>alert(1)</script>", pat));
}

// ── Constant-time comparison ──────────────────────────────────────────
/// Compare two byte slices in constant time to prevent timing attacks.
/// Always examines every byte regardless of where they differ.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    // XOR each byte pair and accumulate — never short-circuit
    let diff = a.iter().zip(b.iter()).fold(0u8, |acc, (x, y)| acc | (x ^ y));
    diff == 0
}

fn test_constant_time_comparison() {
    let secret = b"super_secret_token_2024";
    let correct = b"super_secret_token_2024";
    let wrong = b"super_secret_token_2025";
    let partial = b"super_secret";

    assert!(constant_time_eq(secret, correct));
    assert!(!constant_time_eq(secret, wrong));
    assert!(!constant_time_eq(secret, partial)); // different length
    assert!(constant_time_eq(b"", b""));         // empty is equal
}

// ── Secret zeroing ────────────────────────────────────────────────────
/// Zero sensitive data from memory. Uses volatile write to prevent
/// the compiler from optimizing away the zeroing.
fn secure_zero(buf: &mut [u8]) {
    for byte in buf.iter_mut() {
        // SAFETY: volatile prevents the compiler from eliding this write
        unsafe {
            std::ptr::write_volatile(byte as *mut u8, 0);
        }
    }
    // Compiler fence ensures zeroing completes before any reuse
    std::sync::atomic::fence(std::sync::atomic::Ordering::SeqCst);
}

fn test_secret_zeroing() {
    let mut secret = *b"hunter2_password";
    assert_eq!(&secret, b"hunter2_password");

    secure_zero(&mut secret);
    assert_eq!(&secret, &[0u8; 16]);
}

// ── Path traversal prevention ─────────────────────────────────────────
fn safe_resolve(base: &Path, user_input: &str) -> Result<PathBuf, &'static str> {
    // Reject obvious traversal attempts before canonicalization
    if user_input.contains("..") {
        return Err("path traversal detected");
    }

    let candidate = base.join(user_input);
    // In a real system, canonicalize both paths and verify the prefix:
    //   let resolved = candidate.canonicalize()?;
    //   let base_resolved = base.canonicalize()?;
    //   if !resolved.starts_with(&base_resolved) { return Err(...) }
    //
    // Here we check the joined path doesn't escape via components
    for component in candidate.components() {
        if matches!(component, std::path::Component::ParentDir) {
            return Err("path traversal detected");
        }
    }
    Ok(candidate)
}

fn test_path_traversal_prevention() {
    let base = Path::new("/srv/uploads");

    assert!(safe_resolve(base, "photo.jpg").is_ok());
    assert!(safe_resolve(base, "subdir/file.txt").is_ok());
    assert!(safe_resolve(base, "../../etc/passwd").is_err());
    assert!(safe_resolve(base, "../secret").is_err());
    assert!(safe_resolve(base, "normal/../../escape").is_err());
}

// ── Parameterized query pattern ───────────────────────────────────────
// Demonstrates the pattern, not a real database. The key principle:
// separate code (query structure) from data (parameters).

struct Query {
    template: String,
    params: Vec<String>,
}

impl Query {
    fn new(template: &str) -> Self {
        Self {
            template: template.to_string(),
            params: Vec::new(),
        }
    }

    fn bind(mut self, value: &str) -> Self {
        self.params.push(value.to_string());
        self
    }

    /// Returns (template, params) — the DB engine handles substitution safely
    fn build(self) -> (String, Vec<String>) {
        (self.template, self.params)
    }
}

fn test_parameterized_query_pattern() {
    // BAD: string interpolation (shown for contrast — don't do this)
    let user_input = "'; DROP TABLE users; --";
    let bad_query = format!("SELECT * FROM users WHERE name = '{user_input}'");
    assert!(bad_query.contains("DROP TABLE")); // injection present!

    // GOOD: parameterized query — user input never becomes SQL
    let (template, params) = Query::new("SELECT * FROM users WHERE name = ?")
        .bind(user_input)
        .build();
    assert_eq!(template, "SELECT * FROM users WHERE name = ?");
    assert_eq!(params[0], "'; DROP TABLE users; --"); // treated as data, not code
    assert!(!template.contains("DROP TABLE"));
}

// ── Integer overflow checks ───────────────────────────────────────────
fn safe_add(a: u32, b: u32) -> Option<u32> {
    a.checked_add(b) // Returns None on overflow instead of wrapping
}

fn safe_mul(a: u32, b: u32) -> Option<u32> {
    a.checked_mul(b)
}

fn test_integer_overflow_checks() {
    assert_eq!(safe_add(100, 200), Some(300));
    assert_eq!(safe_add(u32::MAX, 1), None); // would overflow

    assert_eq!(safe_mul(1000, 1000), Some(1_000_000));
    assert_eq!(safe_mul(u32::MAX, 2), None); // would overflow

    // Buffer size calculation: width * height * 4 bytes per pixel
    let width: u32 = 65536;
    let height: u32 = 65536;
    let overflow_check = width
        .checked_mul(height)
        .and_then(|pixels| pixels.checked_mul(4));
    assert!(overflow_check.is_none()); // 16GB — would overflow u32
}

// ── Type-driven security: validated newtypes ──────────────────────────
#[derive(Debug)]
struct Email(String);

impl Email {
    fn parse(input: &str) -> Result<Self, &'static str> {
        // Minimal validation — real email validation is more complex
        let trimmed = input.trim();
        if trimmed.len() > 254 {
            return Err("email too long");
        }
        let at_pos = trimmed.find('@').ok_or("missing @")?;
        if at_pos == 0 {
            return Err("empty local part");
        }
        let domain = &trimmed[at_pos + 1..];
        if domain.is_empty() || !domain.contains('.') {
            return Err("invalid domain");
        }
        Ok(Email(trimmed.to_string()))
    }

    fn as_str(&self) -> &str {
        &self.0
    }
}

fn test_type_driven_validation() {
    assert!(Email::parse("user@example.com").is_ok());
    assert!(Email::parse("user@example.com").unwrap().as_str() == "user@example.com");
    assert!(Email::parse("not-an-email").is_err());
    assert!(Email::parse("@no-local.com").is_err());
    assert!(Email::parse("user@").is_err());
    assert!(Email::parse("user@nodot").is_err());
    assert!(Email::parse("").is_err());
}
