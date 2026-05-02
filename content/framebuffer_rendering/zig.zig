// Vidya — Framebuffer Rendering in Zig
//
// 16x16 BGRA8888 framebuffer mirroring cyrius.cyr.

const std = @import("std");

const FB_W: usize = 16;
const FB_H: usize = 16;
const FB_BPP: usize = 4;
const FB_BYTES: usize = FB_W * FB_H * FB_BPP;

var fb_buf: [FB_BYTES]u8 = undefined;

fn fb_clear() void { @memset(&fb_buf, 0); }

fn fb_set(x: i32, y: i32, color: u32) bool {
    if (x < 0 or x >= @as(i32, FB_W) or y < 0 or y >= @as(i32, FB_H)) return false;
    const off = (@as(usize, @intCast(y)) * FB_W + @as(usize, @intCast(x))) * FB_BPP;
    fb_buf[off]     = @intCast(color & 0xFF);
    fb_buf[off + 1] = @intCast((color >> 8) & 0xFF);
    fb_buf[off + 2] = @intCast((color >> 16) & 0xFF);
    fb_buf[off + 3] = 255;
    return true;
}

fn fb_get(x: i32, y: i32) u32 {
    if (x < 0 or x >= @as(i32, FB_W) or y < 0 or y >= @as(i32, FB_H)) return 0;
    const off = (@as(usize, @intCast(y)) * FB_W + @as(usize, @intCast(x))) * FB_BPP;
    const b: u32 = fb_buf[off];
    const g: u32 = fb_buf[off + 1];
    const r: u32 = fb_buf[off + 2];
    return (r << 16) | (g << 8) | b;
}

fn draw_hline(x: i32, y: i32, len: i32, color: u32) void {
    var i: i32 = 0;
    while (i < len) : (i += 1) _ = fb_set(x + i, y, color);
}

fn draw_vline(x: i32, y: i32, len: i32, color: u32) void {
    var i: i32 = 0;
    while (i < len) : (i += 1) _ = fb_set(x, y + i, color);
}

fn count_lit() usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < FB_BYTES) : (i += FB_BPP) {
        if (fb_buf[i] != 0 or fb_buf[i + 1] != 0 or fb_buf[i + 2] != 0) n += 1;
    }
    return n;
}

pub fn main() !void {
    fb_clear();
    if (count_lit() != 0) return error.ClearFailed;

    _ = fb_set(5, 7, 0xFF0000);
    const off = (7 * FB_W + 5) * FB_BPP;
    if (fb_buf[off] != 0) return error.B;
    if (fb_buf[off + 1] != 0) return error.G;
    if (fb_buf[off + 2] != 255) return error.R;
    if (fb_buf[off + 3] != 255) return error.A;

    if (fb_get(5, 7) != 0xFF0000) return error.GetRed;

    const before = count_lit();
    _ = fb_set(-1, 5, 0x00FF00);
    _ = fb_set(16, 5, 0x00FF00);
    _ = fb_set(5, -1, 0x00FF00);
    _ = fb_set(5, 16, 0x00FF00);
    if (count_lit() != before) return error.OOB;

    if (!fb_set(3, 3, 0x0000FF)) return error.InBoundsTrue;
    if (fb_set(-5, 3, 0x0000FF)) return error.OOBFalse;

    fb_clear();
    draw_hline(2, 8, 4, 0x00FF00);
    if (count_lit() != 4) return error.HLineCount;
    if (fb_get(2, 8) != 0x00FF00) return error.HLine_2_8;
    if (fb_get(5, 8) != 0x00FF00) return error.HLine_5_8;
    if (fb_get(6, 8) != 0) return error.HLineStops;

    fb_clear();
    draw_vline(7, 2, 4, 0x0000FF);
    if (count_lit() != 4) return error.VLineCount;
    if (fb_get(7, 2) != 0x0000FF) return error.VLine_7_2;
    if (fb_get(7, 5) != 0x0000FF) return error.VLine_7_5;
    if (fb_get(7, 6) != 0) return error.VLineStops;

    fb_clear();
    draw_hline(14, 5, 4, 0xFF0000);
    if (count_lit() != 2) return error.HLineClip;

    std.debug.print("framebuffer_rendering: 18/18 ok\n", .{});
}
