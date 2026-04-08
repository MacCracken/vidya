// Basic usage of the Vidya crate.
//
// Demonstrates loading content, searching, comparing across languages,
// and browsing best practices/gotchas/performance notes.
//
// Run: cargo run --example basic

use std::path::Path;
use vidya::compare::compare;
use vidya::loader::load_all;
use vidya::search::search;
use vidya::{Language, SearchQuery, Topic};

fn main() {
    // ── Load the content corpus ───────────────────────────────────────
    let registry = load_all(Path::new("content")).expect("content directory should load");

    println!("Loaded {} concepts:", registry.list().len());
    for concept in registry.list() {
        let langs: Vec<_> = concept.examples.keys().map(|l| l.to_string()).collect();
        println!("  {} — {} languages", concept.id, langs.len());
    }

    // ── Search ────────────────────────────────────────────────────────
    println!("\nSearch for 'quantum':");
    let results = search(&registry, &SearchQuery::text("quantum"));
    for r in &results {
        println!("  {} (score: {:.1})", r.title, r.score);
    }

    // Search with tag filter
    println!("\nSearch tag 'security':");
    let results = search(&registry, &SearchQuery::tagged(vec!["security".into()]));
    for r in &results {
        println!("  {} (score: {:.1})", r.title, r.score);
    }

    // Search with language filter
    let mut query = SearchQuery::text("error");
    query.language = Some(Language::Rust);
    println!("\nSearch 'error' (Rust only):");
    let results = search(&registry, &query);
    for r in &results {
        println!("  {} (score: {:.1})", r.title, r.score);
    }

    // ── Compare across languages ──────────────────────────────────────
    println!("\nCompare 'algorithms' — Rust vs Python vs Go:");
    if let Ok(cmp) = compare(
        &registry,
        "algorithms",
        &[Language::Rust, Language::Python, Language::Go],
    ) {
        println!("  Concept: {}", cmp.concept_title);
        for impl_ in &cmp.implementations {
            println!("  {} — {} chars of code", impl_.language, impl_.code.len());
        }
    }

    // ── Browse by topic ───────────────────────────────────────────────
    println!("\nKernel Topics:");
    for concept in registry.by_topic(&Topic::KernelTopics) {
        println!("  {}: {}", concept.title, concept.description);
        println!("    Best practices: {}", concept.best_practices.len());
        println!("    Gotchas: {}", concept.gotchas.len());
        println!("    Performance notes: {}", concept.performance_notes.len());
    }

    // ── Gotchas deep dive ─────────────────────────────────────────────
    if let Some(concept) = registry.get("security") {
        println!("\nSecurity gotchas:");
        for g in &concept.gotchas {
            println!("  ⚠ {}", g.title);
            println!("    {}", g.explanation);
            if let Some(ref bad) = g.bad_example {
                println!("    BAD:  {bad}");
            }
            if let Some(ref good) = g.good_example {
                println!("    GOOD: {good}");
            }
        }
    }

    // ── Performance notes ─────────────────────────────────────────────
    if let Some(concept) = registry.get("quantum_computing") {
        println!("\nQuantum computing performance notes:");
        for p in &concept.performance_notes {
            println!("  ⚡ {}", p.title);
            if let Some(ref ev) = p.evidence {
                println!("    Evidence: {ev}");
            }
        }
    }
}
