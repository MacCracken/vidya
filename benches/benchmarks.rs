use criterion::{Criterion, criterion_group, criterion_main};
use std::path::Path;
use vidya::compare::compare;
use vidya::loader::load_all;
use vidya::search::search;
use vidya::{Language, Registry, SearchQuery};

/// Load the real content directory for realistic benchmarks.
fn loaded_registry() -> Registry {
    load_all(Path::new("content")).expect("content directory should load")
}

// ── Registry operations ────────────────────────────────────────────

fn bench_registry_get_hit(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_get_hit", |b| {
        b.iter(|| {
            std::hint::black_box(reg.get("strings"));
        });
    });
}

fn bench_registry_get_miss(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_get_miss", |b| {
        b.iter(|| {
            std::hint::black_box(reg.get("nonexistent"));
        });
    });
}

fn bench_registry_list(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_list", |b| {
        b.iter(|| {
            std::hint::black_box(reg.list());
        });
    });
}

fn bench_registry_by_topic(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_by_topic", |b| {
        b.iter(|| {
            std::hint::black_box(reg.by_topic(&vidya::Topic::DataTypes));
        });
    });
}

// ── Search operations ──────────────────────────────────────────────

fn bench_search_text_hit(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::text("string");
    c.bench_function("search_text_hit", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_text_miss(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::text("nonexistent_xyzzy_term");
    c.bench_function("search_text_miss", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_tag(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::tagged(vec!["concurrency".into()]);
    c.bench_function("search_tag", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_text_with_language(c: &mut Criterion) {
    let reg = loaded_registry();
    let mut query = SearchQuery::text("error");
    query.language = Some(Language::Rust);
    c.bench_function("search_text_with_language_filter", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_broad(c: &mut Criterion) {
    let reg = loaded_registry();
    // Empty query returns everything
    let query = SearchQuery {
        text: None,
        language: None,
        tags: vec![],
        limit: None,
    };
    c.bench_function("search_broad_all", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_quantum(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::text("quantum");
    c.bench_function("search_quantum", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_multi_tag(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::tagged(vec!["security".into(), "validation".into()]);
    c.bench_function("search_multi_tag", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

// ── Compare operations ─────────────────────────────────────────────

fn bench_compare_two_languages(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("compare_two_languages", |b| {
        b.iter(|| {
            let _ = std::hint::black_box(compare(
                &reg,
                "strings",
                &[Language::Rust, Language::Python],
            ));
        });
    });
}

fn bench_compare_all_languages(c: &mut Criterion) {
    let reg = loaded_registry();
    let all_langs = [
        Language::Rust,
        Language::Python,
        Language::C,
        Language::Go,
        Language::TypeScript,
        Language::Shell,
        Language::Zig,
        Language::AsmX86_64,
        Language::AsmAarch64,
        Language::OpenQASM,
    ];
    c.bench_function("compare_all_languages", |b| {
        b.iter(|| {
            let _ = std::hint::black_box(compare(&reg, "strings", &all_langs));
        });
    });
}

// ── Search operations (new topics) ────────────────────────────────

fn bench_search_compiler_text(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::text("parser");
    c.bench_function("search_compiler_text", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_syscall_tag(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::tagged(vec!["syscall".into()]);
    c.bench_function("search_syscall_tag", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_ssa_tag(c: &mut Criterion) {
    let reg = loaded_registry();
    let query = SearchQuery::tagged(vec!["SSA".into()]);
    c.bench_function("search_ssa_tag", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_search_allocator_with_language(c: &mut Criterion) {
    let reg = loaded_registry();
    let mut query = SearchQuery::text("allocator");
    query.language = Some(Language::Rust);
    c.bench_function("search_allocator_rust_filter", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

// ── Registry operations (new topics) ─────────────────────────────

fn bench_registry_by_topic_compiler(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_by_topic_compiler", |b| {
        b.iter(|| {
            std::hint::black_box(reg.by_topic(&vidya::Topic::LexingAndParsing));
        });
    });
}

fn bench_registry_get_new_topic(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("registry_get_new_topic", |b| {
        b.iter(|| {
            std::hint::black_box(reg.get("intermediate_representations"));
        });
    });
}

// ── Compare operations (new topics) ──────────────────────────────

fn bench_compare_new_topic(c: &mut Criterion) {
    let reg = loaded_registry();
    c.bench_function("compare_new_topic_rust_only", |b| {
        b.iter(|| {
            let _ = std::hint::black_box(compare(&reg, "lexing_and_parsing", &[Language::Rust]));
        });
    });
}

// ── Loader operations ──────────────────────────────────────────────

fn bench_load_all(c: &mut Criterion) {
    c.bench_function("load_all_content", |b| {
        b.iter(|| {
            std::hint::black_box(load_all(Path::new("content")).unwrap());
        });
    });
}

fn bench_load_single_concept(c: &mut Criterion) {
    c.bench_function("load_single_concept", |b| {
        b.iter(|| {
            std::hint::black_box(
                vidya::loader::load_concept(Path::new("content/strings")).unwrap(),
            );
        });
    });
}

fn bench_load_new_concept(c: &mut Criterion) {
    c.bench_function("load_new_concept_lexing", |b| {
        b.iter(|| {
            std::hint::black_box(
                vidya::loader::load_concept(Path::new("content/lexing_and_parsing")).unwrap(),
            );
        });
    });
}

criterion_group!(
    benches,
    // Registry
    bench_registry_get_hit,
    bench_registry_get_miss,
    bench_registry_list,
    bench_registry_by_topic,
    bench_registry_by_topic_compiler,
    bench_registry_get_new_topic,
    // Search
    bench_search_text_hit,
    bench_search_text_miss,
    bench_search_tag,
    bench_search_text_with_language,
    bench_search_broad,
    bench_search_quantum,
    bench_search_multi_tag,
    bench_search_compiler_text,
    bench_search_syscall_tag,
    bench_search_ssa_tag,
    bench_search_allocator_with_language,
    // Compare
    bench_compare_two_languages,
    bench_compare_all_languages,
    bench_compare_new_topic,
    // Loader
    bench_load_all,
    bench_load_single_concept,
    bench_load_new_concept,
);
criterion_main!(benches);
