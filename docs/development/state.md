# Vidya — Current State

> **Refresh cadence**: every release. The release post-hook should touch this file; if it doesn't, fix the hook.
>
> **What lives here**: volatile state that drifts every release — current version, cyrius pin, binary size, in-flight slot, consumer pin status. Durable rules / process live in [`../../CLAUDE.md`](../../CLAUDE.md).

## Version

- **Vidya**: 2.8.3 (canonical source: [`../../VERSION`](../../VERSION); `cyrius.cyml` reads it via `${file:VERSION}`)
- **Cyrius pin**: 6.5.31 (in [`../../cyrius.cyml`](../../cyrius.cyml); the wrapper is 6.5.31 too — no drift, so a plain `cyrius build` matches the pin; no `CYRIUS_HOME` + `--strict-pin` override needed). ⚠ `CYRIUS_HOME` takes the **install root** (`~/.cyrius`), not the versioned dir — pointing it at `~/.cyrius/versions/<pin>` makes the resolver look for `<pin>/versions/<pin>/lib` and fail.
- **Binary size**: **~2.56 MB static ELF** (`build/vidya`, 2,564,304 B; +1,040 B over 2.8.2) — down from 14.66 MB at 2.8.0 (**−82.5%**). The 2.8.0 note called the ~13 MB of sigil parallel-crypto static data (`SIGIL_CRYPTO_BANKS = 64`, linked via the `tls` → `sha384_init_into` transitive) unavoidable for a sandhi consumer and not DCE-reclaimable. 6.5.x makes that obsolete: the compiler's large-static-data report fell 13,119,032 B → 862,168 B with the constant still 64 in both snapshots, so the change is in toolchain placement/reachability, not sigil config. `serve` remains plaintext localhost and never executes the crypto at runtime.
- **Corpus**: 77 topics × 11 languages = 847 examples; coverage gaps = 0 (P4 complete: build_systems + package_resolution + reproducible_builds, shipped 2.7.3)
- **Source layout**: `src/main.cyr` (598 lines — CLI plumbing, route table, `main()`) + `src/vidya_core.cyr` (1,537 lines — types, registry, TOML loader, hot-reload, search, compare, code, validate, and the `json_*` builders). Split at 2.8.2 so `tests/vidya.tcyr` and `tests/vidya.bcyr` can `include` the domain layer: a `.tcyr` cannot bind a port and could not reach into a file whose only entry point is `main()`. Tests and benchmarks now run the same code the binary serves.
- **Gates**: `cyrius test` **139 assertions**, `cyrius bench tests/vidya.bcyr` **12 benchmarks**, content gate **847/847** under `VIDYA_STRICT=1`.
- **Gate depth (new at 2.8.3)**: the content gate no longer just compiles-and-runs. Rust gets an additive `--test` pass, Go gets `gofmt -l` + `go vet`, TypeScript is `tsc --noEmit --strict` type-checked before running, Python runs with `EncodingWarning` as an error, and any Cyrius `duplicate fn` fails the build. ⚠ Every one of these is mirrored in `validate_command` in `src/vidya_core.cyr` — the two validators drifted twice in the 2.8.x series and each time the shipped CLI silently skipped work the shell gate ran. **Still invisible to the gate**: comment-level falsehoods, semantics it never executes (no OpenQASM circuit is simulated), and anything a language's own tooling does not flag.

## Dep pins (from `cyrius.cyml`)

| Dep | Pin | Notes |
|---|---|---|
| cyrius (toolchain) | 6.5.31 | 6.4.2 → 6.5.29 at 2.8.1, → **6.5.31** post-2.8.2. The 6.4.2 → 6.5.29 jump had **zero stdlib module removals** (three additions only: `async_macos`, `async_win`, `thread_macos`, none declared here) and fixed the 6.4.x `cyrius bench` discovery regression. The 6.5.29 → 6.5.31 step is **purely compiler-side**: no module added, none removed, and none of the 25 declared modules changed content (sha256-verified per module), so nothing to migrate. Ecosystem on 6.5.x: sit **6.5.31**, sakshi 6.5.29, hoosh 6.5.27, sandhi 6.5.20, vyakarana 6.5.4; agnoshi still trails at 6.3.34. |
| sakshi | **2.4.11, as a stdlib leaf** | **No longer a `[deps.sakshi]` git block** as of 2.8.1 — see the shadow-override note below. Resolves from the toolchain snapshot (`lib/sakshi.cyr` ships with cyrius as of 6.5.24). Net movement 2.4.4 → 2.4.10 at 2.8.1, then **2.4.10 → 2.4.11 at 2.8.2 with no manifest change** — the 6.5.29 snapshot was refreshed in place and `cyrius lib sync` picked it up. That is the 2.8.1 prediction coming true, and the clearest argument for the leaf shape: under the old git block the repo would still be pinned at 2.4.4. |
| vyakarana | 2.2.3 → **2.3.2** | Still a real git dep — vyakarana is *not* folded into the snapshot. 2.3.0 moved vyakarana's own pin 6.1.24 → 6.5.4 and re-cut its vendored `lib/`; 2.3.1–2.3.2 are tokenizer-correctness patches (`TK_ERROR` adjudication across 37 grammars). No token-kind, `Token`-layout, or public-API change — `code` highlighting gains accuracy with no call-site change. Streaming API migration landed in [ADR 0002](../adr/0002-vyakarana-2x-streaming-api.md). |

### ⚠ sakshi: why it is NOT a git dep

cyrius folded sakshi into its stdlib snapshot at **6.5.24**. Through 2.8.0 vidya still declared `[deps.sakshi]` at tag 2.4.4, and `cyrius deps` overlays a git dep's resolution **on top of** the folded snapshot on every build — so the 2.4.4 file was *replacing* the toolchain's 2.4.10. It was a silent downgrade with three tells, all now gone: `duplicate fn 'sakshi_span_enter' / 'sakshi_span_exit' (last definition wins)` on every compile; `cyrius deps --verify` reporting clean because the lock is written **from disk** and recorded the hash of the downgraded file; and the stale copy being pushed at anything reaching vidya transitively. sit hit the identical trap and dropped its pin for the same reason — see the `[deps]` comment in `~/Repos/sit/cyrius.cyml`. **Do not re-add the git block.** Pinning sakshi means pinning the toolchain, and the `cyrius` pin in `[package]` is that lever.

### Stdlib modules

From `cyrius.cyml` `[deps] stdlib` (**25 modules**): `syscalls, string, alloc, str, fmt, vec, hashmap, io, fs, process, chrono, tagged, bayan, ct, keccak, sigil, fnptr, args, regex, net, dynlib, tls, fdlopen, sandhi, sakshi`. (`process` was added post-2.8.1 for `exec_cmd` in `vidya validate`; it was already on disk as a transitive, so the vendored file count is unchanged — declaring it is what keeps it from being someone else's transitive, the class of dep that fails at **runtime**.) A clean `cyrius lib sync` + `cyrius deps` vendors **62 files** into `lib/` (declared set plus transitives). As of 6.5.29 both `cyrius lib sync` and `cyrius deps` **overwrite** a stale `lib/<mod>.cyr` from the pinned snapshot — verified during the 2.8.1 bump by staging a 6.4.2 `fmt.cyr` into a 6.5.29 tree and watching each command restore it. The older never-refreshes behavior that vyakarana's 2.3.0 entry documented at 6.5.4 does not apply here, so `rm -rf lib` before a pin bump is belt-and-braces rather than required. Note this is what makes a **git-dep overlay** the dangerous case: the overlay is reapplied on every build *by design*, so it is not staleness the sync can heal — see the sakshi note above.

**6.1.x consolidated the former standalone `json` / `toml` / `base64` modules into the bundled `bayan` distlib** — those `lib/{json,toml,base64}.cyr` no longer ship, so `src/main.cyr`, `tests/vidya.tcyr`, and `tests/vidya.bcyr` `include "lib/bayan.cyr"`. **The 6.2.x→6.4.x sandhi/TLS refolds grew the transitive surface**, adding five modules that had to be listed explicitly (the cyrius transitive resolver doesn't chase refold-added enum/const/call-site refs): `chrono` (`clock_now_ns`/`clock_now_ms`, sandhi keep-alive), `dynlib` (`dynlib_auxv_get`/`dynlib_read_auxv`, `fdlopen`), and `sigil` + `ct` + `keccak` (`sha384_init_into`, `tls_native`). Re-measured at 6.5.29 during the 2.8.1 bump: the arc has caught up for three of the five — dropping `ct`, `keccak`, `sigil` still vendors the same 62 modules and builds clean (binary 4,080 B smaller), so those three are now redundant rather than load-bearing. `chrono` and `dynlib` remain hard requirements (removing either is a build error). All five are kept regardless, because an undeclared module of this class fails at **runtime**, not at build time — see roadmap "2.7.x dep-track follow-ups".

**Five `undefined function` warnings are expected and benign**: `random_bytes`, `async_new_in`, `async_spawn`, `async_run`, `async_await_readable`. `async_*` is unreachable because vidya's `serve` is synchronous; `random_bytes` is referenced only by `lib/sigil.cyr` and the agnos/windows syscall shims, none reachable from a Linux-hosted plaintext `serve`.

## Cycle posture

- **Shipped 2.8.3 (2026-08-20)**: cyrius **6.5.29 → 6.5.31** (pure compiler-side; no declared stdlib module changed), C **C17 → C23** (77/77 compile *and* run unchanged), Zig deprecated-alias sweep, and a corpus-wide example review that found **80 verified defects behind a green gate** — memory-safety bugs, tests that could not fail, and code teaching the opposite of its subject. Four gate checks added to close those classes, each mirrored in both validators. No content added (77/847, 0 gaps). The lesson worth carrying: `847/847 green` was true the whole time a C parser had six unbounded `memcpy`s and three security suites could not fail.
- **Shipped 2.8.2 (2026-08-20)**: correctness cut on the 2.8.1 infra base — no content change (77/847, 0 gaps). Five user-visible defects, three in surfaces agnoshi/hoosh read directly: `search` was byte-exact (so `tcp` missed what `TCP` found) and had tag search commented out; `/info/{topic}` reported `1` for every section count (`&&` yields 0/1, so the null-vec guard became the value); `/search?q=` spliced the query unescaped, allowing JSON structure injection; and `vidya validate` reported **462 false FAILs of 847** from a broken fork/exec (empty `envp`, two under-reserved stack buffers — `var buf[N]` reserves N *bytes* — and asm templates ending `; rm -f` so a failing example reported PASS). All five shared one root cause: **nothing tested the code that had them**. `src/vidya_core.cyr` is the structural fix; tests went **41 → 139**, benchmarks **6 → 12**. sakshi also moved 2.4.10 → 2.4.11 with no manifest change.
- **Shipped 2.8.1 (2026-08-20)**: infra-only cut — cyrius **6.4.2 → 6.5.29**, sakshi reshaped from a git dep to a stdlib leaf (**2.4.4 → 2.4.10**, fixing a silent downgrade), vyakarana **2.2.3 → 2.3.2**. No content change (corpus stays 77/847, 0 gaps). Build green; `cyrius test` 41/0. Headline: **binary 14.66 MB → 2.56 MB (−82.5%)**, retiring 2.8.0's "unavoidable sandhi-consumer cost" note. Also fixed **dead span tracing** — `src/main.cyr` carried no-op `sakshi_span_enter`/`_exit` stubs (comment cited sakshi v0.5.0, four majors stale) that overrode the real implementations, so `load_all`'s span recorded nothing; stubs removed. Benchmarks: only `toml_sections` (−17.7%, non-overlapping distributions) and `load_all` (−7.2%) clear the noise floor; the other four are flat.
- **Shipped 2.8.0 (2026-07-04)**: infra-only cut — cyrius bump **6.1.41 → 6.4.2** + sakshi **2.2.10 → 2.4.4**. No new content topics. Two consumer-visible effects at the time: binary grew ~2.1 → ~14.7 MB (since reversed at 6.5.x — see Binary size), and `cyrius bench` stopped discovering `tests/*.bcyr` from the no-arg form (since fixed at 6.5.x; CI still passes the explicit path, which works either way). Also hardened one flaky content assertion (`process_and_scheduling/shell.sh` live-nice `== 0` → range check).
- **Shipped 2.7.3**: **P4 (build systems) COMPLETE**. v2.7.0–v2.7.2 were infra-only cycles (dep bumps, cyrius 5→6, zig 0.16, bayan consolidation); the 2.7.3 content cycle landed all three P4 topics — `build_systems`, `package_resolution`, `reproducible_builds` — at 11/11 each (847/847). See [`roadmap.md`](roadmap.md) "P4 — Build Systems".
- **Next**: a 2.8.x content cycle opens P5 (functional / type theory) — same infra-first-then-content rhythm as 2.7.x. A content review is queued ahead of it.
- **Loose ends**: zugot recipe pin + sha256 backfill (still at 2.7.2 — two releases behind); watch CI wallclock on the content-validation gate; see "2.7.x dep-track follow-ups" in roadmap.

## Consumers

| Consumer | Status | Vidya pin |
|---|---|---|
| agnoshi | active | follows main |
| hoosh | active | follows main |
| sandhi | active (vidya is *consumer*, sandhi provides HTTP stdlib) | n/a (other direction) |
| sakshi | active (vidya is *consumer*; as of 2.8.1 sakshi arrives via the cyrius stdlib snapshot, not a git pin) | n/a (other direction) |
| cyrius | bidirectional (vidya documents cyrius, cyrius runs vidya) | n/a |
| zugot | `marketplace/vidya.cyml` pinned at **2.7.3** (state.md said 2.7.2 through 2.8.0 — that was itself wrong) — **two releases stale**. Its `[build] make = "cyrius build"` is also broken: bare `cyrius build` does not read `[build] entry`/`output` from `cyrius.cyml` and exits with a usage error; it needs `cyrius build src/main.cyr build/vidya`. sha256 still pending the release artifact. |

## Verification hosts

Vidya runs on any x86_64 Linux host with the pinned cyrius toolchain. CI runs on `ubuntu-latest`. No host-specific bootstrap state — the binary is a single static ELF.

## What does NOT belong here

- Process rules, work-loop discipline, content standards → [`../../CLAUDE.md`](../../CLAUDE.md).
- Per-release narrative → [`../../CHANGELOG.md`](../../CHANGELOG.md).
- Forward roadmap → [`roadmap.md`](roadmap.md).
- Doc currency ledger → [`../doc-health.md`](../doc-health.md).
