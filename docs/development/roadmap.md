# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-03
>
> **Version**: 2.6.1 | **Cyrius**: 5.8.34
> **Topics**: 71 (71 fully covered) — **P0 → P2 complete; P3 2/5** 🎉
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 781 source files; concept files: 71
> **Validator**: 781/781 green
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
| 2.4.0 | 2026-05-02 | **P1 kickoff — Networking & Infrastructure (minor bump)** — 2 new topics × 11 langs: `networking_fundamentals` (TCP socket state machine + bind/listen/connect/send/recv/close lifecycle, port-reuse + half-closed semantics), `http_and_web_protocols` (HTTP/1.1 request parser — sequential parse, case-insensitive header lookup, Content-Length body framing, malformed-request rejection). 24 new source files; validator 660/660 → **682/682**. P1 is 2/6 topics in flight; tls_and_encryption + dns slated for 2.4.1, ipc + serialization for 2.4.2. |
| 2.4.1 | 2026-05-02 | **P1 batch 2 — 2 new topics × 11 langs** — `tls_and_encryption` (TLS 1.3 handshake state machine, cipher-suite negotiation rejecting legacy 1.2 suites, certificate chain validation with issuer/subject linkage to trust root, AEAD seal/open with tag verification + hostname check), `dns` (in-memory resolver: zone with A/AAAA/CNAME/MX/TXT, recursive lookup with depth-bounded CNAME chase, TTL cache with monotonic clock, negative caching). 22 new source files; validator 682/682 → **704/704**. P1 is 4/6 topics in flight; ipc + serialization slated for 2.4.2. |
| 2.4.2 | 2026-05-02 | **P1 complete + cyrius pin bump 5.8.14 → 5.8.18** — `ipc` (shared memory + bounded FIFO pipe + named-endpoint message channel), `serialization` (LEB128 varint + length-prefix framing + stream parser + DoS guards: varint overflow cap, oversize-length rejection). 22 new source files; validator 704/704 → **726/726**. **🎉 P1 Networking & Infrastructure complete — 6/6 topics × 11 langs landed.** |
| 2.4.3 | 2026-05-02 | **Cyrius reference closeout + cyrius pin 5.8.18 → 5.8.19** — both `content/cyrius/` surfaces reorganized in one release. Retired the 4144-line `language.cyml` (73 entries) into `language/` subfolder organized by surface area: core / features / stdlib_modules / tooling / agents (52 entries across 6 files). Recast the chronological per-version `field_notes/compiler/` (8 files, 60 entries) as topical (gotchas / methodology / patterns) plus `retros/` subfolder for chronological narrative (9 files, 46 entries). End state: humans + agents get current-state docs organized by lookup workflow, not historical accretion. Loader unaffected (`content/cyrius/` is skipped). Topics/examples/validator counts unchanged (66/66/726). |
| 2.4.4 | 2026-05-03 | **Cyrius pin bump 5.8.19 → 5.8.34** — patch-level alignment, no source changes (CLI surface identical, build clean, 41/41 tests, 726/726 validator). Field-notes verification range extended. |
| 2.5.0 | 2026-05-03 | **P2 kickoff — Distributed Systems (minor bump)** — 1 new topic × 11 langs: `transactions_and_acid` (OCC store with explicit read-set/write-set tracking; A/C/I/D demonstrated under tests in HLLs; asm ports cover the single-tx OCC core). 11 new source files; validator 726/726 → **737/737**. P2 is 1/3 topics in flight; `consensus` + `distributed_systems` slated for 2.5.1 / 2.5.2. |
| 2.5.1 | 2026-05-03 | **P2 batch 2 — `consensus` (Raft)** — 1 new topic × 11 langs: 3-node Raft cluster, election state machine + log replication + commit-on-majority + log up-to-date check + Figure-8 rule (only commit current-term entries directly). HLLs do full Raft (10 tests / 41 asserts); asm ports do the focused election subset (6 tests / 12 asserts). 11 new source files; validator 737/737 → **748/748**. P2 is 2/3; `distributed_systems` slated for 2.5.2. |
| 2.5.2 | 2026-05-03 | **P2 complete — `distributed_systems`** — 1 new topic × 11 langs: vector clocks (with the four-outcome compare — LESS / EQUAL / GREATER / **CONCURRENT**), Dynamo-style quorum reads/writes (R+W>N intersection), partition handling. HLLs do all three (12 tests / 17 asserts); asm ports focus on quorum-replication (5 tests / 11 asserts); OpenQASM uses entanglement-as-replication. 11 new source files; validator 748/748 → **759/759**. **🎉 P2 Distributed Systems complete — 3/3 topics × 11 langs landed.** |
| 2.6.0 | 2026-05-03 | **P3 kickoff — Audio + AI/ML (minor bump)** — 1 new topic × 11 langs: `audio_dsp` (Q15 fixed-point biquad lowpass + FIR convolution + peak/mean-absolute level metering). HLLs do all three (9 tests / 14 asserts); asm ports focus on biquad + level metering (8 tests / 10 asserts); OpenQASM uses interference-as-filtering. 11 new source files; validator 759/759 → **770/770**. P3 is 1/5; `audio_synthesis`, `neural_networks`, `inference`, `embeddings` slated for 2.6.1–2.6.4. Two cyrius parser issues filed during port: `kernel` reserved-word + arithmetic-in-fn-args rejection (see `cyrius/docs/development/issues/2026-05-03-*`). |
| 2.6.1 | 2026-05-03 | **P3 batch 2 — `audio_synthesis`** — 1 new topic × 11 langs: Q15 oscillator (sine LUT, saw, square via 16-bit phase accumulator) + ADSR 5-state envelope + voice = osc × env. API surface mirrors AGNOS production synth crate `naad` (Adsr, EnvelopeState, gate_on/off, Voice) for instant familiarity; corpus uses Q15 + naive waveforms vs naad's f32 + PolyBLEP. HLLs do all three primitives (11 tests / 25 asserts); asm ports focus on phase + sine LUT + square + ADSR (8 tests / 13 asserts); OpenQASM uses rotation-as-oscillation. 11 new source files; validator 770/770 → **781/781**. P3 is 2/5; `neural_networks`, `inference`, `embeddings` slated for 2.6.2–2.6.4. |

---

## Current State

### 71 topics fully covered (11/11 languages) — P0 → P2 complete; P3 2/5 🎉

The original 36 P0 topics, plus 24 P0C additions (v2.3.2–v2.3.10),
plus 6 P1 additions (v2.4.0–v2.4.2), plus 3 P2 (v2.5.0–v2.5.2),
plus 2 P3 (v2.6.0–v2.6.1):

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
- v2.4.0 P1 (2): networking_fundamentals, http_and_web_protocols
- v2.4.1 P1 (2): tls_and_encryption, dns
- v2.4.2 P1 (2): ipc, serialization
- v2.5.0 P2 (1): transactions_and_acid
- v2.5.1 P2 (1): consensus
- v2.5.2 P2 (1): distributed_systems
- v2.6.0 P3 (1): audio_dsp
- **v2.6.1 P3 (1): audio_synthesis**

`vidya stats` reports `Topics: 71, Complete: 71 (all 11 languages),
Examples: 781`; validator 781/781 green.

### 0 topics partial; P3 2/5 in flight

P0 → P2 complete. P3 (Audio + AI/ML) is 2/5: `audio_dsp` +
`audio_synthesis` shipped. Remaining: `neural_networks` (2.6.2),
`inference` (2.6.3), `embeddings` (2.6.4). After 2.6.4, P3 closes
and the next minor (2.7.x) opens **P4 build systems**.

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

## Completed minor (2.4.x) — Networking & Infrastructure (P1) ✅

Shipped across 3 patch releases (2.4.0/1/2):

| Topic | Status | Notes |
|---|---|---|
| **networking_fundamentals** | ✅ shipped 2.4.0 | TCP socket state machine, bind/listen/connect/send/recv/close lifecycle, port-reuse + half-closed semantics |
| **http_and_web_protocols** | ✅ shipped 2.4.0 | HTTP/1.1 request parser — sequential parse, case-insensitive headers, Content-Length body framing |
| **tls_and_encryption** | ✅ shipped 2.4.1 | TLS 1.3 handshake state machine, certificate chain validation, cipher suite negotiation (TLS 1.3 only), AEAD seal/open with tag check |
| **dns** | ✅ shipped 2.4.1 | Resolver state machine, record types (A, AAAA, CNAME, MX, TXT), TTL cache with monotonic clock, negative caching, depth-bounded CNAME chase |
| **ipc** | ✅ shipped 2.4.2 | Shared memory + bounded FIFO pipe + named-endpoint message channel |
| **serialization** | ✅ shipped 2.4.2 | LEB128 varint + length-prefix framing + stream parser + DoS guards |

6 topics × 11 langs = 66 new examples + 6 concept files. **All 6
shipped.** Plus cyrius pin progression: 5.8.14 (entered 2.4.x) →
5.8.18 (exited 2.4.x).

---

## Completed minor (2.5.x) — Distributed Systems (P2) ✅

Shipped across 3 patch releases (2.5.0/1/2):

| Topic | Status | Notes |
|---|---|---|
| **transactions_and_acid** | ✅ shipped 2.5.0 | OCC store with read-set version snapshots; A/C/I/D under test |
| **consensus** | ✅ shipped 2.5.1 | 3-node Raft: election + log replication + Figure-8 commit rule |
| **distributed_systems** | ✅ shipped 2.5.2 | Vector clocks (4-outcome compare) + Dynamo quorum (R+W>N) + partition handling |

3 topics × 11 langs = 33 new examples + 3 concept files. **All 3 shipped.**

## In-flight minor (2.6.x) — Audio + AI/ML (P3)

| Topic | Status | Notes |
|---|---|---|
| **audio_dsp** | ✅ shipped 2.6.0 | Q15 fixed-point biquad lowpass + FIR convolution + peak/mean-absolute |
| **audio_synthesis** | ✅ shipped 2.6.1 | Q15 oscillator (sine/saw/square) + ADSR envelope + voice; mirrors naad API |
| **neural_networks** | planned 2.6.2 | Forward pass: dense layer + ReLU + softmax (Q15 or float — TBD) |
| **inference** | planned 2.6.3 | Tokenization + greedy decoding + temperature sampling |
| **embeddings** | planned 2.6.4 | Cosine similarity + nearest-neighbour search over a small fixed corpus |

5 topics × 11 langs total; 2 done, 3 to go.

## Future minor versions

Each minor is one thematic cluster, sized similarly to P1 (3–6 topics).
Order is rough; exact sequencing depends on which AGNOS components
need vidya support next.

| Minor | Theme | Topics | Notes |
|---|---|---|---|
| 2.6.x | **P3 audio + AI/ML** (in flight 2/5) | audio_dsp ✅, audio_synthesis ✅, neural_networks, inference, embeddings | The AI/ML topics align with hoosh's RAG needs. |
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
- v2.4.2 — cyrius 5.8.18 (no API delta)
- v2.4.3 — cyrius 5.8.19 (no API delta; content/cyrius/ closeout)
- v2.4.4 — cyrius 5.8.34 (no API delta; verification range bumped)

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

*Last Updated: 2026-05-03 (v2.6.1) — **P3 batch 2: audio_synthesis 11/11 (mirrors naad API); 71/71 at 11/11; 781/781 validator; next: neural_networks (2.6.2)***
