# Content Grouping Plan

> When topic count exceeds ~50, reorganize content/ into subdirectories.
> Until then, the flat structure is simpler.

## Proposed Structure

```
content/
├── fundamentals/          — language-agnostic programming concepts
│   ├── strings/
│   ├── error_handling/
│   ├── concurrency/
│   ├── memory_management/
│   ├── iterators/
│   ├── pattern_matching/
│   ├── type_systems/
│   ├── testing/
│   ├── performance/
│   ├── security/
│   ├── design_patterns/
│   ├── algorithms/
│   ├── input_output/
│   └── tracing/
│
├── compiler/              — compilation pipeline
│   ├── lexing_and_parsing/
│   ├── intermediate_representations/
│   ├── optimization_passes/
│   ├── code_generation/
│   ├── instruction_encoding/
│   ├── linking_and_loading/
│   ├── compiler_bootstrapping/
│   ├── binary_formats/
│   └── elf_and_executable_formats/
│
├── systems/               — OS and low-level programming
│   ├── boot_and_startup/
│   ├── virtual_memory/
│   ├── interrupt_handling/
│   ├── process_and_scheduling/
│   ├── filesystems/
│   ├── syscalls_and_abi/
│   ├── kernel_topics/
│   └── allocators/
│
├── languages/             — programming language design concepts
│   ├── ownership_and_borrowing/
│   ├── trait_and_typeclass_systems/
│   ├── macro_systems/
│   └── module_systems/
│
├── quantum/               — quantum computing
│   └── quantum_computing/
│
├── networking/            — (P1, future)
├── data/                  — (P2, future)
├── graphics/              — (P3, future)
└── cyrius/                — Cyrius-specific (P6, future)
    ├── language.toml
    ├── types.toml
    ├── implementation.toml
    └── ecosystem.toml
```

## Migration Rules

1. **Don't reorganize until 50+ topics** — flat is simpler for now
2. **Update loader** — `load_all()` must recurse into subdirectories
3. **Update content paths** — `source_path` in examples changes from `strings/rust.rs` to `fundamentals/strings/rust.rs`
4. **One PR** — reorganize everything in a single atomic move
5. **Update tests** — all hardcoded paths in tests must be updated
6. **Backward compat** — keep old paths as symlinks for one version

## Current Topic Count: 36

Trigger threshold: 50 topics. At current pace (~6 topics per release), this is roughly 2-3 releases away if P1 networking topics are added.
