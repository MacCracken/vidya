# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-01
>
> **Version**: 2.3.2 | **Cyrius**: 5.8.3
> **Topics**: 60 (36 fully covered, 24 added since v2.2 — most still need backfill)
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 411 source files (288 mainstream-lang + 78 ASM + 45 Cyrius); concept files: 60
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Current State

### Original 36 topics — fully covered (11/11 languages each)

algorithms, allocators, binary_formats, boot_and_startup, code_generation,
compiler_bootstrapping, concurrency, design_patterns, elf_and_executable_formats,
error_handling, filesystems, input_output, instruction_encoding,
intermediate_representations, interrupt_handling, iterators, kernel_topics,
lexing_and_parsing, linking_and_loading, macro_systems, memory_management,
module_systems, optimization_passes, ownership_and_borrowing, pattern_matching,
performance, process_and_scheduling, quantum_computing, security, strings,
syscalls_and_abi, testing, tracing, trait_and_typeclass_systems, type_systems,
virtual_memory

396 source files (36 × 11). All 11 languages green for these.

### 24 new topics added since v2.2 — partial coverage

These landed alongside cyrius-doom, mabda v3 GPU, and ENCOM's Hits content
work. Most still need non-Cyrius backfill (see P0C below).

**Graphics cluster (mabda v3 + cyrius-doom) — 9 topics, 0 of 99 non-Cyrius slots filled**
- bindless_resources, bloom_and_glow, direct_drm_gpu_compute,
  explicit_gpu_synchronization, framebuffer_rendering, gpu_memory_pooling,
  line_rasterization, render_graph_architecture, sprite_rendering

**Game-engine cluster (cyrius-doom + ENCOM's Hits) — 8 topics, partial**
- collision_detection_2d (X+Y), fixed_point_arithmetic (X+Y),
  game_ai_decisions (X+Y), game_loop_architecture (none),
  grid_pathfinding (none), maze_generation (none),
  projectile_physics (X+Y), state_machines (X+Y)

**Database cluster — 3 topics, Cyrius-only**
- btree_indexing (Y), sql_parsing (Y), write_ahead_logging (none)

**Systems & misc — 4 topics, mixed**
- compression (none), concurrent_file_access (none),
  jsonl_format (none), page_management (Y)

Coverage legend in matrix: R/P/C/G/T/S/Z = Rust/Python/C/Go/TS/Shell/Zig,
X/A = x86_64/AArch64 ASM, Q = OpenQASM, Y = Cyrius.

411 examples across 60 topics. Gap to 60 × 11 = 660: **~249 source files**
(plus per-topic AArch64 follow-ups where x86_64 already exists).

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

### P0B-1 — Wire `/compare` and `/gaps` HTTP endpoints

The CLI handlers (`cmd_compare`, `cmd_gaps`) already produce JSON-shaped
output. Add route matchers in `cmd_serve`'s connection handler analogous
to the existing `/search` and `/info/` blocks. Smoke-test from `curl` and
add to `tests/vidya.tcyr`.

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

## P0C — Backfill non-Cyrius coverage on the 24 new topics

This is the largest concrete gap: ~249 source files across 24 topics × 11
languages. Sized as a multi-release sweep, prioritized by cluster maturity.

### P0C-1 — Game-engine cluster (8 topics, ~80 source files)

Six of the eight have x86_64 + Cyrius implementations already; the other
two (game_loop_architecture, grid_pathfinding) are concept-only. Extend
each to all 11 languages, mirroring the original-36 pattern.

| Topic | Has | Needs |
|---|---|---|
| collision_detection_2d | X, Y | RPCGTSZA, Q |
| fixed_point_arithmetic | X, Y | RPCGTSZA, Q |
| game_ai_decisions | X, Y | RPCGTSZA, Q |
| projectile_physics | X, Y | RPCGTSZA, Q |
| sprite_rendering | X, Y | RPCGTSZA, Q |
| state_machines | X, Y | RPCGTSZA, Q |
| game_loop_architecture | — | All 11 |
| grid_pathfinding | — | All 11 |
| maze_generation | — | All 11 |

(maze_generation is closer to game-engine than systems/misc — moved here
for the backfill plan.)

### P0C-2 — Graphics cluster (9 topics, ~99 source files)

The mabda v3 GPU work generated all of these. Cyrius implementations
exist in mabda's source tree but haven't been pulled into vidya yet.
Pull from mabda first, then expand to other languages.

bindless_resources, bloom_and_glow, direct_drm_gpu_compute,
explicit_gpu_synchronization, framebuffer_rendering, gpu_memory_pooling,
line_rasterization, render_graph_architecture, sprite_rendering

### P0C-3 — Database cluster (3 topics, ~30 source files)

btree_indexing (Y), sql_parsing (Y), write_ahead_logging (none).
Cyrius implementations for two of three; expand to all 11 languages.
Subsumes P2's `database_fundamentals`.

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

*Last Updated: 2026-05-01 (v2.3.2)*
