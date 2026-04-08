# Vidya Benchmarks

> **Last run**: 2026-04-08 | **Version**: 1.6.0 (Cyrius port) | **Platform**: x86_64 Linux
>
> Cyrius binary: 85KB static ELF | Rust binary: ~4MB (debug) / ~800KB (release)

## Cyrius vs Rust

Comparable benchmarks between the Cyrius port and the original Rust implementation (criterion).

| Benchmark | Cyrius (ns) | Rust (ns) | Ratio | Tier |
|-----------|------------|-----------|-------|------|
| **reg_get_hit** | 493 | 16.60 | 29.7x | Micro |
| **reg_get_miss** | 523 | 15.69 | 33.3x | Micro |
| **search_text** | 4,000 | 30,496 | **0.13x** | Meso |
| **load_concept** | 28,000 | 123,324 | **0.23x** | Meso |
| **load_all** | 2,353,000 | 3,830,121 | **0.61x** | Macro |
| **toml_sections** | 1,000 | — | — | Micro |

**Key findings**:

- **Registry lookup** (hashmap get): Rust is ~30x faster. Rust uses a highly optimized `HashMap` with SipHash; Cyrius uses FNV-1a with open addressing. Expected — Rust's stdlib hashmap is world-class.
- **Search**: Cyrius is **7.6x faster**. Cyrius does a simple `cstr_contains` scan over C strings; Rust does case-insensitive multi-token scoring with allocation. Simpler algorithm wins on a 35-topic corpus.
- **Load concept**: Cyrius is **4.4x faster**. Cyrius TOML parser is ~250 lines of hand-written C-string manipulation; Rust uses the full `toml` crate with serde deserialization.
- **Load all**: Cyrius is **1.6x faster**. Both scan the content directory and parse TOML. Cyrius's simpler allocator (bump) and smaller TOML parser give it an edge at this scale.

## Benchmark Tiers

Following the AGNOS benchmark classification:

### Micro (<1μs) — data structure operations

| Benchmark | Mean | Min | Max | Iters |
|-----------|------|-----|-----|-------|
| reg_get_hit | 493ns | 461ns | 6μs | 10,000 |
| reg_get_miss | 523ns | 501ns | 24μs | 10,000 |
| toml_sections | 1μs | 1μs | 6μs | 1,000 |

### Meso (1μs–1ms) — algorithmic operations

| Benchmark | Mean | Min | Max | Iters |
|-----------|------|-----|-----|-------|
| search_text | 4μs | 4μs | 20μs | 1,000 |
| load_concept | 28μs | 24μs | 134μs | 100 |

### Macro (>1ms) — full system operations

| Benchmark | Mean | Min | Max | Iters |
|-----------|------|-----|-----|-------|
| load_all (35 topics) | 2.35ms | 2.20ms | 2.58ms | 10 |

## Benchmark History

Results tracked in `bench-history.csv` (Cyrius) and `bench-history-rust.csv` (Rust baseline).

### Running benchmarks

```sh
# Cyrius
cyrb bench tests/vidya.bcyr

# Or manually
cat tests/vidya.bcyr | cc2 > /tmp/vidya_bench && chmod +x /tmp/vidya_bench && /tmp/vidya_bench
```

## Notes

- Rust benchmarks were collected with criterion (statistical, N=100+ iterations with warmup)
- Cyrius benchmarks use `lib/bench.cyr` (nanosecond precision via `clock_gettime(CLOCK_MONOTONIC_RAW)`)
- The Cyrius port is ~600 lines; the Rust crate was 2,396 lines
- Binary size: Cyrius 85KB vs Rust ~800KB (release)
- Rust benchmarks from the pre-port v1.5.0 crate (bench-history-rust.csv)
