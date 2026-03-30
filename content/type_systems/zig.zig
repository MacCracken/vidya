// Vidya — Type Systems in Zig
//
// Zig has a strong static type system with comptime generics. Types
// are first-class values at compile time. No inheritance — use
// composition and interfaces via duck-typed comptime functions.
// Every type decision is explicit: no implicit conversions.

const std = @import("std");
const expect = std.testing.expect;

// ── Structs ────────────────────────────────────────────────────────

const Point = struct {
    x: f64,
    y: f64,

    fn distance(self: Point) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    fn add(self: Point, other: Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
};

// ── Enums with payloads (tagged unions) ────────────────────────────

const Value = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    none,
};

fn isNumeric(v: Value) bool {
    return switch (v) {
        .int, .float => true,
        .string, .none => false,
    };
}

// ── Comptime generics ──────────────────────────────────────────────

fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

fn sum(comptime T: type, items: []const T) T {
    var total: T = 0;
    for (items) |item| {
        total += item;
    }
    return total;
}

// ── Generic data structure ─────────────────────────────────────────

fn Stack(comptime T: type) type {
    return struct {
        items: std.ArrayListUnmanaged(T) = .empty,
        allocator: std.mem.Allocator,

        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        fn push(self: *Self, value: T) !void {
            try self.items.append(self.allocator, value);
        }

        fn pop(self: *Self) ?T {
            return self.items.pop();
        }

        fn len(self: *const Self) usize {
            return self.items.items.len;
        }
    };
}

// ── Newtypes via distinct structs ──────────────────────────────────

const Meters = struct {
    value: f64,

    fn init(v: f64) Meters {
        return .{ .value = v };
    }
};

const Seconds = struct {
    value: f64,

    fn init(v: f64) Seconds {
        return .{ .value = v };
    }
};

fn speed(distance: Meters, time: Seconds) f64 {
    return distance.value / time.value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Struct usage ───────────────────────────────────────────────
    const p1 = Point{ .x = 3.0, .y = 4.0 };
    try expect(p1.distance() == 5.0);

    const p2 = Point{ .x = 1.0, .y = 1.0 };
    const p3 = p1.add(p2);
    try expect(p3.x == 4.0);

    // ── Tagged union ───────────────────────────────────────────────
    const v1 = Value{ .int = 42 };
    const v2 = Value{ .string = "hello" };
    const v3 = Value.none;
    try expect(isNumeric(v1));
    try expect(!isNumeric(v2));
    try expect(!isNumeric(v3));

    // ── Comptime generics ──────────────────────────────────────────
    try expect(max(i32, 3, 7) == 7);
    try expect(max(f64, 3.14, 2.71) == 3.14);

    const ints = [_]i32{ 1, 2, 3, 4, 5 };
    try expect(sum(i32, &ints) == 15);

    const floats = [_]f64{ 1.0, 2.0, 3.0 };
    try expect(sum(f64, &floats) == 6.0);

    // ── Generic stack ──────────────────────────────────────────────
    var stack = Stack(i32).init(allocator);
    defer stack.deinit();

    try stack.push(1);
    try stack.push(2);
    try stack.push(3);
    try expect(stack.len() == 3);
    try expect(stack.pop().? == 3);
    try expect(stack.len() == 2);

    // ── Newtypes (type safety) ─────────────────────────────────────
    const d = Meters.init(100.0);
    const t = Seconds.init(9.58);
    const v = speed(d, t);
    try expect(v > 10.0);
    // speed(t, d); // ← compile error! Seconds is not Meters

    // ── @typeInfo: reflect on types at comptime ────────────────────
    const info = @typeInfo(Point);
    switch (info) {
        .@"struct" => |s| {
            try expect(s.fields.len == 2);
        },
        else => unreachable,
    }

    // ── Comptime type construction ─────────────────────────────────
    // Types are values at comptime — you can compute them
    const IntStack = Stack(i32);
    const FloatStack = Stack(f64);
    try expect(@sizeOf(IntStack) > 0);
    try expect(@sizeOf(FloatStack) > 0);

    // ── Optional types ─────────────────────────────────────────────
    var maybe: ?i32 = null;
    try expect(maybe == null);
    maybe = 42;
    try expect(maybe.? == 42);

    // ── Error unions ───────────────────────────────────────────────
    const ParseError = error{BadInput};
    const result: ParseError!i32 = 42;
    try expect((try result) == 42);

    // ── Explicit casting ───────────────────────────────────────────
    // Zig never converts implicitly between numeric types
    const big: u32 = 1000;
    const small: u16 = @intCast(big); // explicit, checked
    try expect(small == 1000);

    const float_val: f64 = 3.14;
    const int_val: i32 = @intFromFloat(float_val); // explicit truncation
    try expect(int_val == 3);

    // ── Packed structs: exact layout control ───────────────────────
    const Flags = packed struct {
        read: bool,
        write: bool,
        execute: bool,
        _padding: u5 = 0,
    };
    try expect(@sizeOf(Flags) == 1); // exactly 1 byte

    const rwx = Flags{ .read = true, .write = true, .execute = false };
    try expect(rwx.read);
    try expect(rwx.write);
    try expect(!rwx.execute);

    std.debug.print("All type system examples passed.\n", .{});
}
