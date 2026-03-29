use std::path::Path;
use vidya::Language;
use vidya::loader::{load_all, load_concept};

#[test]
fn load_strings_concept() {
    let topic_dir = Path::new("content/strings");
    let concept = load_concept(topic_dir).expect("should load strings concept");

    assert_eq!(concept.id, "strings");
    assert_eq!(concept.title, "Strings");
    assert!(!concept.description.is_empty());
    assert!(!concept.tags.is_empty());
    assert!(!concept.best_practices.is_empty());
    assert!(!concept.gotchas.is_empty());
    assert!(!concept.performance_notes.is_empty());

    // Should have discovered the rust.rs implementation
    let rust_example = concept.example(Language::Rust);
    assert!(rust_example.is_some(), "should find rust.rs");
    let ex = rust_example.unwrap();
    assert!(!ex.code.is_empty());
    assert_eq!(ex.source_path.as_deref(), Some("strings/rust.rs"));
}

#[test]
fn load_all_content() {
    let content_dir = Path::new("content");
    let registry = load_all(content_dir).expect("should load all content");

    // At minimum, strings should be loaded
    assert!(
        registry.get("strings").is_some(),
        "registry should contain strings"
    );
}

#[test]
fn load_concept_missing_toml() {
    let topic_dir = Path::new("content/concurrency");
    let result = load_concept(topic_dir);
    assert!(result.is_err(), "should fail without concept.toml");
}

#[test]
fn loaded_concept_is_searchable() {
    let content_dir = Path::new("content");
    let registry = load_all(content_dir).expect("should load content");

    let results = vidya::search::search(&registry, &vidya::SearchQuery::text("string"));
    assert!(
        !results.is_empty(),
        "should find strings concept via search"
    );
    assert_eq!(results[0].id, "strings");
}
