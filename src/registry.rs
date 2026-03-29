//! In-memory concept registry.
//!
//! The [`Registry`] holds all loaded concepts and provides lookup by ID.
//! Concepts can be loaded from the content directory or registered programmatically.

use crate::concept::Concept;
use crate::error::{Result, VidyaError};
use std::collections::HashMap;

/// The concept registry — holds all programming concepts in memory.
///
/// Build programmatically with [`Registry::register`], or load from
/// a content directory with [`crate::loader::load_all`].
pub struct Registry {
    concepts: HashMap<String, Concept>,
}

impl Registry {
    /// Create an empty registry.
    #[must_use]
    pub fn new() -> Self {
        Self {
            concepts: HashMap::new(),
        }
    }

    /// Register a concept. Overwrites if the ID already exists.
    pub fn register(&mut self, concept: Concept) {
        tracing::debug!(id = %concept.id, "registered concept");
        self.concepts.insert(concept.id.clone(), concept);
    }

    /// Get a concept by ID.
    #[must_use]
    pub fn get(&self, id: &str) -> Option<&Concept> {
        self.concepts.get(id)
    }

    /// Get a concept by ID, returning an error if not found.
    pub fn get_or_err(&self, id: &str) -> Result<&Concept> {
        self.concepts
            .get(id)
            .ok_or_else(|| VidyaError::ConceptNotFound(id.into()))
    }

    /// List all concept IDs, sorted alphabetically.
    #[must_use]
    pub fn list_ids(&self) -> Vec<&str> {
        let mut ids: Vec<&str> = self.concepts.keys().map(|s| s.as_str()).collect();
        ids.sort_unstable();
        ids
    }

    /// List all concepts, sorted by ID.
    #[must_use]
    pub fn list(&self) -> Vec<&Concept> {
        let mut concepts: Vec<&Concept> = self.concepts.values().collect();
        concepts.sort_by(|a, b| a.id.cmp(&b.id));
        concepts
    }

    /// Number of registered concepts.
    #[must_use]
    #[inline]
    pub fn len(&self) -> usize {
        self.concepts.len()
    }

    #[must_use]
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.concepts.is_empty()
    }

    /// Filter concepts by topic.
    #[must_use]
    pub fn by_topic(&self, topic: &crate::concept::Topic) -> Vec<&Concept> {
        self.concepts
            .values()
            .filter(|c| &c.topic == topic)
            .collect()
    }
}

impl Default for Registry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::concept::Topic;
    use std::collections::HashMap;

    fn make_concept(id: &str) -> Concept {
        Concept {
            id: id.into(),
            title: id.into(),
            topic: Topic::DataTypes,
            description: format!("Test concept: {id}"),
            best_practices: vec![],
            gotchas: vec![],
            performance_notes: vec![],
            tags: vec![],
            examples: HashMap::new(),
        }
    }

    #[test]
    fn registry_empty() {
        let reg = Registry::new();
        assert!(reg.is_empty());
        assert_eq!(reg.len(), 0);
    }

    #[test]
    fn registry_register_and_get() {
        let mut reg = Registry::new();
        reg.register(make_concept("strings"));
        assert_eq!(reg.len(), 1);
        assert!(reg.get("strings").is_some());
        assert!(reg.get("missing").is_none());
    }

    #[test]
    fn registry_get_or_err() {
        let mut reg = Registry::new();
        reg.register(make_concept("strings"));
        assert!(reg.get_or_err("strings").is_ok());
        assert!(reg.get_or_err("missing").is_err());
    }

    #[test]
    fn registry_list_sorted() {
        let mut reg = Registry::new();
        reg.register(make_concept("concurrency"));
        reg.register(make_concept("algorithms"));
        reg.register(make_concept("strings"));
        let ids = reg.list_ids();
        assert_eq!(ids, vec!["algorithms", "concurrency", "strings"]);
    }

    #[test]
    fn registry_overwrite() {
        let mut reg = Registry::new();
        reg.register(make_concept("strings"));
        let mut updated = make_concept("strings");
        updated.description = "updated".into();
        reg.register(updated);
        assert_eq!(reg.len(), 1);
        assert_eq!(reg.get("strings").unwrap().description, "updated");
    }

    #[test]
    fn registry_by_topic() {
        let mut reg = Registry::new();
        reg.register(make_concept("strings"));
        let mut conc = make_concept("threads");
        conc.topic = Topic::Concurrency;
        reg.register(conc);
        let data_types = reg.by_topic(&Topic::DataTypes);
        assert_eq!(data_types.len(), 1);
        assert_eq!(data_types[0].id, "strings");
    }
}
