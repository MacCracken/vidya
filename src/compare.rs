//! Side-by-side cross-language comparison.

use crate::error::Result;
use crate::language::Language;
use crate::registry::Registry;
use serde::{Deserialize, Serialize};

/// A side-by-side comparison of a concept across languages.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Comparison {
    /// The concept ID.
    pub concept_id: String,
    /// The concept title.
    pub concept_title: String,
    /// Implementations, one per requested language (in order).
    pub implementations: Vec<ComparedExample>,
}

/// One language's implementation in a comparison.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComparedExample {
    pub language: Language,
    pub code: String,
    pub explanation: String,
}

/// Compare a concept across multiple languages.
///
/// Returns implementations for all requested languages that have examples.
/// Languages without implementations are silently skipped.
pub fn compare(
    registry: &Registry,
    concept_id: &str,
    languages: &[Language],
) -> Result<Comparison> {
    let concept = registry.get_or_err(concept_id)?;

    let implementations: Vec<ComparedExample> = languages
        .iter()
        .filter_map(|lang| {
            concept.example(*lang).map(|ex| ComparedExample {
                language: *lang,
                code: ex.code.clone(),
                explanation: ex.explanation.clone(),
            })
        })
        .collect();

    Ok(Comparison {
        concept_id: concept.id.clone(),
        concept_title: concept.title.clone(),
        implementations,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::concept::{Concept, Example, Topic};
    use std::collections::HashMap;

    fn make_registry() -> Registry {
        let mut reg = Registry::new();
        let mut ex = HashMap::new();
        ex.insert(
            Language::Rust,
            Example {
                language: Language::Rust,
                code: "let s = String::from(\"hello\");".into(),
                explanation: "Owned string".into(),
                source_path: None,
            },
        );
        ex.insert(
            Language::Python,
            Example {
                language: Language::Python,
                code: "s = \"hello\"".into(),
                explanation: "Python string".into(),
                source_path: None,
            },
        );
        reg.register(Concept {
            id: "strings".into(),
            title: "String Basics".into(),
            topic: Topic::DataTypes,
            description: "Basic string operations.".into(),
            best_practices: vec![],
            gotchas: vec![],
            performance_notes: vec![],
            tags: vec![],
            examples: ex,
        });
        reg
    }

    #[test]
    fn compare_two_languages() {
        let reg = make_registry();
        let cmp = compare(&reg, "strings", &[Language::Rust, Language::Python]).unwrap();
        assert_eq!(cmp.implementations.len(), 2);
        assert_eq!(cmp.implementations[0].language, Language::Rust);
        assert_eq!(cmp.implementations[1].language, Language::Python);
    }

    #[test]
    fn compare_skips_missing() {
        let reg = make_registry();
        let cmp = compare(&reg, "strings", &[Language::Rust, Language::C]).unwrap();
        assert_eq!(cmp.implementations.len(), 1);
    }

    #[test]
    fn compare_concept_not_found() {
        let reg = make_registry();
        assert!(compare(&reg, "missing", &[Language::Rust]).is_err());
    }
}
