// Vidya — Embeddings and Vector Search — Zig port. Q15 fixed-point.

const std = @import("std");

const SCALE: u6 = 15;
const ONE: i64 = 32768;
const DIM: usize = 4;
const N_CORPUS: usize = 4;

fn qMul(a: i64, b: i64) i64 {
    const p = a * b;
    return if (p < 0) -(@divTrunc(-p, 1 << SCALE)) else @divTrunc(p, 1 << SCALE);
}

const CORPUS: [N_CORPUS][DIM]i64 = [_][DIM]i64{
    [_]i64{ 32767, 0, 0, 0 },
    [_]i64{ 0, 32767, 0, 0 },
    [_]i64{ 16384, 16384, 16384, 16384 },
    [_]i64{ -32767, 0, 0, 0 },
};

fn dot(a: []const i64, b: []const i64) i64 {
    var acc: i64 = 0;
    var i: usize = 0;
    while (i < a.len) : (i += 1) acc += qMul(a[i], b[i]);
    return acc;
}

fn corpusSim(query: []const i64, idx: usize) i64 {
    return dot(query, CORPUS[idx][0..]);
}

fn nearest(query: []const i64) usize {
    var best_idx: usize = 0;
    var best_sim = corpusSim(query, 0);
    var i: usize = 1;
    while (i < N_CORPUS) : (i += 1) {
        const s = corpusSim(query, i);
        if (s > best_sim) {
            best_sim = s;
            best_idx = i;
        }
    }
    return best_idx;
}

fn topKNeighbors(query: []const i64, k: usize, out: []usize) usize {
    var marks: [N_CORPUS]bool = [_]bool{false} ** N_CORPUS;
    var picked: usize = 0;
    while (picked < k) {
        var best_idx: i32 = -1;
        var best_sim: i64 = 0;
        var first = true;
        var j: usize = 0;
        while (j < N_CORPUS) : (j += 1) {
            if (!marks[j]) {
                const s = corpusSim(query, j);
                if (first) {
                    best_idx = @intCast(j);
                    best_sim = s;
                    first = false;
                } else if (s > best_sim) {
                    best_idx = @intCast(j);
                    best_sim = s;
                }
            }
        }
        if (best_idx < 0) return picked;
        marks[@intCast(best_idx)] = true;
        out[picked] = @intCast(best_idx);
        picked += 1;
    }
    return picked;
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
    var i: usize = 0;
    while (i < N_CORPUS) : (i += 1) {
        const s = corpusSim(CORPUS[i][0..], i);
        check(s >= 32760, "self-sim ≈ ONE");
    }

    check(corpusSim(CORPUS[0][0..], 1) == 0, "v0·v1 = 0");
    {
        const s = corpusSim(CORPUS[0][0..], 3);
        check(s >= -ONE and s <= -32760, "v0·v3 ≈ -ONE");
    }
    check(corpusSim(CORPUS[2][0..], 2) == ONE, "v2 self-sim = ONE");
    {
        const s = corpusSim(CORPUS[0][0..], 2);
        check(s >= 16380 and s <= 16384, "v0·v2 ≈ 0.5");
    }
    check(dot(CORPUS[0][0..], CORPUS[2][0..]) == dot(CORPUS[2][0..], CORPUS[0][0..]), "dot symmetric");

    {
        const q = [_]i64{ 29490, 0, 0, 0 };
        check(nearest(q[0..]) == 0, "near-x → v0");
    }
    {
        const q = [_]i64{ 0, 32767, 0, 0 };
        check(nearest(q[0..]) == 1, "y-axis → v1");
    }
    {
        const q = [_]i64{ 16384, 16384, 16384, 16384 };
        check(nearest(q[0..]) == 2, "diagonal → v2");
    }
    {
        const q = [_]i64{ -29490, 0, 0, 0 };
        check(nearest(q[0..]) == 3, "negative-x → v3");
    }

    {
        const q = [_]i64{ 32767, 0, 0, 0 };
        var out: [N_CORPUS]usize = undefined;
        const n = topKNeighbors(q[0..], 3, out[0..]);
        check(n == 3 and out[0] == 0 and out[1] == 2 and out[2] == 1, "top-3 ranked");
    }
    {
        const q = [_]i64{ 32767, 0, 0, 0 };
        var out: [N_CORPUS]usize = undefined;
        const n = topKNeighbors(q[0..], 10, out[0..]);
        check(n == 4, "top_k caps");
    }
    {
        const q = [_]i64{ 29490, 0, 0, 0 };
        check(nearest(q[0..]) == nearest(q[0..]), "deterministic");
    }

    std.debug.print("=== embeddings ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
