---
name: Ecosystem GitHub Action Pins
description: Cross-repo record of AGNOS GitHub Action major-version staleness found during the vidya 2.8.4 dependency cut, with the per-repo migration and the evidence that it is safe
type: reference
---

# Ecosystem GitHub Action Pins

> **Surveyed**: 2026-08-22, during the vidya 2.8.4 dependency cut.
> **Status**: vidya migrated. The other five repos are **unmigrated** — this
> file is the write-up, not a change to them.
>
> This is a **cross-repo** note living in vidya only because vidya is where the
> survey happened. Each repo owns its own workflows; nothing here has been
> applied outside vidya.

## What was found

vidya's GitHub Actions were 3–4 majors behind. The survey that followed found
this is not a vidya oversight — **every AGNOS repo with workflows was on the
identical `v4` / `v2` pins**, so the whole ecosystem drifted together.

| Action | Ecosystem pin | Latest (2026-08-22) | Majors behind |
|---|---|---|---|
| `actions/checkout` | v4 | **v7.0.1** | 3 |
| `actions/upload-artifact` | v4 | **v7.0.1** | 3 |
| `actions/download-artifact` | v4 | **v8.0.1** | 4 |
| `softprops/action-gh-release` | v2 | **v3.0.2** | 1 |

**cyrius is the exception and the better pattern**: it pins by full commit SHA
(`actions/checkout@34e114876b…`, `softprops/action-gh-release@3bb12739c2…`).
SHA pinning trades currency for supply-chain integrity. If any of these repos
is ever hardened rather than merely updated, that is the shape to copy — and
the tradeoff is that SHA pins need a deliberate refresh cadence or they rot
silently, which is arguably what a floating `v4` was protecting against.

## Why the bump is safe

Every one of these majors is fundamentally a **Node 20 → Node 24 runtime
move**, requiring Actions Runner ≥ 2.327.1. GitHub-hosted `ubuntu-latest`
satisfies that; **self-hosted fleets must be checked before migrating**.

Two changes advertise as breaking. Neither applies to any AGNOS repo, and both
were checked against upstream release notes rather than assumed:

- **`download-artifact` v5 — path behaviour.** The fix makes single-artifact
  downloads *by ID* extract to `path/` instead of `path/<name>/`. It applies to
  `artifact-ids:` only. Upstream's own migration guide lists "you download
  artifacts by **name**" under *no action needed*. **No AGNOS repo uses
  `artifact-ids:`** — verified by grep across all five.

- **`upload-artifact` v7 — direct uploads.** Adds an opt-in `archive:` input
  for uploading a single file unzipped. Multi-file globs with an explicit
  `name:`, which is what every AGNOS release workflow does, are unchanged. v7
  also moves the module to ESM, which is internal to the action.

`action-gh-release` v3 is a pure runtime move; **v2.6.2** is the last Node 20
line if a self-hosted runner ever needs to stay back.

## Per-repo migration

Mechanical in every case — the same four substitutions:

```bash
sed -i 's|actions/checkout@v4|actions/checkout@v7|g; s|actions/upload-artifact@v4|actions/upload-artifact@v7|g; s|actions/download-artifact@v4|actions/download-artifact@v8|g; s|softprops/action-gh-release@v2|softprops/action-gh-release@v3|g' .github/workflows/*.yml
```

| Repo | Files | checkout | upload | download | gh-release | Notes |
|---|---|---|---|---|---|---|
| **vidya** | ci.yml, release.yml | 4 | 1 | 1 | 1 | ✅ **Migrated at 2.8.4.** |
| **sit** | ci.yml, release.yml | 3 | 1 | 1 | 1 | Straight substitution. Downloads by `name: release-artifacts`. |
| **sakshi** | ci.yml, release.yml | 6 | 1 | 1 | 1 | Straight substitution. Downloads by `name: release-artifacts`. |
| **sandhi** | ci.yml, release.yml | 4 | 1 | 1 | 1 | Straight substitution. Downloads by `name: release-artifacts`. |
| **hoosh** | ci.yml, release.yml | 3 | 1 | 0 | 1 | No `download-artifact` at all — three substitutions. |
| **vyakarana** | ci.yml, release.yml | 4 | 2 | 1 | 1 | ⚠ **Check this one by hand.** Its `download-artifact` step passes `path: dist-raw` with **no `name:`** — the download-*all* form, which extracts each artifact into `path/<artifact-name>/` — and a following "Consolidate artifacts" step depends on that layout. The v5 change does not touch the download-all path, so it should be fine, but this is the only repo whose consolidation logic is coupled to the extraction layout. |
| **cyrius** | ci.yml, release.yml | — | — | — | — | SHA-pinned. Out of scope for a major bump; needs a SHA refresh instead. |

## Verification

None of this can be verified locally — GitHub Actions only run on GitHub. The
first real test of vidya's migration is the **2.8.4 release tag**. Migrate the
others one at a time and watch the first workflow run, rather than doing all
five at once.

## Also checked in the same sweep

- **Zig** — CI installs `0.16.0`; latest release is `0.16.0`. **Already
  current**, no change.
- **`ubuntu-latest` / gcc** — the C standard probe (`-std=c23` with `-std=c2x`
  fallback) added at 2.8.3 remains correct; it probes rather than assumes, so a
  runner-image gcc bump cannot break it the way the hardcoded flag did.
- **Unpinned installs** — `tsx`, `typescript`, `@types/node` (npm) and `qiskit`
  (pip) all install latest at CI time. Deliberate, but it means a breaking
  upstream release lands as a red build with no vidya change; recorded here
  rather than treated as settled.
