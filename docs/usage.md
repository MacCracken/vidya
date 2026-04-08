# Vidya Usage Guide

## Building

Vidya is a Cyrius program. Build with cc2:

```sh
cat src/main.cyr | cc2 > build/vidya && chmod +x build/vidya
```

Or with cyrb:

```sh
cyrb build src/main.cyr build/vidya
```

The binary is ~85KB, statically linked, no runtime dependencies.

## Commands

### List topics

```sh
vidya list
```

Shows all topics with their category and language count:

```
  strings [DataTypes] (11 languages)
  concurrency [Concurrency] (11 languages)
  allocators [Allocators] (2 languages)
  ...
35 topics
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

Language names: `rust`, `python`, `c`, `go`, `typescript`, `shell`, `zig`, `x86_64`, `aarch64`, `openqasm`, `cyrius`

### Validate examples

```sh
vidya validate              # all topics, all languages
vidya validate strings      # single topic
```

Compiles and runs every language implementation. Reports pass/fail:

```
  PASS: strings/Rust
  PASS: strings/Python
  FAIL: strings/Zig
```

Requires each language's toolchain to be installed. Missing toolchains are skipped.

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
  Topics:     35
  Complete:   14 (all 11 languages)
  Examples:   193
  Languages:  11
```

## Tracing

Vidya uses [sakshi](../sakshi/) for structured logging to stderr. Default level is INFO.

Trace output appears on stderr:

```
[timestamp] [INFO] vidya loaded
```

Error messages use `sakshi_error` and always display:

```
[timestamp] [ERROR] no content found in content/
```

## Testing

Run the test suite:

```sh
cyrb test tests/vidya.tcyr
```

Tests cover: language enum, TOML loading, section parsing, gotcha field validation, registry operations, file discovery, content scanning.

## Benchmarks

Run benchmarks:

```sh
cyrb bench tests/vidya.bcyr
```

Benchmarks: `load_concept`, `load_all`, `reg_get_hit`, `reg_get_miss`, `search_text`, `toml_sections`.

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

See [content-format.md](development/content-format.md) for the full specification.

## Dependencies

- **Build**: cc2 (Cyrius compiler)
- **Runtime**: none (static ELF binary)
- **Vendored stdlib**: 29 modules in `lib/` (string, vec, hashmap, toml, sakshi, etc.)
- **Validate**: requires each language's toolchain (rustc, python3, gcc, go, etc.)
