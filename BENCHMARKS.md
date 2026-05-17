# Vidya Benchmarks

> **Last run**: 2026-05-16 | **Version**: 2.7.1 | **Platform**: x86_64 Linux | **Cyrius**: 5.11.55
>
> Vidya binary: ~1.1 MB static ELF (74 topics × 11 languages = 814 examples in the corpus)

## Current results

`cyrius bench tests/vidya.bcyr` against the v2.7.1 binary and the 74-topic corpus:

| Benchmark | Mean | Min | Max | Iters | Tier |
|-----------|------|-----|-----|-------|------|
| **reg_get_hit** | 390 ns | 370 ns | 5 μs | 10,000 | Micro |
| **reg_get_miss** | 401 ns | 390 ns | 3 μs | 10,000 | Micro |
| **toml_sections** | 1 μs | 1 μs | 6 μs | 1,000 | Micro |
| **search_text** | 499 ns | 421 ns | 5 μs | 1,000 | Micro |
| **load_concept** | 29 μs | 27 μs | 40 μs | 100 | Meso |
| **load_all** (74 topics) | 4.18 ms | 4.09 ms | 4.37 ms | 10 | Macro |

## Benchmark tiers

Following the AGNOS benchmark classification:

- **Micro** (<1 μs): data structure operations — registry lookup, TOML section scan, search
- **Meso** (1 μs–1 ms): algorithmic operations — single-concept TOML parse
- **Macro** (>1 ms): full system operations — load every concept in `content/`

## Cyrius vs Rust (frozen v2.0 port comparison)

The original Rust crate (v1.5.0, 2,396 lines, ~800 KB release binary) was ported to Cyrius at v2.0. Numbers below are the v2.0 cut comparison — frozen for historical reference; the current corpus is ~2× the size, so absolute numbers above don't compare directly.

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
- Cyrius CLI source: ~1,900 lines of `src/main.cyr` (v2.7.1).
- Binary growth (85 KB at v2.0 → ~1.1 MB at v2.7.1) is content-driven: corpus parsing, serde of 814 examples, vyakarana tokenizer bundled, sandhi HTTP service stdlib.
- Raw history in `target/bench-history/` (per-snapshot via `scripts/bench-history.sh`). Rust baseline frozen in `bench-history-rust.csv`.

## Running benchmarks

```bash
cyrius bench tests/vidya.bcyr             # auto-build + run
./scripts/bench-history.sh                # snapshot to target/bench-history/<ts>-<sha>.txt
```
