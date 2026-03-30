//! Example validation — compile/run verification.
//!
//! Validates that code examples actually work by invoking the appropriate
//! compiler or interpreter. Used in CI to ensure every example in the
//! content directory is correct.

use crate::language::Language;
use crate::registry::Registry;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::Instant;

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
/// `{out}` is replaced with a unique temporary output path.
#[must_use]
pub fn validation_command(lang: Language) -> Option<&'static str> {
    match lang {
        Language::Rust => Some("rustc --edition 2024 {file} -o {out} && {out}"),
        Language::Python => Some("python3 -c \"exec(open('{file}').read())\""),
        Language::C => Some("gcc -std=c11 -Wall -Werror {file} -o {out} && {out}"),
        Language::Go => Some("go run {file}"),
        Language::TypeScript => Some("npx tsx {file}"),
        Language::Shell => Some("bash -n {file}"),
        Language::Zig => Some("zig build-exe {file} -femit-bin={out} && {out}"),
        Language::AsmX86_64 => {
            Some("as --64 {file} -o {out}.o && ld {out}.o -o {out} && {out} ; rm -f {out}.o")
        }
        Language::AsmAarch64 => Some(
            "aarch64-linux-gnu-as {file} -o {out}.o && aarch64-linux-gnu-ld {out}.o -o {out} && qemu-aarch64 {out} ; rm -f {out}.o",
        ),
        Language::OpenQASM => Some(
            "QASM_PY=$(if [ -f .venv/bin/python3 ]; then echo .venv/bin/python3; else echo python3; fi) && $QASM_PY -c \"from qiskit import qasm2; import os; qc = qasm2.load('{file}', include_path=[os.path.dirname('{file}') + '/..']); print(f'valid: {{qc.num_qubits}}q depth={{qc.depth()}}')\"",
        ),
    }
}

/// Run validation for a single source file.
///
/// Executes the language-appropriate compile/run command and captures
/// the result. Returns a [`ValidationResult`] indicating pass/fail.
pub fn run_validation(concept_id: &str, language: Language, file_path: &Path) -> ValidationResult {
    let start = Instant::now();

    let Some(cmd_template) = validation_command(language) else {
        return ValidationResult {
            concept_id: concept_id.to_string(),
            language,
            passed: false,
            error: Some("no validation command for this language".into()),
            duration_ms: 0,
        };
    };

    let file_str = file_path.display().to_string();
    let out_path = format!("/tmp/vidya_test_{}_{}", concept_id, std::process::id());
    let cmd = cmd_template
        .replace("{file}", &file_str)
        .replace("{out}", &out_path);

    let result = std::process::Command::new("sh")
        .args(["-c", &cmd])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .output();

    // Clean up compiled binary
    let _ = std::fs::remove_file(&out_path);

    let duration_ms = start.elapsed().as_millis() as u64;

    match result {
        Ok(output) => {
            if output.status.success() {
                ValidationResult {
                    concept_id: concept_id.to_string(),
                    language,
                    passed: true,
                    error: None,
                    duration_ms,
                }
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let stdout = String::from_utf8_lossy(&output.stdout);
                let msg = if stderr.is_empty() {
                    stdout.into_owned()
                } else {
                    stderr.into_owned()
                };
                ValidationResult {
                    concept_id: concept_id.to_string(),
                    language,
                    passed: false,
                    error: Some(msg),
                    duration_ms,
                }
            }
        }
        Err(e) => ValidationResult {
            concept_id: concept_id.to_string(),
            language,
            passed: false,
            error: Some(format!("failed to execute command: {e}")),
            duration_ms,
        },
    }
}

/// Validate all examples in a registry against their source files.
///
/// `content_dir` is the root content directory (e.g. `content/`).
/// Each concept's examples are validated using their `source_path` field.
pub fn validate_all(registry: &Registry, content_dir: &Path) -> Vec<ValidationResult> {
    let mut results = Vec::new();

    for concept in registry.list() {
        for (lang, example) in &concept.examples {
            let Some(ref source_path) = example.source_path else {
                continue;
            };
            let file_path = content_dir.join(source_path);
            if !file_path.exists() {
                results.push(ValidationResult {
                    concept_id: concept.id.clone(),
                    language: *lang,
                    passed: false,
                    error: Some(format!("source file not found: {}", file_path.display())),
                    duration_ms: 0,
                });
                continue;
            }
            results.push(run_validation(&concept.id, *lang, &file_path));
        }
    }

    results
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
