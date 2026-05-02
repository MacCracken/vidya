// Vidya — 2D Collision Detection in Rust
//
// All coordinates in 16.16 fixed-point on i64. Squared-distance
// comparisons avoid sqrt — see best practice "use squared distances".
// Pre-shift the deltas before squaring (asr by 4) so a 16.16 ×
// 16.16 product can't overflow i64 even for large coordinates;
// for fully precise products, widen to i128 explicitly. Rust's
// `>>` on signed ints is arithmetic, so we don't need an `asr`
// helper — but we keep the >>4 pattern from the Cyrius reference
// to make the loss-of-precision step visible at every site.

const FX_SHIFT: u32 = 16;

#[inline]
fn fx(n: i64) -> i64 {
    n << FX_SHIFT
}

// dist_sq: pre-shift deltas by 4 to keep the squared sum inside i64
// even at large coordinate magnitudes. Result is in reduced units.
fn dist_sq(x1: i64, y1: i64, x2: i64, y2: i64) -> i64 {
    let dx = (x2 - x1) >> 4;
    let dy = (y2 - y1) >> 4;
    dx * dx + dy * dy
}

fn circle_circle(x1: i64, y1: i64, r1: i64, x2: i64, y2: i64, r2: i64) -> bool {
    let d2 = dist_sq(x1, y1, x2, y2);
    let sum_r = (r1 + r2) >> 4;
    d2 <= sum_r * sum_r
}

fn aabb_overlap(
    l1: i64, t1: i64, r1: i64, b1: i64,
    l2: i64, t2: i64, r2: i64, b2: i64,
) -> bool {
    if l1 >= r2 { return false; }
    if r1 <= l2 { return false; }
    if t1 >= b2 { return false; }
    if b1 <= t2 { return false; }
    true
}

fn point_in_rect(px: i64, py: i64, left: i64, top: i64, right: i64, bottom: i64) -> bool {
    px >= left && px < right && py >= top && py < bottom
}

fn circle_aabb(cx: i64, cy: i64, cr: i64, left: i64, top: i64, right: i64, bottom: i64) -> bool {
    // Clamp circle center onto the AABB, then distance-check.
    let closest_x = cx.clamp(left, right);
    let closest_y = cy.clamp(top, bottom);
    let d2 = dist_sq(cx, cy, closest_x, closest_y);
    let r = cr >> 4;
    d2 <= r * r
}

fn point_in_circle(px: i64, py: i64, cx: i64, cy: i64, cr: i64) -> bool {
    let d2 = dist_sq(px, py, cx, cy);
    let r = cr >> 4;
    d2 <= r * r
}

// push_apart: dominant-axis separation vector (returns dx for entity 1)
fn push_apart_x(x1: i64, _y1: i64, x2: i64, _y2: i64, overlap: i64) -> i64 {
    let dx = x2 - x1;
    let half = overlap >> 1;
    if dx > 0 { -half } else { half }
}

// Swept AABB (1D form sufficient for this test set): moving rect A with
// velocity (vx, vy) over one frame against static rect B. Returns
// time-of-impact in [0, FX_ONE] or FX_ONE if no impact this frame.
fn swept_aabb_x(
    al: i64, ar: i64, vx: i64,
    bl: i64, br: i64,
) -> i64 {
    let fx_one = 1i64 << FX_SHIFT;
    if vx == 0 {
        return fx_one;
    }
    // Time to enter / exit on the X axis (positive sweep direction).
    let (enter_dist, exit_dist) = if vx > 0 {
        (bl - ar, br - al)
    } else {
        (br - al, bl - ar)
    };
    // Avoid overflow: shift before dividing by velocity.
    let abs_v = vx.abs();
    let enter = (enter_dist.abs() << FX_SHIFT) / abs_v;
    let exit  = (exit_dist.abs()  << FX_SHIFT) / abs_v;
    if enter > exit || enter > fx_one { fx_one } else { enter }
}

// ── Tests ────────────────────────────────────────────────────────────

fn main() {
    // Circle-circle: overlapping
    assert!(circle_circle(fx(10), fx(10), fx(5), fx(13), fx(10), fx(5)),
            "overlapping circles collide");

    // Circle-circle: distant
    assert!(!circle_circle(fx(0), fx(0), fx(1), fx(100), fx(100), fx(1)),
            "distant circles don't collide");

    // Circle-circle: touching exactly (sum-of-radii == distance)
    assert!(circle_circle(fx(0), fx(0), fx(5), fx(10), fx(0), fx(5)),
            "touching circles collide");

    // AABB overlap: overlapping
    assert!(aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                         fx(5), fx(5), fx(15), fx(15)),
            "overlapping AABBs");

    // AABB overlap: separated
    assert!(!aabb_overlap(fx(0), fx(0), fx(5), fx(5),
                          fx(10), fx(10), fx(20), fx(20)),
            "separated AABBs");

    // AABB overlap: touching edge — strictly disjoint per Cyrius reference
    assert!(!aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                          fx(10), fx(0), fx(20), fx(10)),
            "edge-adjacent AABBs don't overlap");

    // Point-in-rect: inside
    assert!(point_in_rect(fx(5), fx(5), fx(0), fx(0), fx(10), fx(10)),
            "point inside rect");
    // Point-in-rect: outside
    assert!(!point_in_rect(fx(15), fx(5), fx(0), fx(0), fx(10), fx(10)),
            "point outside rect");
    // Point-in-rect: edge inclusivity (left/top inclusive, right/bottom exclusive)
    assert!(point_in_rect(fx(0), fx(5), fx(0), fx(0), fx(10), fx(10)),
            "left edge is inside");
    assert!(!point_in_rect(fx(10), fx(5), fx(0), fx(0), fx(10), fx(10)),
            "right edge is outside");

    // Circle vs AABB
    assert!(circle_aabb(fx(5), fx(5), fx(3), fx(0), fx(0), fx(10), fx(10)),
            "circle inside AABB");
    assert!(!circle_aabb(fx(20), fx(20), fx(3), fx(0), fx(0), fx(10), fx(10)),
            "circle far from AABB");

    // Point-in-circle
    assert!(point_in_circle(fx(1), fx(1), fx(0), fx(0), fx(5)),
            "point inside circle");
    assert!(!point_in_circle(fx(100), fx(100), fx(0), fx(0), fx(5)),
            "point outside circle");

    // Distance squared sanity check (3-4-5 triangle, pre-shifted result > 0)
    let d2 = dist_sq(fx(0), fx(0), fx(3), fx(4));
    assert!(d2 > 0, "distance squared positive for 3-4-5 triangle");

    // Push-apart along dominant axis
    let pdx = push_apart_x(fx(0), fx(0), fx(4), fx(0), fx(2));
    assert!(pdx < 0, "entity 1 pushed left when entity 2 is to its right");

    // Swept AABB time-of-impact: A=[0,2] moving right with v=fx(8) toward B=[6,10]
    // Distance to enter = 6 - 2 = 4, velocity per frame = 8 → toi = 0.5
    let fx_one = 1i64 << FX_SHIFT;
    let toi = swept_aabb_x(fx(0), fx(2), fx(8), fx(6), fx(10));
    assert!(toi < fx_one && toi > 0, "swept AABB returns mid-frame TOI");

    // Swept AABB: A moving away from B → no collision in this frame
    let toi2 = swept_aabb_x(fx(0), fx(2), -fx(1), fx(6), fx(10));
    assert_eq!(toi2, fx_one, "moving away yields no in-frame impact");

    println!("All collision_detection_2d examples passed.");
}
