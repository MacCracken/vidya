// Vidya — Audio DSP — Zig port. Q15 fixed-point throughout.

const std = @import("std");

const SCALE: u6 = 15;
const ONE: i64 = 32768;
const SMAX: i64 = 32767;
const SMIN: i64 = -32767;

fn qMul(a: i64, b: i64) i64 {
    const p = a * b;
    return if (p < 0) -(@as(i64, @intCast(@as(u64, @bitCast(-p)) >> SCALE))) else (p >> SCALE);
}

fn absI(x: i64) i64 { return if (x < 0) -x else x; }

fn clip(s: i64) i64 {
    if (s > SMAX) return SMAX;
    if (s < SMIN) return SMIN;
    return s;
}

const Biquad = struct {
    b0: i64 = 0, b1: i64 = 0, b2: i64 = 0, a1: i64 = 0, a2: i64 = 0,
    x1: i64 = 0, x2: i64 = 0, y1: i64 = 0, y2: i64 = 0,

    fn set(self: *Biquad, b0: i64, b1: i64, b2: i64, a1: i64, a2: i64) void {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2;
        self.x1 = 0; self.x2 = 0; self.y1 = 0; self.y2 = 0;
    }
    fn lowpass1Pole(self: *Biquad, a_q15: i64) void {
        self.set(a_q15, 0, 0, a_q15 - ONE, 0);
    }
    fn step(self: *Biquad, x: i64) i64 {
        const y = qMul(self.b0, x) + qMul(self.b1, self.x1) + qMul(self.b2, self.x2)
                - qMul(self.a1, self.y1) - qMul(self.a2, self.y2);
        self.x2 = self.x1; self.x1 = x;
        self.y2 = self.y1; self.y1 = y;
        return y;
    }
};

fn firStep(taps: []const i64, history: []i64, x_new: i64) i64 {
    var i: usize = history.len;
    while (i > 1) {
        i -= 1;
        history[i] = history[i - 1];
    }
    history[0] = x_new;
    var acc: i64 = 0;
    var j: usize = 0;
    while (j < taps.len) : (j += 1) acc += qMul(taps[j], history[j]);
    return acc;
}

fn peak(buf: []const i64) i64 {
    var p: i64 = 0;
    for (buf) |s| {
        const a = absI(s);
        if (a > p) p = a;
    }
    return p;
}

fn meanAbsolute(buf: []const i64) i64 {
    var sum: i64 = 0;
    for (buf) |s| sum += absI(s);
    return @divTrunc(sum, @as(i64, @intCast(buf.len)));
}

var pass_count: i32 = 0;
var fail_count: i32 = 0;
fn check(cond: bool, name: []const u8) void {
    if (cond) {
        pass_count += 1;
    } else {
        fail_count += 1;
        std.debug.print("  FAIL: {s}\n", .{name});
    }
}

pub fn main() !void {
    check(qMul(ONE, 100) == 100, "ONE * 100 = 100");
    check(qMul(@divTrunc(ONE, 2), @divTrunc(ONE, 2)) == @divTrunc(ONE, 4), "0.5 * 0.5 = 0.25");
    const r = qMul(@divTrunc(ONE, 2), SMAX);
    check(r >= 16383 and r <= 16384, "0.5 * SMAX in [16383,16384]");

    check(clip(50000) == SMAX, "clip(50000) = SMAX");
    check(clip(-50000) == SMIN, "clip(-50000) = SMIN");
    check(clip(1234) == 1234, "clip(1234) unchanged");

    {
        var b = Biquad{};
        b.lowpass1Pole(3277);
        var i: usize = 0;
        while (i < 200) : (i += 1) _ = b.step(30000);
        check(b.y1 >= 29900 and b.y1 <= 30100, "DC settled near 30000");
    }
    {
        var b = Biquad{};
        b.lowpass1Pole(3277);
        var i: usize = 0;
        while (i < 200) : (i += 1) {
            const x: i64 = if ((i & 1) == 0) 20000 else -20000;
            _ = b.step(x);
        }
        check(absI(b.y1) < 2000, "Nyquist heavily attenuated");
    }
    {
        const taps = [_]i64{ONE, 0, 0};
        var history = [_]i64{0, 0, 0};
        check(firStep(taps[0..], history[0..], 1234) == 1234, "identity 1234");
        check(firStep(taps[0..], history[0..], 5678) == 5678, "identity 5678");
    }
    {
        const third = @divTrunc(ONE, 3);
        const taps = [_]i64{third, third, third};
        var history = [_]i64{0, 0, 0};
        _ = firStep(taps[0..], history[0..], 9000);
        _ = firStep(taps[0..], history[0..], 9000);
        const y = firStep(taps[0..], history[0..], 9000);
        check(y >= 8990 and y <= 9010, "moving avg = 9000");
    }
    {
        const buf = [_]i64{100, -5000, 200, 3000, -1500};
        check(peak(buf[0..]) == 5000, "peak = 5000");
    }
    {
        const buf = [_]i64{4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000};
        check(meanAbsolute(buf[0..]) == 4000, "mean-abs constant = constant");
    }
    {
        var buf: [8]i64 = undefined;
        var i: usize = 0;
        while (i < 8) : (i += 1) buf[i] = if ((i & 1) == 0) 4000 else -4000;
        check(meanAbsolute(buf[0..]) == 4000, "mean-abs alternating = 4000");
    }

    std.debug.print("=== audio_dsp ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
