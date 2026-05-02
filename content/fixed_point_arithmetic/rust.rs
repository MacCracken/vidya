// Vidya — Fixed-Point Arithmetic in Rust
//
// 16.16 fixed-point: i64 carries fractional value in lower 16 bits.
// Rust's integer overflow is checked in debug, wraps in release —
// use `wrapping_*` / `checked_*` to make intent explicit. `>>` on
// signed integers is arithmetic (sign-extending), so we don't need
// the asr() helper Cyrius needs.

const FX_SHIFT: u32 = 16;
const FX_ONE: i64 = 1 << FX_SHIFT;
const FX_HALF: i64 = 1 << (FX_SHIFT - 1);

fn fx_from_int(n: i64) -> i64 {
    n << FX_SHIFT
}

fn fx_to_int(v: i64) -> i64 {
    // Truncate toward zero. Rust's >> on signed is arithmetic (sign-fills),
    // which rounds negative values toward -infinity, not zero.
    if v < 0 {
        -((-v) >> FX_SHIFT)
    } else {
        v >> FX_SHIFT
    }
}

fn fx_to_int_round(v: i64) -> i64 {
    if v < 0 {
        -((-v + FX_HALF) >> FX_SHIFT)
    } else {
        (v + FX_HALF) >> FX_SHIFT
    }
}

fn fx_mul(a: i64, b: i64) -> i64 {
    // Standard multiply: (a * b) >> 16. Wraps silently in release on
    // overflow — use fx_mul_safe for large magnitudes.
    a.wrapping_mul(b) >> FX_SHIFT
}

fn fx_mul_safe(a: i64, b: i64) -> i64 {
    // Pre-shift both inputs to avoid overflow. Trades 8 bits of precision.
    (a >> 8) * (b >> 8)
}

fn fx_div(a: i64, b: i64) -> i64 {
    if b == 0 {
        return 0;
    }
    (a << FX_SHIFT) / b
}

// ── Sine table — quarter-wave, 256 entries ────────────────────────────
// Table generated at runtime via f64; values frozen into i64 16.16.
// Mirror across quadrants for full circle (1024 = 2π).

fn build_sin_table() -> [i64; 256] {
    let mut t = [0i64; 256];
    for i in 0..256 {
        // i = 0 → 0 rad ; i = 256 → π/2
        let angle = (i as f64) * (std::f64::consts::PI / 2.0) / 256.0;
        t[i] = (angle.sin() * (FX_ONE as f64)) as i64;
    }
    t
}

fn sin_lookup(table: &[i64; 256], angle: i64) -> i64 {
    let a = (angle & 1023) as usize;
    if a < 256 {
        table[a]
    } else if a < 512 {
        table[511 - a]
    } else if a < 768 {
        -table[a - 512]
    } else {
        -table[1023 - a]
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

fn main() {
    assert_eq!(fx_from_int(1), 65536, "1.0 == 65536");
    assert_eq!(fx_from_int(10), 655360, "10.0 == 655360");
    assert_eq!(fx_from_int(0), 0, "0.0 == 0");

    // 3.0 * 2.5 = 7.5
    let three = fx_from_int(3);
    let two_half = 163840; // 2.5 in 16.16
    assert_eq!(fx_mul(three, two_half), 491520, "3.0 * 2.5 == 7.5");
    assert_eq!(fx_mul(FX_ONE, FX_ONE), FX_ONE, "1.0 * 1.0 == 1.0");
    assert_eq!(fx_mul(FX_HALF, FX_HALF), 16384, "0.5 * 0.5 == 0.25");

    // 1000.0 * 1000.0 — overflow-safe
    let big = fx_from_int(1000);
    assert!(fx_mul_safe(big, big) > 0, "safe mul of 1000*1000 stays positive");

    // 10.0 / 4.0 = 2.5
    assert_eq!(fx_div(fx_from_int(10), fx_from_int(4)), 163840, "10/4 == 2.5");
    assert_eq!(fx_div(FX_ONE, 0), 0, "div-by-zero returns 0");

    // Negative truncation toward zero
    assert_eq!(fx_to_int(-fx_from_int(3)), -3, "fx_to_int(-3.0) == -3");
    assert_eq!(fx_to_int(-(FX_ONE + FX_HALF)), -1, "fx_to_int(-1.5) == -1");
    assert_eq!(fx_to_int_round(-(FX_ONE + FX_HALF)), -2, "round(-1.5) == -2");

    // Sine table
    let table = build_sin_table();
    assert_eq!(sin_lookup(&table, 0), 0, "sin(0) == 0");
    assert!(sin_lookup(&table, 256) > 60000, "sin(π/2) near 1.0");
    assert_eq!(sin_lookup(&table, 512), 0, "sin(π) == 0");
    assert!(sin_lookup(&table, 768) < -60000, "sin(3π/2) near -1.0");

    // Roundtrip
    for i in 0..100 {
        assert_eq!(fx_to_int(fx_from_int(i)), i, "roundtrip");
    }

    println!("All fixed_point_arithmetic examples passed.");
}
