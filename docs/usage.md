# Vidya Usage Guide

## Building

Vidya is a Cyrius program. Build with the Cyrius toolchain:

```sh
cyrius lib sync                        # vendor the pinned stdlib into lib/
cyrius deps                            # resolve the [deps.*] git deps
cyrius build src/main.cyr build/vidya
```

The binary is statically linked with no runtime dependencies; the current size is recorded in [`development/state.md`](development/state.md).

## Commands

### Topic ids

A topic lives at `content/<group>/<topic>/`, and its id is that path: `fundamentals/strings`, `compilers/lexing_and_parsing`. Every command and route takes the full id. A bare name such as `strings` (the 2.x id) is not found; the error names the topic it probably meant:

```
error: topic not found: strings (did you mean fundamentals/strings?)
```

### List topics

```sh
vidya list              # every group and its topics
vidya list languages    # one group
```

Groups print in reading order, each with its title and topic count:

```
fundamentals — Fundamentals (14 topics)
  fundamentals/algorithms (11 languages)
  fundamentals/concurrency (11 languages)
  ...

80 topics in 14 groups
```

### Search

```sh
vidya search <query>
```

Full-text search across topic IDs, titles, descriptions, and tags:

```sh
vidya search memory
# 5 result(s) for "memory":
#   memory_management — How programs allocate, use, and free memory...
#   virtual_memory — The abstraction that gives every process...
```

Matching is substring-based and **case-insensitive** (ASCII): `tcp`, `TCP`,
and `Tcp` are the same query. Bytes outside ASCII are compared exactly, so a
non-ASCII query matches only an identical byte sequence.

Tags are searched too, which is often the only route to a topic — `interpolation`
is a tag on `fundamentals/strings` but appears in no id, title, or description:

```sh
vidya search interpolation
# 1 result(s) for "interpolation":
#   strings — Text representation and manipulation...
```

A concept matches if the query appears in **any** of the four fields; results
are listed in corpus order, not ranked.

### Topic info

```sh
vidya info <group>/<topic>
```

Full concept details: description, tags, languages, best practices, gotchas, performance notes:

```sh
vidya info fundamentals/strings
# # Strings
# Group: fundamentals — Fundamentals
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
vidya compare <group>/<topic> <lang1> <lang2>
```

Side-by-side view of a concept in two languages:

```sh
vidya compare fundamentals/strings rust python
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
vidya validate                         # all topics, all languages (in-process)
vidya validate fundamentals/strings    # one topic
vidya validate audio                   # one group
```

For full CI-grade validation across the 11-language toolchain matrix, run `./scripts/validate-content.sh` — installs are documented in `.github/workflows/ci.yml`.

### Coverage gaps

```sh
vidya gaps
```

Reports missing language implementations per topic. Currently zero (all 80 topics complete across all 11 languages — 880/880).

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
  Topics:     80
  Complete:   80 (all 11 languages)
  Examples:   880
  Languages:  11
```

### HTTP service

```sh
vidya serve <port>     # 0 = ephemeral port (logged)
```

Memory-resident HTTP service for programmatic consumers (agnoshi, hoosh). Loads the corpus once at startup; routes:

| Route | Returns |
|---|---|
| `GET /stats` (and `/`) | `{groups, topics, complete, examples, languages}` |
| `GET /groups` | `[{id, title, description, topics}]`, in reading order |
| `GET /list` | `[{id, group, languages}]` for every topic |
| `GET /list?group={group}` | The same, for one group (`[]` for an unknown group) |
| `GET /info/{group}/{topic}` | Full concept JSON: `{id, title, group, description, tags, languages, best_practices, gotchas, performance_notes}` (the last three are counts) |
| `GET /search?q=...` | Search hits JSON |
| `GET /languages` | The 11 languages and their extensions |
| `GET /compare?topic={group}/{topic}&left={lang}&right={lang}` | Both sides' presence and paths (`/` in the id may be sent raw or as `%2F`) |
| `GET /code/{group}/{topic}/{lang}` | `{topic, language, path, source, tokens:[{kind, start, len}]}` — same vyakarana tokens as the CLI `code` command; theme is consumer's responsibility (palette indexed by kind-name string per vyakarana ADR 0004). The last segment is the language; the rest is the topic id. |
| `GET /gaps` | Coverage gaps JSON |

Paths in responses (`path` in `/compare` and `/code`) are relative to `content/`: `fundamentals/strings/rust.rs`.

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

Benchmarks: `load_concept`, `load_all`, `reg_get_hit`, `reg_get_miss`, `search_text`, `search_text_exact`, `toml_sections`, and the JSON builders (`json_info_response`, `json_search_response`, `json_list_response`, `field_escaped`, `field_raw_splice`). See [`BENCHMARKS.md`](../BENCHMARKS.md) for current numbers.

## Quality

```sh
cyrius check src/main.cyr    # syntax check
cyrius vet src/main.cyr      # audit include dependencies
cyrius deny src/main.cyr     # enforce project policies
cyrius fmt src/main.cyr      # format code
cyrius lint src/main.cyr     # static analysis (per-file in 5.7+)
```

## Content directory

Vidya reads from `content/` relative to the working directory. Each group is a directory with a `group.toml`, and each topic a directory inside it:

```
content/fundamentals/
  group.toml         # id, title, description, order
content/fundamentals/strings/
  concept.toml       # metadata: id ("fundamentals/strings"), title, description, tags,
                     #   related_topics, [[best_practices]], [[gotchas]], [[performance_notes]]
  rust.rs            # Rust implementation
  python.py          # Python implementation
  cyrius.cyr         # Cyrius implementation
  ...
```

See [`development/content-format.md`](development/content-format.md) for the full specification.

## Dependencies

- **Build**: `cyrius` (Cyrius toolchain pinned in `cyrius.cyml`)
- **Runtime**: none (static ELF binary)
- **Vendored stdlib**: 62 modules in `lib/` (a gitignored build artifact — rehydrate with `cyrius lib sync` then `cyrius deps`; **not** `cyrius update`, which ignores the pin under wrapper drift)
- **Git deps**: vyakarana (tokenizer) only — see `[deps.vyakarana]` in `cyrius.cyml`. sakshi is **not** a git dep: cyrius folds it into the stdlib snapshot as of 6.5.24, so it is declared in `[deps] stdlib`
- **Validate (full)**: requires each language's toolchain (rustc, python3, gcc, go, npx/tsx, bash, zig, aarch64-linux-gnu binutils, qemu-user-static, qiskit, cyrius). Missing toolchains are skipped by `validate-content.sh`.
