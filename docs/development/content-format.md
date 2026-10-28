# Content Format Specification

## Directory Structure

`content/` holds three kinds of entries — topic directories, the
Cyrius language reference, and shared toolchain resources:

```
content/
├── {topic}/                  # 77× topic directories (see below)
├── cyrius/                   # Cyrius language reference + field notes
│   ├── language/             #   index, stdlib_modules, syntax notes
│   └── field_notes/          #   recurring-pain notes (cyim, compiler, …)
```

`vidya stats` and the topic count in `state.md` refer to the topic directories
only — `cyrius/` is the language-reference subtree (loaded separately
by the field-notes path). Through 2.9.3 a shared `qelib1.inc` sat at the
content root for the OpenQASM 2.0 circuits; OpenQASM 3's `stdgates.inc`
is built into the importer, so 2.9.4 removed it.

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
├── openqasm.qasm      # OpenQASM 3.1 quantum circuit
└── cyrius.cyr         # Cyrius implementation (primary content language)
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
| `tags`              | Array of strings  | Search tags — matched case-insensitively by `vidya search`, alongside `id` / `title` / `description`. Use them for terms a reader would search for that the prose does not contain. |
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
- Every check must be able to fail when the code it demonstrates is wrong.
  An assert that can only compare literals is a comment in a test's clothes,
  and it pads the count of what the example proves. Examples: a constant
  against the literal it was defined as, `len()` of a list written just
  above, arithmetic on literals. Write the fact as a comment beside the
  definition. Checks of the language's or the platform's own behaviour (an
  f-string format, `logging.DEBUG == 10`) are real, and so is an
  `assert False` reached only when a call that must raise did not.

### Language-Specific Notes

| Language | Compiler/Runner | Flags |
|----------|----------------|-------|
| Rust | `rustc --edition 2024` (latest stable) | plus a `--test` pass when the file has tests |
| Python | `$VIDYA_PYTHON` (3.15) | `-X warn_default_encoding -W error::EncodingWarning` |
| C | `gcc -std=c23 -Wall -Werror` | `-lm -lpthread` |
| Go | `gofmt -l`, `go vet`, `go run` | |
| TypeScript | `tsc --noEmit --strict`, then `npx tsx` | `--target es2025 --lib es2025` |
| Shell | `bash` | `set -euo pipefail` |
| Zig | `zig build-exe` or `zig run` | Zig 0.17 |
| x86_64 ASM | `as --64` + `ld` | Intel syntax (`.intel_syntax noprefix`) |
| AArch64 ASM | `aarch64-linux-gnu-as` + `ld` | Cross-compiled, run via `qemu-aarch64` |
| OpenQASM | `scripts/qasm_check.py` (qiskit's OpenQASM 3 importer + qiskit-aer) | `OPENQASM 3.1; include "stdgates.inc";` |

### Explanation Extraction

The loader reads consecutive comment lines from the top of the file as the explanation. Shebangs are skipped.

```rust
// Vidya — Strings in Rust        ← extracted
//                                 ← blank line preserved
// Rust has two string types.      ← extracted

fn main() { }                     ← stops here
```

### OpenQASM Notes

- Use `OPENQASM 3.1;` and `include "stdgates.inc";` (built into the
  importer; there is no file to ship). The corpus moved from 2.0 at 2.9.4:
  `qubit[n] q;` / `bit[n] c;`, `c = measure q;`, `cp` for the old `cu1`,
  `p` for `u1`, `U` for `u3`, and `ctrl @ U(θ, φ, λ)` (or `cry` / `crz` /
  `cp` where they apply) for `cu3`. Avoid `cu`: its phase convention
  differs between qiskit's importer and the reference `stdgates.inc`
  (which adds `p(γ - θ/2)` on the control), so one file would mean two
  different circuits.
- `swap`, `cp` and the other `stdgates.inc` gates are fine to use. The old
  rule against them was a limit of qiskit's 2.0 parser, not of the
  language. A circuit may still spell a gate out to show its cost; say so
  in a comment.
- OpenQASM 3 leaves a declared qubit in an **undefined** state (2.0
  guaranteed |0⟩). The corpus relies on qiskit starting every qubit at
  |0⟩, as hardware backends do. Where a lesson depends on the starting
  state, `reset` first or say so.
- qiskit-qasm3-import 0.6.0 cannot index a register with a `for` loop
  variable, and rejects `uint` declarations, so a loop body cannot use
  its index. Single-bit `if` / `else`, `ctrl(n) @`, `negctrl @`, `inv @`
  and `pow(k) @` all work.
- Names that OpenQASM 3 reserves (`input`, `output`, `in`, `inv`, `ctrl`,
  `box`, …) or that `stdgates.inc` defines (`phase`, …) cannot be register
  names.
- State what a register measures with an `@expect` line, beside the prose
  that says it in words. `scripts/qasm_check.py` checks every one in a
  seeded qiskit-aer simulation:
  - `// @expect <reg> == <int>`: every shot reads this value.
  - `// @expect <reg> in {<int>, ...}`: every shot is in the set, and each
    value occurs.

  A value is the register read as an unsigned integer with bit `[0]` least
  significant, the way `if (c == n)` reads it.
