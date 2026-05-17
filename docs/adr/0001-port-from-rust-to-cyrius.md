# 0001 — Port from Rust to Cyrius

**Status**: Accepted
**Date**: 2026-04-08

## Context

Vidya started as a Rust crate at v1.x — 2,396 lines of Rust across 11 modules, serving 36 programming topics with 193 examples across 10 languages. Fifteen topics had full coverage; twenty-one had only Rust implementations scaffolded during Cyrius compiler development but never fleshed out. The crate worked. It was clean. But it was two-thirds empty, and it had a more fundamental contradiction: **vidya's job is to document AGNOS / Cyrius programming patterns, but vidya itself was written in Rust.** Every consumer of vidya (agnoshi, hoosh, Cyrius developers) was reading a Cyrius reference written in a foreign language.

Two constraints made this a real choice rather than reflex:

1. **Self-documentation.** A reference library has more authority when it dogfoods. Cyrius needed to prove it could carry a non-trivial application end-to-end before becoming the canonical implementation language for AGNOS first-party tooling. Vidya was the right size — large enough to be load-bearing, small enough to port in a single sustained sweep.
2. **Stdlib forcing function.** Porting vidya from Rust to Cyrius would surface real gaps in the Cyrius stdlib (TOML parser, hashmap, allocator, fmt, etc.) at exactly the moment they could be filled. Every bug found in vidya's port would land as a fix in Cyrius itself.

The cost: throwing away 2,396 lines of working Rust, the criterion benchmark harness, the `cargo doc` browsable reference, the `serde` deserializer path. Real value, deliberately retired.

## Decision

**Port vidya from Rust to Cyrius at v2.0.** Move the Rust source to `rust-old/` as a frozen historical artifact (per the first-party-standards `rust-old/` convention for ported crates). Re-implement the CLI in Cyrius (`src/main.cyr`) using the Cyrius toolchain. Re-vendor the stdlib. Re-write the loader, registry, search, and validation paths in Cyrius. Preserve the `content/` corpus exactly — that layer is language-agnostic by design.

**Scope in**:
- All CLI commands (`list`, `search`, `info`, `compare`, `gaps`, `stats`, `languages`, `validate`).
- TOML parser (hand-rolled in Cyrius, ~250 lines vs Rust's `toml` + `serde` chain).
- Hashmap-backed registry (FNV-1a + open addressing).
- Per-language validation harness invoking external toolchains.
- The `cyrius` content track is added as the 11th language during the port (vidya now documents the language it's written in).

**Scope out**:
- `cargo doc` generation (lose the auto-generated API browser — vidya's API is CLI-shaped, not library-shaped, after the port).
- `criterion`-style statistical benchmarking (replaced by `lib/bench.cyr` — simpler, fewer iterations, nanosecond-precise via `clock_gettime`).
- The Rust crate's feature-flag system (`std`, `logging`, `mcp`, `openqasm`, `full`) — replaced by a single static binary with all behavior built in.

## Consequences

### Positive

- **Self-documentation closed.** Vidya is now a working example of the patterns it documents. The Cyrius content track lands at v2.0 with vidya's own source as one of its reference implementations.
- **Binary size collapse.** 800 KB Rust release → 85 KB Cyrius (v2.0 snapshot; v2.7.1 has grown to ~1.1 MB driven by content + vyakarana + sandhi, but per-feature density is still ~10× better than the Rust equivalent would be).
- **Stdlib forcing function paid off.** Real bugs surfaced and got fixed in Cyrius: null-termination semantics in TOML strings, `fmt_int` register clobber under large stack frames, sakshi BSS overflow. Every port bug shipped as a Cyrius compiler / stdlib fix.
- **Content surge unblocked.** The Cyrius CLI's `vidya gaps` command (added during the port) turned "we need more content" into a concrete list of N missing files per language. Coverage went from 193 → 396 examples in the same v2.0 cycle ([retired narrative](#retired-narrative-the-v20-content-surge) below).
- **Algorithm asymmetry held.** Cyrius wins where simpler algorithms beat library-grade machinery on small data: 7.6× faster on text search (simple `cstr_contains` vs Rust's multi-token scoring), 4.4× faster on TOML parse (hand-rolled vs `serde`), 1.6× faster on full-corpus load (bump allocator + smaller parser). Rust still wins on world-class data structures: 30× faster on hashmap lookup (SipHash vs FNV-1a). Both are *correct* outcomes for what each language optimizes for.

### Negative

- **No `cargo doc` browsable reference.** Discovery of the public surface relies on reading `src/main.cyr` directly. Acceptable because the public surface is the CLI (`vidya --help`), not the library.
- **Hashmap lookup is ~30× slower.** FNV-1a + open addressing vs Rust's SipHash + ahash. Acceptable at the 74-topic / 814-example scale; would need revisiting if the corpus crossed ~10K topics.
- **No `criterion`.** Lose statistical significance + outlier rejection. Acceptable because vidya's benchmarks gate per-release perf, not per-PR regression detection.
- **`rust-old/` is dead weight in the repo tree.** Preserved per first-party-standards convention but gitignored from CI; readers may briefly mistake it for current code. Mitigated by the `(no longer a Rust crate; migrated at v2.0)` note in CLAUDE.md.

### Neutral

- The 11-language corpus convention (rust, python, c, go, typescript, shell, zig, x86_64 asm, aarch64 asm, openqasm, **cyrius**) — Cyrius added as the 11th track during the port.
- Content-expansion-as-side-effect: porting forced building `vidya gaps`, which made the 203-implementation content surge concrete and trackable.

## Alternatives considered

- **Keep the Rust crate, add a `cyrius` content track.** Rejected. Would have left the "vidya documents Cyrius but isn't Cyrius" contradiction in place permanently. Self-documentation is the load-bearing argument.
- **Dual-stack: maintain both Rust and Cyrius implementations.** Rejected as scope creep. Two CLIs to maintain, two test paths, two release artifacts, no clear deprecation horizon for the Rust side.
- **Rewrite in C instead of Cyrius.** Rejected. C is supported as a content language, but vidya is a first-party AGNOS project — the language-of-choice for first-party tooling is Cyrius per first-party-standards. C would have been a third option that satisfied neither the self-documentation argument nor the AGNOS convention.
- **Generate the CLI from Cyrius bindings while keeping the library in Rust.** Rejected. Doubles the build complexity, halves the self-documentation value, and the binding generator doesn't exist.

## Retired narrative — the v2.0 content surge

(Originally lived at `docs/content-expansion-2026-04-08.md`; retired into this ADR at the 2026-05-16 doc sweep.)

With the Cyrius port working and `vidya gaps` reporting 141 missing implementations across 21 topics, the content sweep happened in seven rounds:

1. **High-priority topics** (compiler + systems) — 9 topics × {Python, C, Go, Cyrius}. Cyrius files are pattern-focused: they document the actual Cyrius bootstrap chain (29 KB seed → 12 KB stage1f → 164 KB cc2) rather than reimplementing a compiler.
2. **Medium-priority topics** (OS + language design) — 11 topics × {Python, C, Cyrius}. OS topics needed C for struct layouts; language-design topics needed each language to show how IT handles the concept.
3. **Quantum computing** — `quantum_computing/cyrius.cyr` only. Fixed-point integer arithmetic to simulate qubits, Hadamard, Bell states, Grover's, decoherence decay.
4. **Language sweep** — Go, Zig, TypeScript, Shell. 16–21 files each. Every file tested via the language's native runner.
5. **Assembly** — x86_64 (assembled with `as --64`, linked with `ld`, runs as a Linux executable) and AArch64 (cross-compiled, runs under `qemu-aarch64`).
6. **OpenQASM** — quantum analogies for classical concepts. All valid OpenQASM 2.0, all parse cleanly.
7. **Closing the last four** — tracing got Rust, Python, C, AArch64 ASM. Zero gaps.

Final v2.0 cut:

| Metric | Before (v1.x Rust) | After (v2.0 Cyrius) |
|---|---|---|
| Topics complete (11/11 langs) | 15 | 36 |
| Total examples | 193 | 396 |
| Languages | 10 | 11 (+Cyrius) |
| Coverage gaps | 203 | 0 |
| Implementation | 2,396 lines Rust | 600 lines Cyrius |
| Binary | ~800 KB | 85 KB |

What made it work: parallel subagents writing language batches in parallel with the main thread verifying as they landed, pattern-focused Cyrius files (don't reimplement compilers, document patterns), the `vidya gaps` command turning "we need content" into a concrete punch list, and testing every file with its native runner — no exceptions.

The post-v2.0 corpus continued to expand through P1 (networking), P2 (distributed), P3 (audio + AI/ML), reaching 74 topics × 11 languages = 814 examples by v2.7.x. The infrastructure built during the v2.0 port carried all of it.
