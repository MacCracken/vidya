# Architecture Overview

## Two Layers

Vidya has two complementary layers:

```
┌─────────────────────────────────────────────────┐
│  Content Layer (content/)                       │
│  Markdown docs + source files per topic         │
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
- `concept.md` — Human-readable documentation (not parsed)
- Language files (`rust.rs`, `python.py`, etc.) — Tested implementations

See [content-format.md](../development/content-format.md) for the spec.

### Crate Layer

```
src/
├── lib.rs          # Public API surface
├── concept.rs      # Core types: Concept, Topic, BestPractice, Gotcha, etc.
├── language.rs     # Language enum (Rust, Python, C, Go, TS, Shell, Zig)
├── registry.rs     # In-memory concept store
├── loader.rs       # Reads content/ into Registry
├── search.rs       # Text + tag search with relevance scoring
├── compare.rs      # Cross-language comparison
├── validate.rs     # Compile/run verification of examples
├── error.rs        # VidyaError enum
├── logging.rs      # Tracing-based logging (feature: logging)
└── mcp.rs          # MCP tool integration via bote (feature: mcp)
```

## Data Flow

```
content/strings/concept.toml  ──┐
content/strings/rust.rs        ──┤ loader::load_all()
content/strings/python.py      ──┘        │
                                           ▼
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

| Feature   | Default | Description |
|-----------|---------|-------------|
| `std`     | yes     | Standard library support |
| `logging` | no      | Tracing subscriber with `VIDYA_LOG` env var |
| `mcp`     | no      | MCP tools via bote for AI agent integration |
| `full`    | no      | All features enabled |

## Key Design Decisions

1. **TOML over YAML** — Rust ecosystem native, `toml` crate is lightweight, TOML syntax works well for structured content metadata.

2. **Separate concept.toml from concept.md** — Machine-readable data in TOML, human-readable prose in Markdown. No fragile markdown parsing.

3. **No runtime content directory dependency** — The loader is opt-in. You can build concepts programmatically via `Registry::register()` without any filesystem access.

4. **Feature-gated MCP** — The `bote` dependency is optional. Core library has minimal deps (serde, thiserror, tracing).

5. **Validation via subprocess** — Examples are validated by invoking the real compiler/interpreter. No language-specific parsing or emulation.
