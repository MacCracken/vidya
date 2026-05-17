---
name: Vidya Documentation Health
description: Living state of doc currency in the vidya repo — fresh / stale / dated-artifact / open-question, refreshed as docs are touched
type: state
---

# Documentation Health — vidya

> **Last refresh**: 2026-05-16 (v2.7.1 ship — first scaffold + first sweep + standards-conformance pass). **Sweep fixes**: `BENCHMARKS.md` (v2.1.0 / 35 topics → v2.7.1 / 74 topics), `docs/usage.md` (added `code` + `serve`, 36 → 74 topics), `docs/sources.md` (Cyrius row added), `docs/development/learning-paths.md` (5 → 12 paths, 65 verified topic IDs). **Standards-conformance additions**: `CODE_OF_CONDUCT.md` (required), `docs/adr/` tier (template + README + 2 ADRs covering Rust→Cyrius port and vyakarana streaming migration — the latter retires `content-expansion-2026-04-08.md` into ADR 0001), `docs/architecture/README.md` (index), `docs/guides/getting-started.md` (zero-to-CLI), `docs/examples/README.md` (placeholder for consumer-integration examples), `docs/development/state.md` (volatile-state ledger — cyrius pin moved out of CLAUDE.md per first-party-documentation §"CLAUDE.md"). | **Refresh cadence**: when docs are touched, update the affected row.
>
> **Scope**: This repo only (`vidya`) — root-level files (README, BENCHMARKS, CHANGELOG, CLAUDE.md, CONTRIBUTING, SECURITY, VERSION) plus `docs/`. Cross-repo state (cyrius pin, sakshi/vyakarana versions, zugot recipe) is tracked in [`development/roadmap.md`](development/roadmap.md) and the relevant section of [`CHANGELOG.md`](../CHANGELOG.md), not here.
>
> **Convention adopted from cyrius/agnosticos** (2026-05-16): pattern from `cyrius/docs/doc-health.md` (which adopted it from `agnosticos/docs/doc-health.md`). Vidya's doc tree is ~14 markdown files (vs cyrius's ~81 and agnosticos's ~265) so the tier structure here is leaner — no ADRs, audits, FFI, issues/proposals subdirs at this scale.

This is a **ledger**, not a one-time audit. Rewrite-in-place as docs change.

---

## At a glance — 2026-05-16 inventory

**~20 markdown files** across the repo (+6 since first scaffold: 4 ADR tier files + state.md + 3 standards-conformance scaffolds, minus 1 retired narrative). Bucket counts:

| Bucket | Count | What it means |
|---|---|---|
| ✅ **Fresh / touched in current cycle** | 18 | All root files + this ledger + every `docs/` entry. Includes the 4 sweep refreshes, 1 README rewrite, and the standards-conformance batch (adr tier, architecture index, guides, examples, state.md). |
| 🟡 **Stale — refresh in place** | 0 | First sweep cleared all four flagged docs. |
| 🟠 **Read-through outstanding** | 2 | `CONTRIBUTING.md` (2026-04-09 — Cyrius-aware shape, looked correct on inspection but pre-P0C/P1/P2/P3 surface; verify the topic-addition recipe against the 74-topic reality). `SECURITY.md` (2026-04-09 — minimal, references `rust-old/` archive which is still accurate context). |
| 🔵 **Dated artifact — frozen by design** | 0 | `docs/content-expansion-2026-04-08.md` was retired into [`adr/0001-port-from-rust-to-cyrius.md`](adr/0001-port-from-rust-to-cyrius.md) at the 2026-05-16 sweep — the narrative is preserved as the ADR's "Retired narrative" appendix. No standalone dated artifacts remain. |
| ❓ **Open strategic question** | 0 | All previously-flagged standards-conformance items (Commitments §5–7) were adopted during the 2026-05-16 pass. |

Numbers approximate; rolls up from the per-tier tables below.

**Why now**: doc-health convention seen in `cyrius/docs/doc-health.md`. Vidya's doc tree has been **partially maintained** (CHANGELOG / CLAUDE.md / roadmap rotate every release) but the user-facing docs (README, BENCHMARKS, usage) drifted three minors during the v2.6.x → v2.7.x content + infra surge. This file is the surface.

**2026-05-16 scaffold notes**: ledger created alongside the 2.7.1 ship. The 2.7.1 sweep already caught the README's Rust-crate Quick Start (rewritten). Remaining drift surface area: 4 stale docs flagged above. No untracked docs found.

---

## Tier 1 — Structural docs (root + `docs/` root)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-05-16 | ✅ Fresh | Rewritten at v2.7.1 — Rust-crate Quick Start replaced with Cyrius CLI invocations; topic count refreshed 33 → 74; languages table moved Cyrius to row 1 marked Primary. |
| `BENCHMARKS.md` | 2026-05-16 | ✅ Fresh | **Refreshed during 2026-05-16 sweep.** Fresh numbers from `cyrius bench tests/vidya.bcyr` at v2.7.1 / 5.11.55. v2.0 → Rust v1.5.0 comparison preserved as historical frozen table. |
| `CHANGELOG.md` | 2026-05-16 | ✅ Fresh | **Source of truth.** v2.7.1 entry covers cyrius 5.11.55 / sakshi 2.2.4 / vyakarana 2.2.1 streaming migration / CI refresh. Refreshed every release. |
| `CLAUDE.md` | 2026-05-16 | ✅ Fresh | **Volatile-state split done 2026-05-16** — cyrius pin and binary size moved out to `docs/development/state.md`; CLAUDE.md now points to it. Identity / process / standards remain inline (durable). |
| `CODE_OF_CONDUCT.md` | 2026-05-16 | ✅ Fresh | **Added during 2026-05-16 sweep.** Required per first-party-documentation standards; vidya was missing it. Contributor Covenant v2.1 stub matching cyrius/mabda/vani. |
| `CONTRIBUTING.md` | 2026-04-09 | 🟠 Read-through | Cyrius-aware shape on inspection. Verify the "Adding a Topic" recipe against the 74-topic reality (does it still match content-format.md? Does it mention `cyrius.cyr` requirement? — yes). Spot-check at next minor closeout. |
| `SECURITY.md` | 2026-04-09 | 🟠 Read-through | Minimal. References `rust-old/` archive (still accurate). Verify the `validate` command security note still matches `scripts/validate-content.sh` shape. |
| `VERSION` | 2026-05-16 | ✅ Fresh | `2.7.1`. Bumped via `scripts/version-bump.sh` (cleaned up at v2.7.1 — pre-2.0 cargo references removed). `cyrius.cyml` reads from this via `${file:VERSION}`. |
| `docs/usage.md` | 2026-05-16 | ✅ Fresh | **Refreshed during 2026-05-16 sweep.** 36 → 74 topics, 85 KB → 1.1 MB binary, 29 → 81 lib modules; added `vidya code <topic> <lang>` (CLI) and `vidya serve <port>` (HTTP) sections, full HTTP route table. |
| `docs/sources.md` | 2026-05-16 | ✅ Fresh | **Refreshed during 2026-05-16 sweep.** Added Cyrius row to language specs (pinned 5.11.55); Zig 0.15 entry annotated with the 0.15.2 CI pin. Algorithm / standards / compiler reference tables unchanged. |
| `docs/doc-health.md` | 2026-05-16 | ✅ Fresh | **This file** — first scaffold 2026-05-16 alongside the sweep. Pattern from `cyrius/docs/doc-health.md`. |
| ~~`docs/content-expansion-2026-04-08.md`~~ | retired 2026-05-16 | — | **Retired** — converted into [`adr/0001-port-from-rust-to-cyrius.md`](adr/0001-port-from-rust-to-cyrius.md) "Retired narrative" appendix. The decision rationale now lives in proper ADR form; the execution narrative is preserved verbatim. |

---

## Tier 2 — Architecture (`docs/architecture/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — tier index. Currently lists `overview.md` as the only entry; numbered architecture notes (`NNN-*.md`) added as invariants surface. |
| `overview.md` | 2026-05-02 | ✅ Fresh | Module map, data flow, consumer list. Touched early v2.7.x; verify consumer list (agnoshi / hoosh / cyrius / sandhi / sakshi) matches roadmap "Relationship to AGNOS" section. Spot-check at next minor closeout. |

---

## Tier 3 — ADRs (`docs/adr/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — tier index + conventions. Two ADRs cataloged. |
| `template.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — standard ADR template (cloned from cyrius). |
| `0001-port-from-rust-to-cyrius.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — retires `docs/content-expansion-2026-04-08.md`. Documents the v2.0 decision + the content-surge narrative as an appendix. |
| `0002-vyakarana-2x-streaming-api.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — documents the v2.7.1 vyakarana 1.x → 2.x migration (only scheduled break in vyakarana's roadmap; rewrites the two `cmd_code` / `/code/...` call sites). |

---

## Tier 4 — Guides (`docs/guides/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `getting-started.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — zero-to-CLI in five minutes; cross-references `docs/usage.md` for the full command surface. |

---

## Tier 5 — Examples (`docs/examples/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `README.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — placeholder pointing at `content/` for the largest example collection in the project. Consumer-integration examples (agnoshi / hoosh / curl recipes for `vidya serve`) land here as they emerge. |

---

## Tier 6 — Operational / Development (`docs/development/`)

| File | Last touched | Status | Action |
|---|---|---|---|
| `roadmap.md` | 2026-05-16 | ✅ Fresh | **Rotates every release.** Rewritten at v2.7.1: pin refreshed (5.9.43 → 5.11.55), vyakarana section rewritten for the 2.x streaming-API migration, slot drift noted (2.7.0 + 2.7.1 were infra-only — build_systems et al. unpinned from specific patch slots), new "2.7.x dep-track follow-ups" section. |
| `state.md` | 2026-05-16 | ✅ Fresh | **New 2026-05-16** — volatile-state ledger split out of CLAUDE.md per first-party-documentation standards. Refreshed every release. |
| `content-format.md` | 2026-05-08 | ✅ Fresh | Content directory specification. Touched at v2.7.0 (extended to document the two non-topic entries — `cyrius/` language reference + `qelib1.inc`). Stable; verify per minor closeout. |
| `content-grouping.md` | 2026-05-01 | ✅ Fresh | Subdir reorg trigger condition (~50 topics). Currently at 74 — reorg overdue, called out in roadmap. Spec itself is current. |
| `learning-paths.md` | 2026-05-16 | ✅ Fresh | **Refreshed during 2026-05-16 sweep.** 5 original paths preserved + 7 new paths added (Networked Service / Database Internals / Distributed Systems / Audio / AI-ML / Graphics / Game Systems / Observability). 65 unique topic IDs verified against `content/` — zero broken references. |

---

## Refresh procedure

When docs are touched:

1. Find the affected row in the relevant tier table.
2. Update **Last touched** to the new date.
3. Update **Status** if the bucket changed.
4. Update **Action** if the next step changed.
5. If a doc moved or was archived, update its row.
6. Re-anchor "Last refresh" date in the header.

When the bucket counts at the top drift by more than ~2 in any cell, refresh the at-a-glance table.

This file's refresh cadence is **opportunistic** (touched when other docs are touched), not periodic.

---

## What this file is NOT

- Not a CHANGELOG (which records what shipped, not what's stale).
- Not a TODO list (open work for the project lives in [`development/roadmap.md`](development/roadmap.md)).
- Not a per-doc review log (this is the ledger of where each doc stands, not the per-doc reasoning).

---

## Forward doc-policy commitments

Items that are *scheduled* doc decisions, not stale state. Surfaced here so they aren't forgotten when the trigger date arrives.

| # | Commitment | Trigger | Source | Notes |
|---|---|---|---|---|
| 1 | **Roadmap + CHANGELOG sync at every minor closeout** — release narrative lands in CHANGELOG, slot disposition + dep-track follow-ups in roadmap. | Every minor closeout | [`CLAUDE.md`](../CLAUDE.md) "Work Loop" §10 | Already automated via process; included for visibility. |
| 2 | **Zugot recipe sync after every vidya release** — `zugot/marketplace/vidya.cyml` version + sha256 backfilled once the release tarball ships. | After release artifact builds | [`CLAUDE.md`](../CLAUDE.md) "Work Loop" §11 | Cross-repo; not gated by vidya CI. Loose end called out in `roadmap.md` 2.7.x dep-track table. |
| 3 | **Content subdir reorg** — when topic count crosses ~50, reorganize `content/` into category subdirs per [`content-grouping.md`](development/content-grouping.md). | Topic count > ~50 | [`docs/development/content-grouping.md`](development/content-grouping.md) | **Overdue** at 74. Roadmap pins this as a 3.0.0 candidate (single atomic move; one minor of symlink compat). |
| 4 | **Benchmark refresh per minor** — `cyrius bench tests/vidya.bcyr` + bench-history snapshot per release. | Every minor closeout | [`CLAUDE.md`](../CLAUDE.md) "Work Loop" §4 | Refreshed in the 2026-05-16 sweep. Watch BENCHMARKS.md header date drift > 1 minor. |
| 5 | ~~CLAUDE.md volatile-state split~~ | — | — | **Adopted 2026-05-16.** Cyrius pin + binary size moved to `docs/development/state.md`; CLAUDE.md identity block now points there. |
| 6 | ~~`docs/adr/` directory~~ | — | — | **Adopted 2026-05-16.** Template + README + 2 ADRs scaffolded (0001 retires content-expansion narrative; 0002 documents vyakarana migration). |
| 7 | ~~`docs/architecture/README.md` + `docs/guides/` + `docs/examples/`~~ | — | — | **Adopted 2026-05-16.** All three scaffolded — architecture index, getting-started guide, examples placeholder pointing at `content/`. |

---

*Initial scaffold: 2026-05-16 (v2.7.1). Refresh in place when docs are touched.*
