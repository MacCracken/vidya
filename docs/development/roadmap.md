# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-06-12
>
> **Version**: 2.7.2 | **Cyrius**: 6.1.41 (Zig content pin: 0.16.0)
> **Topics**: 75 (75 fully covered) — **P0 → P3 complete; P4 build_systems landed (Unreleased)** 🎉
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 825 source files; concept files: 75
> **Validator**: 825/825 green
>
> Vidya is the library's reference shelf — every programming concept with implementations,
> best practices, gotchas, and performance notes across 11 languages.

---

## Release History

Per-release detail lives in [CHANGELOG.md](../../CHANGELOG.md).
This table is one row per minor for navigation only.

| Minor | Theme | Topics | Validator | Closed |
|---|---|---|---|---|
| 2.0–2.2 | **P0 originals** + P0A infrastructure | 36 | (pre-counter) | 2026-04-08 |
| 2.3.x | **P0B service layer** + **P0C content infill** (games + database + systems + graphics) | +24 → 60 | 660/660 | 2026-05-02 |
| 2.4.x | **P1 networking & infrastructure** | +6 → 66 | 726/726 | 2026-05-02 |
| 2.5.x | **P2 distributed systems** | +3 → 69 | 759/759 | 2026-05-03 |
| 2.6.x | **P3 audio + AI/ML** | +5 → 74 | 814/814 | 2026-05-03 |

---

## Current State

**75 topics fully covered (11/11 languages) — P0 → P3 complete; P4
`build_systems` landed (Unreleased).**

`vidya stats` reports `Topics: 75, Complete: 75 (all 11 languages),
Examples: 825`; validator 825/825 green. No partial topics.

---

## In flight (2.7.x) — Build Systems (P4)

3 topics × 11 langs ≈ 33 new examples. Aligns with cyrius/zugot
tooling work; each primitive has a direct cyrius-toolchain
counterpart.

**Slot drift:** 2.7.0 and 2.7.1 were infra-only cycles
(cyrius/sakshi/vyakarana bumps, streaming-API migration, CI
refresh — no topic content). The three P4 topics below have
slid to the next available patch slots. Original pinning
(2.7.0/.1/.2) is preserved here as historical intent; actual
patch slots will be filled as the topics ship.

| Topic | Status | Plan |
|---|---|---|
| **build_systems** | ✅ **landed (Unreleased)** — 11/11, 825/825 | DAG of build targets + content-signature dirty-tracking + Kahn topological order + ninja-style incremental rebuild + cycle detection. Cyrius reference designed first, then 10 ports. |
| **package_resolution** | **next content slot** | Semver constraint matching + dependency-graph build + cycle detection + version selection (pubgrub or naive backtracking). cyrius.cyml's resolver is the reference. |
| **reproducible_builds** | closes P4 | Deterministic timestamps (SOURCE_DATE_EPOCH) + sorted file iteration + content-addressable artifact paths + verifying byte-identical rebuilds. The cyrius compiler self-host check is the reference. |

After P4 closes, next minor (2.8.x) opens **P5 functional /
type theory**.

---

## 2.7.x dep-track follow-ups

Items surfaced by the 2.7.0 / 2.7.1 infra cycles. None gate
content work, but each closes a loose end opened by the dep
churn. Ordered by trigger condition, not by patch slot.

### Waiting on upstream

| Item | Trigger | Action on vidya side |
|---|---|---|
| **Cyrius transitive-stdlib arc** | cyrius closes the v5.10.x SLOT 19 follow-through (enum/constant references not pulled transitively) | Prune `tls`, `base64`, `fdlopen` from `cyrius.cyml` `[deps] stdlib` — they're explicit today only because sandhi's transitives don't fan out. Mirrors the gap-list sit's `cyrius.cyml` documents. |
| **sandhi `hashmap_*` rename** | upstream sandhi (or cyrius stdlib) reconciles `hashmap_new_a` / `hashmap_get` / `hashmap_set_a` / `hashmap_len` against the current `map_*` API | Drop the `(will crash at runtime)` DCE noise from `cyrius build` output. Today the references are dead-code-eliminated so the binary works; if sandhi ever stops DCE'ing them, vidya would crash. |
| **vyakarana 2.0.1+ per-feed drain** | vyakarana ships the scanner refactor (per ADR 0017 "When to revisit") | Convert the two streaming sites (`src/main.cyr:877` and `:1569`) to a feed-drain loop for large sources. Today both are buffer-then-finish; benefit only when source > 1 MB. |
| **vyakarana pull adapter** (`tokenize_stream_next`) | vyakarana exports the thin iterator wrapper queued in ADR 0017 | Collapse the five-call dance back to a one-liner. Cosmetic but reduces the cognitive cost at each new call site. |
| **vyakarana OpenQASM grammar** | vyakarana ships a `.qasm` grammar (none through 2.2.1 by design) | Drop the `has_grammar("openqasm") == 0` fallback in `cmd_code`. Update the comment at `src/main.cyr:870`. |
| **Cyrius aarch64 cross-build** | cc5_aarch64 stops dying on stdlib syscall-table gaps (`SYS_OPEN` etc.) | The best-effort step added to `release.yml` in 2.7.1 will start shipping `vidya-<tag>-aarch64-linux` automatically once the upstream gap closes. No vidya-side action — just monitor the CI warning. |

### Vidya-side opportunities (not blocked)

| Item | Why now | Notes |
|---|---|---|
| **`sakshi_clock_recalibrate()` in `cmd_serve`** | sakshi 2.2.1+ exposes it for long-running consumers. `cmd_serve` runs for days under sandhi. | Call once per N minutes (or on a `kill -USR1`); cycle-counter drift is the failure mode if we don't. |
| **Theme externalization** | renderer is past wire-up; per-kind ANSI palette is hard-coded inline at `src/main.cyr:827` | Move palettes to `content/theme/*.toml`; expose `--theme=<name>` on `code`, `theme=<name>` on `GET /code/...`. Decouples vidya's style from CLI-vs-HTTP consumers. |
| **Renderer wider scope** | streaming API is live, byte-identical to 2.7.0 | Wire `info <topic>` to render inline; add `compare <topic> rust go` side-by-side view. |
| **sigil (content integrity)** | sit/owl already pull it for SHA hashing | Hash `content/` at startup, expose via `/integrity` HTTP route. Lets hoosh/agnoshi verify the corpus they're querying matches a known-good snapshot. Speculative — only worth doing if a consumer actually asks. |
| **Field-note promotion** | per CLAUDE.md "field-note recurring pain — when the same gotcha bites in 3+ ports" | The `cyrius update` vs `cyrius deps` rehydration gotcha (saved in `memory/`) hit vidya and is documented in sit's `.gitignore` comment. If sandhi or sigil land the same pattern, promote to `content/cyrius/field_notes/`. |

### CI / release plumbing

| Item | Trigger | Action |
|---|---|---|
| **Zugot recipe SHA backfill** | first 2.7.1 release tarball builds on GitHub Actions | Compute `sha256sum vidya-2.7.1-src.tar.gz` from the release artifact; fill the `sha256 = ""` placeholder in `zugot/marketplace/vidya.cyml`. |
| **Content-validation matrix** | observed CI wallclock for the new `scripts/validate-content.sh` step | If the 814-example sweep exceeds ~15 min, split the content job per-language (matrix strategy) for parallelism. The script's per-language stages are independent. |
| **Zig pin maintenance** | observed failures on `content/*/zig.zig` examples | Track zig's release cadence; bump the CI install pin (`0.16.0` today, matching `docs/sources.md` / `README.md`) when content needs newer language features. The 0.15→0.16 bump at v2.7.2 migrated all 14 zig examples to `std.Io` (Threaded backend, Writer "Writergate", `DebugAllocator`). |
| **`scripts/bench-history.sh` audit** | next benchmark cycle (P4 work) | Pre-2.0 era script; haven't verified it works against the 5.11.x toolchain layout. Skim before relying on it for the build_systems benchmarks. |

---

## Future minor versions

Each minor is one thematic cluster, sized similarly to P2/P3
(3–5 topics). Order is rough; sequencing depends on which AGNOS
component needs vidya support next.

| Minor | Theme | Topics | Notes |
|---|---|---|---|
| 2.7.x | **P4 build systems** (in flight) | build_systems, package_resolution, reproducible_builds | Aligns with cyrius/zugot tooling. |
| 2.8.x | **P5 functional / type theory** | functional_patterns, effect_systems, dependent_types | More research-flavored; lowest priority. |
| 2.9.x | **P6 Cyrius-specific concepts** | cyrius_basics, cyrius_bootstrap, cyrius_agents, cyrius_capabilities, cyrius_ipc | Programming-concept slots that document Cyrius patterns the way other topics document general patterns. Distinct from `content/cyrius/` (the language reference + field notes). |

---

## Future major (3.0.0) — Content reorganization

Trigger condition (from `docs/development/content-grouping.md`):
**when topic count exceeds ~50, reorganize `content/` into
subdirectories.** We're at 74. The reorg is overdue and should
land before topic count crosses ~80 (likely during 2.7.x or
2.8.x).

Planned shape (per content-grouping.md):

```
content/
├── fundamentals/        — strings, error_handling, concurrency, ...
├── compiler/            — lexing, IR, optimization, codegen, ...
├── systems/             — boot, virtual_memory, syscalls, ...
├── languages/           — ownership, traits, macros, modules
├── networking/          — (post-P1)
├── data/                — (post-P0C-3)
├── graphics/            — (post-P0C-2)
├── games/               — (post-P0C-1)
├── distributed/         — (post-P2)
├── ai/                  — (post-P3)
├── build/               — (post-P4)
└── cyrius/              — corpus + field notes (already a subdir)
```

Migration is a single atomic move: update `load_all()` to recurse,
update `source_path` references, update tests. Backward compat via
symlinks for one minor.

---

## Cyrius pin maintenance

Every Cyrius minor drives a vidya patch bump for stdlib +
language-feature alignment. The cadence:

1. Cyrius minor lands upstream
2. `cyrius.cyml` bumps `cyrius = "X.Y.Z"`
3. Field notes capture surfaced gotchas in
   `content/cyrius/field_notes/compiler/`
4. `content/cyrius/field_notes/index.cyml` verification range bumped
5. CHANGELOG patch entry summarises the bump
6. zugot recipe (in the upstream repo) tracks the same version

Current pin: **5.11.55** (vidya 2.7.1; 5.10.x + 5.11.x cycles
absorbed in one bump from 5.9.43). The 5.11.x model treats `lib/`
and `cyrius.lock` as build artifacts (gitignored, rehydrated via
`cyrius update`), and per-file `cyrius lint` / `cyrius fmt` from
5.7+. See CHANGELOG 2.7.1 for the full call-out, including the
transitive-stdlib gap (sandhi pulls `TLS_EARLY_DATA_*`,
`fdlopen_*`, `base64_encode` via enum/constant refs that v5.10.x
SLOT 19 doesn't follow) — vidya's `[deps] stdlib` mirrors sit's
explicit list until the transitive arc closes upstream.

Upstream cyrius issues filed during 2.6.x — see
`cyrius/docs/development/issues/`.

---

## Renderer integration — vyakarana (live)

> **Status**: Live on **vyakarana 2.2.1** as of 2026-05-16
> (migrated from 1.11.1 in 2.7.1; the only scheduled API break
> in the vyakarana roadmap landed at 2.0.0 — see ADR 0017).
> `vidya code <topic> <lang>` (CLI, ANSI-colored) and
> `GET /code/{topic}/{lang}` (HTTP, JSON tokens) both flow
> through the streaming primitives: `tokenize_stream_new` /
> `_feed` / `_finish` / `_free` → `tokenbuf_*` / `kind_name`.
> Theme contract per vyakarana ADR 0004 (palette indexed by
> kind-name string, never integer). OpenQASM falls back to
> `tokens:[]` — no grammar in vyakarana 2.2.1 by design.
> Output is byte-identical to the 1.x integration: 2187 tokens
> on the rust track of `content/lexing_and_parsing/` (8829
> source bytes) — same numbers as the 2.7.0 reference.

vyakarana ships 38 bundled grammars covering every language in
vidya's reference shelf (the 11 vidya tracks plus 27 more). It
also ships a stable public API and a written contract for
how renderers integrate with it. Vidya can swap its current
code-rendering path over to vyakarana whenever a renderer
rewrite is planned.

**Open work on the vidya side** (the wire-up steps from 2.7.0
and the streaming-API migration from 2.7.1 are both done):

1. **Pick a wider rendering scope.** Today `code` is per-topic
   per-language — one example at a time. Suggested next users:
   - **Topic concept pages** — `info <topic>` could render the
     example for the requested language inline rather than just
     printing the file path.
   - **Cross-language compare view** — `compare <topic> rust go`
     could render both side-by-side with shared theming.
2. **Decide on a theme.** Today the ANSI palette in
   `ansi_open_for_kind` (`src/main.cyr`) is hard-coded inline.
   vyakarana's bundled `default` theme is the reference palette;
   for vidya's HTTP / web rendering, a named theme (or a couple
   — light/dark) externalised into `content/theme/*.toml` would
   let consumers pick.
3. **OpenQASM grammar.** `has_grammar("openqasm") == 0` in
   vyakarana 2.2.1 — vidya's `code` command falls back to plain
   source. Watch for the version that adds it; until then the
   fallback is the right behavior.
4. **Future per-feed drain.** Vidya currently buffers the whole
   source then `tokenize_stream_finish`. vyakarana 2.0.1+ plans
   to emit tokens per-feed (per ADR 0017 "When to revisit");
   when that ships, `cmd_serve`'s per-request `/code/...` path
   could drain incrementally for large sources. Not load-bearing
   today (all examples fit well under the 1 MB stream cap).

**Required reading (in order):**

- [Consumer integration guide](https://github.com/MacCracken/vyakarana/blob/main/docs/guides/consumer-integration.md)
  — full setup + API walkthrough. **Start here.**
- [Architecture note 004 — theme-palette contract](https://github.com/MacCracken/vyakarana/blob/main/docs/architecture/004-theme-palette-contract.md)
  — how to bind vidya's renderer styles to the 10 token kinds
  via stable `kind_name` strings.
- [Architecture note 001 — coverage invariant](https://github.com/MacCracken/vyakarana/blob/main/docs/architecture/001-coverage-invariant.md)
  — guarantees you can rely on. Every input byte produces
  exactly one token; never partial state.
- [Architecture overview](https://github.com/MacCracken/vyakarana/blob/main/docs/architecture/overview.md)
  "Frozen public contracts" — the names / signatures that
  don't change across the 1.x line.

**API stability**: 2.0.0 was the only scheduled API break in
the vyakarana roadmap — `tokenize_source` removed, streaming
primitives added (ADR 0017). Vidya migrated in 2.7.1. The 2.x
public surface (`tokenize_stream_*`, `tokenbuf_*`, `kind_name`,
`has_grammar`, the kind-name palette contract) is stable across
the 2.x line.

**Reciprocal corpus relationship**: Vidya's
`content/lexing_and_parsing/<lang>` files are vyakarana's test
corpus for those languages. When vidya updates a sample, the
vyakarana repo can re-snapshot it (manual, per
[vyakarana ADR 0001](https://github.com/MacCracken/vyakarana/blob/main/docs/adr/0001-corpus-sync-policy.md)).
Vidya doesn't need to coordinate the snapshot — vyakarana
pulls when it wants. New language tracks vidya adds eventually
flow into vyakarana grammars (already happened in
vyakarana 1.9.0 for cyrius via `content/cyrius/`).

**Bugs to file upstream, not work around**: If vyakarana
mistokenizes a sample, file the issue at vyakarana's repo —
don't add per-token corrections in vidya's renderer. The
tokenizer's `error` kind is a real signal, and silent
work-arounds would mask grammar bugs that affect every
consumer.

**Ahead-of-time questions for whoever picks this up:**

- Does vidya's HTTP service (sandhi-based) render content
  per-request, at build time, or both? That affects whether
  the tokenize path is hot.
- Does vidya already have a renderer-style schema for code
  blocks, or will the integration also define the styling
  vocabulary?
- Should the cutover be a single replace-the-renderer cut, or
  an opt-in flag (e.g. a `vidya stats --renderer=vyakarana`
  comparison mode) before flipping the default?

These are vidya design calls; the integration guide handles
the vyakarana side regardless of the answers.

---

## Relationship to AGNOS

Vidya feeds directly into the ecosystem:
- **agnoshi** — shell uses vidya for programming help responses
- **hoosh** — LLM uses vidya corpus for grounded programming advice
- **Cyrius** — vidya documents compiler patterns being implemented
  in real-time; field notes capture the gotchas as they surface
- **mabda** — vidya documents the GPU patterns mabda implements
- **naad** — vidya `audio_dsp` + `audio_synthesis` are the
  educational portable counterparts to naad's production f32 +
  PolyBLEP synth
- **sakshi** — vidya uses sakshi for tracing; documents tracing patterns
- **sandhi** — vidya's HTTP service runs on sandhi
- **vyakarana** — source-code tokenizer; ready for vidya to
  adopt as the code-rendering layer (see "Renderer integration"
  above). 38 bundled grammars covering all 11 vidya language
  tracks plus 27 more. Reciprocal: vidya's
  `content/lexing_and_parsing/<lang>` files are vyakarana's
  test corpus for those languages.
- **`docs/sources.md`** standard — vidya IS the source citation for
  programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-05-16 (v2.7.1) — **🎉 P3 complete; 74/74 at 11/11; 814/814 validator. 2.7.1 dep-bump cycle: cyrius 5.9.43 → 5.11.55 (5.10.x + 5.11.x absorbed), sakshi 2.0.0 → 2.2.4 (cycle-counter timestamps + aarch64 lane), vyakarana 1.11.1 → 2.2.1 with streaming-API migration (ADR 0017; output byte-identical at 2187 tokens / 8829 bytes on the rust lexing_and_parsing track). CI/release modernised for the 5.11.x model: `cyrius update`-style rehydration, gitignored `lib/`+`cyrius.lock`, lint gate, validate-content.sh full gate, best-effort aarch64 cross-build. See "2.7.x dep-track follow-ups" for queued cleanup items.***
