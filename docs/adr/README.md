# Architecture Decision Records

This directory captures the *why* behind structural choices in vidya — decisions that could credibly have gone the other way.

**Conventions** (per [agnosticos first-party-documentation §"ADRs"](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#architecture-decision-records-adrs)):

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. **Never renumber.**
- **One decision per ADR.** Supersessions add a new ADR and mark the old one `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use `template.md` as the starting point.

**When to write an ADR**: competing approaches with real trade-offs, adopting or rejecting a dependency, changing a public API, accepting a performance or portability trade-off. If the decision could credibly have gone the other way, write the ADR.

**Where vidya's other doc layers live** (per `docs/doc-health.md`):

- *How the code is* (invariants, quirks) → `docs/architecture/`
- *How to do X* → `docs/usage.md` and the README quick-start (the project is small enough that a single guide covers it)
- *What changed in version N* → `CHANGELOG.md`
- *What's done / next / future* → `docs/development/roadmap.md`

## Index

| # | Title | Status | Date | Hook |
|---|---|---|---|---|
| [0001](0001-port-from-rust-to-cyrius.md) | Port from Rust to Cyrius | Accepted | 2026-04-08 | Vidya documents Cyrius; vidya itself should be written in Cyrius. Retires the v1.x Rust crate, vendors the source to `rust-old/`, vidya becomes a Cyrius CLI binary. |
| [0002](0002-vyakarana-2x-streaming-api.md) | Adopt vyakarana 2.x streaming tokenizer API | Accepted | 2026-05-16 | vyakarana 2.0 removed `tokenize_source` in favor of streaming primitives (ADR 0017 on the vyakarana side). Vidya's two consumers migrated to `tokenize_stream_new` / `_feed` / `_finish` / `_free` at v2.7.1. Output is byte-identical to the 1.x integration. |
