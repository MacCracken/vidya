# Vidya — Current State

> **Refresh cadence**: every release. The release post-hook should touch this file; if it doesn't, fix the hook.
>
> **What lives here**: volatile state that drifts every release — current version, cyrius pin, binary size, in-flight slot, consumer pin status. Durable rules / process live in [`../../CLAUDE.md`](../../CLAUDE.md).

## Version

- **Vidya**: 2.7.1 (canonical source: [`../../VERSION`](../../VERSION); `cyrius.cyml` reads it via `${file:VERSION}`)
- **Cyrius pin**: 5.11.55 (in [`../../cyrius.cyml`](../../cyrius.cyml))
- **Binary size**: ~1.1 MB static ELF (`build/vidya`)
- **Corpus**: 74 topics × 11 languages = 814 examples; coverage gaps = 0

## Dep pins (from `cyrius.cyml`)

| Dep | Pin | Notes |
|---|---|---|
| cyrius (toolchain) | 5.11.55 | Absorbed 5.10.x + 5.11.x cycles in one bump at v2.7.1 |
| sakshi | 2.2.4 | Cycle-counter timestamps via `rdtsc` / `cntvct_el0`; aarch64 portability |
| vyakarana | 2.2.1 | Streaming API (ADR 0017 on vyakarana side); migration landed in [ADR 0002](../adr/0002-vyakarana-2x-streaming-api.md) |

Stdlib modules used (see `cyrius.cyml` `[deps] stdlib`): `syscalls, string, alloc, str, fmt, vec, hashmap, io, fs, tagged, json, fnptr, args, toml, regex, net, tls, base64, fdlopen, sandhi`. `tls`/`base64`/`fdlopen` are explicit until the cyrius v5.10.x SLOT 19 transitive-stdlib arc closes — see roadmap "2.7.x dep-track follow-ups".

## Cycle posture

- **In flight**: v2.7.x — P4 (build systems) on the topic side. v2.7.0 + v2.7.1 were infra-only cycles; build_systems / package_resolution / reproducible_builds slid to the next content slots. See [`roadmap.md`](roadmap.md) "In flight (2.7.x)" for slot disposition.
- **Loose ends** from v2.7.1 ship: zugot recipe sha256 backfill (post-release-artifact), watch CI wallclock on the new content-validation gate, see "2.7.x dep-track follow-ups" in roadmap.

## Consumers

| Consumer | Status | Vidya pin |
|---|---|---|
| agnoshi | active | follows main |
| hoosh | active | follows main |
| sandhi | active (vidya is *consumer*, sandhi provides HTTP stdlib) | n/a (other direction) |
| sakshi | active (vidya is *consumer*, sakshi provides tracing) | n/a (other direction) |
| cyrius | bidirectional (vidya documents cyrius, cyrius runs vidya) | n/a |
| zugot | `marketplace/vidya.cyml` pinned at 2.7.1; sha256 backfill pending release artifact |

## Verification hosts

Vidya runs on any x86_64 Linux host with the pinned cyrius toolchain. CI runs on `ubuntu-latest`. No host-specific bootstrap state — the binary is a single static ELF.

## What does NOT belong here

- Process rules, work-loop discipline, content standards → [`../../CLAUDE.md`](../../CLAUDE.md).
- Per-release narrative → [`../../CHANGELOG.md`](../../CHANGELOG.md).
- Forward roadmap → [`roadmap.md`](roadmap.md).
- Doc currency ledger → [`../doc-health.md`](../doc-health.md).
