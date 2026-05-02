// Vidya — Game Loop Architecture in Rust
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loop_step` takes an elapsed-microsecond delta and returns the number
// of fixed-step updates fired this frame. Rust's `i64` is the natural
// choice for monotonic-time math: 64 bits of microseconds wraps at
// ~292 years, so wrap-around never bites a real game. Tests use
// deterministic per-frame deltas (no real clock) so behavior is
// reproducible across machines and CI.

#![allow(dead_code, unused_assignments)]

const DT_US: i64 = 16667;        // ~1/60 second
const MAX_ACCUM: i64 = 5 * DT_US; // 83335 — spiral-of-death cap

#[derive(Copy, Clone, Debug, Default)]
struct GameLoop {
    accum: i64,
    update_count: i64,
    render_count: i64,
}

fn loop_step(g: &mut GameLoop, elapsed_us: i64) -> i64 {
    let mut accum = g.accum + elapsed_us;
    // Spiral-of-death cap: never let the accumulator exceed MAX_ACCUM.
    // Without this, a long pause grows accum unboundedly, demanding
    // more updates per frame, making it worse. Accept slowdown.
    if accum > MAX_ACCUM {
        accum = MAX_ACCUM;
    }
    let mut updates: i64 = 0;
    while accum >= DT_US {
        accum -= DT_US;
        updates += 1;
    }
    g.accum = accum;
    g.update_count += updates;
    g.render_count += 1;
    updates
}

fn test_exact_dt_fires_one_update() {
    let mut g = GameLoop::default();
    let u = loop_step(&mut g, DT_US);
    assert_eq!(u, 1, "exactly one update per dt");
    assert_eq!(g.update_count, 1, "update_count = 1");
}

fn test_under_dt_no_update() {
    let mut g = GameLoop::default();
    let u = loop_step(&mut g, DT_US / 2);
    assert_eq!(u, 0, "no update when elapsed < dt");
}

fn test_catchup_50ms() {
    // 50000us / 16667us = 2.999 → 2 fixed-step updates
    let mut g = GameLoop::default();
    let u = loop_step(&mut g, 50_000);
    assert_eq!(u, 2, "50ms produces 2 fixed-step updates");
}

fn test_spiral_of_death_cap() {
    // 1000ms (one full second) hang — capped at MAX_ACCUM (5 * dt).
    let mut g = GameLoop::default();
    let u = loop_step(&mut g, 1_000_000);
    assert_eq!(u, 5, "spiral cap: exactly 5 updates per call");
}

fn test_render_per_frame() {
    let mut g = GameLoop::default();
    loop_step(&mut g, DT_US);
    loop_step(&mut g, DT_US);
    loop_step(&mut g, DT_US);
    assert_eq!(g.render_count, 3, "3 renders for 3 frames");
    assert_eq!(g.update_count, 3, "3 updates total");
}

fn test_accumulator_remainder() {
    // 1.5 * dt → 1 update with ~0.5 * dt left in accumulator
    let mut g = GameLoop::default();
    let one_and_half = DT_US + (DT_US / 2);
    loop_step(&mut g, one_and_half);
    assert!(g.accum > DT_US / 4, "remainder is positive");
    assert!(g.accum < DT_US, "remainder < full dt");
}

fn test_input_update_render_separation() {
    // 30ms + 5ms + 30ms = 65ms total → 3 updates, 3 renders
    let mut g = GameLoop::default();
    loop_step(&mut g, 30_000);  // 30ms → 1 update (8333 left)
    loop_step(&mut g, 5_000);   //  5ms → 0 updates (13333 left)
    loop_step(&mut g, 30_000);  // 30ms (43333 → 2 updates, 9999 left)
    assert_eq!(g.update_count, 3, "3 updates from 65ms total");
    assert_eq!(g.render_count, 3, "3 renders from 3 frames");
}

fn main() {
    test_exact_dt_fires_one_update();
    test_under_dt_no_update();
    test_catchup_50ms();
    test_spiral_of_death_cap();
    test_render_per_frame();
    test_accumulator_remainder();
    test_input_update_render_separation();
    println!("All game_loop_architecture examples passed.");
}
