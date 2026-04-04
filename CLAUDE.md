# Vidya — Claude Code Instructions

## Project Identity

**Vidya** (Sanskrit: विद्या — knowledge, learning) — Programming reference library and queryable corpus

- **Type**: Flat library crate + content directory
- **License**: GPL-3.0-only
- **MSRV**: 1.89
- **Version**: SemVer 1.5.0
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Philosophy**: [AGNOS Philosophy & Intention](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)
- **Recipes**: [zugot](https://github.com/MacCracken/zugot) — takumi build recipes

## Consumers

- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- All AGNOS developers — vidya is the programming reference for the ecosystem

## What This Is

Vidya is both a curated programming reference and a Rust crate that serves it:

1. **Content directory** (`content/`) — TOML metadata + source files per topic. No compilation needed. Humans read it. AI trains on it.
2. **Rust crate** (`src/`) — Queryable interface. Types, search, compare, validate. `cargo doc` = browsable reference.

Every code example in `content/` is a test. CI compiles/runs every implementation in every language.

## Content Structure

```
content/{topic}/
├── concept.toml       # Structured metadata (parsed by loader)
├── rust.rs            # Tested Rust implementation
├── python.py          # Tested Python implementation
├── c.c                # Tested C implementation
├── go.go              # Tested Go implementation
├── typescript.ts      # Tested TypeScript implementation
├── shell.sh           # Tested Shell implementation
├── zig.zig            # Tested Zig implementation
├── asm_x86_64.s       # Tested x86_64 Assembly implementation
├── asm_aarch64.s      # Tested AArch64 Assembly implementation
└── openqasm.qasm      # Tested OpenQASM 2.0 quantum circuit
```

**Rust is the primary language.** Complete Rust coverage first, then add other languages.

## Key Types

- `Concept` — A programming topic with examples, best practices, gotchas, performance notes
- `Topic` — Enum of programming topic categories (33 variants)
- `Gotcha` — Common mistake with bad/good example (teaches what NOT to do)
- `PerformanceNote` — Optimization insight with evidence (benchmark numbers)
- `BestPractice` — The right way, with explanation of why
- `Registry` — In-memory concept store with lookup/search
- `Comparison` — Side-by-side cross-language view
- `Language` — Supported language enum (10 languages)

## Content Standards

- Every concept MUST have: description, at least one best practice, at least one gotcha, at least one performance note
- Every code example MUST compile/run successfully
- Gotchas MUST include both bad and good examples
- Performance notes SHOULD include evidence (benchmark numbers or complexity)
- Best practices explain WHY, not just WHAT
- Content is instructional — write for someone learning, not someone who already knows

## Development Process

### P(-1): Scaffold Hardening (before any new features)

0. Read roadmap, CHANGELOG, and open issues — know what was intended before auditing what was built
1. Test + benchmark sweep of existing code
2. Cleanliness check: `cargo fmt --check`, `cargo clippy --all-features --all-targets -- -D warnings`, `cargo audit`, `cargo deny check`, `RUSTDOCFLAGS="-D warnings" cargo doc --all-features --no-deps`
3. Get baseline benchmarks (`./scripts/bench-history.sh`)
4. Internal deep review — gaps, correctness, documentation quality
5. External research — are there better examples, newer best practices, more complete gotchas?
6. Cleanliness check — must be clean after review
7. Additional tests/benchmarks from findings
8. Post-review benchmarks — prove the wins
9. Documentation audit — ADRs, source citations, guides, examples (see [Documentation Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md))
10. Repeat if heavy

### Work Loop (continuous)

1. Work phase — new concepts, new languages, improvements
2. Cleanliness check: `cargo fmt --check`, `cargo clippy --all-features --all-targets -- -D warnings`, `cargo audit`, `cargo deny check`, `RUSTDOCFLAGS="-D warnings" cargo doc --all-features --no-deps`
3. Test + benchmark additions for new content
4. Run benchmarks (`./scripts/bench-history.sh`)
5. Internal review — correctness, completeness, instructional quality
6. Cleanliness check — must be clean after review
7. Deeper tests from review
8. Run benchmarks again — prove the wins
9. If review heavy → return to step 5
10. Documentation — update CHANGELOG, roadmap, ADRs for design decisions, source citations for algorithms/references, update docs/sources.md, verify recipe version in zugot
11. Version check — VERSION, Cargo.toml, recipe (in zugot) all in sync
12. Return to step 1

### Task Sizing

- **Low/Medium effort**: Batch freely — multiple topics per work loop cycle
- **Large effort**: Small bites only — one topic at a time, verify each before moving to the next
- **If unsure**: Treat it as large

### Refactoring

- Refactor when the code tells you to — duplication, unclear boundaries, performance bottlenecks
- Never refactor speculatively. Wait for the third instance before extracting an abstraction
- Every refactor must pass the same cleanliness + benchmark gates as new code

### Key Principles

- Never skip benchmarks
- `#[non_exhaustive]` on ALL public enums (forward compatibility)
- `#[must_use]` on all pure functions
- Every type must be Serialize + Deserialize (serde)
- Feature-gate optional modules — consumers pull only what they need
- Zero unwrap/panic in library code
- All types must have serde roundtrip tests
- **Every code example must compile and run** — content is tested, not decorative
- **Cite sources** — algorithm references, language spec versions, textbook citations in docs/sources.md

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add unnecessary dependencies
- Do not break backward compatibility without a major version bump
- Do not skip benchmarks before claiming performance improvements
- Do not write examples that don't compile/run
- Do not write gotchas without both bad and good examples
- Do not claim performance improvements without evidence

## Documentation Structure

```
Root files (required):
  README.md, CHANGELOG.md, CLAUDE.md, CONTRIBUTING.md, SECURITY.md, CODE_OF_CONDUCT.md, LICENSE

docs/ (required):
  architecture/overview.md — module map, data flow, consumers
  development/roadmap.md — completed, backlog, future, v1.0 criteria
  development/content-format.md — content directory specification

docs/ (when earned):
  adr/ — architectural decision records
  guides/ — usage guides, integration patterns
  examples/ — worked examples
  standards/ — external spec conformance
  compliance/ — regulatory, audit, security compliance
  sources.md — source citations for algorithms, language specs, textbook references
```

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims MUST include benchmark numbers. Breaking changes get a **Breaking** section with migration guide.
