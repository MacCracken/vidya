// Vidya — Sprite Rendering in Zig
//
// Software sprite blitting onto a flat 8-bit palette framebuffer.
// Zig's `[]u8` is a slice (pointer + length) over a contiguous byte
// region — same wire format as a C `uint8_t*` and a Go `[]byte`. We
// stash the framebuffer in a module-level `var` so functions can
// borrow it as `*[FB_SIZE]u8` without dynamic allocation; clipping
// and indexing match the C/Cyrius reference byte-for-byte.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const SCREEN_W: i32 = 320;
const SCREEN_H: i32 = 240;
const FB_SIZE: usize = 320 * 240; // 76800
const COLOR_KEY: u8 = 0;
const FX_SHIFT: u5 = 16;

var fb: [FB_SIZE]u8 = [_]u8{0} ** FB_SIZE;

fn fbClear(color: u8) void {
    @memset(&fb, color);
}

fn fbGet(x: i32, y: i32) u8 {
    if (x < 0 or x >= SCREEN_W or y < 0 or y >= SCREEN_H) return 0;
    const idx: usize = @intCast(y * SCREEN_W + x);
    return fb[idx];
}

fn fbSet(x: i32, y: i32, color: u8) void {
    if (x < 0 or x >= SCREEN_W or y < 0 or y >= SCREEN_H) return;
    const idx: usize = @intCast(y * SCREEN_W + x);
    fb[idx] = color;
}

const Sprite = struct {
    data: []const u8,
    width: i32,
    height: i32,
};

fn blit(sprite: *const Sprite, dst_x_in: i32, dst_y_in: i32) void {
    var dst_x = dst_x_in;
    var dst_y = dst_y_in;
    var start_x: i32 = 0;
    var start_y: i32 = 0;
    var end_x: i32 = sprite.width;
    var end_y: i32 = sprite.height;

    if (dst_x < 0) {
        start_x = -dst_x;
        dst_x = 0;
    }
    if (dst_y < 0) {
        start_y = -dst_y;
        dst_y = 0;
    }
    if (dst_x + (end_x - start_x) > SCREEN_W) {
        end_x = start_x + (SCREEN_W - dst_x);
    }
    if (dst_y + (end_y - start_y) > SCREEN_H) {
        end_y = start_y + (SCREEN_H - dst_y);
    }

    var sy: i32 = start_y;
    while (sy < end_y) : (sy += 1) {
        var sx: i32 = start_x;
        while (sx < end_x) : (sx += 1) {
            const sidx: usize = @intCast(sy * sprite.width + sx);
            const pixel = sprite.data[sidx];
            if (pixel != COLOR_KEY) {
                const dx = dst_x + (sx - start_x);
                const dy = dst_y + (sy - start_y);
                const didx: usize = @intCast(dy * SCREEN_W + dx);
                fb[didx] = pixel;
            }
        }
    }
}

fn blitScaled(sprite: *const Sprite, dst_x: i32, dst_y: i32, dst_w: i32, dst_h: i32) void {
    if (dst_w <= 0 or dst_h <= 0) return;
    const step_x: i32 = @divTrunc(sprite.width << FX_SHIFT, dst_w);
    const step_y: i32 = @divTrunc(sprite.height << FX_SHIFT, dst_h);

    var src_y: i32 = 0;
    var dy: i32 = 0;
    while (dy < dst_h) : (dy += 1) {
        const screen_y = dst_y + dy;
        if (screen_y >= 0 and screen_y < SCREEN_H) {
            const row_base: i32 = (src_y >> FX_SHIFT) * sprite.width;
            var src_x: i32 = 0;
            var dx: i32 = 0;
            while (dx < dst_w) : (dx += 1) {
                const screen_x = dst_x + dx;
                if (screen_x >= 0 and screen_x < SCREEN_W) {
                    const sidx: usize = @intCast(row_base + (src_x >> FX_SHIFT));
                    const pixel = sprite.data[sidx];
                    if (pixel != COLOR_KEY) {
                        const didx: usize = @intCast(screen_y * SCREEN_W + screen_x);
                        fb[didx] = pixel;
                    }
                }
                src_x += step_x;
            }
        }
        src_y += step_y;
    }
}

pub fn main() !void {
    const sprite_data = [_]u8{
        0, 1, 1, 0,
        1, 2, 2, 1,
        1, 2, 2, 1,
        0, 1, 1, 0,
    };
    const sprite = Sprite{ .data = &sprite_data, .width = 4, .height = 4 };

    // clear
    fbClear(42);
    assert(fbGet(100, 100) == 42);
    assert(fbGet(0, 0) == 42);
    assert(fbGet(319, 239) == 42);

    // blit opaque
    fbClear(0);
    blit(&sprite, 10, 10);
    assert(fbGet(11, 11) == 2);
    assert(fbGet(12, 11) == 2);

    // transparency
    fbClear(99);
    blit(&sprite, 10, 10);
    assert(fbGet(10, 10) == 99);
    assert(fbGet(13, 10) == 99);
    assert(fbGet(11, 10) == 1);

    // clipping right
    fbClear(0);
    blit(&sprite, 318, 0);
    assert(fbGet(319, 1) == 2);
    assert(fbGet(318, 0) == 0);

    // clipping left
    fbClear(0);
    blit(&sprite, -2, 0);
    assert(fbGet(0, 1) == 2);

    // scaled blit
    fbClear(0);
    blitScaled(&sprite, 20, 20, 8, 8);
    assert(fbGet(22, 22) == 2);
    assert(fbGet(23, 23) == 2);

    // depth sort
    fbClear(0);
    blit(&sprite, 50, 50);
    assert(fbGet(51, 51) == 2);
    fbSet(51, 51, 7);
    assert(fbGet(51, 51) == 7);

    // scaled shrink
    fbClear(0);
    blitScaled(&sprite, 100, 100, 2, 2);
    const any_drawn = fbGet(100, 100) != 0 or
        fbGet(101, 100) != 0 or
        fbGet(100, 101) != 0 or
        fbGet(101, 101) != 0;
    assert(any_drawn);

    print("All sprite_rendering examples passed.\n", .{});
}
