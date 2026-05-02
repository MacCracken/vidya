// Vidya — Projectile Physics in Zig
//
// Semi-implicit Euler integration in 16.16 fixed-point on i64. Zig's
// `>>` on signed integers is arithmetic, and overflow is checked at
// runtime in safe modes — `*%` is the explicit "wrap on overflow"
// multiply, used for the bounce intermediate (vy * RESTITUTION ≈
// 3.6e10 worst case fits in i64, but `*%` makes the wrap-on-overflow
// intent visible at the call site rather than implicit).

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const FX_SHIFT: u6 = 16;
const GRAVITY: i64 = 6554;          // 0.1 per frame
const FLOOR_Y: i64 = 14745600;      // 225.0
const RESTITUTION: i64 = 45875;     // 0.7 in 16.16

const Ball = struct {
    x: i64,
    y: i64,
    vx: i64,
    vy: i64,
};

fn physicsStep(b: *Ball) void {
    // Semi-implicit Euler: velocity first, then position.
    b.vy += GRAVITY;
    b.y  += b.vy;
    b.x  += b.vx;
}

fn bounceCheck(b: *Ball) void {
    if (b.y > FLOOR_Y) {
        b.y = FLOOR_Y;
        // vy = -(vy * restitution) >> 16  — wrapping mul keeps intent explicit.
        const prod: i64 = b.vy *% RESTITUTION;
        b.vy = -(prod >> FX_SHIFT);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

fn testGravity() void {
    var b = Ball{ .x = 0, .y = 0, .vx = 0, .vy = 0 };
    physicsStep(&b);
    assert(b.vy == GRAVITY);
    assert(b.y  == GRAVITY); // semi-implicit: position uses NEW velocity
}

fn testParabolicArc() void {
    var b = Ball{ .x = 0, .y = 6553600, .vx = 0, .vy = -1310720 }; // y=100.0, vy=-20.0
    const initial_y = b.y;

    var i: usize = 0;
    while (i < 50) : (i += 1) physicsStep(&b);
    assert(b.y < initial_y);

    i = 0;
    while (i < 400) : (i += 1) physicsStep(&b);
    assert(b.y > initial_y);
}

fn testBounce() void {
    var b = Ball{ .x = 0, .y = FLOOR_Y + 1, .vx = 0, .vy = 655360 }; // vy=10.0 down
    bounceCheck(&b);
    assert(b.vy < 0);
    assert(-b.vy < 655360);
    assert(b.y == FLOOR_Y);
}

fn testHorizontalUnchanged() void {
    const vx_initial: i64 = 131072; // 2.0
    var b = Ball{ .x = 0, .y = 0, .vx = vx_initial, .vy = 0 };
    physicsStep(&b);
    physicsStep(&b);
    physicsStep(&b);
    assert(b.vx == vx_initial);
    assert(b.x  == 3 * vx_initial);
}

fn testEnergyDecay() void {
    var b = Ball{ .x = 0, .y = 0, .vx = 0, .vy = 655360 }; // vy=10.0 down

    // 1000 frames — |vy| plateaus around 2700, well under 2*GRAVITY=13108.
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        physicsStep(&b);
        bounceCheck(&b);
    }

    const abs_vy: i64 = if (b.vy < 0) -b.vy else b.vy;
    assert(abs_vy < GRAVITY * 2);
}

fn testSemiImplicitStability() void {
    const start_y: i64 = FLOOR_Y - 655360;                                    // 10.0 above floor
    var b = Ball{ .x = 0, .y = start_y, .vx = 0, .vy = -655360 };             // vy=-10.0 upward
    var min_y: i64 = start_y;

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        physicsStep(&b);
        bounceCheck(&b);
        if (b.y < min_y) min_y = b.y;
    }

    const max_rise: i64 = 1000 * 65536;
    assert(min_y > start_y - max_rise);
}

pub fn main() !void {
    testGravity();
    testParabolicArc();
    testBounce();
    testHorizontalUnchanged();
    testEnergyDecay();
    testSemiImplicitStability();
    print("All projectile_physics examples passed.\n", .{});
}
