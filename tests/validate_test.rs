use std::path::Path;
use vidya::Language;
use vidya::loader::load_all;
use vidya::validate::run_validation;

#[test]
fn validate_rust_strings() {
    let file_path = Path::new("content/strings/rust.rs");
    if !file_path.exists() {
        panic!("content/strings/rust.rs not found");
    }

    let result = run_validation("strings", Language::Rust, file_path);
    assert!(
        result.passed,
        "rust strings should validate: {:?}",
        result.error
    );
    assert!(result.duration_ms > 0);
}

#[test]
fn validate_all_loaded_content() {
    let content_dir = Path::new("content");
    let registry = load_all(content_dir).expect("should load content");
    let results = vidya::validate::validate_all(&registry, content_dir);

    for result in &results {
        assert!(
            result.passed,
            "{}/{} failed: {:?}",
            result.concept_id, result.language, result.error
        );
    }
}
