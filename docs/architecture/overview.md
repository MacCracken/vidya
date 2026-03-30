# Architecture Overview

## Two Layers

Vidya has two complementary layers:

```
┌─────────────────────────────────────────────────┐
│  Content Layer (content/)                       │
│  150 source files across 15 topics × 10 langs  │
│  Human-readable, AI-trainable, CI-tested        │
└─────────────┬───────────────────────────────────┘
              │ loader module
┌─────────────▼───────────────────────────────────┐
│  Crate Layer (src/)                             │
│  Types, search, compare, validate, MCP tools    │
│  Queryable interface over the content           │
└─────────────────────────────────────────────────┘
```

### Content Layer

Each topic is a directory under `content/` containing:
- `concept.toml` — Structured metadata (parsed by the loader)
- Language files (`rust.rs`, `python.py`, `c.c`, `go.go`, `typescript.ts`, `shell.sh`, `zig.zig`, `asm_x86_64.s`, `asm_aarch64.s`, `openqasm.qasm`) — Tested implementations

See [content-format.md](../development/content-format.md) for the spec.

### Crate Layer

```
src/
├── lib.rs          # Public API surface
├── concept.rs      # Core types: Concept, Topic, BestPractice, Gotcha, etc.
├── language.rs     # Language enum (10 languages)
├── registry.rs     # In-memory concept store
├── loader.rs       # Reads content/ into Registry
├── search.rs       # Text + tag search with relevance scoring
├── compare.rs      # Cross-language comparison
├── validate.rs     # Compile/run verification + native QASM validation
├── error.rs        # VidyaError enum
├── logging.rs      # Tracing-based logging (feature: logging)
└── mcp.rs          # MCP tool integration via bote (feature: mcp)
```

## Data Flow

```
content/strings/concept.toml  ──┐
content/strings/rust.rs        ──┤ loader::load_all()
content/strings/python.py      ──┘        │
  ... (10 language files)                  ▼
                                      Registry
                                      (HashMap<String, Concept>)
                                           │
                         ┌─────────────────┼─────────────────┐
                         ▼                 ▼                 ▼
                    search::search   compare::compare   validate::validate_all
                         │                 │                 │
                         ▼                 ▼                 ▼
                   Vec<SearchResult>   Comparison       Vec<ValidationResult>
```

## Feature Flags

| Feature    | Default | Description |
|------------|---------|-------------|
| `std`      | yes     | Standard library support |
| `logging`  | no      | Tracing subscriber with `VIDYA_LOG` env var |
| `mcp`      | no      | MCP tools via bote for AI agent integration |
| `openqasm` | no      | Native OpenQASM 2.0 validation via Rust parser |
| `full`     | no      | All features enabled |

## Key Design Decisions

1. **TOML over YAML** — Rust ecosystem native, `toml` crate is lightweight, TOML syntax works well for structured content metadata.

2. **Separate concept.toml from language files** — Machine-readable data in TOML, implementations in their native files. No fragile markdown parsing.

3. **No runtime content directory dependency** — The loader is opt-in. You can build concepts programmatically via `Registry::register()` without any filesystem access.

4. **Feature-gated MCP** — The `bote` dependency is optional. Core library has minimal deps (serde, thiserror, tracing).

5. **Validation: native + subprocess** — OpenQASM files are validated natively in Rust (feature `openqasm`). All other languages are validated by invoking their real compiler/interpreter as subprocesses.

6. **10 languages, idiomatic per-language** — Each language file demonstrates concepts using that language's natural idioms. No forced OOP in C, no class hierarchies in Go, quantum circuits in OpenQASM.
