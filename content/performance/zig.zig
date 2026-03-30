// Vidya — Performance in Zig
//
// Zig gives you C-level performance with safety in debug mode. Key
// levers: comptime evaluation, no hidden allocations, SIMD vectors,
// cache-aligned data, and the ability to drop to inline assembly.
// Release modes strip safety checks for maximum speed.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Comptime evaluation: zero runtime cost ─────────────────────
    // Compute at compile time — result is embedded in the binary
    const table = comptime blk: {
        var t: [256]u8 = undefined;
        for (0..256) |i| {
            t[i] = @as(u8, @intCast(i)) *% 2;
        }
        break :blk t;
    };
    try expect(table[10] == 20);
    try expect(table[128] == 0); // wrapping multiply

    // ── Pre-allocated ArrayList ────────────────────────────────────
    var list: std.ArrayListUnmanaged(i32) = .empty;
    defer list.deinit(allocator);

    try list.ensureTotalCapacity(allocator, 10000);
    for (0..10000) |i| {
        try list.append(allocator, @as(i32, @intCast(i)));
    }
    try expect(list.items.len == 10000);

    // ── Stack arrays: no allocation ────────────────────────────────
    var stack_buf: [1024]i32 = undefined;
    for (&stack_buf, 0..) |*v, i| {
        v.* = @as(i32, @intCast(i));
    }
    var stack_sum: i64 = 0;
    for (stack_buf) |v| {
        stack_sum += v;
    }
    try expect(stack_sum == 523776); // sum 0..1023

    // ── Sentinel slices: avoid bounds checks ───────────────────────
    // Sentinel-terminated slices let the compiler optimize loops
    const data: [:0]const u8 = "hello world";
    try expect(data.len == 11);
    try expect(data[11] == 0); // sentinel

    // ── @Vector: SIMD operations ───────────────────────────────────
    // Zig vectors map to hardware SIMD (SSE, AVX, NEON)
    const Vec4 = @Vector(4, f32);
    const a: Vec4 = .{ 1.0, 2.0, 3.0, 4.0 };
    const b: Vec4 = .{ 5.0, 6.0, 7.0, 8.0 };
    const c = a + b; // SIMD add: all 4 elements at once
    try expect(c[0] == 6.0);
    try expect(c[3] == 12.0);

    // SIMD multiply
    const product = a * b;
    try expect(product[0] == 5.0);
    try expect(product[3] == 32.0);

    // Reduce: sum all elements
    const vec_sum = @reduce(.Add, a);
    try expect(vec_sum == 10.0); // 1+2+3+4

    // ── @prefetch: cache hint ──────────────────────────────────────
    const big_array = try allocator.alloc(u64, 10000);
    defer allocator.free(big_array);

    @memset(big_array, 0);
    // Prefetch upcoming cache lines during iteration
    var total: u64 = 0;
    for (0..big_array.len) |i| {
        if (i + 64 < big_array.len) {
            @prefetch(&big_array[i + 64], .{ .rw = .read, .locality = 3, .cache = .data });
        }
        big_array[i] = @as(u64, @intCast(i));
        total += big_array[i];
    }
    try expect(total == 49995000); // sum 0..9999

    // ── Packed structs: exact memory layout ─────────────────────────
    const Pixel = packed struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };
    try expect(@sizeOf(Pixel) == 4); // exactly 4 bytes, no padding

    // ── Aligned allocation ─────────────────────────────────────────
    // Align to cache line (64 bytes) for avoiding false sharing
    const aligned = try allocator.alignedAlloc(u8, .@"64", 256);
    defer allocator.free(aligned);
    try expect(@intFromPtr(aligned.ptr) % 64 == 0);

    // ── Branchless with builtins ───────────────────────────────────
    // @min/@max are branchless
    try expect(@min(@as(i32, 42), @as(i32, 99)) == 42);
    try expect(@max(@as(i32, 42), @as(i32, 99)) == 99);

    // ── @popCount, @clz, @ctz: hardware bit operations ─────────────
    const bits: u32 = 0b10110100;
    try expect(@popCount(bits) == 4); // 4 bits set
    try expect(@clz(bits) == 24); // 24 leading zeros in u32
    try expect(@ctz(bits) == 2); // 2 trailing zeros

    // ── Overflow detection ─────────────────────────────────────────
    // Zig detects overflow in debug mode. Use wrapping ops for intentional wrap.
    const x: u8 = 200;
    const y: u8 = 100;
    const wrapped = x +% y; // wrapping add: 200+100 = 44 (mod 256)
    try expect(wrapped == 44);

    // Saturating arithmetic
    const saturated = x +| y; // saturating add: min(300, 255) = 255
    try expect(saturated == 255);

    std.debug.print("All performance examples passed.\n", .{});
}
