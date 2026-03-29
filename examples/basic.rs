use std::collections::HashMap;
use vidya::compare::compare;
use vidya::search::search;
use vidya::{
    BestPractice, Concept, Example, Gotcha, Language, PerformanceNote, Registry, SearchQuery, Topic,
};

fn main() {
    // Build a registry with one concept
    let mut registry = Registry::new();

    let mut examples = HashMap::new();
    examples.insert(
        Language::Rust,
        Example {
            language: Language::Rust,
            code: r#"let s = String::from("hello");"#.into(),
            explanation: "Owned heap-allocated UTF-8 string.".into(),
            source_path: Some("strings/rust.rs".into()),
        },
    );
    examples.insert(
        Language::Python,
        Example {
            language: Language::Python,
            code: r#"s = "hello""#.into(),
            explanation: "Immutable string literal.".into(),
            source_path: Some("strings/python.py".into()),
        },
    );

    registry.register(Concept {
        id: "string_basics".into(),
        title: "String Basics".into(),
        topic: Topic::DataTypes,
        description: "Creating and using strings.".into(),
        best_practices: vec![BestPractice {
            title: "Borrow when you can".into(),
            explanation: "Accept &str, return String.".into(),
            language: Some(Language::Rust),
        }],
        gotchas: vec![Gotcha {
            title: "String indexing".into(),
            explanation: "Rust strings cannot be indexed by byte position.".into(),
            bad_example: Some(r#"let c = s[0];"#.into()),
            good_example: Some(r#"let c = s.chars().nth(0);"#.into()),
            language: Some(Language::Rust),
        }],
        performance_notes: vec![PerformanceNote {
            title: "write! over format!".into(),
            explanation: "Avoids allocation on hot paths.".into(),
            evidence: Some("~40% fewer allocations".into()),
            language: Some(Language::Rust),
        }],
        tags: vec!["strings".into(), "text".into(), "utf-8".into()],
        examples,
    });

    // Search
    let results = search(&registry, &SearchQuery::text("string"));
    println!("Search results for 'string':");
    for r in &results {
        println!("  {} (score: {:.1})", r.title, r.score);
    }

    // Compare
    let cmp = compare(
        &registry,
        "string_basics",
        &[Language::Rust, Language::Python],
    )
    .unwrap();
    println!("\nComparison: {}", cmp.concept_title);
    for impl_ in &cmp.implementations {
        println!("  {} → {}", impl_.language, impl_.code);
    }

    // Gotchas
    let concept = registry.get("string_basics").unwrap();
    println!("\nGotchas:");
    for g in &concept.gotchas {
        println!("  ⚠ {}: {}", g.title, g.explanation);
    }

    // Performance notes
    println!("\nPerformance:");
    for p in &concept.performance_notes {
        println!("  ⚡ {}: {}", p.title, p.explanation);
    }
}
