# Vidya — Claude Code Instructions

## Project Identity

**Vidya** (Sanskrit: विद्या — knowledge, learning) — Programming reference library and queryable corpus

- **Type**: Flat library crate + content directory
- **License**: GPL-3.0
- **MSRV**: 1.89
- **Version**: SemVer 1.5.0

## What This Is

Vidya is both a curated programming reference and a Rust crate that serves it:

1. **Content directory** (`content/`) — Markdown docs + source files. No compilation needed. Humans read it. AI trains on it.
2. **Rust crate** (`src/`) — Queryable interface. Types, search, compare, validate. `cargo doc` = browsable reference.

Every code example in `content/` is a test. CI compiles/runs every implementation in every language.

## Content Structure

```
content/{topic}/
├── concept.md       # Best practices, gotchas, performance notes
├── rust.rs          # Tested Rust implementation
├── python.py        # Tested Python implementation
├── c.c              # Tested C implementation
├── go.go            # Tested Go implementation
├── typescript.ts    # Tested TypeScript implementation
└── shell.sh         # Tested Shell implementation
```

**Rust is the primary language.** Complete Rust coverage first, then add other languages.

## Key Types

- `Concept` — A programming topic with examples, best practices, gotchas, performance notes
- `Gotcha` — Common mistake with bad/good example (teaches what NOT to do)
- `PerformanceNote` — Optimization insight with evidence (benchmark numbers)
- `BestPractice` — The right way, with explanation of why
- `Registry` — In-memory concept store with lookup/search
- `Comparison` — Side-by-side cross-language view

## Content Standards

- Every concept MUST have: description, at least one best practice, at least one gotcha, at least one performance note
- Every code example MUST compile/run successfully
- Gotchas MUST include both bad and good examples
- Performance notes SHOULD include evidence (benchmark numbers or complexity)
- Best practices explain WHY, not just WHAT
- Content is instructional — write for someone learning, not someone who already knows

## Development Process

### P(-1): Scaffold Hardening (before any new features)

1. Test + benchmark sweep of existing code
2. Cleanliness check: `cargo fmt --check`, `cargo clippy --all-features --all-targets -- -D warnings`, `cargo audit`, `cargo deny check`, `RUSTDOCFLAGS="-D warnings" cargo doc --all-features --no-deps`
3. Get baseline benchmarks (`./scripts/bench-history.sh`)
4. Internal deep review — gaps, correctness, documentation quality
5. Cleanliness check — must be clean after review
6. Additional tests/benchmarks from findings
7. Post-review benchmarks — prove the wins

### Work Loop (continuous)

1. Work phase — new concepts, new languages, improvements
2. Cleanliness check
3. Test + benchmark additions for new content
4. Run benchmarks
5. Internal review — correctness, completeness, instructional quality
6. Cleanliness check
7. Deeper tests from review
8. Run benchmarks again
9. Documentation — update CHANGELOG, roadmap

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add unnecessary dependencies
- Do not write examples that don't compile/run
- Do not write gotchas without both bad and good examples
- Do not claim performance improvements without evidence
