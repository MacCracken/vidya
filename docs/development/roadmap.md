# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-04-04
>
> **Version**: 1.5.0 | **Topics**: 36 (15 complete, 21 metadata only)
> **Languages**: 10 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM)
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 10 languages.

---

## Current State

### Complete Topics (15) — all 10 languages + concept.toml

algorithms, concurrency, design_patterns, error_handling, input_output, iterators,
kernel_topics, memory_management, pattern_matching, performance, quantum_computing,
security, strings, testing, type_systems

### Metadata Only (21) — concept.toml present, no language files

These topics were scaffolded during Cyrius compiler development. They need language implementations.

| Topic | Domain | Priority |
|-------|--------|----------|
| allocators | Memory | High — bump, arena, slab, buddy |
| binary_formats | Systems | High — ELF headers, segments, minimal binaries |
| boot_and_startup | OS | High — UEFI, multiboot, GDT/IDT, long mode |
| code_generation | Compiler | High — instruction selection, register alloc, stack codegen |
| compiler_bootstrapping | Compiler | High — self-hosting, multi-stage, seed compilers |
| elf_and_executable_formats | Systems | High — sections, DWARF, symbol tables |
| instruction_encoding | Systems | High — x86_64 ModR/M, SIB, REX, machine code |
| intermediate_representations | Compiler | Medium — SSA, CFG, basic blocks, phi nodes |
| lexing_and_parsing | Compiler | High — tokenizers, recursive descent, Pratt parsing |
| linking_and_loading | Systems | Medium — symbol resolution, GOT/PLT, dynamic linking |
| optimization_passes | Compiler | Medium — DCE, constant folding, inlining |
| syscalls_and_abi | OS | High — Linux syscalls, System V AMD64 ABI |
| ownership_and_borrowing | Language | Medium — move semantics, lifetimes, borrow checking |
| trait_and_typeclass_systems | Language | Medium — monomorphization, vtables, coherence |
| macro_systems | Language | Medium — hygiene, declarative vs procedural |
| module_systems | Language | Low — namespacing, visibility, separate compilation |
| filesystems | OS | Medium — VFS, inodes, block allocation, journaling |
| virtual_memory | OS | Medium — page tables, TLB, mmap, demand paging |
| interrupt_handling | OS | Medium — IDT, exception handlers, IRQ routing |
| process_and_scheduling | OS | Medium — task structs, context switching, CFS |

---

## P0A — Crate & Infrastructure Fixes

| Item | Description | Priority |
|------|-------------|----------|
| **Topic enum ↔ content sync** | Verify all 36 content dirs map to a Topic enum variant. `strings` → `DataTypes`? `iterators` → `DataTypes`? `design_patterns` → `Patterns`? Document the mapping or add dedicated variants | High |
| **docs/sources.md** | Create source citations file — language spec versions (Rust Reference, Python 3.x docs, C17 standard, Go spec, ECMAScript spec, POSIX shell, Zig docs, x86_64 ISA, ARM ARM, OpenQASM 2.0 spec), algorithm textbook references, any papers cited in content | High |
| **Content grouping plan** | Document the future subdirectory structure (fundamentals/, languages/, systems/, compiler/, networking/, data/) for when topic count exceeds ~50. Don't reorganize yet — just plan it | Low |
| **Cross-references** | Add `related_topics` field to concept.toml spec — link allocators↔memory_management↔virtual_memory, lexing↔parsing↔code_generation, etc. | Medium |
| **Learning paths** | Define ordered topic sequences: "Build a compiler" (lexing→parsing→IR→codegen→optimization→linking→bootstrap), "OS from scratch" (boot→kernel→virtual_memory→interrupts→process→filesystems→syscalls) | Medium |
| **Validate coverage gaps** | Expand validate.rs to report which topics are missing language implementations, flag stale examples | Medium |

---

## P0 — Complete Existing Topics

Fill language implementations for the 21 metadata-only topics. Rust first, then fan out.

**Order**: Start with topics most relevant to active development:
1. compiler_bootstrapping, lexing_and_parsing, code_generation, instruction_encoding (Cyrius is building these right now)
2. allocators, syscalls_and_abi, boot_and_startup (OS self-hosting)
3. elf_and_executable_formats, binary_formats, linking_and_loading (build pipeline)
4. Everything else

---

## P1 — New Topics (Networking & Infrastructure)

| Topic | Description | Priority |
|-------|-------------|----------|
| **networking_fundamentals** | TCP/UDP, sockets, connection lifecycle, non-blocking I/O | High |
| **http_and_web_protocols** | HTTP/1.1, HTTP/2, HTTP/3/QUIC, WebSocket, request lifecycle | High |
| **tls_and_encryption** | TLS handshake, certificate chains, cipher suites, AEAD | High |
| **dns** | Resolution, record types, caching, DNSSEC | Medium |
| **ipc** | Shared memory, pipes, Unix sockets, message passing, D-Bus | High |
| **serialization** | Serde patterns, protobuf, flatbuffers, zero-copy parsing, JSON/TOML/MessagePack | High |

---

## P2 — New Topics (Database & Distributed Systems)

| Topic | Description | Priority |
|-------|-------------|----------|
| **database_fundamentals** | SQL, query planning, indexing strategies, B-trees, LSM trees | Medium |
| **transactions_and_acid** | ACID properties, isolation levels, MVCC, write-ahead logging | Medium |
| **consensus** | Raft, Paxos, Byzantine fault tolerance, leader election | Medium |
| **distributed_systems** | CAP theorem, partitioning, replication, CRDTs, eventual consistency | Medium |

---

## P3 — New Topics (Graphics, Audio, AI)

| Topic | Description | Priority |
|-------|-------------|----------|
| **gpu_programming** | Compute shaders, Vulkan basics, GPU memory model, dispatch | Medium |
| **render_pipelines** | Vertex/fragment shaders, rasterization, ray tracing fundamentals | Medium |
| **audio_dsp** | FFT, convolution, filters, sampling theory, Nyquist, windowing | Medium |
| **audio_synthesis** | Oscillators, envelopes, FM, wavetable, additive/subtractive | Medium |
| **neural_networks** | Forward/backward pass, gradient descent, activation functions | Medium |
| **inference** | Quantization, batching, KV cache, attention, tokenization | Medium |
| **embeddings** | Vector representations, similarity search, dimensionality reduction | Low |

---

## P4 — New Topics (Build Systems & Package Management)

| Topic | Description | Priority |
|-------|-------------|----------|
| **build_systems** | Dependency graphs, incremental compilation, caching, reproducibility | Medium |
| **package_resolution** | SAT solving, version constraints, lockfiles, diamond dependencies | Medium |
| **reproducible_builds** | Deterministic output, content-addressed storage, build attestation | Low |

---

## P5 — New Topics (Functional Programming & Type Theory)

| Topic | Description | Priority |
|-------|-------------|----------|
| **functional_patterns** | Monads, functors, applicatives, algebraic data types | Low |
| **effect_systems** | Algebraic effects, capability passing, IO monad alternatives | Low |
| **dependent_types** | Type-level programming, proof carrying code, refinement types | Low |

---

## P6 — New Topics (Cyrius-Specific)

When Cyrius matures beyond the assembler stage, vidya should document Cyrius-specific patterns:

| Topic | Description | Priority |
|-------|-------------|----------|
| **cyrius_basics** | Language syntax, types, control flow, modules | Future |
| **cyrius_bootstrap** | Multi-stage compilation, seed retirement, byte-exact verification | Future |
| **cyrius_agents** | Agent types as language primitives, sandbox-aware borrowing | Future |
| **cyrius_capabilities** | Capability annotations, compile-time sandbox enforcement | Future |
| **cyrius_ipc** | IPC as language-level constructs, channel types | Future |

---

## Language Coverage Goals

| Language | Current Topics | Target | Notes |
|----------|---------------|--------|-------|
| Rust | 15/36 | 36/36+ | Primary language — complete coverage required |
| Python | 15/36 | 36/36+ | Full coverage target |
| C | 15/36 | 36/36+ | Critical for OS/systems topics |
| Go | 15/36 | 30+ | Skip low-level OS topics not applicable to Go |
| TypeScript | 15/36 | 25+ | Skip kernel/hardware topics |
| Shell | 15/36 | 25+ | Scripting patterns where applicable |
| Zig | 15/36 | 36/36+ | Strong systems language, full coverage |
| x86_64 ASM | 15/36 | 30+ | Critical for compiler/OS topics |
| AArch64 ASM | 15/36 | 30+ | ARM64 coverage for cross-platform |
| OpenQASM | 15/36 | 20+ | Quantum topics + algorithms where applicable |
| **Cyrius** | 0 | Future | Add when language reaches sufficient maturity |

---

## Crate Improvements

| Item | Description | Priority |
|------|-------------|----------|
| **Topic enum expansion** | Current Topic enum only has 13 variants — needs to cover all 36+ topics | High |
| **Cross-references** | Link related topics (e.g., allocators → memory_management → virtual_memory) | Medium |
| **Difficulty levels** | Tag topics as beginner/intermediate/advanced | Low |
| **Learning paths** | Ordered sequences: "OS from scratch", "Build a compiler", "Networking stack" | Medium |
| **Cyrius language** | Add Cyrius as 11th language when compiler handles basic programs | Future |
| **Interactive mode** | REPL-style query interface via agnoshi integration | Low |
| **Content validation** | Expand validate.rs to catch more issues (missing languages, stale examples) | Medium |

---

## Relationship to AGNOS

Vidya feeds directly into the ecosystem:
- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- **docs/sources.md** standard — vidya IS the source citation for programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-04-04*
