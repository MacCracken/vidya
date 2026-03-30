# Content Format Specification

## Directory Structure

Each topic lives in its own directory under `content/`:

```
content/{topic}/
├── concept.toml       # Required: structured metadata (parsed by loader)
├── rust.rs            # Rust implementation
├── python.py          # Python implementation
├── c.c                # C implementation
├── go.go              # Go implementation
├── typescript.ts      # TypeScript implementation
├── shell.sh           # Shell (Bash) implementation
├── zig.zig            # Zig implementation
├── asm_x86_64.s       # x86_64 Assembly implementation
├── asm_aarch64.s      # AArch64 Assembly implementation
└── openqasm.qasm      # OpenQASM 2.0 quantum circuit
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

`DataTypes`, `Concurrency`, `ErrorHandling`, `MemoryManagement`, `InputOutput`, `Testing`, `Algorithms`, `Patterns`, `TypeSystems`, `Performance`, `Security`, `KernelTopics`, `QuantumComputing`

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

Named by language (`rust.rs`, `python.py`, `asm_x86_64.s`, `openqasm.qasm`, etc.).

Requirements:
- Must compile/run successfully with the validation command
- Leading comments are extracted as the `explanation` field
- Should demonstrate all concepts described in `concept.toml`
- Must be self-contained (no external dependencies beyond stdlib)
- Must end by printing "All {topic} examples passed." (except OpenQASM)

### Language-Specific Notes

| Language | Compiler/Runner | Flags |
|----------|----------------|-------|
| Rust | `rustc --edition 2024` | |
| Python | `python3` | |
| C | `gcc -std=c17 -Wall -Werror` | `-lm -lpthread` |
| Go | `go run` | |
| TypeScript | `npx tsx` | |
| Shell | `bash` | `set -euo pipefail` |
| Zig | `zig build-exe` or `zig run` | Zig 0.15 |
| x86_64 ASM | `as --64` + `ld` | Intel syntax (`.intel_syntax noprefix`) |
| AArch64 ASM | `aarch64-linux-gnu-as` + `ld` | Cross-compiled, run via `qemu-aarch64` |
| OpenQASM | Native Rust parser or `qiskit` | `OPENQASM 2.0; include "qelib1.inc";` |

### Explanation Extraction

The loader reads consecutive comment lines from the top of the file as the explanation. Shebangs are skipped.

```rust
// Vidya — Strings in Rust        ← extracted
//                                 ← blank line preserved
// Rust has two string types.      ← extracted

fn main() { }                     ← stops here
```

### OpenQASM Notes

- Use `OPENQASM 2.0` (not 3.0)
- Include `qelib1.inc` from the content directory
- Do NOT use `swap` or `cp` gates directly — the qiskit parser doesn't support them. Decompose:
  - `swap a, b` → `cx a,b; cx b,a; cx a,b;`
  - `cp(θ) a, b` → `cu1(θ) a, b;`
