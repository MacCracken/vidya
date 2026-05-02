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
    ├── language.cyml
    ├── types.cyml
    ├── dependencies.cyml
    ├── ecosystem.cyml
    ├── field_notes/       — practical lessons from real software
    │   ├── compiler/      — per-version-arc files (v3, v4, v5_0_to_5_4, v5_5, v5_6, v5_7, ...)
    │   ├── language/      — per-surface-area files (parser_syntax, semantics_runtime, platform_abi, stdlib_format, diagnostics_caps)
    │   ├── mabda_v3_gpu/  — per-phase files (overview, phase_a, phase_b, phase_c, phase_d, research)
    │   ├── doom.cyml      — single-project topic; flat until it grows
    │   ├── cyim.cyml      — single-project topic; flat until it grows
    │   ├── encom-hits.cyml
    │   ├── kernel.cyml
    │   ├── meta.cyml
    │   └── index.cyml     — file-by-file pointer to every entry
    └── archive/           — historical design log
        └── implementation.cyml   (moved here at v5.6.17)
```

## Migration Rules

1. **Don't reorganize until 50+ topics** — flat is simpler for now
2. **Update loader** — `load_all()` must recurse into subdirectories
3. **Update content paths** — `source_path` in examples changes from `strings/rust.rs` to `fundamentals/strings/rust.rs`
4. **One PR** — reorganize everything in a single atomic move
5. **Update tests** — all hardcoded paths in tests must be updated
6. **Backward compat** — keep old paths as symlinks for one version

## Field-notes subfolder pattern (proven at v2.3.1)

Field-note topics follow a different threshold from the top-level `content/` reorg:
when a single `field_notes/<topic>.cyml` grows past ~800 lines or accumulates
distinct sub-topics, convert it into a folder of chunked `.cyml` files.

- **By version arc** when entries cluster around release timelines
  (`compiler/v3.cyml`, `v4.cyml`, ...).
- **By surface area** when entries cluster around language layers
  (`language/parser_syntax.cyml`, `semantics_runtime.cyml`, ...).
- **By phase** when entries cluster around project milestones
  (`mabda_v3_gpu/phase_a.cyml`, `phase_b.cyml`, ...).

Each chunk file gets a 3-line header (title, one-line scope, entry count) and
the same `[[entries]]` body format. `index.cyml` lists every file with its
entry count and per-entry one-liner.

## Current Topic Count: 36

Trigger threshold: 50 topics. At current pace (~6 topics per release), this is roughly 2-3 releases away if P1 networking topics are added.
