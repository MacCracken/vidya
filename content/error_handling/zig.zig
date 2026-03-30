// Vidya — Error Handling in Zig
//
// Zig uses error unions (ErrorType!ResultType) — similar to Rust's Result
// but integrated into the language. The `try` keyword propagates errors,
// `catch` handles them. Error sets are first-class types with comptime
// checking. No hidden control flow, no exceptions.

const std = @import("std");
const expect = std.testing.expect;

// ── Error sets: define your error types ────────────────────────────

const ConfigError = error{
    MissingKey,
    ParseFailed,
    InvalidValue,
};

// ── Functions return error unions ──────────────────────────────────

fn readPort(config: []const u8) ConfigError!u16 {
    const prefix = "port=";
    var start: ?usize = null;

    var i: usize = 0;
    while (i + prefix.len <= config.len) : (i += 1) {
        if (std.mem.eql(u8, config[i .. i + prefix.len], prefix)) {
            start = i + prefix.len;
            break;
        }
    }

    const s = start orelse return ConfigError.MissingKey;

    // Find end of value (newline or end of string)
    var end = s;
    while (end < config.len and config[end] != '\n') : (end += 1) {}

    return std.fmt.parseInt(u16, config[s..end], 10) catch ConfigError.ParseFailed;
}

// ── Wrapping errors with context ───────────────────────────────────

fn processConfig(config: []const u8) ConfigError!u16 {
    const port = try readPort(config); // `try` propagates error
    if (port == 0) return ConfigError.InvalidValue;
    return port;
}

// ── errdefer: cleanup only on error ────────────────────────────────

fn allocateAndParse(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, input.len);
    errdefer allocator.free(buf); // freed only if subsequent code errors

    @memcpy(buf, input);
    if (buf.len == 0) return error.EmptyInput;
    return buf;
}

// ── Optional: absence without error ────────────────────────────────

fn findUser(id: u32) ?[]const u8 {
    return switch (id) {
        1 => "alice",
        2 => "bob",
        else => null,
    };
}

pub fn main() !void {
    // ── Basic error handling ───────────────────────────────────────
    const port = try readPort("host=localhost\nport=3000\n");
    try expect(port == 3000);

    // ── Catching specific errors ───────────────────────────────────
    const missing = readPort("host=localhost\n");
    try expect(missing == ConfigError.MissingKey);

    const bad_parse = readPort("port=abc\n");
    try expect(bad_parse == ConfigError.ParseFailed);

    // ── catch: handle errors inline ────────────────────────────────
    const safe_port = readPort("host=only\n") catch |err| blk: {
        try expect(err == ConfigError.MissingKey);
        break :blk 8080; // default value
    };
    try expect(safe_port == 8080);

    // ── catch with default value ───────────────────────────────────
    const default_port = readPort("nothing\n") catch 9090;
    try expect(default_port == 9090);

    // ── try: propagate errors ──────────────────────────────────────
    const processed = try processConfig("port=8080\n");
    try expect(processed == 8080);

    // ── if with error union ────────────────────────────────────────
    if (readPort("port=1234\n")) |p| {
        try expect(p == 1234);
    } else |_| {
        unreachable;
    }

    // ── errdefer ───────────────────────────────────────────────────
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = try allocateAndParse(allocator, "hello");
    defer allocator.free(result);
    try expect(std.mem.eql(u8, result, "hello"));

    // Empty input triggers error, errdefer frees the buffer
    const empty_result = allocateAndParse(allocator, "");
    try expect(empty_result == error.EmptyInput);

    // ── Optionals ──────────────────────────────────────────────────
    try expect(std.mem.eql(u8, findUser(1).?, "alice"));
    try expect(findUser(999) == null);

    // orelse: default for null
    const name = findUser(999) orelse "anonymous";
    try expect(std.mem.eql(u8, name, "anonymous"));

    // ── Error return traces (debug mode) ───────────────────────────
    // In debug builds, Zig captures error return traces automatically.
    // No extra code needed — stack traces show where errors originated.

    // ── Unreachable: assert impossible error ───────────────────────
    // Use `catch unreachable` only when you've proven the error can't happen
    const known_good = readPort("port=80\n") catch unreachable;
    try expect(known_good == 80);

    std.debug.print("All error handling examples passed.\n", .{});
}
