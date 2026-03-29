# Vidya

> **विद्या** (Sanskrit: knowledge, learning) — Programming reference library and queryable corpus

Vidya is a curated, tested, multi-language programming reference for the AGNOS ecosystem. Every concept includes best practices, gotchas, performance discoveries, and reference implementations — all verified by CI.

## Two Layers

1. **Content** (`content/`) — Markdown docs and source files. No compilation needed. Read directly, train AI on it, or browse as documentation.

2. **Crate** (`src/`) — Rust library that makes the content queryable. Types for concepts, search, cross-language comparison, and example validation. `cargo doc` generates a browsable programming reference.

## Features

- **Best Practices** — The right way to do things, with explanations of *why*
- **Gotchas** — Common mistakes with bad/good examples. What NOT to do and what to do instead
- **Performance Notes** — Optimization discoveries with evidence (benchmarks, complexity analysis)
- **Multi-Language** — Same concept implemented in Rust, Python, C, Go, TypeScript, Shell, Zig
- **Tested** — Every code example compiles and runs. CI validates all implementations
- **Queryable** — Search, compare across languages, filter by topic or tag

## Quick Start

```rust
use vidya::{Language, Registry, SearchQuery};
use vidya::search::search;

let registry = Registry::new();

// Search for concepts
let results = search(&registry, &SearchQuery::text("strings"));

// Compare across languages
let cmp = vidya::compare::compare(&registry, "string_basics", &[Language::Rust, Language::Python]);
```

## Content Topics

| Topic | Description |
|-------|-------------|
| `strings` | Text handling, encoding, interpolation, slicing |
| `error_handling` | Result types, exceptions, error propagation |
| `concurrency` | Threads, async, channels, parallelism |
| `memory_management` | Ownership, borrowing, GC, allocation |
| `iterators` | Lazy evaluation, map/filter/fold, generators |
| `pattern_matching` | Match expressions, destructuring, guards |
| `type_systems` | Generics, traits, interfaces, type inference |
| `testing` | Unit tests, property testing, mocking, coverage |
| `performance` | Profiling, allocation, cache, SIMD, benchmarking |

## License

GPL-3.0
