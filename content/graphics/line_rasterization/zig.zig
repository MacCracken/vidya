// Vidya — Line Rasterization (Bresenham) in Zig
//
// All-octant integer Bresenham on a 16x16 byte framebuffer.

const std = @import("std");

const FB_W: i32 = 16;
const FB_H: i32 = 16;
const FB_BYTES: usize = 256;

var fb: [FB_BYTES]u8 = undefined;

fn fb_clear() void { @memset(&fb, 0); }

fn fb_set(x: i32, y: i32, v: u8) void {
    if (x < 0 or x >= FB_W or y < 0 or y >= FB_H) return;
    fb[@intCast(y * FB_W + x)] = v;
}

fn fb_get(x: i32, y: i32) u8 {
    if (x < 0 or x >= FB_W or y < 0 or y >= FB_H) return 0;
    return fb[@intCast(y * FB_W + x)];
}

fn count_lit() usize {
    var n: usize = 0;
    for (fb) |v| if (v != 0) { n += 1; };
    return n;
}

fn sign(v: i32) i32 {
    if (v > 0) return 1;
    if (v < 0) return -1;
    return 0;
}

fn draw_line(x0: i32, y0: i32, x1: i32, y1: i32, v: u8) void {
    const dx = @abs(x1 - x0);
    const dy = @abs(y1 - y0);
    const sx = sign(x1 - x0);
    const sy = sign(y1 - y0);
    var err: i32 = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));
    var x = x0;
    var y = y0;
    while (true) {
        fb_set(x, y, v);
        if (x == x1 and y == y1) return;
        const e2 = err * 2;
        if (e2 > -@as(i32, @intCast(dy))) { err -= @intCast(dy); x += sx; }
        if (e2 < @as(i32, @intCast(dx)))  { err += @intCast(dx); y += sy; }
    }
}

pub fn main() !void {
    fb_clear(); draw_line(2, 5, 8, 5, 1);
    if (count_lit() != 7) return error.HCount;
    if (fb_get(2, 5) != 1) return error.HL;
    if (fb_get(8, 5) != 1) return error.HR;
    if (fb_get(5, 5) != 1) return error.HM;
    if (fb_get(5, 6) != 0) return error.HOff;

    fb_clear(); draw_line(5, 2, 5, 8, 1);
    if (count_lit() != 7) return error.VCount;
    if (fb_get(5, 2) != 1) return error.VT;
    if (fb_get(5, 8) != 1) return error.VB;
    if (fb_get(5, 5) != 1) return error.VM;
    if (fb_get(6, 5) != 0) return error.VOff;

    fb_clear(); draw_line(2, 2, 7, 7, 1);
    if (count_lit() != 6) return error.PdCount;
    if (fb_get(2, 2) != 1) return error.PdS;
    if (fb_get(7, 7) != 1) return error.PdE;
    if (fb_get(5, 5) != 1) return error.PdM;
    if (fb_get(5, 4) != 0) return error.PdOff;

    fb_clear(); draw_line(2, 7, 7, 2, 1);
    if (count_lit() != 6) return error.NdCount;
    if (fb_get(2, 7) != 1) return error.NdS;
    if (fb_get(7, 2) != 1) return error.NdE;
    if (fb_get(5, 4) != 1) return error.NdM;

    fb_clear(); draw_line(3, 1, 5, 11, 1);
    if (count_lit() != 11) return error.StCount;
    if (fb_get(3, 1) != 1) return error.StS;
    if (fb_get(5, 11) != 1) return error.StE;

    fb_clear(); draw_line(8, 8, 8, 8, 1);
    if (count_lit() != 1) return error.PtCount;
    if (fb_get(8, 8) != 1) return error.PtLit;

    fb_clear(); draw_line(8, 5, 2, 5, 1);
    if (count_lit() != 7) return error.RvCount;
    if (fb_get(2, 5) != 1) return error.RvL;
    if (fb_get(8, 5) != 1) return error.RvR;

    std.debug.print("line_rasterization: 27/27 ok\n", .{});
}
