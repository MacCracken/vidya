# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-04-08
>
> **Version**: 1.6.0 (Cyrius port) | **Topics**: 36 (15 complete, 21 partial)
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 255 | **Binary**: 85KB Cyrius ELF
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Current State

### Complete Topics (15) — all 11 languages

algorithms, concurrency, design_patterns, error_handling, input_output, iterators,
kernel_topics, memory_management, pattern_matching, performance, quantum_computing,
security, strings, testing, type_systems

### Partial Topics (20) — Rust + Python + C + Cyrius minimum, some with Go/TS/Zig/ASM

| Topic | Langs | Have | Missing |
|-------|-------|------|---------|
| compiler_bootstrapping | 6 | Rust, Python, C, Go, Cyrius, x86 ASM | TS, Shell, Zig, AArch64, QASM |
| lexing_and_parsing | 6 | Rust, Python, C, Go, TypeScript, Cyrius | Shell, Zig, x86, AArch64, QASM |
| allocators | 6 | Rust, Python, C, Go, Zig, Cyrius | TS, Shell, x86, AArch64, QASM |
| code_generation | 5 | Rust, Python, C, Go, Cyrius | TS, Shell, Zig, x86, AArch64, QASM |
| binary_formats | 5 | Rust, Python, C, Cyrius, x86 ASM | Go, TS, Shell, Zig, AArch64, QASM |
| syscalls_and_abi | 5 | Rust, Python, C, Go, Cyrius | TS, Shell, Zig, x86, AArch64, QASM |
| linking_and_loading | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| intermediate_representations | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| optimization_passes | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| instruction_encoding | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| elf_and_executable_formats | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| boot_and_startup | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| virtual_memory | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| interrupt_handling | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| process_and_scheduling | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| filesystems | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| ownership_and_borrowing | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| trait_and_typeclass_systems | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| macro_systems | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |
| module_systems | 4 | Rust, Python, C, Cyrius | Go, TS, Shell, Zig, x86, AArch64, QASM |

### Minimal (1 language)

| Topic | Langs | Notes |
|-------|-------|-------|
| tracing | 1 | Cyrius only — sakshi patterns |

---

## P0 — Complete Partial Topics to 11/11

Fill remaining languages for the 20 partial topics. Priority order by applicability:

**Tier 1 — Add Go + Zig** (systems-relevant, broadly applicable):
- Go: compiler_bootstrapping, code_generation, syscalls_and_abi, linking_and_loading, intermediate_representations, optimization_passes, instruction_encoding, elf_and_executable_formats, virtual_memory, interrupt_handling, process_and_scheduling, filesystems, ownership_and_borrowing, trait_and_typeclass_systems, macro_systems, module_systems
- Zig: compiler_bootstrapping, lexing_and_parsing, code_generation, syscalls_and_abi, binary_formats, boot_and_startup + all others

**Tier 2 — Add TypeScript + Shell** (where applicable):
- TypeScript: allocators (sim), code_generation, optimization_passes, ownership_and_borrowing, trait_and_typeclass_systems, macro_systems, module_systems, lexing_and_parsing (done)
- Shell: scripting patterns for build/test/deploy topics

**Tier 3 — Add x86_64 ASM + AArch64 ASM** (systems/compiler topics):
- x86 ASM: syscalls_and_abi, instruction_encoding, boot_and_startup, interrupt_handling, code_generation
- AArch64 ASM: same topics, cross-platform coverage

**Tier 4 — Add OpenQASM** (quantum-adjacent topics only):
- Only where quantum computing concepts genuinely apply

**Tier 5 — Expand tracing topic**:
- Add Rust, Python, C, Go implementations for tracing/observability concepts

---

## P0A — Infrastructure (Done / Remaining)

| Item | Status | Notes |
|------|--------|-------|
| ~~docs/sources.md~~ | **Done** | Created 2026-04-08 |
| ~~Cyrius as 11th language~~ | **Done** | Language::Cyrius added, 20 content files |
| ~~Cyrius port~~ | **Done** | src/main.cyr, 85KB binary, sakshi integrated |
| ~~.tcyr tests~~ | **Done** | tests/vidya.tcyr — 37 tests |
| ~~.bcyr benchmarks~~ | **Done** | tests/vidya.bcyr — 6 benchmarks |
| ~~BENCHMARKS.md~~ | **Done** | Cyrius vs Rust comparison with charts |
| ~~docs/usage.md~~ | **Done** | CLI usage guide |
| Content grouping plan | Remaining | Plan subdirectory structure for 50+ topics |
| Cross-references | Remaining | Add related_topics field to concept.toml |
| Learning paths | Remaining | Compiler path, OS path, networking path |
| Validate coverage gaps | Remaining | vidya validate should report missing langs |

---

## P1 — New Topics (Networking & Infrastructure)

| Topic | Description | Priority |
|-------|-------------|----------|
| **networking_fundamentals** | TCP/UDP, sockets, connection lifecycle, non-blocking I/O | High |
| **http_and_web_protocols** | HTTP/1.1, HTTP/2, HTTP/3/QUIC, WebSocket, request lifecycle | High |
| **tls_and_encryption** | TLS handshake, certificate chains, cipher suites, AEAD | High |
| **dns** | Resolution, record types, caching, DNSSEC | Medium |
| **ipc** | Shared memory, pipes, Unix sockets, message passing, D-Bus | High |
| **serialization** | Serde patterns, protobuf, flatbuffers, zero-copy parsing | High |

---

## P2 — New Topics (Database & Distributed Systems)

| Topic | Description | Priority |
|-------|-------------|----------|
| **database_fundamentals** | SQL, query planning, indexing, B-trees, LSM trees | Medium |
| **transactions_and_acid** | ACID, isolation levels, MVCC, write-ahead logging | Medium |
| **consensus** | Raft, Paxos, Byzantine fault tolerance, leader election | Medium |
| **distributed_systems** | CAP theorem, partitioning, replication, CRDTs | Medium |

---

## P3 — New Topics (Graphics, Audio, AI)

| Topic | Description | Priority |
|-------|-------------|----------|
| **gpu_programming** | Compute shaders, Vulkan basics, GPU memory model | Medium |
| **render_pipelines** | Vertex/fragment shaders, rasterization, ray tracing | Medium |
| **audio_dsp** | FFT, convolution, filters, sampling theory, Nyquist | Medium |
| **audio_synthesis** | Oscillators, envelopes, FM, wavetable synthesis | Medium |
| **neural_networks** | Forward/backward pass, gradient descent, activations | Medium |
| **inference** | Quantization, batching, KV cache, attention | Medium |
| **embeddings** | Vector representations, similarity search | Low |

---

## P4 — New Topics (Build Systems & Package Management)

| Topic | Description | Priority |
|-------|-------------|----------|
| **build_systems** | Dependency graphs, incremental compilation, caching | Medium |
| **package_resolution** | SAT solving, version constraints, lockfiles | Medium |
| **reproducible_builds** | Deterministic output, content-addressed storage | Low |

---

## P5 — New Topics (Functional Programming & Type Theory)

| Topic | Description | Priority |
|-------|-------------|----------|
| **functional_patterns** | Monads, functors, applicatives, ADTs | Low |
| **effect_systems** | Algebraic effects, capability passing | Low |
| **dependent_types** | Type-level programming, refinement types | Low |

---

## P6 — Cyrius-Specific Topics

| Topic | Description | Priority |
|-------|-------------|----------|
| **cyrius_basics** | Language syntax, types, control flow | Future |
| **cyrius_bootstrap** | Multi-stage compilation, seed retirement | Future |
| **cyrius_agents** | Agent types as language primitives | Future |
| **cyrius_capabilities** | Capability annotations, sandbox enforcement | Future |
| **cyrius_ipc** | IPC as language-level constructs | Future |

---

## Language Coverage

| Language | Complete | Partial | Total | Target |
|----------|----------|---------|-------|--------|
| Rust | 15 | 21 | 36 | 36+ |
| Python | 15 | 20 | 35 | 36+ |
| C | 15 | 20 | 35 | 36+ |
| Go | 15 | 5 | 20 | 30+ |
| TypeScript | 15 | 1 | 16 | 25+ |
| Shell | 15 | 0 | 15 | 25+ |
| Zig | 15 | 1 | 16 | 30+ |
| x86_64 ASM | 15 | 2 | 17 | 25+ |
| AArch64 ASM | 15 | 0 | 15 | 25+ |
| OpenQASM | 15 | 0 | 15 | 20+ |
| Cyrius | 15 | 20 | 35 | 36+ |

---

## Relationship to AGNOS

Vidya feeds directly into the ecosystem:
- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- **sakshi** — vidya uses sakshi for tracing, documents tracing patterns
- **docs/sources.md** standard — vidya IS the source citation for programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-04-08*
