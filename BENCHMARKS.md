# Vidya Benchmarks

> **Last run**: 2026-08-20 | **Version**: 2.8.1 | **Platform**: x86_64 Linux | **Cyrius**: 6.5.29
>
> Vidya binary: 2,562,008 B static ELF (77 topics × 11 languages = 847 examples in the corpus)

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

`cyrius bench tests/vidya.bcyr`, 4 runs at cyrius 6.5.29 against the 77-topic
corpus. **Mean** is the median of the 4 per-run averages; Min/Max are the
extremes across all 4 runs. The harness subtracts a measured timer floor
(~1.2 µs per clock read) from every sample.

| Benchmark | Mean | Min | Max | Iters | Tier |
|-----------|------|-----|-----|-------|------|
| **reg_get_hit** | 136 ns | 128 ns | 247 ns | 10,000 | Micro |
| **reg_get_miss** | 398 ns | 377 ns | 649 ns | 10,000 | Micro |
| **toml_sections** | 1.93 μs | 1.84 μs | 2.61 μs | 1,000 | Meso |
| **search_text** | 9.52 μs | 8.83 μs | 19.77 μs | 1,000 | Meso |
| **load_concept** | 42.4 μs | 24.2 μs | 85.6 μs | 100 | Meso |
| **load_all** (77 topics) | 5.63 ms | 5.53 ms | 6.06 ms | 10 | Macro |

`search_text` scans every id/title/description in the corpus, so it moved from
the Micro tier to Meso once it had a corpus to scan. `toml_sections` likewise.

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
- **Search**: Cyrius's simple `cstr_contains` scan beats Rust's case-insensitive multi-token scoring with allocation — simpler algorithm wins on small corpora.
- **Load concept**: Cyrius's ~250-line hand-written TOML parser beats Rust's full `toml` crate + serde by ~4×.
- **Load all**: Cyrius's bump allocator + smaller parser wins at scale by ~1.6×.

## Notes

- Cyrius benchmarks use `lib/bench.cyr` (nanosecond precision via `clock_gettime(CLOCK_MONOTONIC_RAW)`).
- Rust v1.5.0 numbers were collected with criterion (statistical, N=100+ iterations with warmup).
- Cyrius CLI source: ~1,900 lines of `src/main.cyr` (v2.8.1).
- Binary size (85 KB at v2.0 → ~1.1 MB at v2.7.1 → 14.66 MB at v2.8.0 → **2.56 MB at v2.8.1**) is driven by content parsing, the bundled vyakarana tokenizer, and the sandhi HTTP stdlib. The v2.8.0 spike was ~13 MB of sigil parallel-crypto static data linked through sandhi's TLS transitive; cyrius 6.5.x no longer places it that way. Current size is tracked in [`docs/development/state.md`](docs/development/state.md).
- Raw history in `target/bench-history/` (per-snapshot via `scripts/bench-history.sh`). Rust baseline frozen in `bench-history-rust.csv`.

## Running benchmarks

```bash
cyrius bench tests/vidya.bcyr             # auto-build + run (explicit path:
                                          # no-arg discovery broke in 6.4.x,
                                          # fixed in 6.5.x — the path works
                                          # on both sides)
./scripts/bench-history.sh                # snapshot to target/bench-history/<ts>-<sha>.txt
```
