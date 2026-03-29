// Vidya — Iterators in Rust
//
// Rust iterators are lazy, zero-cost abstractions. The compiler fuses
// chains of map/filter/fold into tight loops — no intermediate allocations.
// The Iterator trait is the foundation of idiomatic Rust data processing.

fn main() {
    // ── Basic iterator chain ───────────────────────────────────────
    let numbers = vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    let even_squares: Vec<i32> = numbers
        .iter()
        .filter(|&&x| x % 2 == 0)
        .map(|&x| x * x)
        .collect();

    assert_eq!(even_squares, vec![4, 16, 36, 64, 100]);

    // ── Laziness: nothing happens without consumption ──────────────
    // This builds a pipeline but does NOT execute it:
    let _lazy = numbers.iter().map(|x| x * 2); // no side effects
    // You must consume: collect(), sum(), for_each(), count(), etc.

    // ── fold: the universal accumulator ────────────────────────────
    let sum = numbers.iter().fold(0, |acc, &x| acc + x);
    assert_eq!(sum, 55);

    // fold can build any type, not just numbers
    let csv = numbers
        .iter()
        .fold(String::new(), |mut acc, x| {
            if !acc.is_empty() {
                acc.push(',');
            }
            acc.push_str(&x.to_string());
            acc
        });
    assert_eq!(csv, "1,2,3,4,5,6,7,8,9,10");

    // ── Chaining: flat_map, take, skip, zip ────────────────────────
    let nested = vec![vec![1, 2], vec![3, 4], vec![5]];
    let flat: Vec<&i32> = nested.iter().flat_map(|v| v.iter()).collect();
    assert_eq!(flat, vec![&1, &2, &3, &4, &5]);

    let first_three: Vec<&i32> = numbers.iter().take(3).collect();
    assert_eq!(first_three, vec![&1, &2, &3]);

    let pairs: Vec<_> = (0..3).zip(['a', 'b', 'c']).collect();
    assert_eq!(pairs, vec![(0, 'a'), (1, 'b'), (2, 'c')]);

    // ── enumerate: index + value ───────────────────────────────────
    let words = ["hello", "world"];
    for (i, word) in words.iter().enumerate() {
        assert!(i < 2);
        assert!(!word.is_empty());
    }

    // ── windows and chunks ─────────────────────────────────────────
    let data = [1, 2, 3, 4, 5];
    let window_sums: Vec<i32> = data.windows(3).map(|w| w.iter().sum()).collect();
    assert_eq!(window_sums, vec![6, 9, 12]); // [1+2+3, 2+3+4, 3+4+5]

    // ── Iterator adaptors return iterators (lazy) ──────────────────
    // peekable: look ahead without consuming
    let mut iter = [1, 2, 3].iter().peekable();
    assert_eq!(iter.peek(), Some(&&1));
    assert_eq!(iter.next(), Some(&1)); // peek didn't consume

    // chain: concatenate two iterators
    let combined: Vec<i32> = (1..=3).chain(7..=9).collect();
    assert_eq!(combined, vec![1, 2, 3, 7, 8, 9]);

    // ── Custom iterator ────────────────────────────────────────────
    struct Countdown(u32);

    impl Iterator for Countdown {
        type Item = u32;
        fn next(&mut self) -> Option<u32> {
            if self.0 == 0 {
                None
            } else {
                self.0 -= 1;
                Some(self.0 + 1)
            }
        }
    }

    let launch: Vec<u32> = Countdown(3).collect();
    assert_eq!(launch, vec![3, 2, 1]);

    // ── extend: efficient collection building ──────────────────────
    let mut result = Vec::with_capacity(20);
    result.extend(0..10);
    result.extend(10..20);
    assert_eq!(result.len(), 20);

    // ── Consumers: different ways to finish ─────────────────────────
    assert_eq!(numbers.iter().sum::<i32>(), 55);
    assert_eq!(numbers.iter().count(), 10);
    assert_eq!(numbers.iter().min(), Some(&1));
    assert_eq!(numbers.iter().max(), Some(&10));
    assert!(numbers.iter().any(|&x| x > 5));
    assert!(!numbers.iter().all(|&x| x > 5));
    assert_eq!(numbers.iter().find(|&&x| x > 7), Some(&8));
    assert_eq!(numbers.iter().position(|&x| x == 5), Some(4));

    println!("All iterator examples passed.");
}
