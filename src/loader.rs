//! Content loader — reads `content/` directory into a populated [`Registry`].
//!
//! Each topic lives in its own directory under `content/`:
//!
//! ```text
//! content/strings/
//! ├── concept.toml     # Structured metadata (parsed into Concept)
//! ├── concept.md       # Human-readable documentation (not parsed by loader)
//! ├── rust.rs           # Rust implementation
//! └── python.py         # Python implementation
//! ```
//!
//! The loader reads `concept.toml` for structured data and discovers
//! language implementation files by extension.

use crate::concept::{BestPractice, Concept, Example, Gotcha, PerformanceNote};
use crate::error::{Result, VidyaError};
use crate::language::Language;
use crate::registry::Registry;
use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

/// TOML representation of a concept (deserialized from `concept.toml`).
#[derive(Debug, Deserialize)]
struct ConceptFile {
    id: String,
    title: String,
    topic: crate::concept::Topic,
    description: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    best_practices: Vec<BestPracticeEntry>,
    #[serde(default)]
    gotchas: Vec<GotchaEntry>,
    #[serde(default)]
    performance_notes: Vec<PerformanceNoteEntry>,
}

#[derive(Debug, Deserialize)]
struct BestPracticeEntry {
    title: String,
    explanation: String,
    #[serde(default)]
    language: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GotchaEntry {
    title: String,
    explanation: String,
    #[serde(default)]
    bad_example: Option<String>,
    #[serde(default)]
    good_example: Option<String>,
    #[serde(default)]
    language: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PerformanceNoteEntry {
    title: String,
    explanation: String,
    #[serde(default)]
    evidence: Option<String>,
    #[serde(default)]
    language: Option<String>,
}

/// Load a single concept from a topic directory.
///
/// Reads `concept.toml` for metadata and discovers language files
/// (e.g. `rust.rs`, `python.py`) in the same directory.
pub fn load_concept(topic_dir: &Path) -> Result<Concept> {
    let toml_path = topic_dir.join("concept.toml");
    if !toml_path.exists() {
        return Err(VidyaError::ContentDir(format!(
            "missing concept.toml in {}",
            topic_dir.display()
        )));
    }

    let toml_content = std::fs::read_to_string(&toml_path)?;
    let file: ConceptFile = toml::from_str(&toml_content)
        .map_err(|e| VidyaError::Parse(format!("{toml_path:?}: {e}")))?;

    let best_practices = file
        .best_practices
        .into_iter()
        .map(|bp| BestPractice {
            title: bp.title,
            explanation: bp.explanation,
            language: bp.language.as_deref().and_then(Language::from_str_loose),
        })
        .collect();

    let gotchas = file
        .gotchas
        .into_iter()
        .map(|g| Gotcha {
            title: g.title,
            explanation: g.explanation,
            bad_example: g.bad_example,
            good_example: g.good_example,
            language: g.language.as_deref().and_then(Language::from_str_loose),
        })
        .collect();

    let performance_notes = file
        .performance_notes
        .into_iter()
        .map(|p| PerformanceNote {
            title: p.title,
            explanation: p.explanation,
            evidence: p.evidence,
            language: p.language.as_deref().and_then(Language::from_str_loose),
        })
        .collect();

    // Discover language implementation files
    let examples = discover_examples(topic_dir, &file.id)?;

    Ok(Concept {
        id: file.id,
        title: file.title,
        topic: file.topic,
        description: file.description,
        best_practices,
        gotchas,
        performance_notes,
        tags: file.tags,
        examples,
    })
}

/// Discover language implementation files in a topic directory.
///
/// Looks for files named by language (e.g. `rust.rs`, `python.py`)
/// and reads their contents into [`Example`] structs.
fn discover_examples(topic_dir: &Path, concept_id: &str) -> Result<HashMap<Language, Example>> {
    let mut examples = HashMap::new();

    for lang in Language::all() {
        // Try filename patterns: "rust.rs", "python.py", etc.
        let filename = format!(
            "{}.{}",
            lang.display_name().to_lowercase(),
            lang.extension()
        );
        let file_path = topic_dir.join(&filename);

        if file_path.exists() {
            let code = std::fs::read_to_string(&file_path)?;
            let relative = format!("{concept_id}/{filename}");

            // Extract explanation from leading comments
            let explanation = extract_explanation(&code, lang.comment_prefix());

            examples.insert(
                *lang,
                Example {
                    language: *lang,
                    code,
                    explanation,
                    source_path: Some(relative),
                },
            );
        }
    }

    Ok(examples)
}

/// Extract a human-readable explanation from leading comments in a source file.
///
/// Reads consecutive comment lines from the top of the file (skipping shebangs)
/// and strips the comment prefix.
fn extract_explanation(code: &str, comment_prefix: &str) -> String {
    let mut lines = Vec::new();

    for line in code.lines() {
        let trimmed = line.trim();

        // Skip shebang
        if trimmed.starts_with("#!") && lines.is_empty() {
            continue;
        }

        if trimmed.starts_with(comment_prefix) {
            let content = trimmed.strip_prefix(comment_prefix).unwrap_or("").trim();
            lines.push(content.to_string());
        } else if trimmed.is_empty() && !lines.is_empty() {
            // Allow blank lines within the comment block
            lines.push(String::new());
        } else if !trimmed.is_empty() {
            break;
        }
    }

    // Trim trailing empty lines
    while lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }

    lines.join("\n")
}

/// Load all concepts from a content directory into a new [`Registry`].
///
/// Scans `content_dir` for subdirectories containing `concept.toml` files.
/// Directories without `concept.toml` are silently skipped.
pub fn load_all(content_dir: &Path) -> Result<Registry> {
    if !content_dir.is_dir() {
        return Err(VidyaError::ContentDir(format!(
            "not a directory: {}",
            content_dir.display()
        )));
    }

    let mut registry = Registry::new();
    let mut entries: Vec<_> = std::fs::read_dir(content_dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_ok_and(|ft| ft.is_dir()))
        .collect();

    // Sort for deterministic ordering
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let toml_path = entry.path().join("concept.toml");
        if toml_path.exists() {
            let concept = load_concept(&entry.path())?;
            registry.register(concept);
        }
    }

    Ok(registry)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_explanation_rust() {
        let code = "// Vidya — Strings in Rust\n//\n// Rust has two string types.\n\nfn main() {}";
        let result = extract_explanation(code, "//");
        assert_eq!(
            result,
            "Vidya — Strings in Rust\n\nRust has two string types."
        );
    }

    #[test]
    fn extract_explanation_python() {
        let code = "#!/usr/bin/env python3\n# Vidya — Strings in Python\n# Python strings are immutable.\n\nprint('hello')";
        let result = extract_explanation(code, "#");
        assert_eq!(
            result,
            "Vidya — Strings in Python\nPython strings are immutable."
        );
    }

    #[test]
    fn extract_explanation_empty() {
        let code = "fn main() {}";
        let result = extract_explanation(code, "//");
        assert!(result.is_empty());
    }
}
