# Vidya — Current State

> **Refresh cadence**: every release. The release post-hook should touch this file; if it doesn't, fix the hook.
>
> **What lives here**: volatile state that drifts every release — current version, cyrius pin, binary size, in-flight slot, consumer pin status. Durable rules / process live in [`../../CLAUDE.md`](../../CLAUDE.md).

## Version

- **Vidya**: 2.8.0 (canonical source: [`../../VERSION`](../../VERSION); `cyrius.cyml` reads it via `${file:VERSION}`)
- **Cyrius pin**: 6.4.2 (in [`../../cyrius.cyml`](../../cyrius.cyml); the wrapper is 6.4.2 too — no drift, so a plain `cyrius build` matches the pin; no `CYRIUS_HOME=…/versions/<pin>` + `--strict-pin` override needed)
- **Binary size**: ~14.7 MB static ELF (`build/vidya`, 14,661,488 B) — jumped from ~2.1 MB when the 6.2.x→6.4.x sandhi TLS refold began linking sigil's parallel-crypto banks (`SIGIL_CRYPTO_BANKS=64` → ~13 MB reachable static *data*) via the `tls` → `sha384_init_into` transitive. Unavoidable for a sandhi consumer — sit is ~14.9 MB on the same stack. `CYRIUS_DCE=1` does NOT reclaim it (the 13 MB is reachable data, not dead code). vidya's `serve` is plaintext localhost and never executes the crypto at runtime, but the static call graph links it.
- **Corpus**: 77 topics × 11 languages = 847 examples; coverage gaps = 0 (P4 complete: build_systems + package_resolution + reproducible_builds, shipped 2.7.3)

## Dep pins (from `cyrius.cyml`)

| Dep | Pin | Notes |
|---|---|---|
| cyrius (toolchain) | 6.4.2 | Jumped 6.1.41 → 6.4.2 (three minor series). Ecosystem is mid-migration onto 6.3.x (sit 6.3.36, agnoshi 6.3.34, sandhi 6.3.5, hoosh/sakshi 6.3.15); vidya rides the current wrapper head. Churn was mostly internal cycc/self-host — consumer impact was transitive-stdlib growth (see stdlib note) and the `cyrius bench` discovery change (now needs an explicit path). |
| sakshi | 2.4.4 | Bumped 2.2.10 → 2.4.4 (2.2.10 was a 6.1.x artifact). 2.4.4 adds 128-bit W3C trace-id — purely additive, no behavior change for existing callers. Aligns with sit's 2.4.x. |
| vyakarana | 2.2.3 | Unchanged — still the latest tag (repo pins cyrius 6.1.24, not yet re-released for 6.3.x/6.4.x). Its 6.1.x `dist/vyakarana.cyr` compiles + runs clean under 6.4.2; powers `code` syntax highlighting. Streaming API migration landed in [ADR 0002](../adr/0002-vyakarana-2x-streaming-api.md). |

Stdlib modules used (see `cyrius.cyml` `[deps] stdlib`): `syscalls, string, alloc, str, fmt, vec, hashmap, io, fs, chrono, tagged, bayan, ct, keccak, sigil, fnptr, args, regex, net, dynlib, tls, fdlopen, sandhi`. **6.1.x consolidated the former standalone `json` / `toml` / `base64` modules into the bundled `bayan` distlib** — those `lib/{json,toml,base64}.cyr` no longer ship, so `src/main.cyr`, `tests/vidya.tcyr`, and `tests/vidya.bcyr` now `include "lib/bayan.cyr"`. **The 6.2.x→6.4.x sandhi/TLS refolds grew the transitive surface**, adding five modules that had to be listed explicitly (the cyrius transitive resolver doesn't chase refold-added enum/const/call-site refs): `chrono` (`clock_now_ns`/`clock_now_ms`, sandhi keep-alive), `dynlib` (`dynlib_auxv_get`/`dynlib_read_auxv`, `fdlopen`), and `sigil` + `ct` + `keccak` (`sha384_init_into`, `tls_native`). `tls`/`fdlopen`/`sigil` etc. stay explicit until the cyrius transitive-stdlib arc closes — see roadmap "2.7.x dep-track follow-ups".

## Cycle posture

- **Shipped 2.8.0 (2026-07-04)**: infra-only cut — cyrius bump **6.1.41 → 6.4.2** + sakshi **2.2.10 → 2.4.4**. No new content topics (corpus stays 77/847). Build green; `cyrius test` 41/0; full content gate 847/847 under 6.4.2. Two consumer-visible effects, both handled: binary grew ~2.1 → ~14.7 MB (sigil crypto linked via the TLS transitive — see Binary size); and `cyrius bench` no longer discovers `tests/*.bcyr` from the no-arg form, so CI + `scripts/bench-history.sh` now pass the explicit path `tests/vidya.bcyr` (the latter also dropped a dead `cargo bench` line). Also hardened one flaky content assertion (`process_and_scheduling/shell.sh` live-nice `== 0` → range check).
- **Shipped 2.7.3**: **P4 (build systems) COMPLETE**. v2.7.0–v2.7.2 were infra-only cycles (dep bumps, cyrius 5→6, zig 0.16, bayan consolidation); the 2.7.3 content cycle landed all three P4 topics — `build_systems`, `package_resolution`, `reproducible_builds` — at 11/11 each (847/847). 2.8.0 then shipped as an infra-only cut (cyrius 6.4.2); a later 2.8.x content cycle opens P5 (functional / type theory) — same infra-first-then-content rhythm as 2.7.x. See [`roadmap.md`](roadmap.md) "P4 — Build Systems".
- **Loose ends** from v2.7.1 ship: zugot recipe sha256 backfill (post-release-artifact), watch CI wallclock on the new content-validation gate, see "2.7.x dep-track follow-ups" in roadmap.

## Consumers

| Consumer | Status | Vidya pin |
|---|---|---|
| agnoshi | active | follows main |
| hoosh | active | follows main |
| sandhi | active (vidya is *consumer*, sandhi provides HTTP stdlib) | n/a (other direction) |
| sakshi | active (vidya is *consumer*, sakshi provides tracing) | n/a (other direction) |
| cyrius | bidirectional (vidya documents cyrius, cyrius runs vidya) | n/a |
| zugot | `marketplace/vidya.cyml` pinned at 2.7.2; sha256 backfill pending release artifact |

## Verification hosts

Vidya runs on any x86_64 Linux host with the pinned cyrius toolchain. CI runs on `ubuntu-latest`. No host-specific bootstrap state — the binary is a single static ELF.

## What does NOT belong here

- Process rules, work-loop discipline, content standards → [`../../CLAUDE.md`](../../CLAUDE.md).
- Per-release narrative → [`../../CHANGELOG.md`](../../CHANGELOG.md).
- Forward roadmap → [`roadmap.md`](roadmap.md).
- Doc currency ledger → [`../doc-health.md`](../doc-health.md).
