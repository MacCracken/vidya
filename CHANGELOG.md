# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.3.6] — 2026-05-02

P0B-4 content hot-reload. The deferred half of v2.3.5 promoted
to its own focus release. After this patch, P0B is fully done:
all four sub-tasks (B-1 through B-4) shipped.

### Added
- **Hot-reload on `serve`**. Inotify watches every topic dir
  under `content/`; per-request drain detects pending events
  and triggers an inline full-rebuild + atomic registry swap.
  No process restart needed when concepts change.
- **`inotify_init_watches()`** — opens an `IN_NONBLOCK` fd
  via `syscall(294, 2048)` (`inotify_init1`) and adds watches
  on `content/` root + every subdir that contains a
  `concept.toml` (filter matches `load_all`'s — skips
  `content/cyrius/` and other non-topic dirs). Mask = 970
  (`IN_MODIFY|IN_CLOSE_WRITE|IN_MOVED_FROM|IN_MOVED_TO|IN_CREATE|IN_DELETE`).
  Idempotent: closes any prior fd before opening a new one.
  Re-runs after every successful reload to pick up newly-added
  topic dirs.
- **`inotify_drain()`** — non-blocking read loop on the inotify
  fd. Sets `_reload_pending = 1` if any bytes were drained;
  exits on EAGAIN (returns immediately when no events queued).
- **`build_next_registry()` + `swap_registry()` + `do_reload()`**
  — staged registry build into `_reg_entries_next` /
  `_reg_index_next`, all-or-nothing semantics (a malformed
  `concept.toml` aborts the reload and leaves the live
  registry untouched), atomic two-pointer swap. Sakshi event
  per reload: `INFO reload OK: <n> topics in <ns>ns (reload #N)`
  on success, `WARN reload aborted: a concept failed to load`
  on partial failure.
- **`_reload_count` + `_reload_failures`** — module-level
  counters incremented per outcome, included in the sakshi
  events for ops visibility.

### Changed
- **VERSION** 2.3.5 → 2.3.6.
- **`handle_request`** — now calls `inotify_drain()` then
  conditional `do_reload()` at the top before touching the
  serve-status global. Per-request overhead on the no-events
  path is one `read(2)` returning EAGAIN (sub-µs).
- **`cmd_serve`** — calls `inotify_init_watches()` immediately
  before entering `sandhi_server_run`.
- **`docs/architecture/overview.md`** — replaced the prior
  "Future hot-reload (P0B-4) will change this contract" note
  with a fully-specified **Hot-reload contract** section
  covering detection, drain, build, swap, re-watch, and
  observability. Memory-resident contract section refined to
  reflect that the route handlers (`http_route` and the
  `json_*_response` builders) remain forbidden from filesystem
  I/O, while `handle_request` itself is allowed to call into
  `inotify_drain` / `do_reload` as the controlled mutation
  point. Known-limits section gained two entries: "reload is
  triggered by the next request, not immediately" and "no
  partial reload."

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (large-static-data
  warning bumped 309480 → 375064 bytes from the new 8KB
  inotify drain buffer + reload-related str literals).
- `cyrius test` — 41/41 passing (no regressions).
- **End-to-end smoke** across five scenarios:
  1. Baseline: 60 topics.
  2. Add a topic dir (`mkdir + cat > concept.toml`):
     60 → 61, `INFO reload OK: 61 topics in 17.5ms (reload #1)`,
     `/info/<new_topic>` returns the full concept.
  3. Remove the new topic dir:
     61 → 60, `INFO reload OK: 60 topics in 21.6ms (reload #2)`.
  4. Corrupt `algorithms/concept.toml` to garbage:
     `WARN reload aborted: a concept failed to load (failure #1);
     live registry untouched`. `/stats` still reports 60 topics;
     `/info/algorithms` still serves the pre-corruption data.
  5. Restore `algorithms/concept.toml`: stays at 60,
     `INFO reload OK: 60 topics in 19.7ms (reload #3)`.
- Reload latency: 17–22ms for 60 topics, dominated by the
  per-topic TOML parse in `load_concept`. Within the budget
  for an interactive dev tool.

### Notes for follow-up
- **Bump allocator never frees** — each successful reload doubles
  registry memory permanently. Acceptable for sessions with a
  handful of reloads; for sustained edit cycles, restart
  periodically. Documented in overview.md "Known limits."
- **Reload triggered by next request** — drains run in
  `handle_request`, so an idle process won't reload until the
  next hit. Workaround: drive a periodic curl. A SIGHUP-driven
  or accept-loop-integrated trigger is future work.

## [2.3.5] — 2026-05-02

Service-layer polish + recurring-pattern field notes. Doc-heavy
release; no new content topics.

### Added
- **P0B-3: structured access log on `serve`** in `src/main.cyr`.
  New `_serve_log(path, plen, status, elapsed_ns)` helper
  formats one line per request:
  `GET <path> -> <status> (<elapsed_ns>ns)`, level-routed
  through sakshi (200s → INFO, 4xx → WARN, 5xx → ERROR). New
  module-level `_serve_status` global captured by each
  `send_*` leaf so `handle_request` can include the status in
  the access line. Latency captured from `_sk_now_ns()`
  delta around `http_route()`. Smoke-tested on every endpoint:
  ```
  [INFO] GET /stats -> 200 (56222ns)
  [INFO] GET /list -> 200 (138995ns)
  [INFO] GET /info/algorithms -> 200 (43150ns)
  [WARN] GET /nope -> 404 (20007ns)
  [WARN] GET /search -> 400 (20198ns)
  ```
- **`content/cyrius/field_notes/language/shell_runtime.cyml`**
  — new file, 3 entries, promoting recurring bash-port gotchas
  surfaced 4× across v2.3.2–v2.3.4 backfills:
  - `bash_subshell_clobbers_stateful_helpers` — `$(fn)` runs in
    a subshell; mutations don't propagate to the parent. Use
    a side-effect global. (Hit 4×: game_ai_decisions,
    maze_generation, btree_indexing, write_ahead_logging.)
  - `bash_pre_increment_set_e_zero_exit` — `(( i++ ))` returns
    OLD value; when `i=0`, exit code 1 → `set -e` aborts.
    Use `i=$((i+1))`. (Hit in sql_parsing.)
  - `bash_bc_not_posix_mandatory` — `bc` absent on default
    Arch / Alpine / minimal NixOS; use `awk` for fp math.
    (Hit in quantum_computing.)
- **AArch64 ABI gotcha entry** appended to
  `content/cyrius/field_notes/language/platform_abi.cyml`
  (4 → 5 entries): `aarch64_callee_saved_and_imm_limits`
  consolidates three encoding/calling-convention pitfalls
  surfaced repeatedly across v2.3.3–v2.3.4 asm ports —
  cross-`bl` clobber of x0–x18 (rescue: cache in x19–x28
  callee-saveds OR recompute), `cmp xN, #imm` 12-bit unsigned
  ceiling (rescue: `ldr x16, =imm` literal-pool form), and
  `mov xN, #imm` 16-bit ceiling (same rescue). Hit 4× across
  game_loop_architecture, grid_pathfinding, maze_generation,
  btree_indexing, sql_parsing.

### Changed
- **VERSION** 2.3.4 → 2.3.5.
- **`docs/architecture/overview.md` rewritten end-to-end.**
  Was stale from the pre-v2.0 Rust era (talked about
  `src/lib.rs`, MCP/bote, 33 topics × 10 langs, Rust feature
  flags). Now reflects current Cyrius reality: two-layer
  diagram (content + Cyrius CLI), startup vs per-command vs
  per-request data flow, six numbered design decisions, and a
  dedicated **Memory-resident corpus contract (P0B-2)**
  section covering what the contract guarantees, what it
  forbids on the request path, and how P0B-4 will change it.
- **`CLAUDE.md` rewritten end-to-end.** Same staleness as
  overview.md. Replaced the cargo/clippy/audit/deny work-loop
  steps with cyrius-toolchain steps (`cyrius lint / fmt /
  test / bench / build / run / deps`), added a "Toolchains —
  which tool for which surface" section with two tables
  (Surface 1 = vidya project Cyrius commands; Surface 2 =
  per-language content validators with exact invocations
  pulled from `scripts/validate-content.sh`). Explicit
  "never run cargo against the project" prohibition; Rust
  carve-out for content `.rs` files via `rustc`.
- **`content/cyrius/field_notes/index.cyml`** — Language
  Gotchas section count 29 → 33 (added 3 from
  shell_runtime.cyml + 1 from platform_abi.cyml); split count
  5 → 6 files; per-file lines added for shell_runtime.cyml
  and updated for platform_abi.cyml (4 → 5).

### Verified
- **P0B-2 audit**: `reg_init` + `load_all` run once at startup
  (lines 1425, 1433); `cmd_serve` enters `sandhi_server_run`
  blocking accept loop without re-loading; every JSON
  response builder reads only `reg_list()`/`reg_get()` (pure
  in-memory hashmap+vec). Zero file I/O on the request path,
  verified by grep over the
  `http_route` + `handle_request` line range. Contract now
  documented as a featured section in
  `docs/architecture/overview.md`.
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing (10 test groups).
- End-to-end serve smoke (build/vidya serve 18390 + curl
  /stats /list /info/algorithms /nope /search) — all five
  responses correct, all five access-log lines emitted with
  matching status + latency.

### Deferred to a follow-up
- **P0B-4 — content hot-reload (inotify watch on `content/`,
  atomic `_reg_entries` / `_reg_index` swap).** Roadmap had
  this in 2.3.5; deferred because (a) it strictly blocks on
  P0B-2 audit results — landed here — but (b) the design
  needs more thought than the rest of v2.3.5 combined. The
  inotify driver, the swap barrier, the dual-registry memory
  cost, and the question of whether P0B-4 should also handle
  partial-failure (one bad concept.toml shouldn't kill the
  whole reload) all want their own release. Slotted into a
  future patch, likely 2.3.5a or as a prelude to 2.3.6.

## [2.3.4] — 2026-05-02

### Added
- **P0B-1: HTTP `/compare` and `/gaps` endpoints wired** in
  `src/main.cyr`. Two new JSON builders:
  - `json_compare_response(topic_id, lang1_str, lang2_str)` — returns
    `{topic, title, left:{language, present, path}, right:{...}}`.
    Returns 0 (→ HTTP 404) when topic missing; -1 sentinel (→ HTTP
    400) when either language is unknown; otherwise the JSON object.
  - `json_gaps_response()` — returns
    `{topics, languages, gaps:[{id, covered, of, missing:[...]}, ...],
    total_missing}`.
  Smoke-tested via `curl`: `GET /compare?topic=algorithms&left=rust&right=python`
  returns the comparison object; `GET /gaps` returns 60-topic
  coverage breakdown; bad lang → 400, bad topic → 404, missing
  params → 400. P0B is now 7-of-7 endpoints live.
- **P0C-3 database cluster — all 3 topics backfilled to 11/11**
  (31 new source files; validator sweep 498/498 → 529/529):
  - **`btree_indexing`** — 10 new lang files implementing a
    simplified B+ tree (order 8). Tests: insert/lookup, sorted
    iteration, split-on-overflow, descending-input handling.
    OpenQASM uses Grover-search-on-tree as the analog.
  - **`sql_parsing`** — 10 new lang files; tokenizer for
    `SELECT * FROM users WHERE id = 1`, case-insensitive keywords,
    integer literals, parens, validator that rejects malformed
    SELECTs. OpenQASM models the parse as a 4-qubit token stream
    walking the production tree.
  - **`write_ahead_logging`** — 11 new lang files (concept-only
    topic; cyrius reference designed first as part of this
    release). Tests: append + replay, log-before-data invariant,
    uncommitted-writes-lost-on-crash, delete replay, last-write-wins
    on overwrite, monotonic offsets, capacity bound.

### Fixed
- **`tests/vidya.tcyr` — pre-existing failures from the cyrius 5.x
  cstr-key migration**. The toml_loader/toml_sections/gotcha_fields
  groups were silently failing because `toml_get(pairs,
  str_from("id"))` returns 0 under cyrius 5.x stdlib (which expects
  cstr keys, not Str — captured in field-note
  `stdlib_str_to_cstr_key_migration` in v2.3.0). Replaced 6
  `str_from("...")` call sites with bare cstr literals; replaced
  `str_eq(a, str_from("..."))` with `str_eq_cstr(a, "...")`. The
  test file now reports **41/41 passing** (was failing on test 6
  before P0B-1 work began).

### Changed
- **VERSION** 2.3.3 → 2.3.4.
- **Topic coverage**: 60 topics, 44 → 47 fully covered. Per-language
  counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 44 → 47
  - x86_64 ASM / AArch64 ASM: 44 → 47
  - Cyrius: 44 → 47 (`write_ahead_logging` cyrius.cyr designed in
    this release; `btree_indexing` and `sql_parsing` already had it)
  - Examples: 498 → 529 (+31 new source files; +6%)

### Notes (recurring patterns worth field-noting)
- **Bash `(( i++ )) + set -e` interaction**: `(( i++ ))` evaluates
  to the OLD value of `i`; when `i=0`, that's a 0 exit code, which
  `set -e` treats as failure and aborts the script. Fix:
  `i=$((i+1))`. Surfaced in sql_parsing/shell.sh.
- **AArch64 cross-`bl` register clobber (3rd time this release
  arc)**: caller-saved x0–x18 not preserved across `bl`. Cache
  loop state in callee-saved x19–x28 OR recompute after each call.
  Caught independently in btree_indexing/asm_aarch64.s and
  sql_parsing/asm_aarch64.s by their respective backfill agents.
- **Bash subshell + stateful PRNG (4th time)**: `$(fn)` runs in a
  subshell so global mutations don't propagate. Use side-effect
  global (`OUT=...`) for stateful helpers. Hit btree_indexing's
  `node_new_leaf` and write_ahead_logging's full WAL state.

These three patterns + the v2.3.3 AArch64 12-bit `cmp` immediate
limit are now repeated enough to warrant a dedicated
`content/cyrius/field_notes/language/shell_runtime.cyml` (bash
gotchas) and a follow-up entry in
`content/cyrius/field_notes/language/platform_abi.cyml` covering
the AArch64 callee-saved-register convention. Deferred to v2.3.5
or a follow-up doc release.

## [2.3.3] — 2026-05-02

### Added
- **P0C-1 game-engine cluster — all 8 topics backfilled to 11/11**
  (78 new source files; validator sweep 420/420 → 498/498):
  - **`state_machines`** — 9 new lang files mirroring the FSM test
    set (PlayerState/GameState enums, committed-state timers,
    transition detection, idle-shoot-tick-idle).
  - **`projectile_physics`** — 9 new lang files; 1000-frame energy
    decay with `|vy| < 2 * GRAVITY` threshold (matches the v2.3.2
    convergence calibration); semi-implicit Euler stability bounded
    at 1000 units rise.
  - **`sprite_rendering`** — 9 new lang files; framebuffer + blit
    + transparency + clipping + scaled-blit + depth-sort. Shell
    port uses a 16×16 logical FB to keep wall-clock reasonable
    (all 8 test scenarios still exercised).
  - **`game_ai_decisions`** — 9 new lang files; PCG PRNG, stat
    scoring, AI dispatch (high-dunk-stat at close range → DUNK).
  - **`collision_detection_2d`** — 9 new lang files; AABB-vs-AABB,
    circle-vs-circle (squared-distance), AABB-vs-circle clamp,
    point-in-shape, swept AABB time-of-impact.
  - **`game_loop_architecture`** — 11 new lang files (concept-only
    topic; full coverage from scratch, with cyrius.cyr designed
    first as the reference). Fixed-timestep accumulator, spiral-
    of-death cap (5 × dt), update/render separation, deterministic
    timestamps.
  - **`grid_pathfinding`** — 11 new lang files; BFS + A* on an
    8×8 4-connected grid with Manhattan heuristic. A* and BFS
    must agree on path length for uniform-cost grids — verified
    across all 11 ports.
  - **`maze_generation`** — 11 new lang files; iterative recursive
    backtracker on an 8×8 grid with PCG PRNG. **Cross-language byte
    parity confirmed for seed=42**: `cells[0]=13, cells[27]=12,
    cells[63]=6` across Rust/Python/C/Go/TS/Shell/Zig/x86_64/
    AArch64/Cyrius (the PCG output sequence agrees because every
    port uses signed-i64 wrapping arithmetic).

### Changed
- **VERSION** 2.3.2 → 2.3.3.
- **Topic coverage**: 60 topics, 25 → 33 fully covered (the
  original 36 + fixed_point_arithmetic + 8 P0C-1). Per-language
  counts:
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 36 → 44 each
  - x86_64 ASM: 36 → 44 (3 P0C-1 topics added asm_x86_64.s; 5
    already had it)
  - AArch64 ASM: 36 → 44 (all 8 P0C-1 topics added asm_aarch64.s)
  - Cyrius: 36 → 44 (3 P0C-1 topics added cyrius.cyr; 5 already had it)
  - Examples: 411 → 498 (78 new source files; +21%)

### Notes (worth promoting to field-notes in a follow-up)
- **AArch64 `cmp xN, #imm` 12-bit limit**: `cmp` accepts only
  0–4095 unsigned. Larger values (e.g. 4166 = DT_US/4) need
  `ldr xN, =imm` first, same as `mov` 16-bit limit. Surfaced in
  game_loop_architecture's port.
- **AArch64 register clobber across `bl`**: any helper called
  via `bl` clobbers caller-saved x0–x18. Functions that cache
  loop state in caller-saved regs across calls (e.g. `manhattan`
  in grid_pathfinding's A*, `idx` in maze_generation) must use
  callee-saved x19–x28 or recompute after each call. Caught
  cross-call clobber bugs in grid_pathfinding/asm_x86_64.s and
  maze_generation/asm_x86_64.s during port.
- **Bash subshell + stateful PRNG**: `$(rng_next)` runs the
  function in a subshell; `_rng_state` mutations don't propagate.
  Fix: stateful side-effect setter (`rng_next` writes a global
  `RNG_OUT`), callers read the global. Caught in
  game_ai_decisions/shell.sh.

## [2.3.2] — 2026-05-02

### Added
- **`fixed_point_arithmetic` backfilled to 11/11 languages** (P0C-1
  kickoff). Nine new files: `rust.rs`, `python.py`, `c.c`, `go.go`,
  `typescript.ts`, `shell.sh`, `zig.zig`, `asm_aarch64.s`,
  `openqasm.qasm`. All mirror the test set in `cyrius.cyr`
  (`fx_from_int`, `fx_to_int` truncate + round, `fx_mul`,
  `fx_mul_safe`, `fx_div`, sine table peak/trough/zero, roundtrip).
  Each leads with a short comment on the language-specific idiom
  (Rust's `wrapping_*` / `i128`, Python's bigint, C's `__int128`,
  TypeScript's bigint requirement, Bash's `awk`-generated sine
  table, Zig's explicit casts, AArch64's `SMULH+MUL` pair, OpenQASM's
  phase-encoding analog of fixed-point).
- **`scripts/validate-content.sh` now validates Cyrius examples**.
  New `HAS_CYRIUS` toolchain probe + per-topic `cyrius run` block
  mirroring the skip-if-missing pattern of the other languages.
  Toolchain banner expanded: `zig=…  aarch64=…  qasm=…  cyrius=…`.
- **Three new field-note entries in
  `content/cyrius/field_notes/language/parser_syntax.cyml`**
  (5 → 8 entries; total field-note entries 131 → 134), captured
  during the v2.3.2 backfill sweep:
  - `multi_line_struct_enum_bodies_dont_parse` — struct/enum
    bodies must be on one line; multi-line braces silently
    mis-tokenise the body and surface as misleading "undefined
    variable" or "unexpected ';'" errors far from the real cause.
  - `return_struct_literal_dangles_or_rejected` — `return Type {
    … }` either fails to parse or (if wrapped via `var b = …;
    return &b`) returns a dangling stack pointer. Construct in
    caller scope; `alloc()` for heap-resident.
  - `bare_return_in_if_block_rejected` — bare `return;` inside an
    `if { … }` block triggers "unexpected ';'"; must be `return
    0;` (Cyrius has no void).

### Fixed
- **14 pre-existing example failures surfaced by the new validator
  coverage and resolved**. Validator sweep: was 406/420 before
  the Cyrius branch landed, now 420/420 with zero skips on a fully
  stocked toolchain.
  - **4 OpenQASM** files (`instruction_encoding`,
    `linking_and_loading`, `ownership_and_borrowing`,
    `virtual_memory`) used `swap a, b;` — qiskit's `qelib1.inc`
    doesn't define `swap`. Expanded to the canonical 3-CNOT
    decomposition.
  - **2 C** files: `code_generation/c.c` missing `<stdint.h>`
    (gcc 15 strict on `int64_t`); `syscalls_and_abi/c.c` missing
    `_GNU_SOURCE` and `<sys/types.h>` for `pid_t` and `syscall(2)`.
  - **2 x86_64 ASM**: `game_ai_decisions/asm_x86_64.s` had `add
    rax, imm64` (x86 `add` only sign-extends imm32) — split into
    `mov rcx, imm64; add rax, rcx`. `projectile_physics/asm_x86_64.s`
    had a bounce-decay convergence test calibrated for too few
    frames — bumped 200 → 1000 frames, threshold to `2 * GRAVITY`.
  - **5 Cyrius**: `game_ai_decisions`, `state_machines`,
    `sprite_rendering` — multi-line struct/enum bodies, `return
    Struct { … }` builders returning dangling stack pointers, bare
    `return;` inside `if { … }` blocks. `projectile_physics`
    had the same convergence-window miscalibration as its asm
    sibling. `strings` called `fmt_sprintf(buf, fmt, args)` with
    the `bufsz` arg missing (correct shape: `fmt_sprintf(buf,
    bufsz, fmt, args)`). All three cyrius parser quirks captured
    in field notes (see Added).
  - **1 Shell**: `quantum_computing/shell.sh` used `bc -l` for
    floating-point math (`bc` is not POSIX-mandatory and absent
    on default Arch installs); rewrote three helpers to use `awk`
    (always available, same `sqrt`/`log`/`exp` semantics).

### Changed
- **Roadmap rewrite** (`docs/development/roadmap.md`). Header refreshed
  (v2.2.0 → v2.3.2, last-updated 2026-04-08 → 2026-05-01, topics
  36 → 60, examples 396 → 411, Cyrius 5.8.3 noted). Substantive
  updates:
  - **P0B Service Layer marked partially shipped** — HTTP server,
    JSON responses, and 5 of 7 endpoints (`/stats`, `/list`,
    `/languages`, `/search`, `/info/{topic}`) confirmed live in
    `src/main.cyr`'s `cmd_serve`, running on `lib/sandhi.cyr`.
  - **P0B remaining items (P0B-1 … P0B-4)** carved out: wire
    `/compare` and `/gaps` HTTP routes (CLI handlers exist;
    HTTP routing doesn't), verify or implement memory-resident
    mode, sakshi request tracing, content hot-reload.
  - **Completed-since-v2.2 section** added listing the 24 new
    topics that landed alongside cyrius-doom, mabda v3 GPU, and
    ENCOM's Hits, grouped into clusters: graphics (9),
    game-engine (8), database (3), systems & misc (4).
  - **P0C Backfill section** added: ~249 source files needed to
    bring the 24 new topics to 11/11 language parity with the
    original 36. Sized as a multi-release sweep, prioritized by
    cluster maturity (P0C-1 game-engine, P0C-2 graphics, P0C-3
    database, P0C-4 systems & misc). `fixed_point_arithmetic`
    is the first P0C-1 topic landed (see Added).
  - **P3 reorganized**: graphics cluster crossed off (covered by
    P0C-2); audio + AI/ML topics retained.
  - **Field-notes growth pattern** documented as Established at
    v2.3.1 with the three split axes (version arc, surface area,
    phase).
  - **Cyrius pin maintenance** cadence note added: every Cyrius
    minor drives a vidya patch bump for stdlib + language-feature
    alignment, with the 6-step playbook (cyrius.cyml, field
    notes, index verification range, CHANGELOG, zugot recipe).
- **`content/cyrius/field_notes/index.cyml`** — language section
  count 26 → 29 entries; `parser_syntax.cyml` per-file count
  5 → 8 entries with the three new entries listed.
- `VERSION` 2.3.1 → 2.3.2.

## [2.3.1] — 2026-05-01

### Changed
- **Cyrius toolchain pin bumped 5.7.0 → 5.8.3** (`cyrius.cyml`). No
  source changes required — the 5.8.x stdlib is API-compatible with
  the 5.7.0 surface vidya consumes (syscalls, string, alloc, str,
  fmt, vec, hashmap, io, fs, tagged, json, fnptr, args, toml, regex,
  net, sandhi). `cyrius.lock` (sakshi 2.0.0 sha) unchanged.
- **`content/cyrius/field_notes/` reorganised by topic**. The three
  longest field-note files were converted into per-topic subfolders;
  the other five stayed flat. All 131 entries preserved byte-exact
  (`diff` clean against the pre-split source). Index regenerated.
  - `compiler.cyml` (3,944 lines, 46 entries) → `compiler/` split by
    version arc: `v3.cyml` (8), `v4.cyml` (4), `v5_0_to_5_4.cyml` (4),
    `v5_5.cyml` (4), `v5_6.cyml` (11), `v5_7.cyml` (15).
  - `language.cyml` (1,239 lines, 26 entries) → `language/` split by
    surface area: `parser_syntax.cyml` (5), `semantics_runtime.cyml`
    (8), `platform_abi.cyml` (4), `stdlib_format.cyml` (5),
    `diagnostics_caps.cyml` (4).
  - `mabda-v3-gpu.cyml` (1,276 lines, 23 entries) → `mabda_v3_gpu/`
    split by phase: `overview.cyml` (3), `phase_a.cyml` (1),
    `phase_b.cyml` (4), `phase_c.cyml` (9), `phase_d.cyml` (4),
    `research.cyml` (2).
  - `doom.cyml` (11), `cyim.cyml` (12), `encom-hits.cyml` (8),
    `meta.cyml` (4), `kernel.cyml` (1) left flat.
  - `index.cyml` refreshed: stale per-section counts corrected
    (compiler 22→46, language 24→26, mabda 19→23, meta 3→4, encom-hits
    7→8), file-by-file breakdown added for split topics, verification
    range updated to "Cyrius 2.2 → 5.8.x".
- `docs/development/content-grouping.md` field_notes diagram updated
  to `.cyml` extensions and the new subfolder pattern; added a
  "Field-notes subfolder pattern (proven at v2.3.1)" section
  documenting the ~800-line / distinct-sub-topic threshold and the
  three split axes (version arc, surface area, phase).
- `content/cyrius/archive/README.md` path references corrected:
  `../language.toml` → `../language.cyml`,
  `../field_notes/{compiler,language}.toml` → `../field_notes/{compiler,language}/`,
  `../{ecosystem,dependencies,types}.toml` → `.cyml`.

## [2.3.0] — 2026-04-25

### Added
- Four new field-note entries in
  `content/cyrius/field_notes/language.cyml` capturing what surfaced
  during this upgrade:
  - `var_buf_in_library_functions` — `var buf[N]` inside a function
    is **static data**, not stack; consecutive calls clobber any
    Str/buf-borrowing return values. Diagnostic: the build's
    "large static data (N bytes)" warning.
  - `stdlib_str_to_cstr_key_migration` — cyrius 5.x lookup helpers
    (`toml_get`, `toml_get_sections`, …) take cstr keys; passing
    `str_from("…")` silently returns 0.
  - `cyml_toml_plus_markdown_frontmatter` — the CYML format (TOML
    header + markdown body separated by `---`), `lib/cyml.cyr`
    parser API, and the prose-quoting `---` gotcha.
  - `sandhi_service_layer_dep` — sandhi as the cyrius 5.x
    service-boundary stdlib, current `[deps.sandhi]` git-pin
    pattern, planned fold-into-stdlib transition.
- `cyrius.lock` — sha256 hash for `lib/sakshi.cyr` (sakshi 2.0.0,
  the only git-pinned dep); generated by `cyrius deps --lock`,
  enforced by `cyrius deps --verify` on CI once present. Stdlib
  modules (sandhi included) ship with the toolchain and are not
  hashed in the lock.

### Changed
- **HTTP server now runs on `lib/sandhi.cyr`**. Sandhi is the
  service-boundary stdlib that folded into the cyrius toolchain
  at 5.7.0 (HTTP client/server, TLS, headers, service discovery);
  declared as `"sandhi"` in `[deps] stdlib = [...]`. Replaces the
  vendored `lib/http_server.cyr`. Caller renames in
  `src/main.cyr`:
  `http_send_response` → `sandhi_server_send_response`,
  `http_get_param` → `sandhi_server_get_param`,
  `http_path_segment` → `sandhi_server_path_segment`,
  `http_get_path` → `sandhi_server_get_path`,
  `http_server_run` → `sandhi_server_run`.
  `HTTP_OK` / `HTTP_NOT_FOUND` / `HTTP_BAD_REQUEST` / `INADDR_ANY()`
  re-export through sandhi unchanged.
- Build manifest migrated `cyrius.toml` → `cyrius.cyml` with
  `[deps] stdlib = [...]` (sandhi listed as a stdlib name) and a
  `[deps.sakshi]` (2.0.0) git stanza, matching the yukti layout.
  `version = "${file:VERSION}"` so the manifest pulls from the
  VERSION file. Stdlib deps ship with the cyrius toolchain;
  `[deps.<name>]` stanzas are reserved for heavier external
  git-pinned libraries (e.g. sakshi).
- **`content/cyrius/`** migrated TOML → CYML: 13 files, 318
  entries. `[[entries]]` markers preserved; the
  `content = '''...'''` body of each entry moved below a `---`
  delimiter (CYML's TOML-header + markdown-body convention). All
  files round-trip cleanly through `lib/cyml.cyr`. The 64
  `content/<topic>/concept.toml` files are untouched — different
  format, different consumer.
- Vendored stdlib refreshed via `cyrius deps`: `lib/sakshi.cyr`
  (now 2.0.0), `lib/sandhi.cyr` (new, 1.0.0), and incidental
  refreshes to `alloc.cyr`, `args.cyr`, `fmt.cyr`, `fnptr.cyr`,
  `hashmap.cyr`, `io.cyr`, `json.cyr`, `regex.cyr`, `str.cyr`,
  `string.cyr`, `syscalls.cyr`, `tagged.cyr`, `toml.cyr` to match
  the cyrius 5.7.0 stdlib snapshot.
- CI/release workflows ported to the yukti pattern: toolchain
  version derived from `cyrius.cyml` (no env pin), `cyrius deps`
  runs before build, `cyrius deps --verify` gates on `cyrius.lock`
  existing (warns + skips on first push, enforces afterward),
  docs check requires `cyrius.cyml`, version-verify trusts
  `${file:VERSION}` instead of grepping the manifest, and release
  tags accept both `v2.3.0` and `2.3.0` shapes.
- `content/cyrius/field_notes/index.cyml` refreshed: section
  pointer suffixes `.toml` → `.cyml`, "Language Gotchas" entry
  count 17 → 22, verification range "Cyrius 2.2 → 5.7.0".

### Fixed
- Concept loader rewritten to call `toml_parse` directly on a heap-
  allocated read buffer instead of `lib/toml.cyr::toml_parse_file`.
  The stdlib helper declares `var buf[262144]`, which the cyrius
  compiler emits as **static data** (not stack-local) — every
  `toml_parse_file` call shares the same backing memory, so 59 of
  60 concepts' parsed Str values dangled into the last-read file's
  bytes once the 5.7.0 stdlib refresh exposed the path. The build's
  "large static data" warning is the upstream tell.
- All `toml_get` / `toml_get_sections` callers updated from
  `str_from("key")` to bare cstr literals. The 5.x stdlib lookup
  helpers compare via `str_eq_cstr`, which calls `strlen` on the
  second argument — Str values lack a NUL terminator, so every
  lookup silently returned 0, leaving concepts with null ids and
  triggering a `path_join(0, fname)` segfault during content load.

### Removed
- Orphan `lib/http_server.cyr` — superseded by sandhi 1.0.0.
- All `content/cyrius/**/*.toml` files — replaced by `*.cyml`
  equivalents (lossless conversion, verified by entry-count
  parity through the `lib/cyml.cyr` parser).

### Verified
- `cyrius deps --verify` → "1 verified, 0 failed" (sakshi 2.0.0;
  sandhi resolves through the stdlib path, not lockfile-tracked).
- `cyrius build src/main.cyr build/vidya` → 623,712-byte ELF, clean.
- `./build/vidya stats` → 60 topics, 411 examples, 11 languages.
- `list` / `search` / `info` / `gaps` / `languages` exit 0 with
  expected output.
- `lib/cyml.cyr` smoke test against every converted file:
  18 + 6 + 41 + 72 + 1 + 11 + 3 + 8 + 6 + 22 + 31 + 0 + 99 = 318
  entries, matching the original `[[entries]]` counts exactly
  (index.cyml is comment-only, valid as a 0-entry CYML doc).

## [2.2.0] — 2026-04-14

### Changed
- **HTTP server now uses `lib/http_server.cyr`** (cyrius 4.5.0 stdlib).
  Dropped ~270 LOC of hand-rolled plumbing from `src/main.cyr`
  (`make_crlf`, `http_respond`, `http_ok/not_found/bad_request`,
  `http_parse_path`, local `http_get_param`/`http_path_segment`, and
  the bind/listen/accept loop in `cmd_serve`). Routes now go through
  `http_send_response` + `http_server_run`. Behaviour preserved;
  `/info/{topic}` now also benefits from stdlib URL-decoding on
  query strings.
- CI/release workflows bumped to Cyrius 4.5.0 (from 2.7.1).
- Vendored stdlib: added `lib/http_server.cyr`, refreshed
  `lib/fnptr.cyr` to expose `fncall3..fncall6` (needed for the
  `http_server_run` handler callback).

### Verified
- Self-build with cc3 4.5.0: 114KB ELF, clean.
- `vidya serve` end-to-end against `/stats`, `/`, `/list`, `/languages`,
  `/search?q=...`, `/info/{topic}`, plus 400/404 paths — all return
  identical JSON shape to 2.1.0.

## [2.1.0] — 2026-04-09

### Added
- **HTTP service layer** — `vidya serve [port]` starts a localhost JSON API (default port 8390)
  - Endpoints: `/stats`, `/list`, `/search?q=...`, `/info/{topic}`, `/languages`, `/`
  - All responses are JSON, `Connection: close`, proper HTTP/1.1 headers
  - Memory-resident: loads corpus once, serves from RAM
  - 92KB static ELF — no framework, no runtime, no dependencies
- `lib/tagged.cyr`, `lib/json.cyr`, `lib/net.cyr` added to vendored stdlib

### Changed
- CI/release workflows updated to Cyrius 2.7.1 (from 2.2.2)
- Tooling renamed: `cyrb` → `cyrius`, `cyrb.toml` → `cyrius.toml`
- `cyrius.toml` updated to `[package]`/`[build]` section format
- Sakshi re-vendored (v0.7.0)
- CI content validation skips `content/cyrius/` (language reference, not a topic)
- Added `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (missing after port)
- All doc references updated from `cyrb`/`cc2` to `cyrius` CLI

## [2.0.0] — 2026-04-08

Major version bump: vidya is no longer a Rust crate. It is a Cyrius program with a complete
11-language corpus. The Rust implementation is preserved in `rust-old/` but is no longer the
primary interface. This is a breaking change for anyone importing `vidya` as a Rust dependency.

### Breaking
- **Implementation language changed from Rust to Cyrius** — `Cargo.toml`, `src/*.rs` moved to `rust-old/`
- **Binary interface changed** — vidya is now a standalone CLI tool (`build/vidya`, 85KB ELF), not a library crate
- **11th language added** — `Language::Cyrius` variant changes the `Language` enum (was 10 variants, now 11)

### Added — Cyrius Port
- **Ported vidya from Rust to Cyrius** — 85KB static ELF binary, 600 lines of Cyrius replacing 2,396 lines of Rust
- Cyrius CLI tool (`src/main.cyr`) with commands: `list`, `search`, `info`, `compare`, `validate`, `gaps`, `stats`, `languages`, `help`
- TOML content loader, hashmap registry, full-text search, cross-language comparison — all in Cyrius
- **Sakshi integration** — structured tracing and error handling via vendored `lib/sakshi.cyr` (stderr-only profile)
- `cyrb.toml` project manifest for Cyrius build tooling
- Vendored 29 Cyrius stdlib modules in `lib/`
- Rust source preserved in `rust-old/` for reference

### Added — Language: Cyrius
- **Cyrius as 11th language** — `Language::Cyrius` variant with `.cyr` extension, `#` comment prefix
- Cyrius validation command: pipes through `cc2` from `$CYRIUS_HOME`
- 20 Cyrius content implementations across topics (pattern-focused, documenting actual Cyrius/AGNOS patterns)

### Added — Content Expansion (193 → 396 examples)
- **203 new language implementations** across all 36 topics
- All 36 topics now complete (11/11 languages each) — up from 15 complete
- New implementations by language:
  - **Go**: 16 new topics (compiler, OS, language design, tracing)
  - **Zig**: 20 new topics (compiler, OS, language design, tracing)
  - **TypeScript**: 20 new topics (compiler, OS concepts, language design, tracing)
  - **Shell**: 21 new topics (scripting patterns for every domain)
  - **x86_64 Assembly**: 19 new topics (real machine-level demonstrations)
  - **AArch64 Assembly**: 20 new topics (ARM64 cross-platform coverage)
  - **OpenQASM**: 21 new topics (quantum analogies for classical concepts)
  - **Python**: 20 new topics (compiler, OS, language design)
  - **C**: 20 new topics (compiler, OS, systems)
  - **Cyrius**: 20 new topics (AGNOS patterns, cc2 internals)
  - **Rust**: 1 new topic (tracing)

### Added — Testing & Benchmarks
- `tests/vidya.tcyr` — 37 Cyrius-native tests (language enum, TOML loading, registry, file discovery, content scanning)
- `tests/vidya.bcyr` — 6 benchmarks (load_concept: 28μs, load_all: 2.35ms, reg_get: 493ns, search: 4μs)
- `BENCHMARKS.md` — Cyrius vs Rust comparison with charts (`docs/benchmarks.png`, `docs/benchmarks-tiers.png`)
- Benchmark history: `bench-history.csv` (Cyrius), `bench-history-rust.csv` (Rust baseline)

### Added — Documentation & Infrastructure
- `docs/sources.md` — source citations for language specs, algorithms, standards
- `docs/usage.md` — complete CLI usage guide
- `docs/development/learning-paths.md` — 5 ordered learning paths (Compiler, OS, Systems, Language Design, Quantum)
- `docs/development/content-grouping.md` — future subdirectory plan for 50+ topics
- `related_topics` field added to all 36 `concept.toml` files — cross-references between topics
- `vidya gaps` command — reports missing language implementations per topic
- `.gitignore` updated: `*.rlib`, `rust-old/target/`
- Documented `qelib1.inc` location in content-format.md

### Changed
- Version bump from 1.5.0 to 2.0.0 — breaking: implementation language changed from Rust to Cyrius
- Binary: Rust crate (~800KB release) → Cyrius binary (85KB static ELF)
- Dependencies: 8 Rust crates → 0 external deps (vendored Cyrius stdlib)
- Total: **36 topics**, **396 examples** across **11 languages**

### Performance — Cyrius vs Rust
| Benchmark | Cyrius | Rust | Winner |
|-----------|--------|------|--------|
| load_all (35 topics) | 2.35ms | 3.83ms | Cyrius 1.6x |
| load_concept | 28μs | 123μs | Cyrius 4.4x |
| search_text | 4μs | 30μs | Cyrius 7.6x |
| reg_get_hit | 493ns | 17ns | Rust 30x |
| Binary size | 85KB | 800KB | Cyrius 9.4x |

## [1.5.0] — 2026-04-04

### Added
- **18 new topics** covering compiler internals, systems programming, language design, and low-level fundamentals:
  - Compiler internals: `lexing_and_parsing`, `code_generation`, `intermediate_representations`, `linking_and_loading`, `optimization_passes`
  - Systems programming: `syscalls_and_abi`, `virtual_memory`, `interrupt_handling`, `process_and_scheduling`, `filesystems`
  - Language design: `ownership_and_borrowing`, `trait_and_typeclass_systems`, `macro_systems`, `module_systems`
  - High-value additions: `instruction_encoding`, `elf_and_executable_formats`, `allocators`, `boot_and_startup`
- 18 new `Topic` enum variants with Display implementations
- Rust implementations for all 18 new topics (concept.toml + rust.rs each)
- Total: **33 topics**, 173+ content examples across 10 languages

## [1.0.0] — 2026-03-30

### Added
- **Design Patterns** topic: builder, strategy, observer, state machine, RAII/cleanup, dependency injection, factory — all 10 languages
- Total: **150 content examples** across 15 topics and 10 languages
- Native OpenQASM 2.0 validation via `openqasm` crate (feature: `openqasm`) — no Python/qiskit dependency needed
- `openqasm` added to `full` feature set
- `test_qasm` example for standalone QASM validation
- 4 new benchmarks: `search_quantum`, `search_multi_tag`, `compare_all_languages` + fixed `search_text_miss`

### Changed
- Updated `basic.rs` example to demonstrate full 15-topic corpus (load, search, compare, browse)
- Updated README.md with 15 topics, 10 languages, feature flags, validation instructions
- Updated architecture docs and content format spec for all languages
- `validate.rs`: OpenQASM uses native Rust parser when `openqasm` feature is enabled, falls back to Python/qiskit otherwise
- **140 content examples** across 14 topics and 10 languages
- 4 new topics: **Security**, **Algorithms**, **Kernel Topics**, **Quantum Computing**
  - Security: input validation, injection prevention, constant-time comparison, secret zeroing, path traversal, parameterized queries, XSS prevention, safe deserialization
  - Algorithms: binary search, insertion sort, merge sort, BFS/DFS graph traversal, dynamic programming (Fibonacci, LCS), two-sum hash map, GCD
  - Kernel Topics: page table entries (x86_64 4-level), virtual address decomposition, MMIO volatile registers, interrupt descriptor tables, GDT entries, ABI/calling conventions (SysV AMD64, AAPCS64), struct packing, ELF parsing, quantum error correction
  - Quantum Computing: state vector simulation, Hadamard/CNOT/CZ gates, Bell states, GHZ states, Grover's search (2-qubit and 3-qubit), quantum phase estimation, VQE ansatz, Shor's period-finding, noise channels (depolarizing, amplitude damping, dephasing), dynamical decoupling
- `Topic::KernelTopics` and `Topic::QuantumComputing` variants in the crate
- OpenQASM quantum content for all 14 topics — validated via qiskit
- Full quantum simulator in Rust, Python, Go, C, TypeScript, and Zig (complex arithmetic, gate matrices, measurement probabilities)

### Changed
- Version bump from 0.1.0 to 1.0.0 — stable API and content corpus
- `validate-content.sh`: shell scripts now fully execute (was `bash -n` syntax-only)
- `validate-content.sh`: C compilation upgraded to `-std=c17 -lm -lpthread`
- `validate.rs`: C validation now uses `-std=c17 -lm -lpthread` (matching script)
- `validate.rs`: Shell validation now runs `bash` (not `bash -n`)

### Fixed
- Broken rustdoc intra-doc link in `language.rs` (`extension()` → `Self::extension()`)

## [0.1.0] — 2026-03-27

### Added
- Core crate with types: `Concept`, `Topic`, `Example`, `BestPractice`, `Gotcha`, `PerformanceNote`
- `Language` enum supporting Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM
- `Registry` for in-memory concept storage with lookup and filtering
- `SearchQuery` and `search()` for full-text and tag-based search with relevance scoring
- `SearchQuery` builder methods: `with_language()`, `with_limit()`, `with_tags()`
- `Comparison` and `compare()` for cross-language side-by-side views
- `ValidationResult` and `run_validation()` / `validate_all()` for compile/run verification
- Content loader (`loader` module) — reads `concept.toml` + language files into Registry
- TOML-based content format specification (`concept.toml`)
- MCP tool integration via `bote` (feature: `mcp`) — search, get, compare, list tools
- Content: 10 topics with all 10 language implementations
  - strings, error_handling, iterators, memory_management, pattern_matching,
    type_systems, concurrency, testing, performance, input_output
- Integration tests for loader, validation, and MCP dispatch
- `scripts/validate-content.sh` — shell-based content validation
- `scripts/bench-history.sh` — benchmark tracking with git context
- GitHub Actions CI pipeline (stable + MSRV 1.89, content validation)
- Criterion benchmarks: 12 benchmarks covering registry, search, compare, and loader
- `basic` example demonstrating the full API
- Architecture documentation in `docs/`

### Improved
- Search relevance scoring: exact ID/title/tag matches now score higher than substring matches
- Benchmarks use real loaded content instead of empty registries

### Fixed
- Search scoring bug: text+tags queries no longer return false positives when tags match but text doesn't
- Validation temp file collisions: each run uses unique per-process temp paths
