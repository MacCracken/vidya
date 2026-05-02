// Vidya — Projectile Physics in Rust
//
// Semi-implicit Euler integration in 16.16 fixed-point on i64.
// Rust's `>>` on signed integers is arithmetic (sign-extending), so
// the bounce-restitution multiply `(vy * RESTITUTION) >> FX_SHIFT`
// behaves the same as the explicit `asr()` helper Cyrius needs.
// i64 comfortably holds the worst-case intermediate
// (~12*65536 * 45875 ≈ 3.6e10), no `__int128` required.

#![allow(dead_code, unused_assignments)]

const FX_SHIFT: u32 = 16;
const GRAVITY: i64 = 6554; // 0.1 per frame
const FLOOR_Y: i64 = 14745600; // 225.0
const RESTITUTION: i64 = 45875; // 0.7 in 16.16

#[derive(Clone, Copy, Debug)]
struct Ball {
    x: i64,
    y: i64,
    vx: i64,
    vy: i64,
}

fn physics_step(b: &mut Ball) {
    // Semi-implicit Euler: update velocity FIRST, then position.
    b.vy += GRAVITY;
    b.y += b.vy;
    b.x += b.vx;
}

fn bounce_check(b: &mut Ball) {
    if b.y > FLOOR_Y {
        b.y = FLOOR_Y;
        // vy = -(vy * restitution) >> 16
        b.vy = -((b.vy * RESTITUTION) >> FX_SHIFT);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

fn test_gravity() {
    let mut b = Ball { x: 0, y: 0, vx: 0, vy: 0 };
    physics_step(&mut b);
    assert_eq!(b.vy, GRAVITY, "vy == gravity after 1 step");
    assert_eq!(b.y, GRAVITY, "y == gravity after 1 step (semi-implicit)");
}

fn test_parabolic_arc() {
    let mut b = Ball { x: 0, y: 6553600, vx: 0, vy: -1310720 }; // y=100.0, vy=-20.0
    let initial_y = b.y;

    for _ in 0..50 {
        physics_step(&mut b);
    }
    assert!(b.y < initial_y, "ball rises in first 50 frames");

    for _ in 0..400 {
        physics_step(&mut b);
    }
    assert!(b.y > initial_y, "ball falls below start after 450 frames");
}

fn test_bounce() {
    let mut b = Ball { x: 0, y: FLOOR_Y, vx: 0, vy: 655360 }; // vy=10.0 down
    b.y = FLOOR_Y + 1;
    bounce_check(&mut b);

    assert!(b.vy < 0, "vy is negative after bounce");
    assert!(-b.vy < 655360, "bounce reduces velocity magnitude");
    assert_eq!(b.y, FLOOR_Y, "position reset to floor on bounce");
}

fn test_horizontal_unchanged() {
    let vx_initial: i64 = 131072; // 2.0
    let mut b = Ball { x: 0, y: 0, vx: vx_initial, vy: 0 };

    physics_step(&mut b);
    physics_step(&mut b);
    physics_step(&mut b);

    assert_eq!(b.vx, vx_initial, "vx unchanged after 3 frames of gravity");
    assert_eq!(b.x, 3 * vx_initial, "x = 3 * vx after 3 frames");
}

fn test_energy_decay() {
    let mut b = Ball { x: 0, y: 0, vx: 0, vy: 655360 }; // vy=10.0 down

    // 1000 frames; |vy| plateaus around 2700 — well under 2 * GRAVITY = 13108.
    for _ in 0..1000 {
        physics_step(&mut b);
        bounce_check(&mut b);
    }

    let abs_vy = if b.vy < 0 { -b.vy } else { b.vy };
    assert!(abs_vy < GRAVITY * 2, "vy near zero after 1000 bouncing frames");
}

fn test_semi_implicit_stability() {
    let start_y = FLOOR_Y - 655360; // 10.0 above floor
    let mut b = Ball { x: 0, y: start_y, vx: 0, vy: -655360 }; // vy=-10.0 upward

    let mut min_y = start_y;
    for _ in 0..500 {
        physics_step(&mut b);
        bounce_check(&mut b);
        if b.y < min_y {
            min_y = b.y;
        }
    }

    let max_rise: i64 = 1000 * 65536; // 1000 units
    assert!(
        min_y > start_y - max_rise,
        "semi-implicit euler does not explode"
    );
}

fn main() {
    test_gravity();
    test_parabolic_arc();
    test_bounce();
    test_horizontal_unchanged();
    test_energy_decay();
    test_semi_implicit_stability();
    println!("All projectile_physics examples passed.");
}
