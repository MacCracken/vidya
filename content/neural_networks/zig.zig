// Vidya — Neural Network Forward Pass — Zig port. Q15 fixed-point.

const std = @import("std");

const SCALE: u6 = 15;
const ONE: i64 = 32768;
const N_IN: usize = 2;
const N_HIDDEN: usize = 3;
const N_OUT: usize = 2;

fn qMul(a: i64, b: i64) i64 {
    const p = a * b;
    return if (p < 0) -(@divTrunc(-p, 1 << SCALE)) else @divTrunc(p, 1 << SCALE);
}

const W_HIDDEN = [_]i64{ 16384, -16384, -16384, 16384, 16384, 16384 };
const B_HIDDEN = [_]i64{ 0, 0, 0 };
const W_OUTPUT = [_]i64{ 16384, 0, 0, 0, 16384, 0 };
const B_OUTPUT = [_]i64{ 0, 0 };

fn dense(W: []const i64, b: []const i64, x: []const i64, out: []i64, n_in: usize, n_out: usize) void {
    var j: usize = 0;
    while (j < n_out) : (j += 1) {
        var acc = b[j];
        var i: usize = 0;
        while (i < n_in) : (i += 1) {
            acc += qMul(W[j * n_in + i], x[i]);
        }
        out[j] = acc;
    }
}

fn relu(x: []i64) void {
    for (x) |*v| if (v.* < 0) { v.* = 0; };
}

fn argmax(x: []const i64) usize {
    var best_idx: usize = 0;
    var best_val = x[0];
    var i: usize = 1;
    while (i < x.len) : (i += 1) {
        if (x[i] > best_val) {
            best_val = x[i];
            best_idx = i;
        }
    }
    return best_idx;
}

var last_hidden: [N_HIDDEN]i64 = [_]i64{0} ** N_HIDDEN;
var last_output: [N_OUT]i64 = [_]i64{0} ** N_OUT;

fn forward(input: []const i64) usize {
    dense(&W_HIDDEN, &B_HIDDEN, input, last_hidden[0..], N_IN, N_HIDDEN);
    relu(last_hidden[0..]);
    dense(&W_OUTPUT, &B_OUTPUT, last_hidden[0..], last_output[0..], N_HIDDEN, N_OUT);
    return argmax(last_output[0..]);
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
    check(qMul(16384, 16384) == 8192, "0.5 * 0.5 = 0.25");
    check(qMul(-16384, 16384) == -8192, "-0.5 * 0.5 = -0.25");

    {
        const w = [_]i64{ 16384, 16384, 8192, 24576 };
        const b = [_]i64{ 0, 0 };
        const x = [_]i64{ 32767, 32767 };
        var y = [_]i64{ 0, 0 };
        dense(&w, &b, &x, y[0..], 2, 2);
        check(y[0] >= 32765 and y[0] <= 32769, "dense y[0] ~= 1.0");
        check(y[1] >= 32765 and y[1] <= 32769, "dense y[1] ~= 1.0");
    }
    {
        const w = [_]i64{ 0, 0 };
        const b = [_]i64{12345};
        const x = [_]i64{ 32767, 32767 };
        var y = [_]i64{0};
        dense(&w, &b, &x, y[0..], 2, 1);
        check(y[0] == 12345, "bias passes through");
    }
    {
        var y = [_]i64{ -100, 200, -300, 400 };
        relu(y[0..]);
        check(y[0] == 0 and y[1] == 200 and y[2] == 0 and y[3] == 400, "relu clips");
    }
    {
        var y = [_]i64{0};
        relu(y[0..]);
        check(y[0] == 0, "relu(0) = 0");
    }
    {
        const y = [_]i64{ 100, 500, 200, 300 };
        check(argmax(y[0..]) == 1, "argmax picks 1");
    }
    {
        const y = [_]i64{ 100, 500, 500 };
        check(argmax(y[0..]) == 1, "first-found wins");
    }

    {
        const x = [_]i64{ 26214, 6553 };
        check(forward(x[0..]) == 0, "x=[0.8,0.2] → class 0");
    }
    {
        const x = [_]i64{ 6553, 26214 };
        check(forward(x[0..]) == 1, "x=[0.2,0.8] → class 1");
    }
    {
        const x = [_]i64{ 32767, 0 };
        check(forward(x[0..]) == 0, "x=[1.0,0.0] → class 0");
    }
    {
        const x = [_]i64{ 0, 32767 };
        check(forward(x[0..]) == 1, "x=[0.0,1.0] → class 1");
    }
    {
        const x = [_]i64{ 32767, 0 };
        _ = forward(x[0..]);
        check(last_hidden[1] == 0, "relu zeroed hidden[1]");
        check(last_hidden[0] > 0, "hidden[0] passed through");
    }

    std.debug.print("=== neural_networks ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
