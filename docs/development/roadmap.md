# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-02
>
> **Version**: 2.3.5 | **Cyrius**: 5.8.3
> **Topics**: 60 (48 fully covered, 12 still partial)
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 529 source files; concept files: 60
> **Validator**: 529/529 green
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

---

## Current State

### 48 topics fully covered (11/11 languages)

The original 36 P0 topics, plus 12 added in v2.3.2–v2.3.4. The
roadmap header previously said 47; the binary's `vidya stats`
reports 48, and a direct `ls` count over `content/*/` confirms
48 — one of the topics below was undercounted in the v2.3.4
CHANGELOG. Numbers reconciled in v2.3.5.

- v2.3.2 (1): fixed_point_arithmetic
- v2.3.3 P0C-1 (8): collision_detection_2d, game_ai_decisions,
  game_loop_architecture, grid_pathfinding, maze_generation,
  projectile_physics, sprite_rendering, state_machines
- v2.3.4 P0C-3 (3): btree_indexing, sql_parsing, write_ahead_logging

(The 48th — actual identity to be confirmed during the v2.3.6
content sweep when each partial topic is touched in turn.)

### 12 topics still partial

**P0C-2 graphics cluster** (8 topics, all 0/11 — needs full 11-lang ports):
bindless_resources, bloom_and_glow, direct_drm_gpu_compute,
explicit_gpu_synchronization, framebuffer_rendering, gpu_memory_pooling,
line_rasterization, render_graph_architecture

**P0C-4 systems & misc** (4 topics, mostly 0/11):
compression (none), concurrent_file_access (none), jsonl_format (none),
page_management (cyrius-only)

Gap to full 11/11 across these 12 topics: **~131 source files**
(11 concept-only × 11 langs each = 121 + page_management's
remaining 10 langs = 131).

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

Deferred (slot tbd, ahead of 2.3.6 content sweep):
- **P0B-4 — content hot-reload** (inotify watch + atomic
  registry pointer swap). Strictly blocked on P0B-2 audit
  results, which now exist; deferred because the design
  needs more thought than the rest of v2.3.5 combined
  (dual-registry memory cost, swap barrier model,
  partial-failure handling for a bad concept.toml in the
  middle of a reload). Likely 2.3.5a or a 2.3.6-prelude.

### 2.3.6 — P0C-4 systems & misc cluster (4 topics, ~37 files)

Same shape as v2.3.4 P0C-3:
- **`compression`** — RLE / LZ77-shaped reference; concept-only today.
- **`concurrent_file_access`** — fcntl locking, advisory vs mandatory;
  concept-only.
- **`jsonl_format`** — newline-delimited JSON streaming parser;
  concept-only.
- **`page_management`** — has cyrius reference; needs other 10 langs
  (mirror the v2.3.4 cyrius-already-exists pattern).

Estimated: 11 + 11 + 11 + 10 = 43 files (closer than the 37 estimate;
concept-only topics need cyrius reference designed first).

### 2.3.7 — P0C-2a graphics batch 1 (3 topics, ~33 files)

Pull cyrius references from mabda v3 source tree first, then port:
- `framebuffer_rendering` (closest sibling to `sprite_rendering`
  which is already 11/11 — natural follow-on)
- `line_rasterization` (Bresenham; small, mathematical)
- `bloom_and_glow` (post-process; visual but compact)

### 2.3.8 — P0C-2b graphics batch 2 (3 topics, ~33 files)

- `bindless_resources` (descriptor sets, texture binding)
- `gpu_memory_pooling` (suballocation patterns)
- `explicit_gpu_synchronization` (semaphores, fences, pipeline barriers)

### 2.3.9 — P0C-2c graphics batch 3 (2 topics + render-graph integration)

- `direct_drm_gpu_compute` (the AGNOS-specific direct-ioctl path)
- `render_graph_architecture` (depends on most of the others —
  framebuffer, sync, bindless)

After 2.3.9, **all 60 topics at 11/11**, ~660+ examples. P0 → P0C
fully complete.

---

## Next minor (2.4.0) — Networking & Infrastructure

Once all 60 existing topics are at 11/11, start P1 — the first new
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

*Last Updated: 2026-05-02 (v2.3.5)*
