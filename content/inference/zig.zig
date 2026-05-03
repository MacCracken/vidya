// Vidya — LLM Inference (Decoding) — Zig port.

const std = @import("std");

const VOCAB_SIZE: usize = 8;
const TOK_EOS: usize = 1;

var BIGRAM: [VOCAB_SIZE][VOCAB_SIZE]i64 = init_blk: {
    var b: [VOCAB_SIZE][VOCAB_SIZE]i64 = [_][VOCAB_SIZE]i64{[_]i64{0} ** VOCAB_SIZE} ** VOCAB_SIZE;
    b[2][3] = 1000;
    b[2][4] = 100;
    b[3][6] = 800;
    b[3][5] = 200;
    b[4][5] = 700;
    b[5][1] = 600;
    b[6][7] = 900;
    b[6][3] = 100;
    b[7][1] = 950;
    break :init_blk b;
};

fn argmaxLogits(logits: []const i64) usize {
    var best_idx: usize = 0;
    var best_val = logits[0];
    var i: usize = 1;
    while (i < logits.len) : (i += 1) {
        if (logits[i] > best_val) {
            best_val = logits[i];
            best_idx = i;
        }
    }
    return best_idx;
}

fn topkFilter(logits: []i64, k: usize) usize {
    var marks: [VOCAB_SIZE]bool = [_]bool{false} ** VOCAB_SIZE;
    var picked: usize = 0;
    while (picked < k) {
        var best_idx: i32 = -1;
        var best_val: i64 = 0;
        var first = true;
        var j: usize = 0;
        while (j < logits.len) : (j += 1) {
            if (!marks[j]) {
                if (first) {
                    best_idx = @intCast(j);
                    best_val = logits[j];
                    first = false;
                } else if (logits[j] > best_val) {
                    best_idx = @intCast(j);
                    best_val = logits[j];
                }
            }
        }
        if (best_idx < 0) return picked;
        marks[@intCast(best_idx)] = true;
        picked += 1;
    }
    var m: usize = 0;
    while (m < logits.len) : (m += 1) {
        if (!marks[m]) logits[m] = 0;
    }
    return picked;
}

fn bigramLogits(prev: usize, out: *[VOCAB_SIZE]i64) void {
    var i: usize = 0;
    while (i < VOCAB_SIZE) : (i += 1) out[i] = BIGRAM[prev][i];
}

fn decodeSequence(start: usize, output: []usize, max_len: usize) usize {
    var buf: [VOCAB_SIZE]i64 = undefined;
    var current = start;
    var count: usize = 0;
    while (count < max_len) {
        bigramLogits(current, &buf);
        const next = argmaxLogits(buf[0..]);
        output[count] = next;
        count += 1;
        if (next == TOK_EOS) return count;
        current = next;
    }
    return count;
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
    {
        const l = [_]i64{ 100, 500, 200, 300 };
        check(argmaxLogits(l[0..]) == 1, "argmax picks 1");
    }
    {
        const l = [_]i64{ 100, 500, 500 };
        check(argmaxLogits(l[0..]) == 1, "first-found wins");
    }
    {
        const l = [_]i64{ -100, -50, -200 };
        check(argmaxLogits(l[0..]) == 1, "argmax over negatives");
    }

    {
        var l = [_]i64{ 10, 50, 30, 20, 40, 5, 60, 25 };
        check(topkFilter(l[0..], 3) == 3, "topk picked 3");
        check(l[6] == 60 and l[1] == 50 and l[4] == 40, "top 3 kept");
        check(l[0] == 0, "idx 0 zeroed");
        check(l[2] == 0, "idx 2 zeroed");
        check(l[3] == 0, "idx 3 zeroed");
        check(l[5] == 0, "idx 5 zeroed");
        check(l[7] == 0, "idx 7 zeroed");
    }
    {
        var l = [_]i64{ 1, 2, 3 };
        check(topkFilter(l[0..], 3) == 3, "topk(3,3) keeps all");
        check(l[0] == 1 and l[1] == 2 and l[2] == 3, "all preserved");
    }

    {
        var buf: [VOCAB_SIZE]i64 = undefined;
        bigramLogits(2, &buf);
        check(argmaxLogits(buf[0..]) == 3, "after hello → world");
    }

    {
        var out: [16]usize = undefined;
        const n = decodeSequence(2, out[0..], 10);
        check(n == 4, "produced 4 tokens");
        check(out[0] == 3 and out[1] == 6 and out[2] == 7 and out[3] == 1, "hello → ...");
    }
    {
        var out: [16]usize = undefined;
        const n = decodeSequence(5, out[0..], 10);
        check(n == 1 and out[0] == 1, "bar → EOS");
    }
    {
        var out: [16]usize = undefined;
        const n = decodeSequence(2, out[0..], 2);
        check(n == 2 and out[0] == 3 and out[1] == 6, "capped at 2");
    }
    {
        var o1: [16]usize = undefined;
        var o2: [16]usize = undefined;
        const n1 = decodeSequence(2, o1[0..], 10);
        const n2 = decodeSequence(2, o2[0..], 10);
        check(n1 == n2, "same length");
        var eq = true;
        var i: usize = 0;
        while (i < n1) : (i += 1) if (o1[i] != o2[i]) { eq = false; };
        check(eq, "deterministic");
    }

    std.debug.print("=== inference ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
