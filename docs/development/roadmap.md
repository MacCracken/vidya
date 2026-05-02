# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-02
>
> **Version**: 2.3.10 | **Cyrius**: 5.8.14
> **Topics**: 60 (60 fully covered) — **P0 → P0C complete**
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 660 source files; concept files: 60
> **Validator**: 660/660 green
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Release History

Per-release detail lives in [CHANGELOG.md](../../CHANGELOG.md). Highlights:

| Version | Date | What landed |
|---|---|---|
| 2.0.0 — 2.2.0 | through 2026-04-08 | P0 (original 36 topics, 11/11) + P0A infrastructure (sakshi, .tcyr/.bcyr, learning paths, content-grouping plan, gap reporting) |
| 2.3.0 | 2026-04-25 | **P0B Service Layer (most)** — HTTP server on `lib/sandhi.cyr`, JSON, 5 of 7 endpoints; CYML migration |
| 2.3.1 | 2026-05-01 | **Field-notes growth pattern** — split `compiler/`, `language/`, `mabda_v3_gpu/` into per-topic subfolders; cyrius pin → 5.8.3 |
| 2.3.2 | 2026-05-02 | **Roadmap rewrite** + **P0C-1 kickoff** (`fixed_point_arithmetic` 11/11) + Cyrius validation in `validate-content.sh` + 14 latent failures fixed + 3 parser-syntax field-note entries |
| 2.3.3 | 2026-05-02 | **P0C-1 complete** — game-engine cluster: collision_detection_2d, game_ai_decisions, game_loop_architecture, grid_pathfinding, maze_generation, projectile_physics, sprite_rendering, state_machines (78 new files) |
| 2.3.4 | 2026-05-02 | **P0B-1 complete** (`/compare` + `/gaps` HTTP routes; 7-of-7 endpoints live) + **P0C-3 complete** (database cluster: btree_indexing, sql_parsing, write_ahead_logging — 31 new files) + vidya.tcyr cstr-key fix |
| 2.3.5 | 2026-05-02 | **P0B-2 + P0B-3 complete** — memory-resident contract audited and documented; sakshi structured access log on `serve` (path + status + level-routed latency). Field notes promoted: `language/shell_runtime.cyml` (3 entries) + AArch64 ABI consolidation in `language/platform_abi.cyml`. CLAUDE.md + docs/architecture/overview.md rewritten end-to-end. P0B-4 hot-reload deferred. |
| 2.3.6 | 2026-05-02 | **P0B-4 complete — content hot-reload on `serve`** — inotify watch on every topic dir; per-request drain triggers all-or-nothing rebuild + atomic registry pointer swap; sakshi events per reload (success/failure with timing). End-to-end verified across add/remove/corrupt/restore. Reload latency 17–22ms for 60 topics. **P0B fully done (B-1 → B-4 all shipped).** |
| 2.3.7 | 2026-05-02 | **P0C-4 complete + cyrius pin bump 5.8.3 → 5.8.14** — systems & misc cluster: `compression` (LZ77-shaped 2-byte tokens, RLE overlap, bomb guard), `concurrent_file_access` (real flock per-OPEN with 2-fd contention), `jsonl_format` (build/index/escape/unescape with 2× expansion bounds check), `page_management` (10 lang ports of the existing cyrius reference). 43 new source files; validator 529/529 → 572/572. |
| 2.3.8 | 2026-05-02 | **P0C-2a complete — graphics batch 1 (3 topics × 11 langs)** — `framebuffer_rendering` (16×16 BGRA8888, bounds-checked fb_set/get/clear/hline/vline), `line_rasterization` (all-octant integer Bresenham, 7 line types), `bloom_and_glow` (1-pixel additive bloom + saturation clamp + threshold). Plus completed bloom_and_glow concept.toml (was TODO stub). 33 new source files; validator 572/572 → 605/605. |
| 2.3.9 | 2026-05-02 | **P0C-2b complete — graphics batch 2 (3 topics × 11 langs)** — `bindless_resources` (64-slot descriptor table, slot-0 sentinel, LIFO free-list), `gpu_memory_pooling` (1024-byte bump allocator with alignment + reset), `explicit_gpu_synchronization` (compute + transfer timeline semaphores with signal/wait/wait_all and monotonic invariant). 33 new source files; validator 605/605 → 638/638. **All-first-try clean — no asm or language-specific debugging needed.** |
| 2.3.10 | 2026-05-02 | **P0C-2c complete — final P0C patch (2 topics × 11 langs)** — `direct_drm_gpu_compute` (GEM BO + VA-map + submit + syncobj-wait simulation), `render_graph_architecture` (DAG with topo sort + barrier derivation + dead-pass culling + cycle detection). 22 new source files; validator 638/638 → **660/660**. **🎉 P0 → P0C arc complete — all 60 topics at 11/11 languages.** |

---

## Current State

### 60 topics fully covered (11/11 languages) — P0 → P0C COMPLETE 🎉

The original 36 P0 topics, plus 24 added across v2.3.2–v2.3.10:

- v2.3.2 (1): fixed_point_arithmetic
- v2.3.3 P0C-1 (8): collision_detection_2d, game_ai_decisions,
  game_loop_architecture, grid_pathfinding, maze_generation,
  projectile_physics, sprite_rendering, state_machines
- v2.3.4 P0C-3 (3): btree_indexing, sql_parsing, write_ahead_logging
- v2.3.7 P0C-4 (4): compression, concurrent_file_access,
  jsonl_format, page_management
- v2.3.8 P0C-2a (3): framebuffer_rendering, line_rasterization,
  bloom_and_glow
- v2.3.9 P0C-2b (3): bindless_resources, gpu_memory_pooling,
  explicit_gpu_synchronization
- v2.3.10 P0C-2c (2): direct_drm_gpu_compute, render_graph_architecture

The historical 47→48 discrepancy from v2.3.5 (off-by-one
bookkeeping noise across CHANGELOG entries) is now permanently
resolved: **vidya stats reports `Topics: 60, Complete: 60`;
on-disk count matches; validator 660/660 green**.

### 0 topics partial

The patch backlog for the 2.3.x series is complete. Next
release opens P1 — see "Next minor (2.4.0)" below.

---

## Patch backlog (2.3.x)

Each patch is sized for one focused session. Pattern: bump VERSION,
do the work, validator green, CHANGELOG section, ship.

### 2.3.5 — Service-layer polish + recurring-pattern field notes ✅ shipped 2026-05-02

Most of the planned scope landed; **P0B-4 deferred**.

Done:
- **P0B-2** — Memory-resident mode audited (clean: `reg_init` +
  `load_all` once at startup; `handle_request` does zero file I/O).
  Contract documented as a featured section in
  `docs/architecture/overview.md`.
- **P0B-3** — Sakshi structured access log on `serve`:
  per-request `GET <path> -> <status> (<elapsed_ns>ns)`, level-
  routed (200s INFO, 4xx WARN, 5xx ERROR). Status capture via
  module-level `_serve_status` global set in each `send_*` leaf.
- **`language/shell_runtime.cyml`** — new file, 3 entries
  (subshell-clobbers-stateful-helpers, `(( i++ )) + set -e`,
  `bc` not POSIX-mandatory).
- **`language/platform_abi.cyml`** — AArch64 ABI consolidation
  entry (cross-`bl` clobber + 12-bit cmp + 16-bit mov immediate
  ceilings, with literal-pool rescue).
- **Doc rewrites** — CLAUDE.md + `docs/architecture/overview.md`
  both rewritten end-to-end (were stale from the pre-v2.0
  Rust era).

Deferred to **v2.3.6** (content sweep cascades to 2.3.7+):
- **P0B-4 — content hot-reload** is the entire payload for the
  next patch — see "2.3.6" below.

### 2.3.6 — P0B-4 content hot-reload ✅ shipped 2026-05-02

The deferred half of v2.3.5, promoted to its own focus release.
Landed exactly as scoped — inotify-driven detection, staged
build with all-or-nothing partial-failure semantics, atomic
two-pointer swap, sakshi events per reload outcome.

Done:
- **Detection** — `inotify_init1(IN_NONBLOCK)` fd, watch per
  topic dir (filtered to dirs with `concept.toml`). Drained
  non-blocking at the top of every `handle_request`.
- **Build** — staged into `_reg_entries_next` /
  `_reg_index_next`; all-or-nothing (one bad `concept.toml`
  aborts reload, live registry preserved).
- **Swap** — single-threaded means two pointer assignments,
  no barrier.
- **Re-watch** — `inotify_init_watches()` re-runs after each
  successful swap so newly-added topic dirs get coverage.
- **Observability** — `INFO reload OK: <n> topics in <ns>ns
  (reload #<count>)` / `WARN reload aborted: a concept failed
  to load (failure #<count>); live registry untouched`.

Verified end-to-end across baseline / add / remove / corrupt /
restore. Reload latency 17–22ms for 60 topics.

Documented in `docs/architecture/overview.md` as a new
"Hot-reload contract" section alongside the memory-resident
contract.

Known limits documented (not bugs):
- Bump allocator never frees → each reload doubles registry
  memory permanently. Restart periodically for long sessions.
- Reload triggered by next HTTP request, not immediately on
  file change (drain runs in `handle_request`, not in a
  separate thread or accept-loop hook).
- Full reload, not incremental. ~20ms; not worth optimising
  until topic count crosses ~500.

### 2.3.7 — P0C-4 systems & misc cluster ✅ shipped 2026-05-02

All 4 topics × 11 langs landed (43 new files exactly as estimated).

Done:
- **`compression`** — LZ77-shaped 2-byte token stream, greedy
  O(n²) match-finder, byte-by-byte overlap-aware decoder, bomb
  guard. Asm ports decoder-only with hand-built token streams.
- **`concurrent_file_access`** — real flock per-OPEN with two-fd
  contention model (single-process equivalent of multi-process
  contention). TypeScript falls back to in-process state-machine
  simulation (Node lacks built-in flock binding).
- **`jsonl_format`** — flat byte-buffer record store, per-line
  index with no-trailing-newline edge case, JSON string escape
  with 2× expansion bounds check, escape ↔ unescape roundtrip.
- **`page_management`** — 10-lang port of the existing cyrius
  reference (header, page_alloc with free-list, page_read/write,
  page_free).

Plus: **cyrius pin bump 5.8.3 → 5.8.14** (no API delta; field-
notes verification range bumped to 5.8.14).

### 2.3.8 — P0C-2a graphics batch 1 ✅ shipped 2026-05-02

All 3 topics × 11 langs landed (33 new files):
- **`framebuffer_rendering`** — 16×16 BGRA8888 with bounds-
  checked set/get, hline/vline, lit-pixel count.
- **`line_rasterization`** — all-octant integer Bresenham
  covering 7 line types (horizontal, vertical, +/- diagonals,
  steep, point, reversed).
- **`bloom_and_glow`** — 1-pixel additive bloom with per-
  channel saturation clamp + threshold. Concept.toml
  completed (was a TODO stub).

### 2.3.9 — P0C-2b graphics batch 2 ✅ shipped 2026-05-02

All 3 topics × 11 langs landed (33 new files), all-first-try clean:
- **`bindless_resources`** — 64-slot descriptor table with
  slot-0 sentinel and LIFO free-list reuse.
- **`gpu_memory_pooling`** — 1024-byte bump allocator with
  alignment rounding + atomic reset.
- **`explicit_gpu_synchronization`** — compute + transfer
  timeline semaphores with signal/wait/wait_all and
  monotonic invariant enforcement.

### 2.3.10 — P0C-2c (final P0C patch) ✅ shipped 2026-05-02 🎉

Both topics × 11 langs landed (22 new files), all-first-try clean:
- **`direct_drm_gpu_compute`** — in-memory simulation of the
  GEM BO + VA-map + submit + syncobj-wait flow (no real ioctls);
  models the kernel-side state machine that AMDGPU compute MVPs
  drive.
- **`render_graph_architecture`** — tiny DAG framework with
  reads/writes bitmasks, Kahn-style topological sort with cycle
  detection, write→read barrier derivation, and dead-pass
  culling.

After 2.3.10, **all 60 topics at 11/11**, 660 examples. P0 → P0C
fully complete.

---

## Next minor (2.4.0) — Networking & Infrastructure

P0 → P0C is complete (v2.3.10). Time to open P1 — the first new
thematic addition since v2.2:

| Topic | Notes |
|---|---|
| **networking_fundamentals** | TCP/UDP, sockets, connection lifecycle, non-blocking I/O |
| **http_and_web_protocols** | HTTP/1.1, HTTP/2, HTTP/3/QUIC, WebSocket, request lifecycle |
| **tls_and_encryption** | TLS handshake, certificate chains, cipher suites, AEAD |
| **dns** | Resolution, record types, caching, DNSSEC |
| **ipc** | Shared memory, pipes, Unix sockets, message passing, D-Bus |
| **serialization** | Serde patterns, protobuf, flatbuffers, zero-copy parsing |

6 topics × 11 langs = 66 new examples + 6 concept files. Sized as
~3 patch sub-releases (2.4.0 / 2.4.1 / 2.4.2) of 2 topics each, mirroring
the 2.3.x cadence.

---

## Future minor versions

Each minor is one thematic cluster, sized similarly to P1 (3–6 topics).
Order is rough; exact sequencing depends on which AGNOS components
need vidya support next.

| Minor | Theme | Topics | Notes |
|---|---|---|---|
| 2.5.x | **P2 distributed systems** | transactions_and_acid, consensus, distributed_systems | Subsumes the original `database_fundamentals` (handled in P0C-3). Builds on `concurrent_file_access` (P0C-4) and `write_ahead_logging`. |
| 2.6.x | **P3 audio + AI/ML** | audio_dsp, audio_synthesis, neural_networks, inference, embeddings | The AI/ML topics align with hoosh's RAG needs. |
| 2.7.x | **P4 build systems** | build_systems, package_resolution, reproducible_builds | Aligns with cyrius/zugot tooling. |
| 2.8.x | **P5 functional / type theory** | functional_patterns, effect_systems, dependent_types | More research-flavored; lowest priority. |
| 2.9.x | **P6 Cyrius-specific** | cyrius_basics, cyrius_bootstrap, cyrius_agents, cyrius_capabilities, cyrius_ipc | Programming-concept slots that document Cyrius patterns the way other topics document general patterns. Distinct from `content/cyrius/` (the language reference + field notes). |

---

## Future major (3.0.0) — Content reorganization

Trigger condition (from `docs/development/content-grouping.md`):
**when topic count exceeds ~50, reorganize `content/` into subdirectories.**
We're already at 60. The reorg has been deferred because the flat
structure still works, but it should land before the topic count
crosses ~80.

Planned shape (per content-grouping.md):

```
content/
├── fundamentals/        — strings, error_handling, concurrency, ...
├── compiler/            — lexing, IR, optimization, codegen, ...
├── systems/             — boot, virtual_memory, syscalls, ...
├── languages/           — ownership, traits, macros, modules
├── quantum/             — quantum_computing, quantum_walks (future)
├── networking/          — (post-P1)
├── data/                — (post-P0C-3)
├── graphics/            — (post-P0C-2)
├── games/               — (post-P0C-1)
└── cyrius/              — corpus + field notes (already a subdir)
```

Migration is a single atomic move: update `load_all()` to recurse,
update `source_path` references, update tests. Backward compat via
symlinks for one minor.

---

## Cyrius pin maintenance

Every Cyrius minor (5.5 → 5.6 → 5.7 → 5.8 → ...) drives a vidya
patch bump for stdlib + language-feature alignment. The cadence:

1. Cyrius minor lands upstream
2. `cyrius.cyml` bumps `cyrius = "X.Y.Z"`
3. Field notes capture surfaced gotchas in
   `content/cyrius/field_notes/compiler/vX_Y.cyml`
4. `content/cyrius/field_notes/index.cyml` verification range bumped
5. CHANGELOG patch entry summarises the bump
6. zugot recipe (in the upstream repo) tracks the same version

History:
- v2.3.0 — cyrius 5.7.0 (sandhi fold, CYML migration)
- v2.3.1 — cyrius 5.8.3 (no API delta; field-notes split)
- v2.3.7 — cyrius 5.8.14 (no API delta; verification range bumped)

---

## Relationship to AGNOS

Vidya feeds directly into the ecosystem:
- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented
  in real-time; field notes capture the gotchas as they surface
- **mabda** — vidya documents the GPU patterns mabda implements
  (and its field notes feed back into
  `content/cyrius/field_notes/mabda_v3_gpu/`)
- **sakshi** — vidya uses sakshi for tracing; documents tracing patterns
- **sandhi** — vidya's HTTP service runs on sandhi
- **`docs/sources.md`** standard — vidya IS the source citation for
  programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-05-02 (v2.3.10) — **P0 → P0C complete; 60/60 at 11/11***
