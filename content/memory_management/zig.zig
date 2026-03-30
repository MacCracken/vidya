// Vidya — Memory Management in Zig
//
// Zig has no hidden allocations and no garbage collector. Every
// allocation requires an explicit allocator parameter. defer/errdefer
// provide deterministic cleanup. Slices carry length — no buffer
// overflows from missing size info.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    // ── Allocators: explicit, swappable ────────────────────────────
    // Every allocation takes an allocator — no global heap
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // detect leaks in debug mode
    const allocator = gpa.allocator();

    // ── Heap allocation ────────────────────────────────────────────
    const buf = try allocator.alloc(u8, 64);
    defer allocator.free(buf); // freed when scope exits
    @memset(buf, 0);
    try expect(buf.len == 64);
    try expect(buf[0] == 0);

    // ── Stack allocation (arrays) ──────────────────────────────────
    var stack_buf: [256]u8 = undefined;
    @memset(&stack_buf, 0);
    try expect(stack_buf[100] == 0);
    // No free needed — stack memory is automatic

    // ── Slices: pointer + length (no buffer overflow) ──────────────
    const data = [_]i32{ 10, 20, 30, 40, 50 };
    const slice: []const i32 = data[1..4]; // [20, 30, 40]
    try expect(slice.len == 3);
    try expect(slice[0] == 20);
    try expect(slice[2] == 40);
    // slice[3] would be a runtime error in safe mode

    // ── defer: deterministic cleanup ───────────────────────────────
    {
        const inner = try allocator.alloc(u8, 32);
        defer allocator.free(inner);
        inner[0] = 42;
        try expect(inner[0] == 42);
        // inner freed here at end of scope
    }

    // ── errdefer: cleanup only on error ────────────────────────────
    // See error_handling topic for full example

    // ── ArrayList: dynamic array with allocator ────────────────────
    var list: std.ArrayListUnmanaged(i32) = .empty;
    defer list.deinit(allocator);

    try list.append(allocator, 1);
    try list.append(allocator, 2);
    try list.append(allocator, 3);
    try expect(list.items.len == 3);
    try expect(list.items[0] == 1);

    try list.ensureTotalCapacity(allocator, 100);
    try expect(list.capacity >= 100);

    // ── HashMap with allocator ─────────────────────────────────────
    var map = std.StringHashMap(i32).init(allocator);
    defer map.deinit();

    try map.put("x", 10);
    try map.put("y", 20);
    try expect(map.get("x").? == 10);
    try expect(map.count() == 2);

    // ── FixedBufferAllocator: no heap, fixed memory ────────────────
    var fixed_buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fixed_buf);
    const fixed_alloc = fba.allocator();

    const small = try fixed_alloc.alloc(u8, 64);
    try expect(small.len == 64);
    fixed_alloc.free(small);

    // ── ArenaAllocator: batch lifetime ─────────────────────────────
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit(); // frees everything at once

    const a1 = try arena.allocator().alloc(u8, 100);
    const a2 = try arena.allocator().alloc(u8, 200);
    _ = a1;
    _ = a2;
    // No individual frees needed — arena.deinit() frees all

    // ── Sentinel pointers: null-terminated compatibility ────────────
    const c_str: [:0]const u8 = "hello";
    try expect(c_str.len == 5);
    try expect(c_str[5] == 0); // sentinel accessible

    // ── @alignOf and alignment ─────────────────────────────────────
    try expect(@alignOf(u8) == 1);
    try expect(@alignOf(u32) == 4);
    try expect(@alignOf(u64) == 8);

    // ── @sizeOf: no hidden padding surprises ───────────────────────
    const Point = struct { x: i32, y: i32 };
    try expect(@sizeOf(Point) == 8);

    // ── Comptime allocation ────────────────────────────────────────
    // Comptime values live in the binary, not the heap
    const comptime_arr = comptime blk: {
        var arr: [5]i32 = undefined;
        for (0..5) |i| {
            arr[i] = @as(i32, @intCast(i)) * @as(i32, @intCast(i));
        }
        break :blk arr;
    };
    try expect(comptime_arr[4] == 16); // computed at compile time

    // ── Optional types: no null pointer derefs ─────────────────────
    var maybe: ?*const i32 = null;
    try expect(maybe == null);
    const val: i32 = 42;
    maybe = &val;
    try expect(maybe.?.* == 42);

    std.debug.print("All memory management examples passed.\n", .{});
}
