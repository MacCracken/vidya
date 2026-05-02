# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-02
>
> **Version**: 2.3.4 | **Cyrius**: 5.8.3
> **Topics**: 60 (47 fully covered, 13 still partial — P0C-1+P0C-3 complete, P0C-2/4 remaining)
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 529 source files; concept files: 60
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Current State

### 47 topics — fully covered (11/11 languages each)

**Original 36** — algorithms, allocators, binary_formats, boot_and_startup,
code_generation, compiler_bootstrapping, concurrency, design_patterns,
elf_and_executable_formats, error_handling, filesystems, input_output,
instruction_encoding, intermediate_representations, interrupt_handling,
iterators, kernel_topics, lexing_and_parsing, linking_and_loading,
macro_systems, memory_management, module_systems, optimization_passes,
ownership_and_borrowing, pattern_matching, performance,
process_and_scheduling, quantum_computing, security, strings, syscalls_and_abi,
testing, tracing, trait_and_typeclass_systems, type_systems, virtual_memory

**Added in v2.3.2** — fixed_point_arithmetic

**Added in v2.3.3 — P0C-1 game-engine cluster (8 topics)** — collision_detection_2d,
game_ai_decisions, game_loop_architecture, grid_pathfinding, maze_generation,
projectile_physics, sprite_rendering, state_machines

**Added in v2.3.4 — P0C-3 database cluster (3 topics)** — btree_indexing,
sql_parsing, write_ahead_logging

529 source files across these 47 topics + concept-only stubs. All available
languages green for fully-covered topics.

### 13 topics — still partial coverage

**Graphics cluster (mabda v3 + cyrius-doom) — 9 topics, 0 of 99 non-Cyrius slots filled**
- bindless_resources, bloom_and_glow, direct_drm_gpu_compute,
  explicit_gpu_synchronization, framebuffer_rendering, gpu_memory_pooling,
  line_rasterization, render_graph_architecture, *(sprite_rendering moved
  to fully-covered above)*

**Systems & misc — 4 topics, mixed**
- compression (none), concurrent_file_access (none),
  jsonl_format (none), page_management (Y)

Coverage legend: R/P/C/G/T/S/Z = Rust/Python/C/Go/TS/Shell/Zig,
X/A = x86_64/AArch64 ASM, Q = OpenQASM, Y = Cyrius.

529 examples across 60 topics. Gap to full 11/11 across the remaining 13
topics: **~136 source files** (P0C-2: 99, P0C-4: 37 — see remaining
backfill plan below).

---

## Completed

### P0 — Original 36 topics, 11/11 languages — **Done** (2026-04-08)

### P0A — Infrastructure — **Done** (2026-04-08)
- `docs/sources.md`, `docs/usage.md`, `BENCHMARKS.md`
- Cyrius as 11th language, Cyrius port (`src/main.cyr`, ~85KB binary at the time)
- Sakshi tracing integration
- `.tcyr` tests, `.bcyr` benchmarks
- Content grouping plan (`docs/development/content-grouping.md`)
- Cross-references (`related_topics` in concept files)
- Learning paths (`docs/development/learning-paths.md`)
- Coverage gap reporting (`vidya gaps`)

### P0B — Service Layer (most of it) — **Shipped in v2.3.0** (2026-04-25)

| Item | Status | Notes |
|---|---|---|
| HTTP server | ✅ Shipped | Built on `lib/sandhi.cyr` (Cyrius 5.7.0+) — sandhi replaced the earlier `lib/http_server.cyr`. `cmd_serve(port)` in `src/main.cyr`, default port 8390. |
| JSON responses | ✅ Shipped | All endpoints return JSON via `lib/json.cyr`. |
| Endpoints: `/stats`, `/list`, `/languages`, `/search`, `/info/{topic}` | ✅ Shipped | Five of seven planned routes live. |
| Endpoints: `/compare`, `/gaps` | ⚠️ Pending | CLI commands (`cmd_compare`, `cmd_gaps`) exist but aren't routed in the HTTP handler yet — see P0B-1 below. |
| Memory-resident mode | ❓ Unverified | No explicit hot-cache or registry-preload visible in `cmd_serve`; content is reloaded per-request from disk. Worth a behavior audit (P0B-2). |
| Content hot-reload | ⏳ Future | Not started. Inotify/watch loop would land alongside memory-resident verification. |
| Marja integration | ⏳ Future | Depends on upstream marja landing in AGNOS. |
| Bote/MCP integration | ⏳ Future | Depends on bote supporting Cyrius. Old Rust `src/mcp.rs` retired with the Cyrius port. |

### Field-notes growth pattern — **Established at v2.3.1** (2026-05-01)

Field-note topics over ~800 lines or accumulating distinct sub-topics now
split into per-topic folders. Three axes proven in production:
- **By version arc** — `compiler/v3.cyml`, `v4.cyml`, ... (cyrius compiler)
- **By surface area** — `language/parser_syntax.cyml`, `semantics_runtime.cyml`, ...
- **By phase** — `mabda_v3_gpu/phase_a.cyml`, `phase_b.cyml`, ...

Convention documented in `docs/development/content-grouping.md` § "Field-notes
subfolder pattern (proven at v2.3.1)".

---

## P0B — Service Layer Remaining

### P0B-1 — Wire `/compare` and `/gaps` HTTP endpoints — **Done** (v2.3.4)

`json_compare_response(topic_id, lang1_str, lang2_str)` and
`json_gaps_response()` added to `src/main.cyr`; route matchers
in `http_route` for `/compare?topic=&left=&right=` and `/gaps`.
Smoke-tested via curl: 200 + JSON for happy path, 400 for bad
language or missing params, 404 for missing topic. Path-prefix
matchers added to `tests/vidya.tcyr` (41/41 green).

P0B is now **7-of-7 endpoints live**: `/stats`, `/list`,
`/languages`, `/search`, `/info/{topic}`, `/compare`, `/gaps`.

### P0B-2 — Verify or implement memory-resident mode

`vidya serve` should load content/ once at startup and serve from RAM (a
RAM8 design constraint). Confirm via instrumentation that requests don't
re-read concept files on each hit. If they do, hoist the registry into a
process-lifetime allocation and have handlers read from it. Document the
contract in `docs/architecture/overview.md`.

### P0B-3 — Sakshi request tracing on serve

Per the v2.x design constraints: "Sakshi tracing on all requests." If
that isn't already in place, wrap the connection handler with structured
spans (method, path, status, latency).

### P0B-4 — Content hot-reload (after P0B-2 lands)

Inotify watch on `content/` triggers a registry rebuild without restart.
Useful for the dev workflow — edit a `.cyr` file, query immediately.

---

## P0C — Backfill non-Cyrius coverage on the new topics

The original P0C estimate was ~249 source files across 24 topics. P0C-1
landed in v2.3.2 (`fixed_point_arithmetic`, 9 files) and v2.3.3 (remaining
8 game-engine topics, 78 files). P0C-3 landed in v2.3.4 (3 database topics,
31 files). Remaining: **~136 source files across 13 topics** in clusters
P0C-2 and P0C-4.

### P0C-1 — Game-engine cluster — **Done** (v2.3.2 + v2.3.3)

All 9 game-engine topics now 11/11:
- v2.3.2: fixed_point_arithmetic
- v2.3.3: collision_detection_2d, game_ai_decisions, game_loop_architecture,
  grid_pathfinding, maze_generation, projectile_physics, sprite_rendering,
  state_machines

87 source files added (9 + 78). Cross-language byte parity verified for
the deterministic-PRNG topics (game_ai_decisions, maze_generation): seed=42
produces identical wall bytes / dispatch outputs across all 11 languages.

### P0C-2 — Graphics cluster (9 topics, ~99 source files)

The mabda v3 GPU work generated all of these. Cyrius implementations
exist in mabda's source tree but haven't been pulled into vidya yet.
Pull from mabda first, then expand to other languages.

bindless_resources, bloom_and_glow, direct_drm_gpu_compute,
explicit_gpu_synchronization, framebuffer_rendering, gpu_memory_pooling,
line_rasterization, render_graph_architecture, sprite_rendering

### P0C-3 — Database cluster — **Done** (v2.3.4)

All 3 database topics now 11/11:
- btree_indexing — 10 new lang ports of the simplified B+ tree (order 8)
- sql_parsing — 10 new lang ports of the SELECT tokenizer + validator
- write_ahead_logging — 11 new lang files (concept-only; cyrius reference
  designed in v2.3.4 alongside the ports)

31 source files added. Subsumed P2's planned `database_fundamentals`.

### P0C-4 — Systems & misc (4 topics, ~40 source files)

compression, concurrent_file_access, jsonl_format, page_management.
page_management has Cyrius coverage; the other three are concept-only.

---

## P1 — New Topics (Networking & Infrastructure)

| Topic | Description | Priority |
|---|---|---|
| networking_fundamentals | TCP/UDP, sockets, connection lifecycle, non-blocking I/O | High |
| http_and_web_protocols | HTTP/1.1, HTTP/2, HTTP/3/QUIC, WebSocket, request lifecycle | High |
| tls_and_encryption | TLS handshake, certificate chains, cipher suites, AEAD | High |
| dns | Resolution, record types, caching, DNSSEC | Medium |
| ipc | Shared memory, pipes, Unix sockets, message passing, D-Bus | High |
| serialization | Serde patterns, protobuf, flatbuffers, zero-copy parsing | High |

---

## P2 — New Topics (Database & Distributed Systems)

`database_fundamentals` is partially covered by P0C-3 (btree_indexing,
sql_parsing, write_ahead_logging) — leaving the higher-level topics here.

| Topic | Description | Priority |
|---|---|---|
| transactions_and_acid | ACID, isolation levels, MVCC, write-ahead logging | Medium |
| consensus | Raft, Paxos, Byzantine fault tolerance, leader election | Medium |
| distributed_systems | CAP theorem, partitioning, replication, CRDTs | Medium |

---

## P3 — Graphics, Audio, AI

P3 graphics partially shipped via P0C-2 (9 topics). Remaining:

| Topic | Description | Priority |
|---|---|---|
| audio_dsp | FFT, convolution, filters, sampling theory, Nyquist | Medium |
| audio_synthesis | Oscillators, envelopes, FM, wavetable synthesis | Medium |
| neural_networks | Forward/backward pass, gradient descent, activations | Medium |
| inference | Quantization, batching, KV cache, attention | Medium |
| embeddings | Vector representations, similarity search | Low |

---

## P4 — Build Systems & Package Management

| Topic | Description | Priority |
|---|---|---|
| build_systems | Dependency graphs, incremental compilation, caching | Medium |
| package_resolution | SAT solving, version constraints, lockfiles | Medium |
| reproducible_builds | Deterministic output, content-addressed storage | Low |

---

## P5 — Functional Programming & Type Theory

| Topic | Description | Priority |
|---|---|---|
| functional_patterns | Monads, functors, applicatives, ADTs | Low |
| effect_systems | Algebraic effects, capability passing | Low |
| dependent_types | Type-level programming, refinement types | Low |

---

## P6 — Cyrius-Specific Topics

The `content/cyrius/` directory already exists as the Cyrius corpus
(language reference, types, ecosystem, dependencies, field notes,
archive) — distinct from a regular concept topic. The items below
are programming-concept slots that would document Cyrius patterns
the way other topics document general patterns.

| Topic | Description | Priority |
|---|---|---|
| cyrius_basics | Language syntax, types, control flow | Future |
| cyrius_bootstrap | Multi-stage compilation, seed retirement | Future |
| cyrius_agents | Agent types as language primitives | Future |
| cyrius_capabilities | Capability annotations, sandbox enforcement | Future |
| cyrius_ipc | IPC as language-level constructs | Future |

---

## Cyrius Pin Maintenance

Every Cyrius minor (5.5 → 5.6 → 5.7 → 5.8) has driven a vidya patch
bump for stdlib and language-feature alignment. The cadence:

1. Cyrius minor lands upstream
2. `cyrius.cyml` bumps `cyrius = "X.Y.Z"`
3. Field notes capture any surfaced gotchas in
   `content/cyrius/field_notes/compiler/vX_Y.cyml`
4. `index.cyml` verification range bumped
5. CHANGELOG patch entry summarises the bump
6. zugot recipe (in the upstream repo) tracks the same version

History:
- v2.3.0 — cyrius 5.7.0 (sandhi fold, CYML migration)
- v2.3.1 — cyrius 5.8.3 (no API delta; field-notes split)
- next — cyrius 5.9.x when it lands

---

## Language Coverage — Original 36 Topics

| Language | Topics | Status |
|---|---|---|
| Rust | 36/36 | Complete |
| Python | 36/36 | Complete |
| C | 36/36 | Complete |
| Go | 36/36 | Complete |
| TypeScript | 36/36 | Complete |
| Shell | 36/36 | Complete |
| Zig | 36/36 | Complete |
| x86_64 ASM | 36/36 | Complete (+6 partial new) |
| AArch64 ASM | 36/36 | Complete |
| OpenQASM | 36/36 | Complete |
| Cyrius | 36/36 | Complete (+9 partial new = 45/60 overall) |

Coverage on the **24 new topics** is tracked in P0C above.

---

## Relationship to AGNOS

Vidya feeds directly into the ecosystem:
- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented in real-time
- **mabda** — vidya documents the GPU patterns mabda implements (and its
  field notes feed back into `content/cyrius/field_notes/mabda_v3_gpu/`)
- **sakshi** — vidya uses sakshi for tracing, documents tracing patterns
- **sandhi** — vidya's HTTP service runs on sandhi
- **`docs/sources.md`** standard — vidya IS the source citation for
  programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-05-02 (v2.3.4)*
