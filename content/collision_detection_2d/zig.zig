// Vidya — 2D Collision Detection in Zig
//
// All coordinates in 16.16 fixed-point on i64. Zig's `>>` on signed
// integers is arithmetic (sign-preserving), and signed overflow is
// runtime-checked in safe modes — so we use the i128 builtin for
// the squared-distance intermediate when full precision matters.
// In this test set we keep coordinates small and mirror the Cyrius
// >>4 pre-shift pattern so dx*dx + dy*dy fits in i64 without widen.
// Squared-distance comparisons avoid sqrt — the central trick.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const FX_SHIFT: u6 = 16;
const FX_ONE: i64 = @as(i64, 1) << FX_SHIFT;

fn fx(n: i64) i64 {
    return n << FX_SHIFT;
}

fn distSq(x1: i64, y1: i64, x2: i64, y2: i64) i64 {
    const dx: i64 = (x2 - x1) >> 4;
    const dy: i64 = (y2 - y1) >> 4;
    return dx * dx + dy * dy;
}

fn circleCircle(x1: i64, y1: i64, r1: i64,
                x2: i64, y2: i64, r2: i64) bool {
    const d2 = distSq(x1, y1, x2, y2);
    const sum_r: i64 = (r1 + r2) >> 4;
    return d2 <= sum_r * sum_r;
}

fn aabbOverlap(l1: i64, t1: i64, r1: i64, b1: i64,
               l2: i64, t2: i64, r2: i64, b2: i64) bool {
    if (l1 >= r2) return false;
    if (r1 <= l2) return false;
    if (t1 >= b2) return false;
    if (b1 <= t2) return false;
    return true;
}

fn pointInRect(px: i64, py: i64,
               left: i64, top: i64,
               right: i64, bottom: i64) bool {
    return px >= left and px < right and py >= top and py < bottom;
}

fn clampI(v: i64, lo: i64, hi: i64) i64 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

fn circleAabb(cx: i64, cy: i64, cr: i64,
              left: i64, top: i64,
              right: i64, bottom: i64) bool {
    const closest_x = clampI(cx, left, right);
    const closest_y = clampI(cy, top, bottom);
    const d2 = distSq(cx, cy, closest_x, closest_y);
    const r: i64 = cr >> 4;
    return d2 <= r * r;
}

fn pointInCircle(px: i64, py: i64,
                 cx: i64, cy: i64, cr: i64) bool {
    const d2 = distSq(px, py, cx, cy);
    const r: i64 = cr >> 4;
    return d2 <= r * r;
}

fn pushApartX(x1: i64, x2: i64, overlap: i64) i64 {
    const dx = x2 - x1;
    const half: i64 = overlap >> 1;
    return if (dx > 0) -half else half;
}

fn absI(v: i64) i64 {
    return if (v < 0) -v else v;
}

fn sweptAabbX(al: i64, ar: i64, vx: i64,
              bl: i64, br: i64) i64 {
    if (vx == 0) return FX_ONE;
    var enter_dist: i64 = 0;
    var exit_dist: i64 = 0;
    if (vx > 0) {
        enter_dist = bl - ar;
        exit_dist = br - al;
    } else {
        enter_dist = br - al;
        exit_dist = bl - ar;
    }
    const abs_v = absI(vx);
    const enter = @divTrunc(absI(enter_dist) << FX_SHIFT, abs_v);
    const exit_ = @divTrunc(absI(exit_dist)  << FX_SHIFT, abs_v);
    if (enter > exit_ or enter > FX_ONE) return FX_ONE;
    return enter;
}

// ── Tests ─────────────────────────────────────────────────────────────

pub fn main() !void {
    assert(circleCircle(fx(10), fx(10), fx(5), fx(13), fx(10), fx(5)));
    assert(!circleCircle(fx(0), fx(0), fx(1), fx(100), fx(100), fx(1)));
    assert(circleCircle(fx(0), fx(0), fx(5), fx(10), fx(0), fx(5)));

    assert(aabbOverlap(fx(0), fx(0), fx(10), fx(10),
                       fx(5), fx(5), fx(15), fx(15)));
    assert(!aabbOverlap(fx(0), fx(0), fx(5), fx(5),
                        fx(10), fx(10), fx(20), fx(20)));
    assert(!aabbOverlap(fx(0), fx(0), fx(10), fx(10),
                        fx(10), fx(0), fx(20), fx(10)));

    assert(pointInRect(fx(5), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(!pointInRect(fx(15), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(pointInRect(fx(0), fx(5), fx(0), fx(0), fx(10), fx(10)));
    assert(!pointInRect(fx(10), fx(5), fx(0), fx(0), fx(10), fx(10)));

    assert(circleAabb(fx(5), fx(5), fx(3), fx(0), fx(0), fx(10), fx(10)));
    assert(!circleAabb(fx(20), fx(20), fx(3), fx(0), fx(0), fx(10), fx(10)));

    assert(pointInCircle(fx(1), fx(1), fx(0), fx(0), fx(5)));
    assert(!pointInCircle(fx(100), fx(100), fx(0), fx(0), fx(5)));

    assert(distSq(fx(0), fx(0), fx(3), fx(4)) > 0);

    assert(pushApartX(fx(0), fx(4), fx(2)) < 0);

    const toi = sweptAabbX(fx(0), fx(2), fx(8), fx(6), fx(10));
    assert(toi > 0 and toi < FX_ONE);
    const toi2 = sweptAabbX(fx(0), fx(2), -fx(1), fx(6), fx(10));
    assert(toi2 == FX_ONE);

    print("All collision_detection_2d examples passed.\n", .{});
}
