# Vidya — Claude Code Instructions

## Project Identity

**Vidya** (Sanskrit: विद्या — knowledge, learning) — Programming reference library and queryable corpus

- **Type**: Cyrius CLI binary + content directory (no longer a Rust crate; migrated at v2.0)
- **License**: GPL-3.0-only
- **Cyrius pin**: 5.11.55 (`cyrius.cyml`)
- **Version**: SemVer; canonical source is `VERSION` (read by `cyrius.cyml` via `${file:VERSION}`)
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Philosophy**: [AGNOS Philosophy & Intention](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md)
- **Recipes**: [zugot](https://github.com/MacCracken/zugot) — takumi build recipes

## Consumers

- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- **sandhi** — vidya's HTTP service runs on sandhi (cyrius stdlib)
- **sakshi** — vidya uses sakshi for structured tracing
- All AGNOS developers — vidya is the programming reference for the ecosystem

## What This Is

Vidya is both a curated programming reference and the Cyrius CLI that serves it:

1. **Content directory** (`content/`) — TOML-per-topic metadata + source files in 11 languages. Humans read it, AI trains on it.
2. **Cyrius CLI** (`src/main.cyr`) — Queryable interface (`list`, `search`, `info`, `compare`, `gaps`, `stats`, `languages`, `validate`, `serve`). Built with the cyrius toolchain into `build/vidya` (~600KB static ELF).

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
├── openqasm.qasm      # Tested OpenQASM 2.0 quantum circuit
└── cyrius.cyr         # Tested Cyrius implementation
```

**Cyrius is the primary content language** — vidya itself is written in Cyrius, and the corpus is the live reference for Cyrius/AGNOS patterns. Design the cyrius reference first when adding a new topic, then port to the other 10.

## Toolchains — which tool for which surface

Vidya has two distinct surfaces, each with its own toolchain. Do not cross the streams.

**Surface 1 — the vidya project itself.** Cyrius source under `src/`, `lib/`, `tests/`. Build/test/lint with the cyrius toolchain only.

**Surface 2 — the content corpus.** 11 languages under `content/`. Each example is validated with that language's native toolchain by `scripts/validate-content.sh`.

### Surface 1: vidya project (Cyrius)

| Action | Command | Notes |
|---|---|---|
| Resolve deps | `cyrius deps` | Reads `cyrius.cyml`, refreshes vendored stdlib + sakshi |
| Verify lock | `cyrius deps --verify` | Checks `cyrius.lock` SHAs (sakshi 2.0.0) |
| Build binary | `cyrius build src/main.cyr build/vidya` | Output: ~600KB static ELF |
| Run program | `cyrius run <file.cyr>` | Compile + run in one step (also used by content validator for `cyrius.cyr` examples) |
| Run tests | `cyrius test` | Runs `tests/vidya.tcyr` |
| Run benchmarks | `cyrius bench` | Runs `tests/vidya.bcyr` |
| Format | `cyrius fmt <file>` | **Per-file in 5.7+** (no recursive sweep flag) |
| Lint | `cyrius lint <file>` | **Per-file in 5.7+** |

**Never run `cargo`, `clippy`, `rustc`, `cargo-audit`, or `cargo-deny` against the project.** Those are stale references from the pre-2.0 Rust era. (Rust still appears as a *content* language — see Surface 2.)

### Surface 2: content corpus (per-language validators)

`scripts/validate-content.sh` is the gate. It detects available toolchains and skips missing ones; CI runs with the full set installed. Per-language commands:

| Language | File ext | Validation command |
|---|---|---|
| Rust | `.rs` | `rustc --edition 2024 <file> -o X && X` |
| Python | `.py` | `python3 <file>` |
| C | `.c` | `gcc -std=c17 -Wall -Werror <file> -lm -lpthread -o X && X` |
| Go | `.go` | `go run <file>` |
| TypeScript | `.ts` | `npx tsx <file>` |
| Shell | `.sh` | `bash <file>` |
| Zig | `.zig` | `zig build-exe <file> -femit-bin=X && X` |
| x86_64 ASM | `.s` | `as --64 <file> -o X.o && ld X.o -o X && X` |
| AArch64 ASM | `.s` | `aarch64-linux-gnu-as` + `aarch64-linux-gnu-ld` + `qemu-aarch64` |
| OpenQASM | `.qasm` | `python3 -c "from qiskit import qasm2; qasm2.load(...)"` |
| Cyrius | `.cyr` | `cyrius run <file>` |

### Aggregate scripts

| Script | What it does |
|---|---|
| `scripts/validate-content.sh` | Runs every example in every language; prints `X/Y green` summary; non-zero exit on any failure. |
| `scripts/bench-history.sh` | Snapshots `cyrius bench` output to `target/bench-history/<ts>-<sha>.txt` for diff. |
| `scripts/version-bump.sh` | Bumps `VERSION` — single source of truth; `cyrius.cyml` reads `${file:VERSION}`. |

## Key Types

- `Concept` — A programming topic with examples, best practices, gotchas, performance notes
- `Topic` — Programming topic IDs (currently 60; see `docs/development/roadmap.md` for status)
- `Gotcha` — Common mistake with bad/good example (teaches what NOT to do)
- `PerformanceNote` — Optimization insight with evidence (benchmark numbers)
- `BestPractice` — The right way, with explanation of why
- `Registry` — In-memory concept store with lookup/search
- `Comparison` — Side-by-side cross-language view
- `Language` — Supported language enum (11: Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)

## Content Standards

- Every concept MUST have: description, at least one best practice, at least one gotcha, at least one performance note
- Every code example MUST compile/run successfully (`scripts/validate-content.sh` is the gate)
- Gotchas MUST include both bad and good examples
- Performance notes SHOULD include evidence (benchmark numbers or complexity)
- Best practices explain WHY, not just WHAT
- Content is instructional — write for someone learning, not someone who already knows

## Development Process

### P(-1): Scaffold Hardening (before any new features)

0. Read roadmap, CHANGELOG, and open issues — know what was intended before auditing what was built
1. `cyrius test` + `cyrius bench` sweep of existing tests/benchmarks
2. Cleanliness check: `cyrius lint src/main.cyr`, `cyrius fmt src/main.cyr` (per-file as needed), `scripts/validate-content.sh` (content)
3. Get baseline benchmarks (`./scripts/bench-history.sh`)
4. Internal deep review — gaps, correctness, documentation quality
5. External research — better examples, newer best practices, more complete gotchas?
6. Cleanliness check — must be clean after review
7. Additional tests/benchmarks from findings
8. Post-review benchmarks — prove the wins
9. Documentation audit — ADRs, source citations, guides, examples
10. Repeat if heavy

### Work Loop (continuous)

1. Work phase — new concepts, new languages, improvements
2. Cleanliness check: `cyrius lint src/main.cyr` (if Cyrius source touched), `scripts/validate-content.sh` (if content touched)
3. Test additions for new content; bench additions for code paths
4. Run benchmarks (`./scripts/bench-history.sh`)
5. Internal review — correctness, completeness, instructional quality
6. Cleanliness check — must be clean after review
7. Deeper tests from review
8. Run benchmarks again — prove the wins
9. If review heavy → return to step 5
10. Documentation — update CHANGELOG, roadmap, ADRs for design decisions, source citations for algorithms/references, update `docs/sources.md`, verify recipe version in zugot
11. Version check — `VERSION`, `cyrius.cyml` (via `${file:VERSION}`), zugot recipe all in sync
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
- Zero unwrap/panic in library code (Cyrius equivalent: check sentinel returns from every fallible stdlib call)
- **Every code example must compile and run** — content is tested, not decorative
- **Cite sources** — algorithm references, language spec versions, textbook citations in `docs/sources.md`
- **Memory-resident corpus** — `cmd_serve` loads concepts once at startup; never re-parse per request
- **Field-note recurring pain** — when the same gotcha bites in 3+ ports, promote it to `content/cyrius/field_notes/` (split pattern established at v2.3.1)

## DO NOT

- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- **Never run `cargo` / `clippy` / `rustc` (project) / `cargo-audit` / `cargo-deny` against the project** — vidya migrated off Rust at v2.0. Rust survives only as a content language, validated via `rustc` *per-file* in `scripts/validate-content.sh`.
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
