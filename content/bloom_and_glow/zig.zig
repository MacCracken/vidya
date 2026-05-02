// Vidya — Bloom and Glow in Zig
//
// 1-pixel additive bloom on a 16x16 single-channel intensity buffer.

const std = @import("std");

const FB_W: i32 = 16;
const FB_H: i32 = 16;
const FB_BYTES: usize = 256;
const THRESHOLD: u8 = 128;
const GLOW_FRAC: u8 = 2;

fn fb_set(fb: []u8, x: i32, y: i32, v: u8) void {
    if (x < 0 or x >= FB_W or y < 0 or y >= FB_H) return;
    fb[@intCast(y * FB_W + x)] = v;
}

fn fb_get(fb: []const u8, x: i32, y: i32) u8 {
    if (x < 0 or x >= FB_W or y < 0 or y >= FB_H) return 0;
    return fb[@intCast(y * FB_W + x)];
}

fn fb_add(fb: []u8, x: i32, y: i32, delta: u32) void {
    if (x < 0 or x >= FB_W or y < 0 or y >= FB_H) return;
    const idx: usize = @intCast(y * FB_W + x);
    const s = @as(u32, fb[idx]) + delta;
    fb[idx] = if (s > 255) 255 else @intCast(s);
}

fn apply_bloom(src: []const u8, dst: []u8, threshold: u8) void {
    @memcpy(dst, src);
    var y: i32 = 0;
    while (y < FB_H) : (y += 1) {
        var x: i32 = 0;
        while (x < FB_W) : (x += 1) {
            const v = src[@intCast(y * FB_W + x)];
            if (v >= threshold) {
                const glow: u32 = v / GLOW_FRAC;
                fb_add(dst, x - 1, y, glow);
                fb_add(dst, x + 1, y, glow);
                fb_add(dst, x, y - 1, glow);
                fb_add(dst, x, y + 1, glow);
            }
        }
    }
}

fn count_lit(fb: []const u8) usize {
    var n: usize = 0;
    for (fb) |v| if (v != 0) { n += 1; };
    return n;
}

pub fn main() !void {
    var src: [FB_BYTES]u8 = [_]u8{0} ** FB_BYTES;
    var dst: [FB_BYTES]u8 = [_]u8{0} ** FB_BYTES;

    apply_bloom(&src, &dst, THRESHOLD);
    if (count_lit(&dst) != 0) return error.Empty;

    @memset(&src, 0); fb_set(&src, 8, 8, 200);
    apply_bloom(&src, &dst, THRESHOLD);
    if (fb_get(&dst, 8, 8) != 200) return error.Src;
    if (fb_get(&dst, 7, 8) != 100) return error.L;
    if (fb_get(&dst, 9, 8) != 100) return error.R;
    if (fb_get(&dst, 8, 7) != 100) return error.U;
    if (fb_get(&dst, 8, 9) != 100) return error.D;
    if (fb_get(&dst, 7, 7) != 0) return error.Diag;
    if (count_lit(&dst) != 5) return error.SingleCount;

    @memset(&src, 0); fb_set(&src, 8, 8, 200); fb_set(&src, 9, 8, 250);
    apply_bloom(&src, &dst, THRESHOLD);
    if (fb_get(&dst, 9, 8) != 255) return error.Clamp;
    if (fb_get(&dst, 8, 8) != 255) return error.SumClamp;

    @memset(&src, 0); fb_set(&src, 8, 8, 100);
    apply_bloom(&src, &dst, THRESHOLD);
    if (fb_get(&dst, 8, 8) != 100) return error.DimPreserved;
    if (fb_get(&dst, 7, 8) != 0) return error.DimNoGlow;
    if (count_lit(&dst) != 1) return error.DimCount;

    @memset(&src, 0); fb_set(&src, 0, 0, 200);
    apply_bloom(&src, &dst, THRESHOLD);
    if (fb_get(&dst, 0, 0) != 200) return error.Corner;
    if (fb_get(&dst, 1, 0) != 100) return error.CornerR;
    if (fb_get(&dst, 0, 1) != 100) return error.CornerD;
    if (count_lit(&dst) != 3) return error.CornerCount;

    @memset(&src, 0); fb_set(&src, 4, 8, 200); fb_set(&src, 6, 8, 200);
    apply_bloom(&src, &dst, THRESHOLD);
    if (fb_get(&dst, 5, 8) != 200) return error.Mid;
    if (fb_get(&dst, 3, 8) != 100) return error.OuterL;
    if (fb_get(&dst, 7, 8) != 100) return error.OuterR;

    std.debug.print("bloom_and_glow: 20/20 ok\n", .{});
}
