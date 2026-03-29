# Content Format Specification

## Directory Structure

Each topic lives in its own directory under `content/`:

```
content/{topic}/
├── concept.toml     # Required: structured metadata (parsed by loader)
├── concept.md       # Optional: human-readable documentation
├── rust.rs          # Language implementation (one per language)
├── python.py
├── c.c
├── go.go
├── typescript.ts
├── shell.sh
└── zig.zig
```

## concept.toml

Machine-readable metadata. This is the source of truth for the `Concept` struct.

### Required Fields

| Field         | Type   | Description                                    |
|---------------|--------|------------------------------------------------|
| `id`          | String | Unique identifier (lowercase, underscores)     |
| `title`       | String | Human-readable title                           |
| `topic`       | String | Topic enum variant (see below)                 |
| `description` | String | One-paragraph description                      |

### Optional Fields

| Field               | Type              | Description                         |
|---------------------|-------------------|-------------------------------------|
| `tags`              | Array of strings  | Search tags                         |
| `best_practices`    | Array of tables   | Best practice entries               |
| `gotchas`           | Array of tables   | Gotcha entries                      |
| `performance_notes` | Array of tables   | Performance note entries            |

### Topic Values

`DataTypes`, `Concurrency`, `ErrorHandling`, `MemoryManagement`, `InputOutput`, `Testing`, `Algorithms`, `Patterns`, `TypeSystems`, `Performance`, `Security`

### Entry Formats

**best_practices:**
```toml
[[best_practices]]
title = "Short title"
explanation = "Why this is the right approach."
language = "Rust"  # Optional: omit for universal advice
```

**gotchas:**
```toml
[[gotchas]]
title = "Short title"
explanation = "What goes wrong and why."
bad_example = "let c = s[0];"     # Optional but strongly recommended
good_example = "let c = s.chars().nth(0);"  # Optional but strongly recommended
language = "Rust"  # Optional: omit for universal gotchas
```

**performance_notes:**
```toml
[[performance_notes]]
title = "Short title"
explanation = "What the improvement is and when it applies."
evidence = "~40% fewer allocations"  # Optional but recommended
language = "Rust"  # Optional: omit for universal notes
```

## Language Files

Named `{language}.{extension}` (e.g. `rust.rs`, `python.py`).

Requirements:
- Must compile/run successfully with the validation command
- Leading comments are extracted as the `explanation` field
- Should demonstrate all concepts described in `concept.toml`
- Must be self-contained (no external dependencies beyond std lib)

### Explanation Extraction

The loader reads consecutive comment lines from the top of the file as the explanation. Shebangs are skipped.

```rust
// Vidya — Strings in Rust        ← extracted
//                                 ← blank line preserved
// Rust has two string types.      ← extracted

fn main() { }                     ← stops here
```

## concept.md

Optional human-readable documentation. **Not parsed by the loader** — exists for:
- Humans reading the content directory directly
- AI training on the corpus
- Extended prose that doesn't fit in TOML fields
