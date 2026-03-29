//! Example validation — compile/run verification.
//!
//! Validates that code examples actually work by invoking the appropriate
//! compiler or interpreter. Used in CI to ensure every example in the
//! content directory is correct.

use crate::language::Language;
use serde::{Deserialize, Serialize};

/// Result of validating a single example.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    /// Concept ID.
    pub concept_id: String,
    /// Language of the example.
    pub language: Language,
    /// Whether validation passed.
    pub passed: bool,
    /// Error message if validation failed.
    pub error: Option<String>,
    /// Duration of validation in milliseconds.
    pub duration_ms: u64,
}

/// Validation command for a language.
///
/// Returns the shell command template to compile/run a source file.
/// `{file}` is replaced with the actual file path.
#[must_use]
pub fn validation_command(lang: Language) -> Option<&'static str> {
    match lang {
        Language::Rust => Some("rustc --edition 2024 {file} -o /tmp/vidya_test && /tmp/vidya_test"),
        Language::Python => Some("python3 -c \"exec(open('{file}').read())\""),
        Language::C => {
            Some("gcc -std=c11 -Wall -Werror {file} -o /tmp/vidya_test && /tmp/vidya_test")
        }
        Language::Go => Some("go run {file}"),
        Language::TypeScript => Some("bun run {file}"),
        Language::Shell => Some("bash -n {file}"),
        Language::Zig => Some("zig build-exe {file} -o /tmp/vidya_test && /tmp/vidya_test"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validation_commands_exist() {
        for lang in Language::all() {
            assert!(
                validation_command(*lang).is_some(),
                "missing validation command for {lang}"
            );
        }
    }

    #[test]
    fn validation_result_serde() {
        let result = ValidationResult {
            concept_id: "strings".into(),
            language: Language::Rust,
            passed: true,
            error: None,
            duration_ms: 42,
        };
        let json = serde_json::to_string(&result).unwrap();
        let decoded: ValidationResult = serde_json::from_str(&json).unwrap();
        assert_eq!(decoded.concept_id, "strings");
        assert!(decoded.passed);
    }

    #[test]
    fn validation_result_failure() {
        let result = ValidationResult {
            concept_id: "concurrency".into(),
            language: Language::C,
            passed: false,
            error: Some("segfault".into()),
            duration_ms: 100,
        };
        assert!(!result.passed);
        assert_eq!(result.error.as_deref(), Some("segfault"));
    }
}
