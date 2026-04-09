# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-04-08
>
> **Version**: 2.1.0 | **Topics**: 36 (36 complete — all 11 languages)
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 396 | **Binary**: 85KB Cyrius ELF
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Current State

### All 36 Topics Complete — 11/11 languages each

algorithms, allocators, binary_formats, boot_and_startup, code_generation,
compiler_bootstrapping, concurrency, design_patterns, elf_and_executable_formats,
error_handling, filesystems, input_output, instruction_encoding,
intermediate_representations, interrupt_handling, iterators, kernel_topics,
lexing_and_parsing, linking_and_loading, macro_systems, memory_management,
module_systems, optimization_passes, ownership_and_borrowing, pattern_matching,
performance, process_and_scheduling, quantum_computing, security, strings,
syscalls_and_abi, testing, tracing, trait_and_typeclass_systems, type_systems,
virtual_memory

**396 examples** across **11 languages**: Rust, Python, C, Go, TypeScript, Shell,
Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius

---

## Completed — P0 & P0A

~~P0 — Complete all topics to 11/11 languages~~ **Done** (2026-04-08)

~~P0A — Infrastructure~~ **Done** (2026-04-08):
- docs/sources.md, docs/usage.md, BENCHMARKS.md
- Cyrius as 11th language, Cyrius port (src/main.cyr, 85KB binary)
- Sakshi tracing integration
- .tcyr tests (37), .bcyr benchmarks (6)
- Content grouping plan (docs/development/content-grouping.md)
- Cross-references (related_topics in all 36 concept.toml files)
- Learning paths (docs/development/learning-paths.md)
- Coverage gap reporting (vidya gaps command)

---

## P0B — Service Layer (v2.x)

Vidya as a localhost HTTP service — queryable by humans, agents, and other AGNOS programs without shelling out to the CLI.

| Item | Description | Priority |
|------|-------------|----------|
| **HTTP server** | Localhost JSON API on configurable port. Endpoints: `/search`, `/info/{topic}`, `/compare`, `/list`, `/stats`, `/gaps`, `/languages`. Uses Cyrius `lib/net.cyr` TCP sockets. Static ELF, no runtime deps, resident in memory. | High |
| **JSON responses** | All endpoints return JSON (via `lib/json.cyr`). Structured output for programmatic consumption by agnoshi, hoosh, and external tools. | High |
| **Content hot-reload** | Watch content/ for changes, reload registry without restart. For dev workflow — edit a `.cyr` file, query immediately. | Medium |
| **Marja integration** | When marja (AGNOS HTTP framework) lands, migrate from raw sockets to marja request handling. Same endpoints, cleaner routing. | Future |
| **Bote/MCP integration** | When bote (MCP) supports Cyrius, expose vidya as MCP tools — search, get, compare, list. Agents query vidya through the model context protocol. Replaces the old Rust `src/mcp.rs`. | Future |
| **Memory-resident mode** | `vidya serve` loads all content once, serves from memory. The entire corpus (~400 examples, ~2MB text) fits in RAM alongside the 85KB binary. No disk I/O after startup. | High |

**Design constraints:**
- Single static ELF — no nginx, no Python, no Node
- All-in-memory after startup — RAM8 philosophy
- JSON over HTTP/1.1 — simplest protocol that agents and curl both speak
- Sakshi tracing on all requests — structured observability from day one

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

## Language Coverage — All Targets Met

| Language | Topics | Status |
|----------|--------|--------|
| Rust | 36/36 | Complete |
| Python | 36/36 | Complete |
| C | 36/36 | Complete |
| Go | 36/36 | Complete |
| TypeScript | 36/36 | Complete |
| Shell | 36/36 | Complete |
| Zig | 36/36 | Complete |
| x86_64 ASM | 36/36 | Complete |
| AArch64 ASM | 36/36 | Complete |
| OpenQASM | 36/36 | Complete |
| Cyrius | 36/36 | Complete |

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
