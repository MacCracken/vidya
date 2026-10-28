// Vidya — Pattern Matching in Zig
//
// Zig's switch is exhaustive and powerful — it works on integers, enums,
// tagged unions, and ranges. The compiler enforces handling every case.
// if-captures unwrap optionals and error unions inline. No implicit
// fallthrough.

const std = @import("std");
const expect = std.testing.expect;

// ── Tagged union: Zig's sum type ───────────────────────────────────

const Shape = union(enum) {
    circle: f64,
    rectangle: struct { width: f64, height: f64 },
    triangle: struct { base: f64, height: f64 },
};

fn area(shape: Shape) f64 {
    return switch (shape) {
        .circle => |r| std.math.pi * r * r,
        .rectangle => |rect| rect.width * rect.height,
        .triangle => |tri| 0.5 * tri.base * tri.height,
    };
}

// ── Enum with methods ──────────────────────────────────────────────

const Direction = enum {
    north,
    south,
    east,
    west,

    fn label(self: Direction) []const u8 {
        return switch (self) {
            .north => "up",
            .south => "down",
            .east => "right",
            .west => "left",
        };
    }

    fn isVertical(self: Direction) bool {
        return switch (self) {
            .north, .south => true,
            .east, .west => false,
        };
    }
};

// ── Error set matching ─────────────────────────────────────────────

const ParseError = error{ InvalidChar, Overflow, Empty };

fn classifyError(err: ParseError) []const u8 {
    return switch (err) {
        ParseError.InvalidChar => "bad character",
        ParseError.Overflow => "number too large",
        ParseError.Empty => "empty input",
    };
}

pub fn main() !void {
    // ── switch on integers ─────────────────────────────────────────
    const n: i32 = 42;
    const label: []const u8 = switch (n) {
        0 => "zero",
        1...10 => "small",
        11...100 => "medium",
        else => "large",
    };
    try expect(std.mem.eql(u8, label, "medium"));

    // ── switch on enum ─────────────────────────────────────────────
    const dir = Direction.north;
    try expect(std.mem.eql(u8, dir.label(), "up"));
    try expect(dir.isVertical());
    try expect(!Direction.east.isVertical());

    // ── Tagged union matching ──────────────────────────────────────
    const circle = Shape{ .circle = 1.0 };
    const rect = Shape{ .rectangle = .{ .width = 3.0, .height = 4.0 } };
    const tri = Shape{ .triangle = .{ .base = 6.0, .height = 4.0 } };

    try expect(@abs(area(circle) - std.math.pi) < 1e-10);
    try expect(area(rect) == 12.0);
    try expect(area(tri) == 12.0);

    // ── if-capture: unwrap optionals ───────────────────────────────
    const maybe: ?i32 = 42;
    if (maybe) |val| {
        try expect(val == 42);
    } else {
        unreachable;
    }

    const nothing: ?i32 = null;
    if (nothing) |_| {
        unreachable;
    } else {
        // null case
    }

    // ── if-capture with error unions ───────────────────────────────
    const good: ParseError!i32 = 42;
    if (good) |val| {
        try expect(val == 42);
    } else |_| {
        unreachable;
    }

    const bad: ParseError!i32 = ParseError.InvalidChar;
    if (bad) |_| {
        unreachable;
    } else |err| {
        try expect(err == ParseError.InvalidChar);
    }

    // ── switch on error set ────────────────────────────────────────
    try expect(std.mem.eql(u8, classifyError(ParseError.Empty), "empty input"));
    try expect(std.mem.eql(u8, classifyError(ParseError.Overflow), "number too large"));

    // ── while with optional capture ────────────────────────────────
    var countdown: u32 = 3;
    var total: u32 = 0;
    while (if (countdown > 0) blk: {
        countdown -= 1;
        break :blk countdown + 1;
    } else null) |val| {
        total += val;
    }
    try expect(total == 6); // 3 + 2 + 1

    // ── Comptime switch ────────────────────────────────────────────
    const T = u32;
    const size = switch (@typeInfo(T)) {
        .int => |info| info.bits,
        else => 0,
    };
    try expect(size == 32);

    // ── Boolean patterns ───────────────────────────────────────────
    const flag = true;
    const result = switch (flag) {
        true => "yes",
        false => "no",
    };
    try expect(std.mem.eql(u8, result, "yes"));

    // ── Exhaustive checking: no default needed for enums ───────────
    // The compiler requires all enum variants to be handled.
    // Adding a new variant to Direction would cause compile errors
    // everywhere it's switched on — the safety net Zig provides.

    std.debug.print("All pattern matching examples passed.\n", .{});
}
