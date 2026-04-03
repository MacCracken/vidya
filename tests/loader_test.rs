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
    let topic_dir = Path::new("content/nonexistent_topic");
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

// ── New content topics ────────────────────────────────────────────────

/// All 18 new topics must load successfully and have the required fields.
#[test]
fn load_all_new_topics() {
    let new_topics = [
        "lexing_and_parsing",
        "code_generation",
        "intermediate_representations",
        "linking_and_loading",
        "optimization_passes",
        "syscalls_and_abi",
        "virtual_memory",
        "interrupt_handling",
        "process_and_scheduling",
        "filesystems",
        "ownership_and_borrowing",
        "trait_and_typeclass_systems",
        "macro_systems",
        "module_systems",
        "instruction_encoding",
        "elf_and_executable_formats",
        "allocators",
        "boot_and_startup",
    ];

    for topic_id in &new_topics {
        let topic_dir = Path::new("content").join(topic_id);
        let concept =
            load_concept(&topic_dir).unwrap_or_else(|e| panic!("{} should load: {}", topic_id, e));

        assert_eq!(concept.id, *topic_id, "{} id mismatch", topic_id);
        assert!(
            !concept.description.is_empty(),
            "{} missing description",
            topic_id
        );
        assert!(
            !concept.best_practices.is_empty(),
            "{} missing best_practices",
            topic_id
        );
        assert!(!concept.gotchas.is_empty(), "{} missing gotchas", topic_id);
        assert!(
            !concept.performance_notes.is_empty(),
            "{} missing performance_notes",
            topic_id
        );
        assert!(!concept.tags.is_empty(), "{} missing tags", topic_id);

        // Every new topic should have at least a Rust implementation
        assert!(
            concept.example(Language::Rust).is_some(),
            "{} missing rust.rs",
            topic_id
        );
    }
}

/// The registry should have all 33 topics after loading.
#[test]
fn load_all_has_33_topics() {
    let registry = load_all(Path::new("content")).expect("should load content");
    let ids = registry.list_ids();
    assert!(
        ids.len() >= 33,
        "expected at least 33 topics, got {}",
        ids.len()
    );
}

/// Compiler-internal topics should be discoverable by tag search.
#[test]
fn search_compiler_topics_by_tag() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let results = vidya::search::search(
        &registry,
        &vidya::SearchQuery::tagged(vec!["parser".into()]),
    );
    assert!(!results.is_empty(), "should find topics tagged 'parser'");
    assert!(
        results.iter().any(|r| r.id == "lexing_and_parsing"),
        "lexing_and_parsing should match 'parser' tag"
    );
}

/// Search for systems programming terms finds the new topics.
#[test]
fn search_systems_topics_by_text() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let results = vidya::search::search(&registry, &vidya::SearchQuery::text("syscall"));
    assert!(
        !results.is_empty(),
        "should find topics mentioning 'syscall'"
    );
    assert!(
        results.iter().any(|r| r.id == "syscalls_and_abi"),
        "syscalls_and_abi should rank for 'syscall' query"
    );
}

/// by_topic returns the correct new-topic concepts.
#[test]
fn by_topic_new_variants() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let compiler_topics = [
        (vidya::Topic::LexingAndParsing, "lexing_and_parsing"),
        (vidya::Topic::CodeGeneration, "code_generation"),
        (vidya::Topic::Allocators, "allocators"),
        (vidya::Topic::VirtualMemory, "virtual_memory"),
        (vidya::Topic::Filesystems, "filesystems"),
        (vidya::Topic::MacroSystems, "macro_systems"),
        (vidya::Topic::BootAndStartup, "boot_and_startup"),
    ];

    for (topic, expected_id) in &compiler_topics {
        let results = registry.by_topic(topic);
        assert_eq!(
            results.len(),
            1,
            "expected exactly 1 concept for {:?}, got {}",
            topic,
            results.len()
        );
        assert_eq!(results[0].id, *expected_id);
    }
}

/// Compare works for new topics that have Rust implementations.
#[test]
fn compare_new_topic() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let cmp = vidya::compare::compare(
        &registry,
        "lexing_and_parsing",
        &[Language::Rust, Language::Python],
    )
    .expect("compare should succeed");

    assert_eq!(cmp.concept_id, "lexing_and_parsing");
    // Should have at least Rust
    assert!(
        cmp.implementations
            .iter()
            .any(|i| i.language == Language::Rust),
        "should have Rust implementation"
    );
    // Python may or may not exist yet
}

/// Gotchas in new topics should have both bad and good examples.
#[test]
fn new_topic_gotchas_have_examples() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let topics_to_check = [
        "lexing_and_parsing",
        "code_generation",
        "syscalls_and_abi",
        "virtual_memory",
        "allocators",
    ];

    for topic_id in &topics_to_check {
        let concept = registry.get(topic_id).unwrap();
        for gotcha in &concept.gotchas {
            assert!(
                gotcha.bad_example.is_some(),
                "{}: gotcha '{}' missing bad_example",
                topic_id,
                gotcha.title
            );
            assert!(
                gotcha.good_example.is_some(),
                "{}: gotcha '{}' missing good_example",
                topic_id,
                gotcha.title
            );
        }
    }
}

/// Performance notes in new topics should have evidence.
#[test]
fn new_topic_perf_notes_have_evidence() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let topics_to_check = [
        "lexing_and_parsing",
        "code_generation",
        "linking_and_loading",
        "allocators",
        "virtual_memory",
    ];

    for topic_id in &topics_to_check {
        let concept = registry.get(topic_id).unwrap();
        for note in &concept.performance_notes {
            assert!(
                note.evidence.is_some(),
                "{}: perf note '{}' missing evidence",
                topic_id,
                note.title
            );
        }
    }
}

/// Search with language filter should work for new topics.
#[test]
fn search_new_topics_with_language_filter() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let mut query = vidya::SearchQuery::text("allocator");
    query.language = Some(Language::Rust);
    let results = vidya::search::search(&registry, &query);

    assert!(
        !results.is_empty(),
        "should find allocators topic with Rust filter"
    );
}

/// Multi-tag search across new and old topics.
#[test]
fn search_multi_tag_new_topics() {
    let registry = load_all(Path::new("content")).expect("should load content");

    let results = vidya::search::search(&registry, &vidya::SearchQuery::tagged(vec!["SSA".into()]));
    assert!(!results.is_empty(), "should find topics tagged 'SSA'");
    assert!(
        results
            .iter()
            .any(|r| r.id == "intermediate_representations"),
        "intermediate_representations should match 'SSA' tag"
    );
}
