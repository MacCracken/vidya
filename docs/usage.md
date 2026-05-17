# Vidya Usage Guide

## Building

Vidya is a Cyrius program. Build with the Cyrius toolchain:

```sh
cyrius update                          # rehydrate lib/ from the pinned toolchain
cyrius build src/main.cyr build/vidya
```

The binary is ~1.1 MB, statically linked, no runtime dependencies.

## Commands

### List topics

```sh
vidya list
```

Shows all topics with their category and language count:

```
  algorithms [Algorithms] (11 languages)
  allocators [Allocators] (11 languages)
  audio_dsp [Audio] (11 languages)
  ...
74 topics
```

### Search

```sh
vidya search <query>
```

Full-text search across topic IDs, titles, and descriptions:

```sh
vidya search memory
# 5 result(s) for "memory":
#   memory_management — How programs allocate, use, and free memory...
#   virtual_memory — The abstraction that gives every process...
```

### Topic info

```sh
vidya info <topic>
```

Full concept details: description, tags, languages, best practices, gotchas, performance notes:

```sh
vidya info strings
# # Strings
# Topic: DataTypes
# ...
# Best Practices (5):
#   * Know your encoding
# Gotchas (6):
#   ! String vs &str ownership confusion
# Performance Notes (3):
#   ~ Pre-allocate with with_capacity
```

### Render source with token coloring

```sh
vidya code <topic> <lang>
```

Prints the source for `(topic, lang)` with ANSI token coloring via vyakarana — keyword=blue, string=green, number=cyan, comment=dim, operator=magenta, preprocessor=yellow, error=red-bg. Falls back to plain source for languages without a registered grammar (OpenQASM through vyakarana 2.2.1).

```sh
vidya code quantum_computing rust
vidya code lexing_and_parsing cyrius
```

### Compare implementations

```sh
vidya compare <topic> <lang1> <lang2>
```

Side-by-side view of a concept in two languages:

```sh
vidya compare strings rust python
# --- Rust ---
# Vidya — Strings in Rust
# Rust has two primary string types...
#
# --- Python ---
# Vidya — Strings in Python
# Python strings are immutable sequences...
```

Language names: `rust`, `python`, `c`, `go`, `typescript`, `shell`, `zig`, `x86_64`, `aarch64`, `openqasm`, `cyrius`.

### Validate examples

```sh
vidya validate              # all topics, all languages (in-process)
vidya validate strings      # single topic
```

For full CI-grade validation across the 11-language toolchain matrix, run `./scripts/validate-content.sh` — installs are documented in `.github/workflows/ci.yml`.

### Coverage gaps

```sh
vidya gaps
```

Reports missing language implementations per topic. Currently zero (all 74 topics complete across all 11 languages — 814/814).

### Languages

```sh
vidya languages
```

Lists all 11 supported languages with file extensions.

### Stats

```sh
vidya stats
```

Corpus summary:

```
=== Vidya Corpus Stats ===
  Topics:     74
  Complete:   74 (all 11 languages)
  Examples:   814
  Languages:  11
```

### HTTP service

```sh
vidya serve <port>     # 0 = ephemeral port (logged)
```

Memory-resident HTTP service for programmatic consumers (agnoshi, hoosh). Loads the corpus once at startup; routes:

| Route | Returns |
|---|---|
| `GET /stats` | JSON corpus stats |
| `GET /list` | JSON topic index |
| `GET /info/{topic}` | Full concept JSON |
| `GET /search?q=...` | Search hits JSON |
| `GET /code/{topic}/{lang}` | `{topic, language, path, source, tokens:[{kind, start, len}]}` — same vyakarana tokens as the CLI `code` command; theme is consumer's responsibility (palette indexed by kind-name string per vyakarana ADR 0004). |
| `GET /gaps` | Coverage gaps JSON |

## Tracing

Vidya uses [sakshi](https://github.com/MacCracken/sakshi) for structured logging to stderr. Default level is INFO.

```
[timestamp] [INFO] vidya loaded
```

Error messages always display:

```
[timestamp] [ERROR] no content found in content/
```

## Testing

```sh
cyrius test
```

Auto-discovers `.tcyr` files in `tests/`. Tests cover: language enum, TOML loading, section parsing, gotcha field validation, registry operations, file discovery, content scanning.

## Benchmarks

```sh
cyrius bench tests/vidya.bcyr
```

Benchmarks: `load_concept`, `load_all`, `reg_get_hit`, `reg_get_miss`, `search_text`, `toml_sections`. See [`BENCHMARKS.md`](../BENCHMARKS.md) for current numbers.

## Quality

```sh
cyrius check src/main.cyr    # syntax check
cyrius vet src/main.cyr      # audit include dependencies
cyrius deny src/main.cyr     # enforce project policies
cyrius fmt src/main.cyr      # format code
cyrius lint src/main.cyr     # static analysis (per-file in 5.7+)
```

## Content directory

Vidya reads from `content/` relative to the working directory. Each topic is a subdirectory:

```
content/strings/
  concept.toml       # metadata: id, title, topic, description, tags,
                     #   [[best_practices]], [[gotchas]], [[performance_notes]]
  rust.rs            # Rust implementation
  python.py          # Python implementation
  cyrius.cyr         # Cyrius implementation
  ...
```

See [`development/content-format.md`](development/content-format.md) for the full specification.

## Dependencies

- **Build**: `cyrius` (Cyrius toolchain pinned in `cyrius.cyml`)
- **Runtime**: none (static ELF binary)
- **Vendored stdlib**: 81 modules in `lib/` (gitignored under the v5.11.x model — rehydrate with `cyrius update`)
- **Git deps**: sakshi (tracing), vyakarana (tokenizer) — see `[deps.*]` in `cyrius.cyml`
- **Validate (full)**: requires each language's toolchain (rustc, python3, gcc, go, npx/tsx, bash, zig, aarch64-linux-gnu binutils, qemu-user-static, qiskit, cyrius). Missing toolchains are skipped by `validate-content.sh`.
