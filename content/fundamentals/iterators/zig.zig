// Vidya — Iterators in Zig
//
// Zig iterators are a convention, not a language feature: a struct with
// a next() method returning ?T. For-loops work with slices and ranges.
// Comptime iteration enables metaprogramming. No closures — use
// struct methods with captured state instead.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

// ── Custom iterator: struct with next() ────────────────────────────

const Countdown = struct {
    remaining: u32,

    fn next(self: *Countdown) ?u32 {
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        return self.remaining + 1;
    }
};

// ── Range iterator ─────────────────────────────────────────────────

const Range = struct {
    current: usize,
    end: usize,

    fn init(start: usize, end: usize) Range {
        return .{ .current = start, .end = end };
    }

    fn next(self: *Range) ?usize {
        if (self.current >= self.end) return null;
        const val = self.current;
        self.current += 1;
        return val;
    }
};

pub fn main() !void {
    // ── For loop over slices ───────────────────────────────────────
    const numbers = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var sum: i32 = 0;
    for (numbers) |n| {
        sum += n;
    }
    try expect(sum == 55);

    // ── For with index ─────────────────────────────────────────────
    var index_sum: usize = 0;
    for (numbers, 0..) |_, i| {
        index_sum += i;
    }
    try expect(index_sum == 45); // 0+1+...+9

    // ── Filter: count evens ────────────────────────────────────────
    var even_count: u32 = 0;
    for (numbers) |n| {
        if (@mod(n, 2) == 0) {
            even_count += 1;
        }
    }
    try expect(even_count == 5);

    // ── Map: square into buffer ────────────────────────────────────
    var squares: [10]i32 = undefined;
    for (numbers, 0..) |n, i| {
        squares[i] = n * n;
    }
    try expect(squares[0] == 1);
    try expect(squares[4] == 25);
    try expect(squares[9] == 100);

    // ── Fold: product of first 5 ───────────────────────────────────
    var product: i32 = 1;
    for (numbers[0..5]) |n| {
        product *= n;
    }
    try expect(product == 120);

    // ── Find first > 7 ────────────────────────────────────────────
    var found: ?i32 = null;
    for (numbers) |n| {
        if (n > 7) {
            found = n;
            break;
        }
    }
    try expect(found.? == 8);

    // ── Custom iterator usage ──────────────────────────────────────
    var cd = Countdown{ .remaining = 3 };
    try expect(cd.next().? == 3);
    try expect(cd.next().? == 2);
    try expect(cd.next().? == 1);
    try expect(cd.next() == null);

    // Collect from iterator
    var range = Range.init(0, 5);
    var range_sum: usize = 0;
    while (range.next()) |val| {
        range_sum += val;
    }
    try expect(range_sum == 10); // 0+1+2+3+4

    // ── While loops ────────────────────────────────────────────────
    var i: u32 = 0;
    var while_sum: u32 = 0;
    while (i < 10) : (i += 1) {
        while_sum += i;
    }
    try expect(while_sum == 45);

    // ── mem.splitSequence: string tokenizer ────────────────────────
    var parts = mem.splitSequence(u8, "a,b,c,d", ",");
    var part_count: u32 = 0;
    while (parts.next()) |_| {
        part_count += 1;
    }
    try expect(part_count == 4);

    // ── Sentinel-terminated iteration ──────────────────────────────
    // Zig supports sentinel-terminated types: [*:0]const u8
    const c_str: [*:0]const u8 = "hello";
    var c_len: usize = 0;
    while (c_str[c_len] != 0) : (c_len += 1) {}
    try expect(c_len == 5);

    // ── Comptime iteration ─────────────────────────────────────────
    // Loop at compile time — generates code for each iteration
    const types = .{ u8, u16, u32, u64 };
    var total_size: usize = 0;
    inline for (types) |T| {
        total_size += @sizeOf(T);
    }
    try expect(total_size == 1 + 2 + 4 + 8);

    // ── Two slices in parallel ─────────────────────────────────────
    const a = [_]i32{ 1, 2, 3 };
    const b = [_]i32{ 10, 20, 30 };
    var dot: i32 = 0;
    for (a, b) |x, y| {
        dot += x * y;
    }
    try expect(dot == 140); // 1*10 + 2*20 + 3*30

    std.debug.print("All iterator examples passed.\n", .{});
}
