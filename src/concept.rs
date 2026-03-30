//! Core types for programming concepts.
//!
//! A [`Concept`] represents a programming topic (e.g. "Strings", "Concurrency")
//! with best practices, gotchas, performance notes, and implementations
//! across multiple languages.

use crate::language::Language;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A programming topic category.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[non_exhaustive]
pub enum Topic {
    /// Data types and structures (strings, arrays, maps, etc.)
    DataTypes,
    /// Concurrency and parallelism (threads, async, channels, etc.)
    Concurrency,
    /// Error handling patterns (exceptions, Result types, etc.)
    ErrorHandling,
    /// Memory management (ownership, GC, allocation, etc.)
    MemoryManagement,
    /// I/O operations (files, network, streams, etc.)
    InputOutput,
    /// Testing patterns and strategies
    Testing,
    /// Algorithms and algorithmic thinking
    Algorithms,
    /// Design patterns and architecture
    Patterns,
    /// Type systems and generics
    TypeSystems,
    /// Performance optimization
    Performance,
    /// Security practices
    Security,
    /// Kernel and systems programming (interrupts, page tables, bootloaders, MMIO, ABIs)
    KernelTopics,
    /// Quantum computing algorithms and concepts (Grover's, Shor's, VQE, noise models)
    QuantumComputing,
}

impl std::fmt::Display for Topic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DataTypes => f.write_str("Data Types"),
            Self::Concurrency => f.write_str("Concurrency"),
            Self::ErrorHandling => f.write_str("Error Handling"),
            Self::MemoryManagement => f.write_str("Memory Management"),
            Self::InputOutput => f.write_str("I/O"),
            Self::Testing => f.write_str("Testing"),
            Self::Algorithms => f.write_str("Algorithms"),
            Self::Patterns => f.write_str("Design Patterns"),
            Self::TypeSystems => f.write_str("Type Systems"),
            Self::Performance => f.write_str("Performance"),
            Self::Security => f.write_str("Security"),
            Self::KernelTopics => f.write_str("Kernel Topics"),
            Self::QuantumComputing => f.write_str("Quantum Computing"),
        }
    }
}

/// A programming concept with multi-language implementations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Concept {
    /// Unique identifier (lowercase, underscore-separated, e.g. "string_interpolation").
    pub id: String,
    /// Human-readable title (e.g. "String Interpolation").
    pub title: String,
    /// Topic category.
    pub topic: Topic,
    /// One-paragraph description of the concept.
    pub description: String,
    /// Best practices — the "do this" advice.
    pub best_practices: Vec<BestPractice>,
    /// Gotchas — common mistakes, surprising behavior, footguns.
    pub gotchas: Vec<Gotcha>,
    /// Performance notes — optimization insights, benchmark findings.
    pub performance_notes: Vec<PerformanceNote>,
    /// Tags for search (e.g. ["utf-8", "unicode", "formatting"]).
    pub tags: Vec<String>,
    /// Implementations keyed by language.
    pub examples: HashMap<Language, Example>,
}

impl Concept {
    /// Get the implementation for a specific language.
    #[must_use]
    pub fn example(&self, lang: Language) -> Option<&Example> {
        self.examples.get(&lang)
    }

    /// List all languages that have implementations for this concept.
    #[must_use]
    pub fn available_languages(&self) -> Vec<Language> {
        let mut langs: Vec<Language> = self.examples.keys().copied().collect();
        langs.sort_by_key(|l| l.display_name());
        langs
    }

    /// Check if a tag matches (case-insensitive).
    #[must_use]
    pub fn has_tag(&self, tag: &str) -> bool {
        let lower = tag.to_lowercase();
        self.tags.iter().any(|t| t.to_lowercase() == lower)
    }
}

/// A best practice for a concept — the "do this" advice.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BestPractice {
    /// Short title (e.g. "Use &str for function parameters").
    pub title: String,
    /// Explanation of why this is the right approach.
    pub explanation: String,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A gotcha — common mistake, surprising behavior, or footgun.
///
/// These are the things developers get wrong. Documenting them explicitly
/// prevents AI models from learning the wrong pattern.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Gotcha {
    /// Short title (e.g. "String indexing panics on multi-byte characters").
    pub title: String,
    /// What goes wrong and why.
    pub explanation: String,
    /// The wrong way (what people do).
    pub bad_example: Option<String>,
    /// The right way (what they should do).
    pub good_example: Option<String>,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A performance note — optimization insight or benchmark finding.
///
/// These capture real-world performance discoveries: when a different
/// approach is measurably faster, what the tradeoffs are, and evidence
/// (benchmark numbers or complexity analysis).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceNote {
    /// Short title (e.g. "Pre-allocate with `with_capacity` for known sizes").
    pub title: String,
    /// What the improvement is and when it applies.
    pub explanation: String,
    /// Benchmark numbers or complexity comparison (optional).
    pub evidence: Option<String>,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A code example implementing a concept in a specific language.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Example {
    /// The programming language.
    pub language: Language,
    /// The source code.
    pub code: String,
    /// Inline explanation/comments about the approach.
    pub explanation: String,
    /// File path relative to content directory (e.g. "strings/rust.rs").
    pub source_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_concept() -> Concept {
        let mut examples = HashMap::new();
        examples.insert(
            Language::Rust,
            Example {
                language: Language::Rust,
                code: "let s = format!(\"hello {}\", name);".into(),
                explanation: "Rust uses the format! macro for string interpolation.".into(),
                source_path: Some("strings/rust.rs".into()),
            },
        );
        examples.insert(
            Language::Python,
            Example {
                language: Language::Python,
                code: "s = f\"hello {name}\"".into(),
                explanation: "Python uses f-strings for interpolation.".into(),
                source_path: Some("strings/python.py".into()),
            },
        );

        Concept {
            id: "string_interpolation".into(),
            title: "String Interpolation".into(),
            topic: Topic::DataTypes,
            description: "Embedding expressions inside string literals.".into(),
            best_practices: vec![BestPractice {
                title: "Prefer interpolation over concatenation".into(),
                explanation: "More readable and often more efficient.".into(),
                language: None,
            }],
            gotchas: vec![Gotcha {
                title: "Rust format! allocates a new String".into(),
                explanation: "Use write! to avoid allocation when writing to a buffer.".into(),
                bad_example: Some("let s = format!(\"x={}\", x);".into()),
                good_example: Some("write!(buf, \"x={}\", x)?;".into()),
                language: Some(Language::Rust),
            }],
            performance_notes: vec![PerformanceNote {
                title: "write! over format! on hot paths".into(),
                explanation: "format! allocates; write! appends to existing buffer.".into(),
                evidence: Some("~40% fewer allocations in benchmarks".into()),
                language: Some(Language::Rust),
            }],
            tags: vec![
                "strings".into(),
                "formatting".into(),
                "interpolation".into(),
            ],
            examples,
        }
    }

    #[test]
    fn concept_example_lookup() {
        let c = sample_concept();
        assert!(c.example(Language::Rust).is_some());
        assert!(c.example(Language::Python).is_some());
        assert!(c.example(Language::C).is_none());
    }

    #[test]
    fn concept_available_languages() {
        let c = sample_concept();
        let langs = c.available_languages();
        assert_eq!(langs.len(), 2);
    }

    #[test]
    fn concept_has_tag() {
        let c = sample_concept();
        assert!(c.has_tag("strings"));
        assert!(c.has_tag("STRINGS"));
        assert!(!c.has_tag("concurrency"));
    }

    #[test]
    fn concept_serde_roundtrip() {
        let c = sample_concept();
        let json = serde_json::to_string(&c).unwrap();
        let decoded: Concept = serde_json::from_str(&json).unwrap();
        assert_eq!(c.id, decoded.id);
        assert_eq!(c.examples.len(), decoded.examples.len());
    }

    #[test]
    fn topic_display() {
        assert_eq!(Topic::DataTypes.to_string(), "Data Types");
        assert_eq!(Topic::ErrorHandling.to_string(), "Error Handling");
    }

    #[test]
    fn gotcha_fields() {
        let g = &sample_concept().gotchas[0];
        assert!(g.bad_example.is_some());
        assert!(g.good_example.is_some());
        assert_eq!(g.language, Some(Language::Rust));
    }

    #[test]
    fn performance_note_fields() {
        let p = &sample_concept().performance_notes[0];
        assert!(p.evidence.is_some());
        assert_eq!(p.language, Some(Language::Rust));
    }

    #[test]
    fn best_practice_universal() {
        let bp = &sample_concept().best_practices[0];
        assert!(bp.language.is_none()); // applies to all languages
    }
}
