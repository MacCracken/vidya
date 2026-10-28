// Vidya — Performance in Rust
//
// Rust gives you control over allocation, layout, and dispatch — but
// you must measure to know what matters. Profile first, optimize the
// hot path, and prove the win with benchmarks.

use std::fmt::Write;
use std::hint::black_box;

fn main() {
    // ── Pre-allocation vs growing ──────────────────────────────────
    // Vec::with_capacity avoids reallocations when size is known

    // Count reallocations instead of timing them: this file is built without
    // -O, and debug-build timings measure the debug build, not the pattern.
    let n = 10_000;

    let mut growing = Vec::new();
    let (mut reallocs, mut cap) = (0, growing.capacity());
    for i in 0..n {
        growing.push(i);
        if growing.capacity() != cap {
            reallocs += 1;
            cap = growing.capacity();
        }
    }

    let mut preallocated = Vec::with_capacity(n);
    let cap0 = preallocated.capacity();
    for i in 0..n {
        preallocated.push(i);
    }

    assert_eq!(growing.len(), preallocated.len());
    assert_eq!(preallocated.capacity(), cap0); // never reallocated
    assert!(reallocs >= 10, "geometric growth: ~log2(n) reallocations, got {reallocs}");

    // ── Stack vs Heap allocation ───────────────────────────────────
    // Stack allocation is essentially free (just move the stack pointer)

    let stack_data = [0u8; 4096]; // 4KB on stack — reserving it is one stack-pointer
                                  // adjustment (zero-filling it is still a 4KB memset)
    let heap_data = vec![0u8; 4096]; // 4KB on heap — allocator call
    assert_eq!(stack_data.len(), heap_data.len());

    // ── Reusing buffers in loops ───────────────────────────────────
    // Avoid allocating inside hot loops

    let items = ["alpha", "beta", "gamma", "delta", "epsilon"];

    // GOOD: reuse a String buffer when each formatted value is consumed
    // before the next is built (written out, hashed, compared)
    let mut buf = String::with_capacity(64);
    let mut bracketed = 0;
    for item in &items {
        buf.clear(); // reuse allocation
        write!(buf, "[{item}]").unwrap();
        bracketed += buf.len(); // consume it here
    }
    assert_eq!(bracketed, "[alpha][beta][gamma][delta][epsilon]".len());

    // NOT a win: `buf.clone()` into a Vec<String> allocates once per item,
    // exactly like `results.push(format!("[{item}]"))` — an owned String
    // per element needs its own heap buffer either way.

    // ── Cache-friendly data layout ─────────────────────────────────
    // Sequential access (Vec) is dramatically faster than pointer-chasing

    let sequential: Vec<u64> = (0..10_000).collect();
    let sum: u64 = sequential.iter().sum();
    assert_eq!(sum, 49_995_000);

    // struct-of-arrays is more cache friendly than array-of-structs
    // when you only access a subset of fields

    // Array of structs (AoS)
    struct ParticleAoS {
        x: f32,
        y: f32,
        z: f32,
        _mass: f32, // not used in position sum
    }

    // Struct of arrays (SoA) — better cache use when only reading positions
    struct ParticlesSoA {
        x: Vec<f32>,
        y: Vec<f32>,
        z: Vec<f32>,
        _mass: Vec<f32>,
    }

    let n = 1000;

    // AoS: iterating touches mass even though we don't need it
    let aos: Vec<ParticleAoS> = (0..n)
        .map(|i| ParticleAoS {
            x: i as f32,
            y: i as f32 * 2.0,
            z: i as f32 * 3.0,
            _mass: 1.0,
        })
        .collect();

    let sum_aos: f32 = aos.iter().map(|p| p.x + p.y + p.z).sum();

    // SoA: only read the arrays we need — no wasted cache lines
    let soa = ParticlesSoA {
        x: (0..n).map(|i| i as f32).collect(),
        y: (0..n).map(|i| i as f32 * 2.0).collect(),
        z: (0..n).map(|i| i as f32 * 3.0).collect(),
        _mass: vec![1.0; n],
    };

    let sum_soa: f32 = soa
        .x
        .iter()
        .zip(soa.y.iter())
        .zip(soa.z.iter())
        .map(|((x, y), z)| x + y + z)
        .sum();

    assert!((sum_aos - sum_soa).abs() < 1.0);

    // ── black_box: prevent dead code elimination ───────────────────
    // In benchmarks, the compiler can optimize away pure computations
    // Use black_box() to prevent this

    let x = black_box(42);
    let result = black_box(x * x);
    assert_eq!(result, 1764);

    // ── Collect vs fold: allocation tradeoffs ──────────────────────
    // collect() allocates a new collection; fold() accumulates in-place

    let data: Vec<i32> = (0..1000).collect();

    // Allocates a Vec, then sums — two passes, one allocation
    let sum_collect: i32 = data.iter().copied().collect::<Vec<_>>().iter().sum();

    // Single pass, no allocation
    let sum_fold: i32 = data.iter().sum();

    assert_eq!(sum_collect, sum_fold);

    // ── Small-collection linear search vs HashMap ──────────────────
    // For small N (<50), Vec linear search beats HashMap

    let small_vec: Vec<(u32, &str)> = vec![
        (1, "one"),
        (2, "two"),
        (3, "three"),
        (4, "four"),
        (5, "five"),
    ];

    // Linear search — fast for small N due to cache locality
    let found = small_vec.iter().find(|(k, _)| *k == 3).map(|(_, v)| *v);
    assert_eq!(found, Some("three"));

    // HashMap has overhead from hashing + indirection
    let map: std::collections::HashMap<u32, &str> = small_vec.into_iter().collect();
    assert_eq!(map.get(&3), Some(&"three"));

    // ── Avoid unnecessary cloning ──────────────────────────────────
    let strings: Vec<String> = vec!["hello".into(), "world".into()];

    // GOOD: iterate by reference, no allocation
    let total_len: usize = strings.iter().map(|s| s.len()).sum();
    assert_eq!(total_len, 10);

    // BAD would be: strings.iter().cloned().map(...) — clones each String

    println!("All performance examples passed.");
}
