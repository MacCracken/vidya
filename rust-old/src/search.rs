//! Full-text and tag-based search across concepts.

use crate::concept::Concept;
use crate::language::Language;
use crate::registry::Registry;
use serde::{Deserialize, Serialize};

/// A search query against the registry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchQuery {
    /// Free-text search (matched against title, description, tags).
    pub text: Option<String>,
    /// Filter by language (only concepts with this language's example).
    pub language: Option<Language>,
    /// Filter by tags (all must match).
    pub tags: Vec<String>,
    /// Maximum results to return.
    pub limit: Option<usize>,
}

impl SearchQuery {
    /// Create a simple text search.
    #[must_use]
    pub fn text(query: impl Into<String>) -> Self {
        Self {
            text: Some(query.into()),
            language: None,
            tags: vec![],
            limit: None,
        }
    }

    /// Create a tag-based search.
    #[must_use]
    pub fn tagged(tags: Vec<String>) -> Self {
        Self {
            text: None,
            language: None,
            tags,
            limit: None,
        }
    }

    /// Filter results to concepts that have an example in this language.
    #[must_use]
    pub fn with_language(mut self, lang: Language) -> Self {
        self.language = Some(lang);
        self
    }

    /// Limit the number of results returned.
    #[must_use]
    pub fn with_limit(mut self, limit: usize) -> Self {
        self.limit = Some(limit);
        self
    }

    /// Add required tags (all must match).
    #[must_use]
    pub fn with_tags(mut self, tags: Vec<String>) -> Self {
        self.tags = tags;
        self
    }
}

/// A search result with relevance score.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Concept ID.
    pub id: String,
    /// Concept title.
    pub title: String,
    /// Relevance score (higher = better match).
    pub score: f32,
}

/// Execute a search against the registry.
#[must_use]
pub fn search(registry: &Registry, query: &SearchQuery) -> Vec<SearchResult> {
    let mut results: Vec<SearchResult> = registry
        .list()
        .into_iter()
        .filter_map(|concept| score_concept(concept, query))
        .collect();

    results.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    if let Some(limit) = query.limit {
        results.truncate(limit);
    }

    results
}

fn score_concept(concept: &Concept, query: &SearchQuery) -> Option<SearchResult> {
    let mut score: f32 = 0.0;

    // Language filter (hard filter, not scoring)
    if let Some(lang) = query.language {
        concept.example(lang)?;
    }

    // Tag filter (all must match)
    for tag in &query.tags {
        if !concept.has_tag(tag) {
            return None;
        }
        score += 1.0;
    }

    // Text matching
    if let Some(text) = &query.text {
        let lower = text.to_lowercase();
        let tokens: Vec<&str> = lower.split_whitespace().collect();
        let score_before_text = score;

        let id_lower = concept.id.to_lowercase();
        let title_lower = concept.title.to_lowercase();
        let desc_lower = concept.description.to_lowercase();

        for token in &tokens {
            // Exact ID match is the strongest signal
            if id_lower == *token {
                score += 5.0;
            } else if id_lower.contains(token) {
                score += 3.0;
            }

            // Title: exact match bonus, then substring
            if title_lower == *token {
                score += 4.0;
            } else if title_lower.contains(token) {
                score += 2.0;
            }

            // Description match
            if desc_lower.contains(token) {
                score += 1.0;
            }

            // Tag match — exact tag match is stronger than substring
            for tag in &concept.tags {
                let tag_lower = tag.to_lowercase();
                if tag_lower == *token {
                    score += 2.0;
                } else if tag_lower.contains(token) {
                    score += 1.0;
                }
            }
        }

        // Text was provided but didn't match anything — filter out
        if score == score_before_text {
            return None;
        }
    }

    // If no query criteria at all, return everything with base score
    if query.text.is_none() && query.tags.is_empty() && query.language.is_none() {
        score = 1.0;
    }

    Some(SearchResult {
        id: concept.id.clone(),
        title: concept.title.clone(),
        score,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::concept::{Example, Topic};
    use std::collections::HashMap;

    fn make_registry() -> Registry {
        let mut reg = Registry::new();

        let mut ex = HashMap::new();
        ex.insert(
            Language::Rust,
            Example {
                language: Language::Rust,
                code: "let s = String::new();".into(),
                explanation: "Rust strings".into(),
                source_path: None,
            },
        );
        reg.register(Concept {
            id: "strings".into(),
            title: "String Handling".into(),
            topic: Topic::DataTypes,
            description: "Working with text and string types.".into(),
            best_practices: vec![],
            gotchas: vec![],
            performance_notes: vec![],
            tags: vec!["text".into(), "utf-8".into()],
            examples: ex,
        });

        reg.register(Concept {
            id: "concurrency".into(),
            title: "Concurrency Patterns".into(),
            topic: Topic::Concurrency,
            description: "Threads, async, and parallelism.".into(),
            best_practices: vec![],
            gotchas: vec![],
            performance_notes: vec![],
            tags: vec!["threads".into(), "async".into()],
            examples: HashMap::new(),
        });

        reg
    }

    #[test]
    fn search_text() {
        let reg = make_registry();
        let results = search(&reg, &SearchQuery::text("string"));
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "strings");
    }

    #[test]
    fn search_tag() {
        let reg = make_registry();
        let results = search(&reg, &SearchQuery::tagged(vec!["utf-8".into()]));
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "strings");
    }

    #[test]
    fn search_language_filter() {
        let reg = make_registry();
        let mut q = SearchQuery::text("patterns");
        q.language = Some(Language::Rust);
        let results = search(&reg, &q);
        // "concurrency" matches "patterns" but has no Rust example
        assert!(results.is_empty());
    }

    #[test]
    fn search_no_match() {
        let reg = make_registry();
        let results = search(&reg, &SearchQuery::text("quantum"));
        assert!(results.is_empty());
    }

    #[test]
    fn search_text_with_tags_no_text_match() {
        let reg = make_registry();
        // "text" tag matches "strings", but "quantum" text matches nothing
        let q = SearchQuery {
            text: Some("quantum".into()),
            language: None,
            tags: vec!["text".into()],
            limit: None,
        };
        let results = search(&reg, &q);
        assert!(
            results.is_empty(),
            "should not match when text doesn't match"
        );
    }

    #[test]
    fn search_text_with_tags_both_match() {
        let reg = make_registry();
        let q = SearchQuery {
            text: Some("string".into()),
            language: None,
            tags: vec!["text".into()],
            limit: None,
        };
        let results = search(&reg, &q);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "strings");
    }

    #[test]
    fn search_limit() {
        let reg = make_registry();
        let mut q = SearchQuery::text("");
        q.text = None; // match all
        q.limit = Some(1);
        let results = search(&reg, &q);
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn search_exact_id_ranks_highest() {
        let reg = make_registry();
        // "strings" is an exact ID match — should score higher than substring
        let results = search(&reg, &SearchQuery::text("strings"));
        assert_eq!(results[0].id, "strings");
        assert!(results[0].score >= 5.0); // exact ID match bonus
    }

    #[test]
    fn builder_with_language() {
        let reg = make_registry();
        let q = SearchQuery::text("string").with_language(Language::Rust);
        let results = search(&reg, &q);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "strings");
    }

    #[test]
    fn builder_with_limit() {
        let reg = make_registry();
        let _q = SearchQuery::text("").with_limit(1);
        // Empty text with limit won't match anything (text is empty string, no tokens)
        // Use a broad query instead
        let q = SearchQuery {
            text: None,
            language: None,
            tags: vec![],
            limit: Some(1),
        };
        let results = search(&reg, &q);
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn builder_chaining() {
        let reg = make_registry();
        let q = SearchQuery::text("string")
            .with_language(Language::Rust)
            .with_limit(5);
        let results = search(&reg, &q);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].id, "strings");
    }
}
