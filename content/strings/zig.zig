// Vidya — Strings in Zig
//
// Zig strings are slices of bytes ([]const u8). There is no dedicated
// string type — a string is a pointer + length. Zig is explicit about
// encoding (assumes UTF-8 by convention), ownership, and allocation.
// String literals are comptime-known and null-terminated (*const [N:0]u8).

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    // ── Creation ────────────────────────────────────────────────────
    const literal: []const u8 = "hello";
    try expect(literal.len == 5);
    try expect(mem.eql(u8, literal, "hello"));

    // String literals are null-terminated pointers at comptime
    const c_str: [*:0]const u8 = "hello";
    try expect(c_str[0] == 'h');
    try expect(c_str[5] == 0); // null terminator

    // ── Slicing ────────────────────────────────────────────────────
    const text: []const u8 = "hello world";
    const hello = text[0..5];
    const world = text[6..11];
    try expect(mem.eql(u8, hello, "hello"));
    try expect(mem.eql(u8, world, "world"));

    // ── Concatenation (comptime only for literals) ──────────────────
    const greeting = "hello" ++ " " ++ "world";
    try expect(mem.eql(u8, greeting, "hello world"));

    // Repeat
    const dashes = "-" ** 5;
    try expect(mem.eql(u8, dashes, "-----"));

    // ── Runtime concatenation needs an allocator ───────────────────
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const joined = try std.fmt.allocPrint(allocator, "{s} {s}", .{ "hello", "world" });
    defer allocator.free(joined);
    try expect(mem.eql(u8, joined, "hello world"));

    // ── String comparison ──────────────────────────────────────────
    try expect(mem.eql(u8, "hello", "hello"));
    try expect(!mem.eql(u8, "hello", "world"));

    // Ordering
    try expect(mem.order(u8, "abc", "def") == .lt);
    try expect(mem.order(u8, "def", "abc") == .gt);
    try expect(mem.order(u8, "abc", "abc") == .eq);

    // ── Searching ──────────────────────────────────────────────────
    try expect(mem.indexOf(u8, "hello world", "world") == 6);
    try expect(mem.indexOf(u8, "hello world", "missing") == null);
    try expect(mem.startsWith(u8, "hello world", "hello"));
    try expect(mem.endsWith(u8, "hello world", "world"));

    // ── Character operations ───────────────────────────────────────
    try expect(std.ascii.isAlphabetic('a'));
    try expect(std.ascii.isDigit('5'));
    try expect(std.ascii.isUpper('A'));
    try expect(std.ascii.toLower('A') == 'a');
    try expect(std.ascii.toUpper('a') == 'A');

    // ── Splitting ──────────────────────────────────────────────────
    var iter = mem.splitSequence(u8, "a,b,c", ",");
    try expect(mem.eql(u8, iter.next().?, "a"));
    try expect(mem.eql(u8, iter.next().?, "b"));
    try expect(mem.eql(u8, iter.next().?, "c"));
    try expect(iter.next() == null);

    // ── Trimming ───────────────────────────────────────────────────
    const padded = "  hello  ";
    const trimmed = mem.trim(u8, padded, " ");
    try expect(mem.eql(u8, trimmed, "hello"));

    // ── Format to buffer (no allocation) ───────────────────────────
    var buf: [64]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, "value: {d}", .{42});
    try expect(mem.eql(u8, formatted, "value: 42"));

    // ── UTF-8 iteration ────────────────────────────────────────────
    const cafe: []const u8 = "café";
    try expect(cafe.len == 5); // 5 bytes (é is 2 bytes UTF-8)

    var utf8_len: usize = 0;
    var utf8_iter = std.unicode.Utf8View.initUnchecked(cafe).iterator();
    while (utf8_iter.nextCodepoint()) |_| {
        utf8_len += 1;
    }
    try expect(utf8_len == 4); // 4 codepoints

    // ── Number to string and back ──────────────────────────────────
    const num_str = try std.fmt.allocPrint(allocator, "{d}", .{42});
    defer allocator.free(num_str);
    try expect(mem.eql(u8, num_str, "42"));

    const parsed = try std.fmt.parseInt(i32, "42", 10);
    try expect(parsed == 42);

    std.debug.print("All string examples passed.\n", .{});
}
