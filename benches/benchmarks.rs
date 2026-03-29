use criterion::{Criterion, criterion_group, criterion_main};
use vidya::search::search;
use vidya::{Registry, SearchQuery};

fn bench_search_text(c: &mut Criterion) {
    let reg = Registry::new();
    let query = SearchQuery::text("string");
    c.bench_function("search_text_empty_registry", |b| {
        b.iter(|| {
            std::hint::black_box(search(&reg, &query));
        });
    });
}

fn bench_registry_lookup(c: &mut Criterion) {
    let reg = Registry::new();
    c.bench_function("registry_get_miss", |b| {
        b.iter(|| {
            std::hint::black_box(reg.get("nonexistent"));
        });
    });
}

criterion_group!(benches, bench_search_text, bench_registry_lookup);
criterion_main!(benches);
