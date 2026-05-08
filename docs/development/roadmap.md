# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-08
>
> **Version**: 2.7.0 | **Cyrius**: 5.9.43
> **Topics**: 74 (74 fully covered) — **P0 → P3 complete** 🎉
> **Languages**: 11 (Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM, Cyrius)
> **Examples**: 814 source files; concept files: 74
> **Validator**: 814/814 green
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

**74 topics fully covered (11/11 languages) — P0 → P3 complete.**

`vidya stats` reports `Topics: 74, Complete: 74 (all 11 languages),
Examples: 814`; validator 814/814 green. No partial topics.

---

## In flight (2.7.x) — Build Systems (P4)

3 topics × 11 langs ≈ 33 new examples. Aligns with cyrius/zugot
tooling work; each primitive has a direct cyrius-toolchain
counterpart.

| Topic | Status | Plan |
|---|---|---|
| **build_systems** | planned 2.7.0 | DAG of build targets + dirty-tracking via mtime/hash + topological build order + ninja-style incremental rebuild. Cyrius/zugot are the natural reference points. |
| **package_resolution** | planned 2.7.1 | Semver constraint matching + dependency-graph build + cycle detection + version selection (pubgrub or naive backtracking). cyrius.cyml's resolver is the reference. |
| **reproducible_builds** | planned 2.7.2 | Deterministic timestamps (SOURCE_DATE_EPOCH) + sorted file iteration + content-addressable artifact paths + verifying byte-identical rebuilds. The cyrius compiler self-host check is the reference. |

After 2.7.2, P4 closes; next minor (2.8.x) opens **P5 functional /
type theory**.

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

Current pin: **5.9.43** (vidya 2.7.0; entire 5.9.x cycle absorbed
in one bump — niyama 1.0.1 fold at .0, sovereignty pass at .1
[programs/check.cyr + lib/audit_walk.cyr 78th stdlib], agnosys
`#derive(Serialize)` cascade .33–.39, cx Phase 2c parity at .40,
tls-live gate conversion at .41, lib/regression.cyr 79th stdlib
carve-out at .42, closeout at .43). Upstream cyrius issues
filed during 2.6.x — see `cyrius/docs/development/issues/`.

---

## Renderer integration — vyakarana (live)

> **Status**: Live on **vyakarana 1.11.1** as of 2026-05-08
> (pin bump only; wire-up shipped in 2.7.0). `vidya code
> <topic> <lang>` (CLI, ANSI-colored) and
> `GET /code/{topic}/{lang}` (HTTP, JSON tokens) both flow
> through `tokenize_source` / `tokenbuf_*` / `kind_name`.
> Theme contract per vyakarana ADR 0004 (palette indexed by
> kind-name string, never integer). OpenQASM falls back to
> `tokens:[]` — no grammar in vyakarana 1.11.x by design.
> Smoke verified: 2187 tokens on the rust track of
> `content/lexing_and_parsing/`.

vyakarana ships 38 bundled grammars covering every language in
vidya's reference shelf (the 11 vidya tracks plus 27 more). It
also ships a stable public API and a written contract for
how renderers integrate with it. Vidya can swap its current
code-rendering path over to vyakarana whenever a renderer
rewrite is planned.

**What needs to happen on vidya's side:**

1. ~~Add the dep in `cyrius.cyml`~~ — done in 2.7.0:
   ```toml
   [deps.vyakarana]
   git     = "https://github.com/MacCracken/vyakarana.git"
   tag     = "1.11.0"   # bump as later vyakarana releases ship
   modules = ["dist/vyakarana.cyr"]
   ```
2. ~~Run `cyrius deps`~~ — done; `lib/vyakarana.cyr` vendored.
3. Replace the existing code-rendering path with calls into the
   vyakarana public API (see the integration guide). Expected
   surface:
   - `tokenize_source(src, lang)` → tokenbuf
   - `tokenbuf_count` / `tokenbuf_kind` / `tokenbuf_start` /
     `tokenbuf_len`
   - `kind_name(k)` for theme indirection (the **stable
     contract** — index palettes by kind-name string, not
     integer)
   - 10 token-kind constants (`TK_IDENT` through `TK_ERROR`)
4. Pick a starter scope. Suggested order:
   - **`content/lexing_and_parsing/`** — vyakarana's own test
     corpus root. Best dogfooding loop: bugs in either side
     show up as render diffs.
   - **`content/cyrius/`** — vidya already has Cyrius corpus
     samples; the cyml grammar (vyakarana 1.9.0) handles them.
   - **Topic concept pages** — extend to other languages' tracks
     once the first two prove the pipeline.
5. Decide on a theme. vyakarana's bundled `default` theme is
   the reference palette; for vidya's web-content rendering you
   probably want a vidya-specific theme that maps the 10 kinds
   to vidya's style tokens. The contract is documented; how
   themes look is a vidya design call.

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

**API stability**: The public surface above is stable across
vyakarana 1.0.0 → 1.x.x. **2.0.0** brings one breaking change
(streaming-tokenizer return type goes from `tokenbuf` to
iterator); a migration guide will ship alongside. Until 2.0.0
lands, pinning to `1.x.x` is safe.

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

*Last Updated: 2026-05-08 (v2.7.0) — **🎉 P3 complete; 74/74 at 11/11; 814/814 validator. 2.7.0 infra bump in flight: cyrius 5.9.43, vyakarana 1.11.1 vendored, content-format spec extended, `vidya code` CLI + `GET /code/{topic}/{lang}` HTTP route live (token output flowing — verified 2187 tokens on the rust track of `content/lexing_and_parsing/`). P4 topics (build_systems, package_resolution, reproducible_builds) is the next vidya-side track.***
