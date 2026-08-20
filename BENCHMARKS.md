# Vidya Benchmarks

> **Last run**: 2026-08-20 | **Version**: 2.8.2 | **Platform**: x86_64 Linux | **Cyrius**: 6.5.29
>
> Vidya binary: 2,563,160 B static ELF (77 topics × 11 languages = 847 examples in the corpus)

> ⚠ **These numbers are not comparable to anything this file published before 2.8.1.**
> Four of the six benchmarks — `reg_get_hit`, `reg_get_miss`, `search_text`,
> `toml_sections` — had been measuring an **empty** registry since 2026-04-08.
> `tests/vidya.bcyr` passed `str_from("id")` where `toml_get` requires a **cstr**
> key; that returns 0 silently, so the bench registry was never populated. The
> tell was in the published table and went unread for four months: `reg_get_hit`
> (390 ns) benchmarked *slower* than it should relative to `reg_get_miss`
> (401 ns) — for a populated open-addressed map a hit must be substantially
> cheaper than a miss, and today it is (136 ns vs 398 ns). Fixed in 2.8.1;
> `load_concept` and `load_all` were always measuring real input.

## Current results

`cyrius bench tests/vidya.bcyr`, 3 runs at cyrius 6.5.29 against the 77-topic
corpus, on an otherwise-idle box. **Mean** is the median of the 3 per-run
averages; Min/Max are the extremes across all 3 runs. The harness subtracts a
measured timer floor (~1.2 µs per clock read) from every sample.

**12 benchmarks** as of 2.8.2 — the five `json_*` / `field_*` rows are new,
added with the `src/vidya_core.cyr` extraction that first made the HTTP
builders reachable from a `.bcyr`.

| Benchmark | Mean | Min | Max | Iters | Tier |
|-----------|------|-----|-----|-------|------|
| **reg_get_hit** | 134 ns | 128 ns | 221 ns | 10,000 | Micro |
| **reg_get_miss** | 400 ns | 376 ns | 1.14 μs | 10,000 | Micro |
| **field_raw_splice** | 605 ns | 549 ns | 1.22 μs | 10,000 | Micro |
| **toml_sections** | 1.89 μs | 1.80 μs | 2.64 μs | 1,000 | Meso |
| **field_escaped** | 3.52 μs | 3.28 μs | 7.58 μs | 10,000 | Meso |
| **search_text** | 6.54 μs | 6.15 μs | 7.78 μs | 1,000 | Meso |
| **json_info_response** | 9.84 μs | 9.01 μs | 21.4 μs | 1,000 | Meso |
| **search_text_exact** | 12.00 μs | 11.22 μs | 25.7 μs | 1,000 | Meso |
| **load_concept** | 44.2 μs | 24.0 μs | 113 μs | 100 | Meso |
| **json_list_response** | 117 μs | 109 μs | 248 μs | 100 | Meso |
| **json_search_response** | 280 μs | 269 μs | 714 μs | 200 | Meso |
| **load_all** (77 topics) | 5.794 ms | 5.783 ms | 5.813 ms | 10 | Macro |

`search_text` scans every id/title/description in the corpus, so it moved from
the Micro tier to Meso once it had a corpus to scan. `toml_sections` likewise.

### What the JSON escaping fix costs

Closing the `/search?q=` injection hole meant routing every user- and
content-derived string through `sandhi_json_escape` instead of splicing it
raw. The paired micro-benchmarks isolate that on one real 130-byte corpus
description:

| Path | Mean |
|---|---|
| `field_raw_splice` — unescaped splice (former behavior, the vulnerability) | 605 ns |
| `field_escaped` — through `sandhi_json_escape` (current) | **3.52 μs** |
| Delta | **+2.9 μs per escaped field** |

In context that is cheap: a whole `/info` body is 9.84 μs, and
`json_search_response` at 280 μs is dominated by the 77-concept scan, not by
escaping. The cost is real and worth naming, but it buys a response that
cannot be forged.

### Case-insensitive search: the folding change is a net win

Search was byte-exact and skipped tags. Making it ASCII-case-insensitive and
restoring the tag branch was expected to cost time — folding is per-byte work
the old `memeq` scan never did. It got **faster** instead, because the fold
replaced a bigger cost than it added.

The old path (`str_has`) copied each field into a fresh null-terminated buffer
via `to_cstr` and then ran `memeq`. The new path (`str_has_ci`) folds the query
once per search and scans `str_data`/`str_len` in place — no copy at all. One
allocation removed per field beats one fold added per byte:

| Path | Mean | Min | Max |
|---|---|---|---|
| `search_text_exact` — copy + byte-exact scan (former behavior) | 12.04 μs | 11.14 μs | 25.74 μs |
| `search_text` — folded in-place scan (current) | **6.49 μs** | 6.15 μs | 7.95 μs |
| Delta | **−46.1%** | — | — |

Real, not noise: the distributions do not overlap (fastest old sample 11.14 μs,
slowest new sample 7.95 μs, across 4 runs of 1,000 iterations each).

The saving compounds on the HTTP surface. `serve` answered every `/search?q=`
request with up to four `to_cstr` allocations per concept — ~308 across the
77-topic corpus — from a bump allocator that never frees, so search memory grew
with request count. That allocation is now gone entirely.

> ⚠ **`search_text` is not comparable to the 9.52 μs published for 2.8.1.**
> That figure probed the registry's already-null-terminated hashmap keys, so it
> never paid the `to_cstr` copy `search()` made for every field — it timed a
> shape production did not have. `search_text_exact` was added to restore that
> copy, and is the honest before-number. The other five benchmarks touch no code
> that changed here and land flat against 2.8.1 (within noise), which is what
> makes the two search rows comparable on the same box.

### Movement across the 6.4.2 → 6.5.29 bump

Same box, same day, 4 runs at each pin, **with the harness fix applied at both**
— so this is the first pin-to-pin comparison in vidya's history that measures
real work. Only two rows clear the noise floor:

| Benchmark | 6.4.2 | 6.5.29 | Delta | Verdict |
|---|---|---|---|---|
| `reg_get_miss` | 504 ns | 398 ns | **−21.0%** | real — distributions do not overlap |
| `load_all` | 5.933 ms | 5.633 ms | −5.1% | modest |
| `load_concept` | 44.44 μs | 42.39 μs | −4.6% | modest |
| `reg_get_hit` | 138.5 ns | 136.5 ns | −1.4% | noise |
| `search_text` | 9.650 μs | 9.520 μs | −1.3% | noise |
| `toml_sections` | 1.834 μs | **1.927 μs** | **+5.1%** | real regression — distributions do not overlap |

## Benchmark tiers

Following the AGNOS benchmark classification:

- **Micro** (<1 μs): data structure operations — registry lookup, TOML section scan, search
- **Meso** (1 μs–1 ms): algorithmic operations — single-concept TOML parse
- **Macro** (>1 ms): full system operations — load every concept in `content/`

## Cyrius vs Rust (frozen v2.0 port comparison)

The original Rust crate (v1.5.0, 2,396 lines, ~800 KB release binary) was ported to Cyrius at v2.0. Numbers below are the v2.0 cut comparison — frozen for historical reference; the current corpus is ~2× the size, so absolute numbers above don't compare directly.

This table **predates** the empty-input harness bug described at the top, and its Cyrius column is consistent with real (populated) measurement — `reg_get_hit` 493 ns on a 35-topic corpus sits on the same curve as today's 136 ns, not on the empty-map curve's 33 ns. It has not, however, been re-verified since; treat it as indicative history rather than a live baseline.

| Benchmark | Cyrius v2.0 (ns) | Rust v1.5.0 (ns) | Ratio |
|-----------|------------------|------------------|-------|
| reg_get_hit | 493 | 17 | 29x slower |
| reg_get_miss | 523 | 16 | 33x slower |
| search_text | 4,000 | 30,496 | **7.6× faster** |
| load_concept | 28,000 | 123,324 | **4.4× faster** |
| load_all (35 topics) | 2,353,000 | 3,830,121 | **1.6× faster** |

**Key takeaways from the port**:

- **Registry lookup**: Rust's `HashMap` with SipHash beats Cyrius's FNV-1a + open addressing by ~30×. World-class stdlib hashmap, expected.
- **Search**: Cyrius's simple `cstr_contains` scan beats Rust's case-insensitive multi-token scoring with allocation — simpler algorithm wins on small corpora. (Note the v2.0 Cyrius column is *case-sensitive* search; the Rust column it beats was case-insensitive. Cyrius search is case-insensitive again as of the unreleased fix above, and at 6.49 μs on a 2× larger corpus it stays ahead — but this row compares unlike behavior and was never re-run.)
- **Load concept**: Cyrius's ~250-line hand-written TOML parser beats Rust's full `toml` crate + serde by ~4×.
- **Load all**: Cyrius's bump allocator + smaller parser wins at scale by ~1.6×.

## Notes

- Cyrius benchmarks use `lib/bench.cyr` (nanosecond precision via `clock_gettime(CLOCK_MONOTONIC_RAW)`).
- Rust v1.5.0 numbers were collected with criterion (statistical, N=100+ iterations with warmup).
- Cyrius source: `src/main.cyr` 598 lines (CLI plumbing, routes, `main()`) + `src/vidya_core.cyr` 1,537 lines (domain + JSON layer), split at v2.8.2 so the suite and the benchmarks run the same code the binary serves.
- Binary size (85 KB at v2.0 → ~1.1 MB at v2.7.1 → 14.66 MB at v2.8.0 → 2.56 MB at v2.8.1 → **2,563,160 B at v2.8.2**) is driven by content parsing, the bundled vyakarana tokenizer, and the sandhi HTTP stdlib. The v2.8.0 spike was ~13 MB of sigil parallel-crypto static data linked through sandhi's TLS transitive; cyrius 6.5.x no longer places it that way. Current size is tracked in [`docs/development/state.md`](docs/development/state.md).
- Raw history in `target/bench-history/` (per-snapshot via `scripts/bench-history.sh`). Rust baseline frozen in `bench-history-rust.csv`.

## Running benchmarks

```bash
cyrius bench tests/vidya.bcyr             # auto-build + run (explicit path:
                                          # no-arg discovery broke in 6.4.x,
                                          # fixed in 6.5.x — the path works
                                          # on both sides)
./scripts/bench-history.sh                # snapshot to target/bench-history/<ts>-<sha>.txt
```
