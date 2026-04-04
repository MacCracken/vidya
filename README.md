# Vidya

> **विद्या** (Sanskrit: knowledge, learning) — Programming reference library and queryable corpus

Vidya is a curated, tested, multi-language programming reference for the AGNOS ecosystem. Every concept includes best practices, gotchas, performance discoveries, and reference implementations — all verified by CI.

## Two Layers

1. **Content** (`content/`) — Source files per topic. No compilation needed. Read directly, train AI on it, or browse as documentation.

2. **Crate** (`src/`) — Rust library that makes the content queryable. Types for concepts, search, cross-language comparison, and example validation. `cargo doc` generates a browsable programming reference.

## Features

- **Best Practices** — The right way to do things, with explanations of *why*
- **Gotchas** — Common mistakes with bad/good examples. What NOT to do and what to do instead
- **Performance Notes** — Optimization discoveries with evidence (benchmarks, complexity analysis)
- **Multi-Language** — Same concept implemented in 10 languages: Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 Assembly, AArch64 Assembly, OpenQASM
- **Tested** — Every code example compiles and runs. CI validates all implementations
- **Queryable** — Search, compare across languages, filter by topic or tag

## Quick Start

```rust
use std::path::Path;
use vidya::loader::load_all;
use vidya::search::search;
use vidya::{Language, SearchQuery};

// Load all 33 topics from the content directory
let registry = load_all(Path::new("content")).unwrap();

// Search for concepts
let results = search(&registry, &SearchQuery::text("quantum"));

// Compare implementations across languages
let cmp = vidya::compare::compare(
    &registry,
    "quantum_computing",
    &[Language::Rust, Language::Python, Language::OpenQASM],
).unwrap();

// Browse gotchas
let concept = registry.get("security").unwrap();
for gotcha in &concept.gotchas {
    println!("{}: {}", gotcha.title, gotcha.explanation);
}
```

## Content Topics

| Topic | Description |
|-------|-------------|
| `strings` | Text handling, encoding, interpolation, slicing |
| `error_handling` | Result types, exceptions, error propagation |
| `concurrency` | Threads, async, channels, parallelism |
| `memory_management` | Ownership, borrowing, GC, allocation |
| `iterators` | Lazy evaluation, map/filter/fold, generators |
| `pattern_matching` | Match expressions, destructuring, guards |
| `type_systems` | Generics, traits, interfaces, type inference |
| `testing` | Unit tests, property testing, mocking, coverage |
| `performance` | Profiling, allocation, cache, SIMD, benchmarking |
| `input_output` | Files, streams, buffering, network I/O |
| `security` | Input validation, injection, constant-time, secrets |
| `algorithms` | Search, sort, graphs, dynamic programming, complexity |
| `kernel_topics` | Page tables, interrupts, MMIO, ABIs, bootloaders |
| `quantum_computing` | Grover's, Shor's, VQE, noise models, entanglement |
| `design_patterns` | Builder, strategy, observer, RAII, factory, DI |
| `compiler_bootstrapping` | Self-hosting, multi-stage compilation, seed compilers |
| `binary_formats` | ELF headers, segments, entry points, minimal binaries |
| `lexing_and_parsing` | Tokenizers, recursive descent, Pratt parsing, grammars |
| `code_generation` | Instruction selection, register allocation, stack codegen |
| `intermediate_representations` | SSA, CFG, basic blocks, phi nodes, data flow |
| `optimization_passes` | DCE, constant folding, inlining, strength reduction |
| `linking_and_loading` | Symbol resolution, relocations, GOT/PLT, dynamic linking |
| `syscalls_and_abi` | Linux syscalls, System V AMD64 ABI, calling conventions |
| `instruction_encoding` | x86_64 ModR/M, SIB, REX prefixes, machine code bytes |
| `elf_and_executable_formats` | Sections, DWARF, symbol tables, relocatable objects |
| `allocators` | Bump, arena, slab, buddy allocation strategies |
| `virtual_memory` | Page tables, TLB, mmap, demand paging, huge pages |
| `interrupt_handling` | IDT, exception handlers, IRQ routing, ISR patterns |
| `process_and_scheduling` | Task structs, context switching, CFS, runqueues |
| `filesystems` | VFS, inodes, dentries, block allocation, journaling |
| `ownership_and_borrowing` | Move semantics, lifetimes, borrow checking algorithms |
| `trait_and_typeclass_systems` | Monomorphization, vtables, coherence, associated types |
| `macro_systems` | Hygiene, declarative vs procedural, compile-time codegen |
| `module_systems` | Namespacing, visibility, separate compilation, imports |
| `boot_and_startup` | UEFI, multiboot, GDT/IDT setup, long mode transition |

## Languages

| Language | Extension | Notes |
|----------|-----------|-------|
| Rust | `.rs` | Primary language. Complete coverage. |
| Python | `.py` | Full coverage, stdlib only. |
| C | `.c` | C17 with `_GNU_SOURCE`. |
| Go | `.go` | Full coverage. |
| TypeScript | `.ts` | Node.js runtime via `tsx`. |
| Shell | `.sh` | Bash with `set -euo pipefail`. |
| Zig | `.zig` | Zig 0.15. |
| x86_64 ASM | `.s` | Intel syntax, Linux syscalls. |
| AArch64 ASM | `.s` | ARM64, Linux syscalls via `svc`. |
| OpenQASM | `.qasm` | Quantum assembly (QASM 2.0). |

## Feature Flags

| Feature    | Default | Description |
|------------|---------|-------------|
| `std`      | yes     | Standard library support |
| `logging`  | no      | Tracing subscriber with `VIDYA_LOG` env var |
| `mcp`      | no      | MCP tools via bote for AI agent integration |
| `openqasm` | no      | Native QASM validation (no Python dependency) |
| `full`     | no      | All features enabled |

## Validation

```bash
# Validate all content examples
./scripts/validate-content.sh

# Validate via Rust crate (with native QASM support)
cargo test --features openqasm

# Run benchmarks
cargo bench
```

## License

GPL-3.0-only
