# Vidya — Development Roadmap

> **Status**: Active | **Last Updated**: 2026-05-03
>
> **Version**: 2.6.4 | **Cyrius**: 5.8.34
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

Current pin: **5.8.34** (vidya 2.4.4). Upstream cyrius issues
filed during 2.6.x — see `cyrius/docs/development/issues/`.

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
- **`docs/sources.md`** standard — vidya IS the source citation for
  programming knowledge

Every science crate cites papers. Vidya cites implementations.

---

*Last Updated: 2026-05-03 (v2.6.4) — **🎉 P3 complete; 74/74 at 11/11; 814/814 validator; next: 2.7.x opens P4 build systems with build_systems, package_resolution, reproducible_builds***
