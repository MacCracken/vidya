// Vidya — Testing in Zig
//
// Zig has built-in testing: `test "name" { ... }` blocks are compiled
// and run by `zig test`. std.testing provides expect, expectEqual, etc.
// Tests are first-class — they live alongside the code, run in parallel,
// and support comptime testing. This file uses pub fn main for the
// validation runner pattern.

const std = @import("std");
const expect = std.testing.expect;

// ── Code under test ────────────────────────────────────────────────

fn parseKV(line: []const u8) !struct { key: []const u8, value: []const u8 } {
    const eq_pos = std.mem.indexOf(u8, line, "=") orelse return error.NoEquals;

    const key = std.mem.trim(u8, line[0..eq_pos], " ");
    if (key.len == 0) return error.EmptyKey;

    const value = std.mem.trim(u8, line[eq_pos + 1 ..], " ");
    return .{ .key = key, .value = value };
}

fn clamp(value: i32, min_val: i32, max_val: i32) i32 {
    std.debug.assert(min_val <= max_val);
    if (value < min_val) return min_val;
    if (value > max_val) return max_val;
    return value;
}

const Counter = struct {
    count: u32 = 0,
    max: u32,

    fn increment(self: *Counter) bool {
        if (self.count < self.max) {
            self.count += 1;
            return true;
        }
        return false;
    }
};

// ── Test runner ────────────────────────────────────────────────────

var tests_run: u32 = 0;
var tests_passed: u32 = 0;

fn check(condition: bool, comptime name: []const u8) void {
    tests_run += 1;
    if (condition) {
        tests_passed += 1;
    } else {
        std.debug.print("  FAIL: {s}\n", .{name});
    }
}

fn checkEq(comptime T: type, got: T, expected: T, comptime name: []const u8) void {
    tests_run += 1;
    if (got == expected) {
        tests_passed += 1;
    } else {
        std.debug.print("  FAIL: {s}: got {}, expected {}\n", .{ name, got, expected });
    }
}

fn checkStr(got: []const u8, expected: []const u8, comptime name: []const u8) void {
    tests_run += 1;
    if (std.mem.eql(u8, got, expected)) {
        tests_passed += 1;
    } else {
        std.debug.print("  FAIL: {s}: got '{s}', expected '{s}'\n", .{ name, got, expected });
    }
}

pub fn main() !void {
    // ── parseKV tests ──────────────────────────────────────────────
    {
        const result = try parseKV("host=localhost");
        checkStr(result.key, "host", "parse valid key");
        checkStr(result.value, "localhost", "parse valid value");
    }

    {
        const result = try parseKV("  port = 3000  ");
        checkStr(result.key, "port", "parse trimmed key");
        checkStr(result.value, "3000", "parse trimmed value");
    }

    {
        const result = try parseKV("key=");
        checkStr(result.key, "key", "parse empty value key");
        checkStr(result.value, "", "parse empty value");
    }

    // Error cases
    {
        const no_eq = parseKV("no_equals");
        check(no_eq == error.NoEquals, "missing equals error");
    }

    {
        const empty_key = parseKV("=value");
        check(empty_key == error.EmptyKey, "empty key error");
    }

    // ── clamp table-driven tests ───────────────────────────────────
    const ClampCase = struct { value: i32, min: i32, max: i32, expected: i32 };
    const clamp_cases = [_]ClampCase{
        .{ .value = 5, .min = 0, .max = 10, .expected = 5 },
        .{ .value = -1, .min = 0, .max = 10, .expected = 0 },
        .{ .value = 100, .min = 0, .max = 10, .expected = 10 },
        .{ .value = 0, .min = 0, .max = 10, .expected = 0 },
        .{ .value = 10, .min = 0, .max = 10, .expected = 10 },
        .{ .value = 5, .min = 5, .max = 5, .expected = 5 },
    };

    for (clamp_cases) |tc| {
        checkEq(i32, clamp(tc.value, tc.min, tc.max), tc.expected, "clamp case");
    }

    // ── Counter tests ──────────────────────────────────────────────
    {
        var c = Counter{ .max = 3 };
        checkEq(u32, c.count, 0, "counter initial");
        check(c.increment(), "counter inc 1");
        check(c.increment(), "counter inc 2");
        check(c.increment(), "counter inc 3");
        check(!c.increment(), "counter at max");
        checkEq(u32, c.count, 3, "counter final");
    }

    {
        var c = Counter{ .max = 0 };
        check(!c.increment(), "zero max inc");
        checkEq(u32, c.count, 0, "zero max value");
    }

    // ── Comptime tests ─────────────────────────────────────────────
    // These run at compile time — failure is a compile error
    comptime {
        std.debug.assert(clamp(5, 0, 10) == 5);
        std.debug.assert(clamp(-1, 0, 10) == 0);
        std.debug.assert(clamp(100, 0, 10) == 10);
    }

    // ── Report ─────────────────────────────────────────────────────
    if (tests_passed != tests_run) {
        std.debug.print("FAILED: {d}/{d} passed\n", .{ tests_passed, tests_run });
        std.process.exit(1);
    }

    std.debug.print("All testing examples passed.\n", .{});
}
