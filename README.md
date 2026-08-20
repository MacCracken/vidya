# Vidya

> **विद्या** (Sanskrit: knowledge, learning) — Programming reference library and queryable corpus

Vidya is a curated, tested, multi-language programming reference for the AGNOS ecosystem. Every concept includes best practices, gotchas, performance discoveries, and reference implementations — all verified by CI.

## Two Layers

1. **Content** (`content/`) — Source files per topic. No compilation needed. Read directly, train AI on it, or browse as documentation.

2. **Cyrius CLI** (`src/main.cyr`) — Compiled to `build/vidya` (current size in [`docs/development/state.md`](docs/development/state.md)). Queryable interface for the corpus: `list`, `search`, `info`, `compare`, `code`, `gaps`, `stats`, `languages`, `validate`, `serve`. (Migrated from a Rust crate at v2.0.)

## Features

- **Best Practices** — The right way to do things, with explanations of *why*
- **Gotchas** — Common mistakes with bad/good examples. What NOT to do and what to do instead
- **Performance Notes** — Optimization discoveries with evidence (benchmarks, complexity analysis)
- **Multi-Language** — Same concept implemented in 11 languages: Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 Assembly, AArch64 Assembly, OpenQASM, Cyrius
- **Tested** — Every code example compiles and runs. CI validates all implementations via `scripts/validate-content.sh`
- **Queryable** — CLI commands for search, cross-language compare, gap analysis; HTTP service via `vidya serve` for programmatic consumers (agnoshi, hoosh)

## Quick Start

Build the CLI:

```bash
cyrius lib sync                        # vendor the pinned stdlib into lib/
cyrius deps                            # resolve the [deps.*] git deps
cyrius build src/main.cyr build/vidya
```

Use it:

```bash
build/vidya stats                          # 77 topics, 847 examples, 11 langs
build/vidya list                           # browse all topics
build/vidya search "quantum"               # text search across the corpus
build/vidya info quantum_computing         # full record: practices, gotchas, perf notes
build/vidya code quantum_computing rust    # ANSI-colored source via vyakarana
build/vidya compare strings rust python    # side-by-side cross-language view
build/vidya gaps                           # coverage gaps (currently none — 847/847)
build/vidya serve 8080                     # HTTP service: GET /stats, /code/{topic}/{lang}, ...
```

## Content Topics

77 topics, complete across all 11 languages (847 examples). Browse `content/` directly or run `vidya list` to see the index. Roadmap and per-priority breakdown live in [`docs/development/roadmap.md`](docs/development/roadmap.md).

## Languages

| Language | Extension | Notes |
|----------|-----------|-------|
| Cyrius | `.cyr` | **Primary**. Vidya itself is written in Cyrius; the corpus is the live reference for Cyrius/AGNOS patterns. |
| Rust | `.rs` | Full coverage, edition 2024. |
| Python | `.py` | Full coverage, stdlib only. |
| C | `.c` | C23 with `_GNU_SOURCE`. |
| Go | `.go` | Full coverage. |
| TypeScript | `.ts` | Node.js runtime via `tsx`. |
| Shell | `.sh` | Bash with `set -euo pipefail`. |
| Zig | `.zig` | Zig 0.16. |
| x86_64 ASM | `.s` | Intel syntax, Linux syscalls. |
| AArch64 ASM | `.s` | ARM64, Linux syscalls via `svc`. |
| OpenQASM | `.qasm` | Quantum assembly (QASM 2.0). |

## Validation

```bash
# The gate: validate all content examples across every installed toolchain
./scripts/validate-content.sh

# The quick diagnostic: same commands, from the CLI, filterable by topic
./build/vidya validate
./build/vidya validate compression

# Run the Cyrius test suite for the CLI itself
cyrius test

# Run benchmarks
cyrius bench
```

`scripts/validate-content.sh` is the **authoritative gate** — it is what CI runs and what a release blocks on. Per-language commands and the diagnostic contract are documented in the script header.

`vidya validate` is a **diagnostic surface** over the same commands: it reuses the loaded registry, so it can be filtered to one topic and needs no shell loop. Both skip languages whose toolchain isn't installed (counted separately, and named in the CLI's output); CI installs the full set. If the two ever disagree, the script wins and the CLI has a bug — that has happened, see the `validate` entry in [CHANGELOG.md](CHANGELOG.md).

## Consumers

- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- **sandhi** — vidya's HTTP service runs on sandhi (cyrius stdlib)
- **sakshi** — vidya uses sakshi for structured tracing

## License

GPL-3.0-only
