# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **P4 build-tooling cluster complete — 3 new topics, 77 topics / 847
  examples, all 11/11.** `build_systems`, `package_resolution`, and
  `reproducible_builds` close P4. Each was designed Cyrius-first and
  ported to the other 10 languages (rust / python / c / go / typescript
  / shell / zig 0.16 / x86_64 asm / aarch64 asm + an OpenQASM thematic
  analog), with a fixed scenario contract asserted identically in every
  port. Validator: 847/847 green.
- **New topic: `build_systems` — DAG + topological order + incremental rebuild.**
  A minimal build-system core across all 11 languages: a DAG of build
  targets, Kahn topological ordering, content-signature dirty-tracking
  (input signature = source mixed with dependencies' output signatures,
  `HB=131`/`HM=1000003` polynomial), ninja-style incremental rebuild
  (only dirty targets run; content-addressed outputs let unchanged
  rebuilds cut off downstream), and cycle detection. The Cyrius
  reference (`content/build_systems/cyrius.cyr`) was designed first,
  then ported to rust / python / c / go / typescript / shell / zig 0.16
  / x86_64 asm / aarch64 asm, plus an OpenQASM thematic analog (the
  dependency DAG as a topologically-ordered CNOT cascade with X-driven
  dirty propagation). The same six-scenario contract holds in every
  port: topo orders all 3 targets (app after both deps); cold build
  rebuilds 3; a no-edit build rebuilds 0; editing one leaf rebuilds it
  + the root (2) while the sibling stays untouched; a 2-node mutual
  dependency is detected as a cycle. `concept.toml` carries 4 best
  practices, 4 gotchas (bad/good), and 2 performance notes (ninja null
  build, content-addressed caching).
- **New topic: `package_resolution` — semver + constraint solving.**
  Semantic versions encoded as a comparable integer triple, caret
  (`^x.y.z`) constraint ranges, range intersection for diamond
  dependencies, highest-compatible-version selection, bounded
  backtracking (the highest version of one package can force an
  impossible constraint on another — step down and re-solve), and
  dependency-cycle detection. Contract per port: semver ordering and
  major extraction; caret bounds + satisfaction; `^1.0.0 ∩ ^2.0.0` is
  empty; highest match in `^1.0.0` is 1.5.0; a diamond on a shared dep
  resolves to 1.5.0; conflicting carets are unresolvable; backtracking
  picks A 1.0.0 (not 1.1.0) with C 1.5.0; A↔B is a cycle, a diamond is
  acyclic. `concept.toml`: 4 best practices, 4 gotchas (incl. the 0.x
  caret special case and lexicographic-compare bug), 2 perf notes
  (pubgrub/conflict-learning, lockfiles).
- **New topic: `reproducible_builds` — deterministic, bit-for-bit output.**
  The three classic non-determinism leaks and their fixes: wall-clock
  timestamps → clamp to `SOURCE_DATE_EPOCH`; unstable readdir/hash-map
  order → sort before emitting; non-deterministic artifact names →
  content-addressing. Modeled as a build that folds a (normalized)
  timestamp and a sorted file set into one digest; the contract proves
  a deterministic pipeline (sort + normalize) yields byte-identical
  digests across runs that differ in BOTH input order and wall-clock
  time, while the naive pipeline drifts, and that timestamp
  normalization alone removes clock dependence. `concept.toml`: 4 best
  practices, 4 gotchas (incl. embedded build paths, parallel-write
  ordering), 2 perf notes (Debian reproducible-builds, `-trimpath` /
  go.sum). Validator across the cluster: 847/847 green.

## [2.7.2] — 2026-06-12

### Changed

- **Cyrius pin: 5.11.55 → 6.1.41.** Crosses the 6.0.x line into the
  6.1.x series the rest of the ecosystem now rides (sandhi 6.1.21,
  sakshi 6.1.17, vyakarana 6.1.24, sit 6.1.30, hoosh 6.1.31).
  Rehydration is `cyrius lib sync` (syncs vendored `lib/` to the
  manifest pin — 88 `.cyr` files from
  `~/.cyrius/versions/6.1.41/lib/`) rather than `cyrius update`, which
  re-resolves to the *wrapper's* version and would have pulled 6.2.0.
  Build with the pinned toolchain
  (`CYRIUS_HOME=~/.cyrius/versions/6.1.41 cyrius build --strict-pin …`)
  so cycc matches the pin; the default wrapper is 6.2.0 and
  `--strict-pin` rejects that drift. `cyrius.lock` is now populated
  (89 deps locked) where it had been empty.
- **Stdlib `json` + `toml` + `base64` → bundled `bayan` module.** 6.1.x
  stopped shipping the standalone `lib/{json,toml,base64}.cyr`; they now
  live in the `bayan` distlib (matching sit / hoosh on 6.1.x). Updated
  `cyrius.cyml` `[deps] stdlib` and the `include "lib/…"` lines in
  `src/main.cyr`, `tests/vidya.tcyr`, `tests/vidya.bcyr` (deduped — one
  `bayan` include replaces the separate json/toml includes). Without
  this, a clean `cyrius lib sync` (no stale standalone copies) fails
  with `cannot read ./lib/json.cyr` (and toml/base64) — the dirty mixed
  `lib/` only masked it.
- **sakshi: 2.2.4 → 2.2.10.** Latest tracing release.
- **vyakarana: 2.2.1 → 2.2.3.** Latest streaming-tokenizer release.
- **Binary size: ~1.1 MB → ~2.1 MB static ELF.** The 6.1.x stdlib is
  larger; the build flags ~1934 unreachable fns (DCE-eliminable via
  `CYRIUS_DCE=1`). `cyrius test` green (41 passed, 0 failed); corpus
  holds at 74 topics × 11 languages = 814 examples.
- **Zig content pin: 0.15.2 → 0.16.0** (latest language release; CI
  `ZIG_VER`, `docs/sources.md`, `README.md`, `content-format.md`,
  `getting-started.md`, roadmap all follow). All 14 `content/*/zig.zig`
  examples migrated to the 0.16 API — `std.heap.GeneralPurposeAllocator`
  → `std.heap.DebugAllocator`, and the 0.16 `std.Io` interface
  (`std.Io.Threaded` backend) now threads through the filesystem
  (`std.Io.Dir.cwd`, positional `read/writePositionalAll`), `std.Io.Mutex`,
  `io.random`, and the rewritten `std.Io.Writer` ("Writergate":
  `std.Io.Writer.Allocating`, `.fixed`, `PriorityQueue` unmanaged
  `push`/`pop`). Each rebuilt + run green under Zig 0.16.

### Added

- **Kernel field notes brought current through agnos 1.41.x** —
  `content/cyrius/field_notes/kernel.cyml` grew from 5 to 9 entries,
  closing the gap from the 1.31.x storage trio (where it had stalled)
  through the shell-separation arc. Each entry was mined from the agnos
  CHANGELOG + agnosticos iron-nuc-zen-log + kernel source, then
  adversarially fact-checked against those sources (every version
  number, byte-size, date, and the QEMU-vs-iron honesty bar
  re-derived, not taken from the draft):
  - `the_unicast_that_couldnt_arrive` — agnos 1.32.x networking. The
    ~14-burn chase of a phantom RTL8168H/8111H L2 accept-filter that
    ended at an RX descriptor ring 16→64 deepening; the
    audit-re-derive-don't-validate-comments lesson. Iron-validated
    2026-05-25.
  - `learning_to_write` — the two write arcs: 1.33.x ext2 indirect
    write (demo→base exit, iron-proven 2026-05-25) and the 1.41.x
    `VFS_SEC_WFILE` FAT/exFAT write-fd (software-complete, iron burn
    pending). Buffer lifecycle under an alloc-only heap; why
    iron-validation is per-arc and never transfers.
  - `exec_from_disk_the_four_in_one_burn` — agnos 1.40.x exec-from-disk.
    Loading a static ELF64 off ext2 into ring 3; the iron-only fault
    chain (gnoboot's ≥4 GB `boot_info` read, the scheduler dead-proc
    reset, the boot-stack `.rodata` stomp, the mount-routing lie) and
    the single `14013` burn that iron-validated four cuts at once
    (2026-05-31). The 1.40.14 teardown closeout shipped QEMU-only.
  - `the_shell_leaves_the_kernel` — agnos 1.37.5 + 1.41.x. The console
    font extracted to the `kashi` library (and the build-prepend
    footgun that left `bench.sh` latently broken), then the interactive
    shell walked out of ring 0 into a userland `agnsh` while a recovery
    REPL stays behind — the permanent kernel↔userland boundary.
    Software-complete and QEMU-green; **iron burn pending** (staged at
    1.41.11 behind the `#tracker-141x-cycle` A1–A4 rubric).

### Fixed

- **4 Cyrius examples broke under the 6.x toolchain** (surfaced by the
  pin bump; `scripts/validate-content.sh` is the gate):
  - `type_systems`, `design_patterns` — Cyrius 6.x dropped struct
    *field-access sugar* (`v.x` read/write silently resolved to 0).
    `Struct { … }` value-literals and `v.method()` dispatch still work;
    field access is now explicit pointer ops — `load64(&v + off)` /
    `store64(&v + off, …)` for inline value structs, `load64(ptr + off)`
    for heap records — the idiom vidya's own `Concept` type already used.
  - `distributed_systems` — single-letter uppercase globals `W`/`R`
    collided with reserved identifiers in 6.x (`W` silently read as 0,
    breaking the quorum gate); renamed to `W_QUORUM`/`R_QUORUM`.
  - `tracing` — `include "sakshi.cyr"` → `include "lib/sakshi.cyr"`
    (sakshi now vendors into `lib/`).
- `content/allocators/c.c` — unused-but-set `count` under gcc 16's
  stricter `-Werror`; folded into the fill-loop status print.
- `content/cyrius/field_notes/index.cyml` Kernel section was stale —
  it claimed "3 entries," listed only 2, and the file already held 5.
  Now lists all 9 (registering the previously-unlisted
  `the_mvp_gate_at_attempt_68` and `the_storage_trio_iron_debut`) with
  the count and subtitle corrected.

## [2.7.1] — 2026-05-16

### Changed

- **Cyrius pin: 5.9.43 → 5.11.55.** Absorbs the 5.10.x and 5.11.x
  cycles in one bump. Rehydration is now `cyrius update` (copies
  stdlib from `~/.cyrius/versions/<ver>/lib/` into `lib/` and
  re-resolves git deps); `cyrius deps` alone only handles
  `[deps.NAME]` git entries.
- **sakshi: 2.0.0 → 2.2.4.** Picks up cycle-counter timestamps
  (`_sk_now_ns` no longer goes through the kernel; ~22 ns on
  x86_64 via `rdtsc`+Q32 mul-shift, instant on aarch64 via
  `mrs cntvct_el0`), opt-in `sakshi_clock_recalibrate()`,
  aarch64 portability with arch-dispatched syscalls, and the
  v5.11.x `: i64` annotation pass. Public API surface
  unchanged.
- **vyakarana: 1.11.1 → 2.2.1.** Major bump; only scheduled
  API break in the roadmap. `tokenize_source(src, lang)`
  removed in favor of the push-based streaming API
  (`tokenize_stream_new` / `_feed` / `_finish` / `_free`) per
  vyakarana ADR 0017. Vidya's two consumers — `vidya code`
  CLI (`src/main.cyr:877`) and `GET /code/{topic}/{lang}`
  (`src/main.cyr:1569`) — migrated in place; observable
  output is byte-identical (rust track of
  `content/lexing_and_parsing/` re-verified at 2187 tokens
  on 8829 source bytes, same as 2.7.0). Also gets the
  compose-rule prefix-buffering streaming fix (2.2.1
  FINDING-011).
- `cyrius.cyml` `[deps] stdlib` extended with `tls`, `base64`,
  `fdlopen` — sandhi pulls `TLS_EARLY_DATA_*`, `fdlopen_*`,
  `base64_encode` via transitives that cyrius v5.10.x SLOT 19
  doesn't follow through enum/constant references. Mirrors sit's
  documented gap-list. Other undefined-symbol notes from sandhi
  (`hashmap_*`, `cyr_munmap`, `dynlib_*`, `clock_now_*`) land in
  DCE-eliminated paths and don't gate the build.
- `lib/` and `cyrius.lock` are now build artifacts under the
  5.11.x model — `lib/` is gitignored; lockfile defaults to empty
  on resolve.
- **CI/release workflows refreshed** for the 5.11.x model
  (mirrors sit / sigil / sandhi):
  - Cyrius install: hand-rolled tarball extract → upstream
    `install.sh` pipe (lays out `$HOME/.cyrius/versions/$VER/`
    + flat symlinks + `current` pointer correctly).
  - Dep resolution: two-step — `cp -rL $HOME/.cyrius/lib/* lib/`
    then `cyrius deps`. The pre-5.11 `cyrius deps --verify` step
    is gone (lockfile is empty under 5.11.x and gitignored).
  - `cyrius lint src/main.cyr` added as a CI gate (per-file in
    5.7+; cosmetic 120-char warnings tolerated, everything else
    hard-fails).
  - Release tarball no longer ships `lib/` (binary is statically
    linked) or `cyrius.lock` (gitignored).
- **`scripts/version-bump.sh` rewritten** — pre-2.0 cargo-era
  references (`Cargo.toml`, `cargo generate-lockfile`, the
  CLAUDE.md `**Version**` sed that no longer matches anything)
  are gone. Bump now writes `VERSION` and stamps
  `CHANGELOG.md`; cyrius.cyml inherits via `${file:VERSION}`.

### Added

- **`scripts/validate-content.sh` is now a CI gate.** The
  Content Validation job installs every language toolchain
  (zig 0.13.0, aarch64 binutils, qemu-user-static, tsx, qiskit,
  cyrius) and runs the full 814-example × 11-language sweep on
  every push/PR. Per CLAUDE.md Content Standards: every example
  MUST compile/run; ~10 min wallclock.
- **aarch64 release artifact (best-effort).** `release.yml`
  cross-builds `vidya-<tag>-aarch64-linux` via
  `cyrius build --aarch64` when `cc5_aarch64` is shipped with
  the pinned cyrius. Mirrors sit's pattern; ships x86_64 alone
  if cross-build fails or the cross-compiler isn't bundled.

## [2.7.0] — 2026-05-08

**Minor opens P4 (build systems) — infra bump turn before topic
work.** No new topic content; surface area is toolchain alignment,
new dependency wiring, and spec/doc cleanup ahead of the
2.7.x topic batch (build_systems, package_resolution,
reproducible_builds).

### Changed

- **Cyrius pin: 5.8.34 → 5.9.43.** Entire 5.9.x cycle absorbed
  in one bump (43 patches over 2 days, closed 2026-05-08).
  Highlights: niyama 1.0.1 fold (.0, 8th sibling distfile,
  6,664 lines, 5 regex engines), sovereignty pass kickoff (.1,
  743 LOC of bash audit-dispatcher → `programs/check.cyr` +
  `lib/audit_walk.cyr` 78th stdlib module),
  agnosys `#derive(Serialize)` cascade incl. Mach-O ARM64 fnptr
  ASLR fix (.33–.39), cx Phase 2c parity (.40), tls-live gate
  conversion + `.sh-conversion arc CLOSED (.41),
  `lib/regression.cyr` 79th stdlib testing-stdlib carve-out
  (.42, 22 verbs across display/buffer-scan/process/network/SSH).
  Self-host byte-identical at 751,744 B.
- `content/cyrius/language/index.cyml` verified-on bumped to
  5.9.42; `content/cyrius/language/stdlib_modules.cyml` adds
  16th entry documenting `regression_module`.
- `docs/development/content-format.md` extended to document the
  two non-topic entries under `content/`: the `cyrius/`
  language-reference subtree and `qelib1.inc` (load-bearing
  shared OpenQASM include — qiskit `include_path=[content/]`).
  Resolves the long-standing 76-vs-74 entry-count confusion in
  `ls content/` output.

### Added

- `[deps.vyakarana]` in `cyrius.cyml` pinned at **1.11.1**;
  `lib/vyakarana.cyr` vendored via `cyrius deps` (2547 lines;
  inlines all 38 grammars via `_grammar_blob_data` so consumers
  don't need `grammars/*.cyml` at runtime cwd).
- **`vidya code <topic> <lang>` CLI** — prints source with
  vyakarana token coloring (ANSI: keyword=blue, string=green,
  number=cyan, comment=dim, operator=magenta, preprocessor=
  yellow, error=red-bg). Falls back to plain source for
  languages without a vyakarana grammar (OpenQASM in 1.11.x).
- **`GET /code/{topic}/{lang}` HTTP route** — JSON response
  `{topic, language, path, source, tokens:[{kind, start, len}]}`.
  Theme contract per vyakarana ADR 0004: consumers index palettes
  by `kind` string, never by integer. Smoke-verified end-to-end:
  2187 tokens on the rust track of `content/lexing_and_parsing/`
  (8829 source bytes); OpenQASM gracefully returns `tokens:[]`.

### Fixed

- Repo hygiene: removed 7× `qemu_*.core` debris (~57 MB) from
  repo root left behind by 2026-05-02 aarch64 cross-test runs.
  Already gitignored (`*.core` + `qemu_*.core`); was a working-
  tree leak only.

## [2.6.4] — 2026-05-03

**P3 complete — `embeddings` shipped at 11/11 languages.**
Closes the Audio + AI/ML minor (5 topics × 11 langs over
2.6.0–2.6.4).

Three vector-search primitives in Q15 fixed-point:
- **Cosine similarity** as a plain dot product over pre-normalized
  unit vectors (the production trick — normalize once at insert,
  cosine is sqrt-free at query time)
- **Brute-force nearest-neighbour** scan
- **Top-k neighbours** via repeated argmax-on-unmarked

Hand-designed 4-vector unit-length corpus (axis-aligned + diagonal +
opposite) demonstrates: self-similarity ≈ 1.0, orthogonal = 0,
opposite ≈ -1.0, ranking by alignment, all bit-identical across
ports.

11 new source files; validator 803/803 → **814/814**. **🎉 P3
Audio + AI/ML complete — 5/5 topics × 11 langs landed.**

### Added

- `content/embeddings/` — vector-search primitives across 11
  languages: cyrius (13 tests / 23 asserts), HLLs (13 tests /
  16–17 asserts each), asm pair (9 tests / 9 asserts focused on
  dot + brute-force nearest; top-k mark/scan/zero in cyrius.cyr —
  too verbose for asm), OpenQASM (inner-product-as-overlap: SWAP
  test with cswap decomposed as cx + ccx + cx since qiskit
  qasm2's standard set excludes cswap).

## [2.6.3] — 2026-05-03

**P3 batch 4 — `inference` shipped at 11/11 languages.**
Three decode-time primitives in pure integer arithmetic: greedy
decoding (argmax over logits), top-k filtering (zero out all but
the K highest), and an autoregressive bigram decode loop with
EOS termination + max_length cap.

Hand-designed bigram table demonstrates greedy decode from
"hello" → "world" → "the" → "end" → EOS, deterministic across
all ports.

Skipped intentionally: temperature scaling, softmax, random
sampling — those need either exp() or a portable PRNG, both of
which fight cross-port portability (especially asm + shell).
concept.toml covers them as best practices and gotchas.

11 new source files; validator 792/792 → **803/803**. P3 is 4/5
topics in flight; `embeddings` (2.6.4) closes P3.

### Added

- `content/inference/` — inference decode primitives across 11
  languages: cyrius (10 tests / 29 asserts), HLLs (10 tests /
  17–21 asserts each — variations from per-element vs array
  comparisons), asm pair (5 tests / 9 asserts focused on argmax
  + bigram lookup + decode loop; top-k's triple-nested
  mark/scan/zero pattern lives in cyrius.cyr — too verbose for
  asm), OpenQASM (measurement-as-greedy-decode: ry encodes
  logits as amplitudes, measurement collapses to argmax, top-k
  modeled as amplitude amplification).

## [2.6.2] — 2026-05-03

**P3 batch 3 — `neural_networks` shipped at 11/11 languages.**
Tiny 2 → 3 → 2 MLP forward pass in Q15 fixed-point. Three
primitives (dense layer, ReLU, argmax) composed into a binary
classifier on hand-designed weights — predicts which input
feature is larger.

Skips softmax intentionally: argmax preserves order, and
production inference does the same (softmax is a training-time
construct for cross-entropy loss). This keeps the example pure
integer arithmetic across all 11 ports — no exp() approximation
needed.

11 new source files; validator 781/781 → **792/792**. P3 is 3/5
topics in flight; `inference` + `embeddings` slated for
2.6.3–2.6.4.

### Added

- `content/neural_networks/` — Q15 MLP forward pass across 11
  languages: cyrius (12 tests / 21 asserts), HLLs (12 tests / 16
  asserts each — HLLs collapse the per-element ReLU checks into
  array-equality), asm pair (8 tests / 8 asserts focused on full
  forward pass through dense + ReLU + argmax with hardcoded layer
  sizes), OpenQASM (rotation-as-weighted-sum: ry encodes inputs as
  amplitudes, cu3 applies controlled rotations as weights, reset
  models ReLU, measurement models argmax). One AArch64 gotcha
  surfaced: `mov w0, #-N` zero-extends to a large positive i64
  before mul; use `mov x0, #-N` for negative immediates.

## [2.6.1] — 2026-05-03

**P3 batch 2 — `audio_synthesis` shipped at 11/11 languages.**
Q15 fixed-point synth primitives (oscillators, ADSR envelope,
voice). API surface mirrors the production AGNOS synth crate
`naad` (Waveform, Adsr, EnvelopeState, gate_on/off, Voice) so
the corpus example reads as a portable educational version of
the same algorithms — naad uses f32 + PolyBLEP for production;
this corpus uses Q15 + naive waveforms for clarity and bit-exact
cross-port portability.

Three primitives:
- **Oscillator** — 16-bit phase accumulator + 16-entry Q15 sine
  LUT, naive saw (linear ramp), naive square (sign-of-phase).
- **ADSR envelope** — 5-state machine (Idle → Attack → Decay →
  Sustain → Release → Idle). Linear segments, sample-counted
  phases. Captures `release_start` at gate_off so Release
  ramps from current level (the click-on-early-release fix).
- **Voice** — oscillator × envelope, sample by sample.

11 new source files; validator 770/770 → **781/781**. P3 is 2/5
topics in flight; `neural_networks`, `inference`, `embeddings`
slated for 2.6.2–2.6.4.

### Added

- `content/audio_synthesis/` — Q15 synth primitives across 11
  languages: cyrius (11 tests / 25 asserts), HLLs (11 tests / 25
  asserts each — naad-style API names), asm pair (8 tests / 13
  asserts focused on phase + sine LUT + square + ADSR full state
  machine; saw + Voice dispatch in cyrius.cyr — too verbose for
  asm), OpenQASM (rotation-as-oscillation: `ry` advances phase,
  H+Z prepares square, `ccx` gates voice on env × osc).

## [2.6.0] — 2026-05-03

**P3 kickoff — Audio + AI/ML (minor bump)** — `audio_dsp`
shipped at 11/11 languages. Q15 fixed-point throughout (matches
hardware PCM, bit-exact across language ports).

Three building blocks:
- **Biquad filter** — Direct Form I IIR with 5 coefs (b0,b1,b2,a1,a2)
  + 4 state slots; one topology, every filter shape. 1-pole lowpass
  helper demonstrated under tests (passes DC, attenuates Nyquist).
- **FIR convolution** — N-tap kernel with shifting history; identity
  + moving-average kernels under test.
- **Level metering** — peak (max abs) and mean-absolute over a
  sample buffer.

11 new source files; validator 759/759 → **770/770**. P3 is 1/5
topics in flight; `audio_synthesis`, `neural_networks`,
`inference`, `embeddings` slated for 2.6.1–2.6.4.

### Added

- `content/audio_dsp/` — Q15 fixed-point DSP across 11 languages:
  cyrius (9 tests / 17 asserts), HLLs (9 tests / 14 asserts each
  — collapse the q_mul-bounds-check pair into a single range),
  asm pair (8 tests / 10 asserts focused on biquad lowpass + peak
  + mean-absolute; FIR omitted — variable-size kernels too verbose
  for asm), OpenQASM (interference-as-filtering: ry rotation as
  filter coefficient, Hadamard interference as 2-tap moving-avg,
  Toffoli OR as peak-detection).

## [2.5.2] — 2026-05-03

**P2 complete — `distributed_systems` shipped at 11/11 languages.**
Closes the Distributed Systems minor (3 topics × 11 langs over
2.5.0–2.5.2).

The topic covers three foundational patterns not subsumed by
`transactions_and_acid` or `consensus`:

- **Vector clocks** — per-node logical counters with element-wise
  compare returning LESS / EQUAL / GREATER / **CONCURRENT** (the
  fourth outcome that integer compare doesn't have)
- **Quorum reads/writes** — Dynamo-style N=3, W=R=2, where R+W>N
  intersection guarantees every read quorum overlaps the latest
  write quorum
- **Partition handling** — partition / heal a node, demonstrate
  write-quorum failures on the minority side, and intersection-
  based stale-data avoidance after heal

11 new source files; validator 748/748 → **759/759**. P2 is
**3/3 done**; next minor (2.6.x) opens **P3 audio + AI/ML**.

### Added

- `content/distributed_systems/` — three foundations across 11
  languages: cyrius (12 tests, 26 asserts), HLLs (12 tests, 17
  asserts each — HLLs collapse repetitive vector-clock comparisons
  into single equality assertions), asm pair (5 tests, 11 asserts
  focused on the quorum-replication core; vector clocks live in
  cyrius.cyr — element-wise compare too verbose for asm),
  OpenQASM (entanglement-as-replication: CNOT fan-out for write
  quorum, measurement of read quorum demonstrates the intersection
  guarantee).

## [2.5.1] — 2026-05-03

**P2 batch 2 — `consensus` (Raft) shipped at 11/11 languages.**
3-node Raft cluster modelled as in-memory state machines.
Demonstrates the five Raft safety properties under tests:

- **Term monotonicity** — terms only increase; stale RPCs rejected
- **Election safety** — vote uniqueness (one vote per node per term)
- **Log matching** — replicate copies leader's log entry-by-entry
  with term-mismatch truncation
- **Leader completeness** — log up-to-date check on RequestVote
  denies candidates with shorter or stale logs
- **State machine safety** — `advance_commit` only commits entries
  from the leader's CURRENT term; prior-term entries are committed
  indirectly when a current-term entry above them commits
  (the Figure-8 rule)

11 new source files; validator 737/737 → **748/748**. P2 is 2/3
topics in flight; `distributed_systems` slated for 2.5.2.

### Added

- `content/consensus/` — 3-node Raft across 11 languages: cyrius
  (10 tests, 42 asserts), HLLs (10 tests, 41 asserts each — Cyrius's
  extra assert is a redundant log-match split that the HLLs do via
  tuple equality), asm pair (6 tests, 12 asserts focused on the
  election state machine — no log replication; see cyrius.cyr for
  that), OpenQASM (vote-as-measurement: voter qubits measured for
  uniqueness, Toffoli for majority detection, gate-depth for term
  monotonicity).

## [2.5.0] — 2026-05-03

**P2 kickoff — Distributed Systems (minor bump)** —
`transactions_and_acid` shipped at 11/11 languages. OCC store with
explicit read-set/write-set tracking; demonstrates the four ACID
properties under tests. Atomicity (commit installs all-or-nothing,
abort discards), Consistency (transfer preserves balance invariant),
Isolation (no dirty reads in HLLs; OCC version-snapshot detects
write-write conflicts in all 11 langs), Durability (committed state
survives "crash-recovery" wipe of tx scratch).

11 new source files; validator 726/726 → **737/737**. P2 is 1/3
topics in flight; `consensus` + `distributed_systems` slated for
2.5.1 / 2.5.2.

### Added

- `content/transactions_and_acid/` — OCC transaction store across
  11 languages: cyrius, rust, python, c, go, typescript, shell, zig,
  asm_x86_64, asm_aarch64, openqasm. The Cyrius reference tests 9
  scenarios with 23 assertions (full multi-tx with dirty-read
  prevention + conflict detection); HLL ports mirror that. The asm
  ports cover a focused single-tx subset (atomicity, consistency,
  durability, OCC validation — 12 asserts each). OpenQASM models
  entanglement-as-commit with a controlled-fan-out gate as the
  all-or-nothing primitive.

## [2.4.4] — 2026-05-03

**Cyrius pin bump 5.8.19 → 5.8.34** — patch-level alignment with
upstream cyrius. No source changes required: build clean, all 41
tests pass, validator 726/726 unchanged. CLI surface identical
across the bump (no verbs added/removed/renamed). Field-notes
verification range extended.

### Changed

- `cyrius.cyml` — `cyrius = "5.8.19"` → `cyrius = "5.8.34"`.
- `content/cyrius/field_notes/index.cyml` — verification range
  `Cyrius 2.2 → 5.8.19` → `Cyrius 2.2 → 5.8.34`.
- `cyrius.lock` refreshed via `cyrius deps`.

## [2.4.3] — 2026-05-02

**Cyrius reference closeout — content/cyrius/ now organized as
it should be, not as it accreted.** Two surfaces both retired
into purpose-built layouts in a single release: the 4144-line
monolithic `language.cyml` (73 entries) split into a
usage-organized `language/` subfolder, and the chronological
per-version `compiler/` field notes (8 files, 60 entries)
recast as topical (gotchas / methodology / patterns) plus a
`retros/` subfolder for chronological narrative.

This is the long-overdue closeout of the incremental cyrius
content cleanup that's been happening since v2.3.1 (field-notes
subfolder split). End state: humans and agents now get the
best docs for where the project is right now — surface-area
organized, current-state focused, no archaeology required.

Plus cyrius pin bump 5.8.18 → 5.8.19 (no source changes).

### Changed — content/cyrius/language/ (NEW subfolder, 6 files, 52 entries)

Retired `content/cyrius/language.cyml` (4144 lines, 73 entries).
Replaced with topical-by-surface-area subfolder:

- **`index.cyml`** — TOC + section markers.
- **`core.cyml`** (7 entries) — overview, syntax,
  compiler_architecture, development_loop, known_limitations,
  porting_guide, stdlib catalog. Version-specific noise trimmed
  from the prior overview.
- **`features.cyml`** (16 entries) — every "how to use this
  language feature" entry: multi_width_types, sizeof_operator,
  unions, bitfield_builtins, struct_field_widths,
  expression_type_propagation, defer_statement, ifplat_directive,
  enum_namespacing, ref_directive, ret2_rethi,
  continue_in_for_loops, derive_str_fields,
  secret_var_compound_ops, slice_type_v58x, relaxed_fn_ordering.
- **`stdlib_modules.cyml`** (12 entries) — per-module usage:
  atoi_stdlib, f64_atan_and_math_lib, base64_module,
  chrono_module, file_locking, csv_module, http_module,
  patra_stdlib_module, strstr_function, hashmap_str_keys,
  fncall_ceiling, identity_lookups_musl_pattern.
- **`tooling.cyml`** (14 entries) — compiler binaries + CLI
  driver + verbs + format files (.tcyr/.bcyr/.fcyr/.scyr/.smcyr)
  + cyml + cyrius.cyml manifest + object directive + env vars +
  flags + LSP plugins + helper scripts + release pipeline +
  audit/test/check pipeline + minimum compiler version pin.
- **`agents.cyml`** (3 entries) — cyrius_for_agents,
  tcyr_test_conventions, agent_anti_patterns.

### Changed — content/cyrius/field_notes/compiler/ (REORGANIZED, 9 files, 46 entries)

Retired the chronological per-version layout
(pre_v3 / v3 / v4 / v5_0_to_5_4 / v5_5 / v5_6 / v5_7 / v5_8.cyml,
60 entries) in favor of topical files for current-work lookups,
with chronological narrative preserved in a `retros/` subfolder.

- **`compiler/index.cyml`** — per-entry TOC for the new layout.
- **`compiler/patterns.cyml`** (7 entries) — reusable design +
  convention patterns. Earn their slot when an agent is making
  a structural decision: ship_now_swap_backend_later,
  dist_bundle_stdlib_dep_convention,
  heap_cap_growth_compiler_grows_to_fit_language,
  version_string_via_generated_source_not_hardcoded,
  stdlib_hook_surface_via_fn_pointer_not_callback_registry,
  object_mode_pic_codegen_no_textrel,
  research_first_optimizer_dce_cfg_lessons.
- **`compiler/methodology.cyml`** (8 entries) — how to debug,
  scope, verify slot premises, triage cross-repo bugs.
  premise_check_at_slot_entry,
  perf_test_dont_assume_correctness_isnt_perf,
  verify_outputs_not_just_exit_codes,
  verify_slot_premise_before_investing,
  triage_dep_boundary_per_row_checksum,
  ci_drift_detection_silent_skip_is_false_green,
  ci_drift_detection_orphaned_path_is_certain_drift,
  anticipated_gotcha_pre_flight_v55x.
- **`compiler/gotchas.cyml`** (12 entries) — non-obvious traps
  in cyrius internals: slice_fn_local_layout_flip,
  slice_high_half_regalloc_pin, tail_call_escape_addr_local,
  pointer_vs_inline_struct_dispatch, stale_fixed_cap_drift,
  stdlib_alloc_grow_step_must_cover_request,
  libssl_needs_fdlopen_not_dynlib_open,
  sysv_odd_stack_args_rsp_alignment,
  pp_pass_helpers_take_src_base,
  ts_lex_jsx_lookahead_terminators,
  fn_keyword_in_param_position,
  lsp_globals_before_fn_definitions.
- **`compiler/retros/`** subfolder — per-version chronological
  narrative preserved for backstory:
  - `pre_v3.cyml` (5 entries) — v0.9–v1.x feature lists +
    cyrius-x VM
  - `v3.cyml` (9 entries) — v3.0 retrospective + v3.3-3.6
    release arcs
  - `v4.cyml` (3 entries) — v4.0 reflections + v4.8.x handoff
  - `v5_chronicle.cyml` (1 entry) — per-cycle v5.x feature lists
  - `v58x_agent_perspective.cyml` (1 entry) — v5.8.x slices
    sub-arc agent's view

### Changed — pin + index

- **Cyrius pin 5.8.18 → 5.8.19** (`cyrius.cyml`). No source
  changes required. Field-notes verification range bumped to
  5.8.19.
- **`field_notes/index.cyml`** — compiler/ section rewritten
  end-to-end to point at the topical layout (`compiler/index.cyml`
  carries the per-entry TOC). The 60-line per-version enumeration
  collapsed to an 8-line per-file pointer.

### Removed

- **`content/cyrius/language.cyml`** — 4144 lines retired.
- **~19 resolved/duplicate entries** dropped from the old
  language.cyml (the fix is in the compiler now and no agent
  action is needed): findvar_last_match, include_path_fallback,
  gt6_args_fix, cyrb_to_cyrius_rename, gvar_expansion,
  p_minus_1_hardening, tail_call_gt6_fix, str_data_expansion,
  constant_fold_identity, patra_module (superseded by
  patra_stdlib_module), function_table_2048,
  nested_while_codegen_bug + …_documented (resolved
  v3.4.6-3.4.9), derive_integers_fix, platform_stubs (Mach-O + PE
  actually work now), cc3_rename (cc5 era), and a few others.
- **~14 entries** consolidated out of the chronological compiler/
  per-version files when reshaped into topical patterns/
  methodology/gotchas (60 → 46 entries via dedup of release-arc
  rollups whose durable lessons now live in the topical files).

### Verified

- `cyrius test` 41/41 passing.
- `scripts/validate-content.sh` 726/726 (no content topics
  changed; `cyrius/` is skipped by the loader anyway).
- `vidya stats`: Topics 66, Complete 66 (all 11 languages),
  Examples 726 — unchanged.

### Notes

- This release closes out the incremental cyrius content
  cleanup that's been happening since v2.3.1's field-notes
  subfolder split. Both `language/` and `compiler/` surfaces
  now follow the same per-surface-area split convention,
  with one TOC file per directory and topical files sized
  for actual lookup workflows (current work) rather than
  chronological accretion (release archaeology).
- VERSION 2.4.2 → 2.4.3.

## [2.4.2] — 2026-05-02

**P1 Networking & Infrastructure complete.** Final 2 topics ship
+ cyrius pin bump 5.8.14 → 5.8.18.

### Added
- **P1 batch 3 — final 2 new topics × 11 languages each, +22
  source files** (validator sweep 704/704 → 726/726):
  - **`ipc`** — new topic. In-memory simulation of three IPC
    primitives: shared memory (multi-region byte buffer with
    multi-reader visibility), bounded FIFO pipe with
    full/empty semantics + ring-buffer wrap-around, and
    named-endpoint message channel (Unix-socket-shaped) with
    per-endpoint queues. 18 assertions covering shm OOB
    rejection, pipe FIFO + full + post-drain wrap, channel
    send-to-closed rejection, channel FIFO recv. OpenQASM
    uses Bell-pair entanglement as the shared-memory analog
    + CNOT chains as the pipe transfer.
  - **`serialization`** — new topic. Varint (LEB128) encode/
    decode + length-prefix framing + stream parser. 19
    assertions covering: varint sizes (1 byte for <128, 2
    for <16384, 3 for <2^21), round-trip, MAX_VARINT_BYTES=10
    overflow guard (the DoS gotcha), frame round-trip, stream
    parse over 3 back-to-back frames, truncated-frame
    rejection, oversize-length rejection (the malloc-bomb
    guard). OpenQASM uses CNOT chains as the
    continuation-bit dependency analog.
- **Cyrius pin 5.8.14 → 5.8.18** (`cyrius.cyml`). No source
  changes required. Field-notes verification range bumped to
  5.8.18.

### Changed
- **VERSION** 2.4.1 → 2.4.2.
- **Topic coverage**: 66 topics, 64 → 66 fully covered. Per-
  language counts (each):
  - All 11 languages: 64 → 66.
  - Examples: 704 → 726 (+22 new source files; +3.1%).

### Notes (recurring patterns worth field-noting)
- **Bash nameref self-cycle warning** (`local: warning: buf:
  circular name reference`). Hit in `serialization/shell.sh`
  when `decode_frame()` had `local -n buf=$1` and then called
  `decode_varint buf $buf_len` — the inner function's
  `local -n buf=$1` saw `buf` as both its declared name and
  its target, producing a cycle. Fix: pass the original $1
  through (`decode_varint $buf_arg $buf_len`) so the inner
  function's nameref points at the caller's caller's variable
  directly. Worth a `bash_nameref_self_cycle` field-note
  entry — this is the second time it's bitten in vidya
  content (first was in compression/shell.sh's PORT_TO_SOCK).
- **Zig u6 shift overflow on 11-byte varint bomb** in
  `serialization/zig.zig`. Iterating MAX_VARINT_BYTES=10
  times with `shift += 7` reaches 63 at the end of iteration
  9; the 10th iteration's `shift += 7` overflows u6 (max 63)
  before the loop's bounds check returns null. Fix: widen
  the shift counter to u32 (or usize) and `@intCast` when
  used. Relevant for any varint decoder in Zig that uses
  bitshift typed too narrowly.
- **x86_64: 3-register addressing modes are illegal**. Hit
  in `serialization/asm_x86_64.s`: `[rbx + r9 + rcx]` and
  `[r13 + rcx + r9]` produced "not a valid base/index
  expression". x86_64 allows `[base + index*scale + disp]`
  (max 2 registers + scale + displacement). Fix: fold one
  pair into a temp register first
  (`mov r8, r9; add r8, rcx; ... [rbx + r8]`). Worth a
  field-note entry.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (under
  cyrius 5.8.18).
- `cyrius test` — 41/41 passing (no regressions across the
  pin bump).
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **726/726 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 66, Complete: 66 (all 11
  languages), Examples: 726`.

### P1 complete (6 of 6) 🎉

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | ✅ shipped 2.4.1 |
| dns | ✅ shipped 2.4.1 |
| ipc | ✅ shipped 2.4.2 |
| serialization | ✅ shipped 2.4.2 |

P1 Networking & Infrastructure cluster fully landed. After
v2.4.2: 66 topics × 11 languages = **726 source files**, all
validated. P0 → P0C → P1 arc complete.

**Next minor (2.5.x): P2 — Distributed Systems.**
transactions_and_acid, consensus, distributed_systems.
Subsumes the original `database_fundamentals` (already
covered as `btree_indexing` + `write_ahead_logging` in
P0C-3); builds on `concurrent_file_access` (P0C-4).

## [2.4.1] — 2026-05-02

P1 Networking & Infrastructure — second batch (2 of the planned 6
new topics). 4/6 P1 topics shipped after this release.

### Added
- **P1 batch 2 — 2 new topics × 11 languages each, +22 source
  files** (validator sweep 682/682 → 704/704):
  - **`tls_and_encryption`** — new topic. Simulation of the four
    load-bearing TLS 1.3 primitives: handshake state machine
    (INIT → HELLO_SENT → SERVER_HELLO → CERT_VERIFIED →
    ESTABLISHED), cipher suite negotiation (TLS 1.3 only —
    rejects 0x002F legacy 1.2 ciphers), certificate chain
    validation (issuer/subject linkage to a trust root,
    rejecting self-signed leafs), AEAD seal/open with auth-tag
    verification (XOR + sum stub captures the structural
    property: any byte flip in ciphertext rejects). Hostname-
    mismatch path tested end-to-end. 16 assertions; 5 in the
    asm focused subset. OpenQASM uses Bell-pair entanglement
    as the ECDHE shared-secret + cert-chain analog.
  - **`dns`** — new topic. In-memory DNS resolver simulation:
    small zone (A/AAAA/CNAME/MX/TXT records), recursive lookup
    that follows CNAME chains with a 16-hop depth bound (per
    RFC convention; libcurl/BIND both use 16), TTL cache with
    monotonic logical clock + advance_time() for deterministic
    expiry tests, negative caching for NXDOMAIN. Tests cover:
    CNAME chain following, CNAME loop detection (depth-bounded),
    cache hit vs miss, post-expiry re-query, negative cache,
    coexisting record types for the same name. 15 assertions;
    5 in the asm focused subset. OpenQASM uses CNOT chaining
    as the recursive-resolution analog.

### Changed
- **VERSION** 2.4.0 → 2.4.1.
- **Topic coverage**: 64 topics, 62 → 64 fully covered. Per-
  language counts (each):
  - All 11 languages: 62 → 64.
  - Examples: 682 → 704 (+22 new source files; +3.2%).

### Notes (recurring patterns worth field-noting)
- **Cyrius `var name[N]` is N BYTES, not N elements** — bit
  again writing `tls_and_encryption/cyrius.cyr`. `var
  leaf_cert[2]` allocates 2 bytes (one byte each for subject
  and issuer), not 2 i64s; the chain pointer-array
  `var chain[8]` allocates 8 bytes (1 ptr) instead of 24 bytes
  (3 ptrs). Already documented in field-note
  `var_name_bracket_is_bytes_not_elements` — this is the 4th+
  time it's bitten in vidya content. Worth promoting to a
  more-prominent CLAUDE.md DO note.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **704/704 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 64, Complete: 64 (all 11
  languages), Examples: 704`.

### P1 progress (4 of 6)

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | ✅ shipped 2.4.1 |
| dns | ✅ shipped 2.4.1 |
| ipc | planned 2.4.2 |
| serialization | planned 2.4.2 |

## [2.4.0] — 2026-05-02

**Minor bump opening P1 — Networking & Infrastructure.** First
new thematic addition since v2.2. Two new topics added (the first
2 of the planned P1 set of 6); v2.4.0/2.4.1/2.4.2 will each ship
2 topics, mirroring the v2.3.x cadence.

### Added
- **P1 cluster — 2 new topics × 11 languages each, +24 source
  files** (validator sweep 660/660 → 682/682):
  - **`networking_fundamentals`** — new topic. In-memory TCP
    socket state machine + lifecycle (no real syscalls): bind,
    listen, connect, accept, send, recv, close. 6-state subset
    of RFC 793 (CLOSED, LISTEN, SYN_RCVD, ESTABLISHED, FIN_WAIT,
    CLOSED). 19 assertions covering: fresh socket starts CLOSED,
    bind+listen transition to LISTEN, two-way connect brings both
    ends to ESTABLISHED, send/recv echoes bytes through, close
    transitions to CLOSED, port reuse rejected while in-use,
    recv on CLOSED returns -1, port becomes available after
    close. OpenQASM uses Bell-pair entanglement as
    handshake-establishes-connection analog.
  - **`http_and_web_protocols`** — new topic. HTTP/1.1 request
    parser. Sequential parse: request line → headers → body
    (RFC 9112). Header names normalized to lowercase for
    case-insensitive lookup (RFC 9110 §5.1). Body framing via
    Content-Length. 24 assertions covering: simple GET parses,
    method/path/version extracted, case-insensitive header
    lookup (Host == host == HOST), multiple headers, POST
    with body, body containing CRLF preserved (the parser
    bug that truncates POST payloads is a real concept.toml
    gotcha), malformed request rejected, absent header lookup
    returns null. Asm ports verify the parsing primitive
    (find_crlf scan + memeq) on known-shape requests.

### Changed
- **VERSION** 2.3.10 → **2.4.0** (minor bump — opens P1).
- **Topic coverage**: 62 topics, 60 → 62 fully covered. Per-
  language counts (each):
  - All 11 languages: 60 → 62.
  - Examples: 660 → 682 (+22 new source files; +3.3%).

### Notes (recurring patterns worth field-noting)
- **Bash `unset 'arr[ARR[s]]'` doesn't expand the inner array
  reference.** Captured in `networking_fundamentals/shell.sh`
  during port: `unset 'PORT_TO_SOCK[PORT[s]]'` failed to
  remove the entry, leaving the port "in use" after close. Fix:
  capture to a scalar first — `local p=${PORT[s]}; unset
  "PORT_TO_SOCK[$p]"`. Worth a `bash_unset_inner_array_ref`
  field-note entry once it bites a third time.
- **Zig `@memset` on >100KB global arrays trips a codegen
  bug.** `var port_to_sock: [65536]usize = ...; @memset(&port_to_sock, 0);`
  produced "emit MIR failed: InvalidInstruction (Zig compiler
  bug)" on the current Zig version. Workaround: replace the
  large fixed-size global with a smaller indirect (linear-scan
  pmap with SOCK_CAP entries). Worth tracking — likely
  upstream-fixable but the workaround is also genuinely
  smaller-data.
- **Cyrius reserves `match` as a keyword.** Hit in
  `http_and_web_protocols/cyrius.cyr` writing the header-lookup
  comparison loop. Renamed to `is_match`. Add to the parser-
  syntax field-notes if it surfaces in another port.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **682/682 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 62, Complete: 62 (all 11
  languages), Examples: 682`.

### P1 progress (2 of 6)

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | planned 2.4.1 |
| dns | planned 2.4.1 |
| ipc | planned 2.4.2 |
| serialization | planned 2.4.2 |

## [2.3.10] — 2026-05-02

**P0C-2c — final P0C patch.** All 60 topics now at 11/11
languages. P0 → P0C arc complete: every programming concept
in vidya's reference shelf has a working, tested implementation
in all 11 supported languages.

### Added
- **P0C-2c cluster — 2 topics × 11 languages each, +22 source
  files** (validator sweep 638/638 → 660/660):
  - **`direct_drm_gpu_compute`** — 11 new lang files (concept-
    only topic; cyrius reference designed first). In-memory
    simulation of the GEM BO → VA-map → submit → syncobj-wait
    flow that AMDGPU compute-MVP code targets. Models the
    kernel-side state (BO table, per-process VA map,
    submission queue, syncobj timeline) so the test surface
    is byte-deterministic. 20 assertions covering: open
    render node returns a non-zero fd, gem_create returns
    sequential handles starting at 1, gem_va_map binds
    handles, va_lookup hits/misses, va_map rejects invalid
    handles, submit returns increasing seqs, syncobj_wait for
    past/current/future, gem_destroy invalidates the VA
    mapping, submit on a destroyed BO is rejected. OpenQASM
    uses qubit-as-BO + CNOT sync chain analog.
  - **`render_graph_architecture`** — 11 new lang files. Tiny
    DAG framework where each pass declares reads/writes as
    bitmasks; the graph derives execution order, barrier
    count, and dead-pass culling from those declarations.
    Mirrors the small load-bearing core that
    Frostbite/UE5/Granite all converged on. 14 assertions
    covering: linear A→B→C add_pass + topo sort, barrier
    count from write→read edges, dead-pass culling (writer
    with no readers gets zeroed), cycle detection (Kahn-style
    sort emits 0 passes when a cycle is present). OpenQASM
    uses qreg-as-resource + gate-as-pass analog (Qiskit's
    DAGCircuit is exactly this pattern).

### Changed
- **VERSION** 2.3.9 → 2.3.10.
- **Topic coverage**: 60 topics, **58 → 60 fully covered, 0
  partial**. Per-language counts (each):
  - All 11 languages: 58 → 60.
  - Examples: 638 → 660 (+22 new source files; +3.4%).

### Resolved
- **The lingering 47→48 discrepancy from v2.3.5**. Various
  CHANGELOG entries through v2.3.4–v2.3.9 carried slightly
  off-by-one historical accounting (e.g. v2.3.4 reported
  "44 → 47 fully covered" when the post-v2.3.3 baseline
  per its own count was 33, not 44). The discrepancy was
  legacy bookkeeping noise that accumulated as topics moved
  from "concept-only" to "fully covered" in batches. Now
  permanently moot: **all 60 topics are at 11/11; the loader
  reports 60/60; the on-disk count matches.** No further
  reconciliation needed.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **660/660 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 60, Complete: 60 (all 11
  languages), Examples: 660`.

### P0 → P0C complete

The original 36 P0 topics (v2.0) plus 24 added across v2.3.2–v2.3.10:
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

Total: 36 + 24 = 60 topics × 11 languages = 660 source files,
660/660 validated. **Next minor (2.4.0) opens P1 — Networking &
Infrastructure** (networking_fundamentals, http_and_web_protocols,
tls_and_encryption, dns, ipc, serialization).

## [2.3.9] — 2026-05-02

P0C-2b graphics batch 2 — 3 topics × 11 languages each (33 new
source files). Largest "first-try clean" run of the v2.3.x arc:
all 33 files passed validation on the first build, no asm or
language-specific debugging required.

### Added
- **P0C-2b cluster — 3 topics × 11 languages each, +33 source
  files** (validator sweep 605/605 → 638/638):
  - **`bindless_resources`** — 11 new lang files (concept-only
    topic; cyrius reference designed first). 64-slot global
    descriptor table with slot 0 reserved as null sentinel
    (matching the page_management pattern). LIFO free-list for
    reuse, sequential bump for fresh allocations. 15 assertions
    covering: sequential alloc returns 1/2/3, slot 0 reserved,
    lookup roundtrip, update preserves ID, free + reuse via
    free-list LIFO, exhaustion returns 0 (null sentinel).
    OpenQASM uses qubits-as-handle-slots analog with
    X/measure/reset for alloc/lookup/free.
  - **`gpu_memory_pooling`** — 11 new lang files. Bump
    allocator over a 1024-byte pool — the "transient per-frame,
    reset on frame boundary" shape from concept.toml's first
    BP. `alloc(size)` returns offsets, `-1` sentinel on
    exhaustion. `alloc_aligned(size, align)` rounds bump up
    to the requested boundary first. `reset()` recycles the
    entire pool atomically. 16 assertions covering initial
    state, sequential allocs, exhaustion, reset + reuse,
    alignment rounding, alloc(0) no-op, monotonic-sum
    invariant across many small allocs.
  - **`explicit_gpu_synchronization`** — 11 new lang files.
    Two timeline semaphores (compute + transfer queues) —
    concept.toml's "monotonic frame counter / timeline
    wait/signal" escape-hatch primitive. `signal(sem, value)`
    advances iff value strictly greater than current (rejects
    regression to enforce monotonicity); `wait_for(sem,
    target)` returns 0/1 reachability; `wait_all(c_target,
    t_target)` is the multi-queue render-graph integration
    pattern — only proceeds when BOTH queues are at or past
    their targets. 19 assertions covering init, signal
    advance, past/current/future wait reachability, regression
    rejection (both `<` and `==`), multi-sem wait_all matrix
    (4 cases), monotonic invariant across 10 sequential
    signals. OpenQASM uses CNOT entanglement chains as
    quantum-fence analog (producer broadcasts state to
    consumers via Bell-pair pattern).

### Changed
- **VERSION** 2.3.8 → 2.3.9.
- **Topic coverage**: 60 topics, 55 → 58 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 55 → 58
  - x86_64 ASM / AArch64 ASM: 55 → 58
  - Cyrius: 55 → 58 (all 3 topics designed cyrius.cyr first)
  - Examples: 605 → 638 (+33 new source files; +5.5%).

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **638/638 green**, 0 failed,
  0 skipped (full toolchain locally available).
- All 33 new files passed first-build validation. The asm
  ports applied the v2.3.8 lessons (callee-saved register
  caching across `bl/call`, `shl` instead of `imul reg, sym`)
  by reflex; no asm rework needed.

## [2.3.8] — 2026-05-02

P0C-2a graphics batch 1 — 3 topics × 11 languages each (33 new
source files). Plus `bloom_and_glow/concept.toml` completed
(was a TODO stub before this release).

### Added
- **P0C-2a cluster — 3 topics × 11 languages each, +33 source
  files** (validator sweep 572/572 → 605/605):
  - **`framebuffer_rendering`** — 11 new lang files (concept-only
    topic; cyrius reference designed first). 16×16 BGRA8888
    framebuffer with `fb_clear` (memset), `fb_set`/`fb_get` with
    explicit bounds-check returning a 0/1 success flag (matching
    the encom-hits pattern in concept.toml), `draw_hline`/
    `draw_vline`, `count_lit_pixels`. 18 assertions covering
    byte-exact BGRA encoding, OOB rejection, line clipping at
    screen edge. Asm ports use a `.bss` arena with the same
    test surface; OpenQASM uses qubit-as-pixel encoding.
  - **`line_rasterization`** — 11 new lang files. All-octant
    integer Bresenham on a 16×16 byte framebuffer; pure
    integer math (no floats, no division). 27 assertions
    covering 7 line types: horizontal (dy=0), vertical
    (dx=0), positive 45° diagonal, negative 45° diagonal,
    steep slope (|dy|>|dx|, octant swap), single-point
    degenerate, reversed start/end produces same pixel set.
    Asm ports use callee-saved x19+/r12+ to cache loop state
    across `bl/call fb_set` (per the AArch64 ABI field-note).
  - **`bloom_and_glow`** — 11 new lang files. 1-pixel additive
    bloom on a 16×16 single-channel intensity buffer. Each
    pixel ≥ THRESHOLD=128 contributes `intensity / GLOW_FRAC`
    to its 4 cardinal neighbors with per-channel saturation
    clamp at 255 (the wrap-gotcha from concept.toml). 20
    assertions covering: empty input → empty output, single
    bright pixel, saturation clamp, threshold cutoff, edge-
    pixel in-bounds-only glow, two adjacent bright pixels
    summing at midpoint. OpenQASM uses controlled rotations
    as amplitude-leakage analog of light-bleed.
- **`bloom_and_glow/concept.toml` completed** — was a TODO stub.
  Now has 4 best practices (threshold-before-blur, separable
  blur, per-channel additive composite with clamp, small-
  radius retro), 3 gotchas (black-background bloom is just the
  blur, per-channel saturation never wrap, hard-threshold
  banding), and 2 performance notes (bandwidth-limited not
  compute-limited, radius=1 is essentially free).

### Changed
- **VERSION** 2.3.7 → 2.3.8.
- **Topic coverage**: 60 topics, 52 → 55 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 52 → 55
  - x86_64 ASM / AArch64 ASM: 52 → 55
  - Cyrius: 52 → 55 (all 3 topics designed cyrius.cyr first)
  - Examples: 572 → 605 (+33 new source files; +5.8%).

### Notes (recurring patterns worth field-noting later)
- **x86_64 caller-saved register clobber across helper calls.**
  `bloom_and_glow/asm_x86_64.s`'s `apply_bloom` cached `glow`
  in `r8` across 4 `call fb_add`. SysV ABI marks `r8` as
  caller-saved, and `fb_add`'s body uses `r8` as scratch — so
  the second `fb_add` saw garbage instead of the saved glow.
  Fix: cache in `rbp` (callee-saved) with explicit
  `push rbp`/`pop rbp` at function entry/exit. Direct sibling
  of the AArch64 cross-`bl` clobber field-note
  (`aarch64_callee_saved_and_imm_limits`). Worth a parallel
  x86_64 entry once it surfaces a third time.
- **GAS `imul reg, symbol` ambiguity.** `imul rax, FB_W` where
  `FB_W` is a `.equ` constant gets parsed as `IMUL r64, r/m64`
  (memory operand) instead of the immediate form, which would
  read 8 bytes from address `[FB_W]`. Initial cause of the
  bloom asm failure; fixed by switching to `shl rax, 4` (since
  FB_W=16). The `cmp r64, symbol` form parses correctly as
  immediate on GAS — this is `imul`-specific. Worth noting if
  the pattern shows up again in another asm port.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **605/605 green**, 0 failed,
  0 skipped (full toolchain locally available).

## [2.3.7] — 2026-05-02

P0C-4 systems & misc cluster — all 4 topics backfilled to 11/11
languages (43 new files). Plus cyrius pin bump 5.8.3 → 5.8.14.

### Added
- **P0C-4 cluster — 4 topics × 11 languages each, +43 source files**
  (validator sweep 529/529 → 572/572):
  - **`page_management`** — 10 new lang files (cyrius reference
    already existed). Tests: header init/verify with magic
    `0x50415452`, page_count starts at 1, sequential alloc
    returns 1 then 2, write 42 to page 1 + read back, free + reuse
    via free-list stack. Layout matches the cyrius reference exactly:
    header at offset 0, page 0 reserved as null sentinel, data
    pages at `PAGE_SZ + num * PAGE_SZ`. Languages with first-class
    file I/O (Rust/Python/C/Go/TS/Zig) use real `open`+`lseek`+
    `read`+`write`; shell + asm use in-memory simulation matching
    the WAL convention; OpenQASM uses qubit-as-page-slot analog
    (allocate/measure/reset).
  - **`compression`** — 11 new lang files (concept-only topic;
    cyrius reference designed first). LZ77-shaped 2-byte token
    stream: `[0, BYTE]` = literal, `[OFFSET, LEN]` = match.
    Greedy O(n²) match-finder over a 255-byte window. Tests:
    round-trip on substring repeat (`ABCABCABC`), overlapping
    RLE match (`AAAAAAAA` with offset=1 length=7), mostly-literal
    text (`Hello, World!`), decompression bomb guard (single
    match claiming length 200 with cap=10 → -1), empty input.
    Asm ports decoder-only with hand-built test token streams
    from the cyrius greedy encoding. OpenQASM uses entanglement
    as state-overlap analog (one Hadamard + 3 CNOTs = "1 source +
    3 back-references").
  - **`concurrent_file_access`** — 11 new lang files. Single-
    process exercise of the file-lock state machine via two
    distinct OPENs of the same path (flock is per-OPEN, so the
    two fds have independent lock state and can contend in one
    process). Tests: LOCK_EX write, LOCK_SH read with roundtrip
    integrity, LOCK_NB exclusive contention (second fd fails
    while first holds), release + acquire, LOCK_SH coexistence
    (multiple shared holders). Real `flock` where available
    (Rust via libc, Python via `fcntl`, C via `<sys/file.h>`,
    Go via `syscall.Flock`, Zig via `linux.syscall2(.flock)`,
    Shell via `flock(1)`, asm via raw syscall 73/32). TypeScript
    in-process state-machine simulation (Node has no built-in
    flock binding); OpenQASM uses GHZ entanglement as shared-
    lock analog.
  - **`jsonl_format`** — 11 new lang files. In-memory JSONL
    primitives: append records to a flat byte buffer with `\n`
    separators, build a per-line index (handles the no-trailing-
    newline edge case from concept.toml's gotcha), extract by
    index, JSON string escape covering all 5 special chars
    (`" \ \n \t \r`) with a 2× expansion bounds check, escape ↔
    unescape roundtrip. Asm ports focus on the
    escape/unescape/bounds-check (the algorithmic piece);
    OpenQASM uses the no-entanglement register as
    independent-records analog.
- **Cyrius pin 5.8.3 → 5.8.14** (`cyrius.cyml`). No source
  changes required — the 5.8.x stdlib is API-compatible with
  the 5.8.3 surface vidya consumes (sandhi, sakshi, syscalls,
  string, alloc, str, fmt, vec, hashmap, io, fs, tagged, json,
  fnptr, args, toml). Verified: build clean, `cyrius test` 41/41,
  full content validator 572/572.
- **`content/cyrius/field_notes/index.cyml`** — verification
  range bumped: "Cyrius 2.2 → 5.8.14".

### Changed
- **VERSION** 2.3.6 → 2.3.7.
- **Topic coverage**: 60 topics, 48 → 52 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 48 → 52
  - x86_64 ASM / AArch64 ASM: 48 → 52
  - Cyrius: 48 → 52 (page_management already had it; the other
    3 topics designed cyrius.cyr first as the reference)
  - Examples: 529 → 572 (+43 new source files; +8%).

### Notes (recurring patterns worth field-noting later)
- **Rust 2024 edition: `extern "C"` blocks must be `unsafe`.**
  Caught by `concurrent_file_access/rust.rs` declaring `flock`/
  `unlink` libc bindings. Fix: `unsafe extern "C" { ... }`. This
  is a 2024 hardening that the older `extern "C"` form rejects
  outright now.
- **Rust LZ77 decoder: capture `out.len()` before the inner copy
  loop.** Using the moving `out.len()` inside the loop caused
  off-by-one corruption on substring matches (offset=3, len=6
  reading from position 4 instead of 3 after pushing one byte).
  Other languages' iteration patterns happen to dodge this; only
  Rust's bytes-pushed-grow-the-vec idiom surfaces it. Worth a
  field-note (`lz77_capture_start_position`) once the third
  surfacing happens.
- **Cyrius `else if` is `elif`.** Re-surfaced writing
  `jsonl_format/cyrius.cyr`. Already documented in CLAUDE.md /
  field-notes from v2.3.5 — flagged again here.
- **Zig `std.io.getStdOut()` removed.** Use `std.debug.print`
  instead (matches existing zig content ports). Surfaced in
  `page_management/zig.zig`. Worth a field-note about the Zig
  stdlib's print API churn (`zig_stdout_api_drift`).

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (large-static-
  data warning at 375064 bytes, unchanged from v2.3.6).
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **572/572 green**, 0 failed,
  0 skipped (full toolchain locally available).

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
