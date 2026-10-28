// Vidya — Fixed-Point Arithmetic in Zig
//
// 16.16 fixed-point on i64. Zig's `>>` on signed integers is arithmetic
// (sign-extending), and overflow is checked at runtime in safe modes —
// so `*%` (wrapping multiply) is the explicit way to ask for silent
// wraparound (which C gives only unsigned types; signed overflow is UB in
// C). This makes intent visible at every site.
//
// fxMul widens to i128 to compute the product without overflow, then
// narrows back to i64 with @intCast — a CHECKED conversion (panics in safe
// modes if the result does not fit), not a truncation. Zig's @intCast /
// @as / @intFromFloat are explicit-by-design — no implicit narrowing
// (only value-preserving widening such as i64 -> i128 is implicit).

const std = @import("std");
const math = std.math;
const print = std.debug.print;
const assert = std.debug.assert;

const FX_SHIFT: u6 = 16;
const FX_ONE: i64 = @as(i64, 1) << FX_SHIFT;
const FX_HALF: i64 = @as(i64, 1) << (FX_SHIFT - 1);

fn fxFromInt(n: i64) i64 {
    return n << FX_SHIFT;
}

fn fxToInt(v: i64) i64 {
    return if (v < 0) -((-v) >> FX_SHIFT) else v >> FX_SHIFT;
}

fn fxToIntRound(v: i64) i64 {
    return if (v < 0)
        -((-v + FX_HALF) >> FX_SHIFT)
    else
        (v + FX_HALF) >> FX_SHIFT;
}

fn fxMul(a: i64, b: i64) i64 {
    const wide = @as(i128, a) * @as(i128, b);
    return @intCast(wide >> FX_SHIFT);
}

// No i128: pre-shift each operand by 8 so the product fits i64 for larger
// inputs, at the cost of the low 8 fraction bits of each. Not overflow-proof.
fn fxMulSafe(a: i64, b: i64) i64 {
    return (a >> 8) * (b >> 8);
}

fn fxDiv(a: i64, b: i64) i64 {
    if (b == 0) return 0;
    const wide = @as(i128, a) << FX_SHIFT;
    return @intCast(@divTrunc(wide, @as(i128, b)));
}

// ── Sine table — quarter-wave, 256 steps (257 entries) ─────────────────
// 1024 steps per full turn, so a quarter is 256 steps and needs 257
// entries (0..256 inclusive, sin(pi/2) included). Mirroring the 2nd and 4th
// quadrants is then sin_table[512 - a] / sin_table[1024 - a]. A 256-entry
// table forces `511 - a`, which is one step off: every descending-quadrant
// lookup returns the previous angle's value (up to 402 LSB, ~0.6%, wrong).

var sin_table: [257]i64 = undefined;

fn buildSinTable() void {
    var i: usize = 0;
    while (i <= 256) : (i += 1) {
        const angle: f64 = @as(f64, @floatFromInt(i)) * (math.pi / 2.0) / 256.0;
        const v: f64 = @sin(angle) * @as(f64, @floatFromInt(FX_ONE));
        sin_table[i] = @intFromFloat(v);
    }
}

fn sinLookup(angle: i64) i64 {
    const a: usize = @intCast(angle & 1023);
    if (a <= 256) return sin_table[a];
    if (a < 512) return sin_table[512 - a];
    if (a <= 768) return -sin_table[a - 512];
    return -sin_table[1024 - a];
}

// ── Tests ─────────────────────────────────────────────────────────────

pub fn main() !void {
    assert(fxFromInt(1) == 65536);
    assert(fxFromInt(10) == 655360);
    assert(fxFromInt(0) == 0);

    const three = fxFromInt(3);
    const two_half: i64 = 163840; // 2.5
    assert(fxMul(three, two_half) == 491520);
    assert(fxMul(FX_ONE, FX_ONE) == FX_ONE);
    assert(fxMul(FX_HALF, FX_HALF) == 16384);

    const big = fxFromInt(1000);
    assert(fxMulSafe(big, big) == fxFromInt(1_000_000));

    assert(fxDiv(fxFromInt(10), fxFromInt(4)) == 163840);
    assert(fxDiv(FX_ONE, 0) == 0);

    assert(fxToInt(-fxFromInt(3)) == -3);
    assert(fxToInt(-(FX_ONE + FX_HALF)) == -1);
    assert(fxToIntRound(-(FX_ONE + FX_HALF)) == -2);

    buildSinTable();
    assert(sinLookup(0) == 0);
    assert(sinLookup(256) == FX_ONE); // sin(pi/2) = 1.0 exactly
    assert(sinLookup(512) == 0);
    assert(sinLookup(768) == -FX_ONE);
    // Mirror symmetry: sin(pi - x) == sin(x), sin(2pi - x) == -sin(x)
    assert(sinLookup(511) == sinLookup(1));
    assert(sinLookup(1023) == -sinLookup(1));
    assert(sinLookup(1) > 0);

    var i: i64 = 0;
    while (i < 100) : (i += 1) {
        assert(fxToInt(fxFromInt(i)) == i);
    }

    print("All fixed_point_arithmetic examples passed.\n", .{});
}
