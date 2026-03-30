// Vidya — Security Practices in Zig
//
// Zig's safety features — bounds checking, no undefined behavior in
// safe mode, explicit error handling — prevent many C-style bugs.
// Security still requires: constant-time comparison, secret zeroing,
// input validation, and safe integer arithmetic.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    try testInputValidation();
    try testConstantTimeComparison();
    try testSecureZeroing();
    try testBoundsChecking();
    try testIntegerOverflow();
    try testPathTraversalPrevention();
    try testSecureRandom();
    try testAllowlistValidation();

    std.debug.print("All security examples passed.\n", .{});
}

// ── Input validation at the boundary ──────────────────────────────────
fn validateUsername(input: []const u8) ![]const u8 {
    if (input.len == 0) return error.EmptyUsername;
    if (input.len > 32) return error.UsernameTooLong;

    for (input) |c| {
        const valid = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            (c == '_');
        if (!valid) return error.InvalidCharacter;
    }
    return input;
}

fn testInputValidation() !void {
    const valid = try validateUsername("alice_42");
    try expect(mem.eql(u8, valid, "alice_42"));

    // These should all fail
    try expect(validateUsername("") == error.EmptyUsername);
    try expect(validateUsername("a" ** 33) == error.UsernameTooLong);
    try expect(validateUsername("alice; DROP") == error.InvalidCharacter);
    try expect(validateUsername("../etc") == error.InvalidCharacter);
    try expect(validateUsername("<script>") == error.InvalidCharacter);
}

// ── Constant-time comparison ──────────────────────────────────────────
// Zig's std.crypto.utils provides constant-time operations
fn constantTimeEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    var diff: u8 = 0;
    for (a, b) |x, y| {
        diff |= x ^ y;
    }
    return diff == 0;
}

fn testConstantTimeComparison() !void {
    const secret = "super_secret_token_2024";
    const correct = "super_secret_token_2024";
    const wrong = "super_secret_token_2025";

    try expect(constantTimeEq(secret, correct));
    try expect(!constantTimeEq(secret, wrong));
    try expect(!constantTimeEq(secret, "short"));
    try expect(constantTimeEq("", ""));

    // Zig std provides std.crypto.timing_safe.eql for fixed-size arrays
    const a: [4]u8 = "test".*;
    const b: [4]u8 = "test".*;
    const c: [4]u8 = "tess".*;
    try expect(std.crypto.timing_safe.eql([4]u8, a, b));
    try expect(!std.crypto.timing_safe.eql([4]u8, a, c));
}

// ── Secure memory zeroing ─────────────────────────────────────────────
fn testSecureZeroing() !void {
    var secret: [16]u8 = "hunter2_password".*;
    try expect(mem.eql(u8, &secret, "hunter2_password"));

    // Zig provides secureZero which won't be optimized away
    std.crypto.secureZero(u8, &secret);

    // Verify all bytes are zero
    for (secret) |byte| {
        try expect(byte == 0);
    }
}

// ── Bounds checking (Zig's built-in safety) ───────────────────────────
fn safeCopy(dst: []u8, src: []const u8) !usize {
    if (src.len > dst.len) return error.BufferTooSmall;
    @memcpy(dst[0..src.len], src);
    return src.len;
}

fn testBoundsChecking() !void {
    // Safe copy with bounds checking
    var buf: [8]u8 = undefined;
    const n = try safeCopy(&buf, "hello");
    try expect(n == 5);
    try expect(mem.eql(u8, buf[0..5], "hello"));

    // Overflow rejected
    try expect(safeCopy(&buf, "this is way too long for the buffer") == error.BufferTooSmall);

    // Edge: exactly fits
    const n2 = try safeCopy(&buf, "12345678");
    try expect(n2 == 8);
}

// ── Integer overflow safety ───────────────────────────────────────────
fn safeMultiply(a: u32, b: u32) !u32 {
    return std.math.mul(u32, a, b) catch error.IntegerOverflow;
}

fn safeAdd(a: u32, b: u32) !u32 {
    return std.math.add(u32, a, b) catch error.IntegerOverflow;
}

fn testIntegerOverflow() !void {
    // Safe arithmetic
    try expect(try safeMultiply(1000, 1000) == 1_000_000);
    try expect(try safeAdd(100, 200) == 300);

    // Overflow detected (not wrapped silently like in C)
    try expect(safeMultiply(65536, 65536) == error.IntegerOverflow);
    try expect(safeAdd(std.math.maxInt(u32), 1) == error.IntegerOverflow);

    // Buffer size calculation: width * height * bpp
    const width: u32 = 65536;
    const height: u32 = 65536;
    const pixels = safeMultiply(width, height);
    try expect(pixels == error.IntegerOverflow);
}

// ── Path traversal prevention ─────────────────────────────────────────
fn pathIsSafe(user_input: []const u8) bool {
    // Reject ".." components
    if (mem.indexOf(u8, user_input, "..") != null) return false;
    // Reject absolute paths
    if (user_input.len > 0 and user_input[0] == '/') return false;
    return true;
}

fn testPathTraversalPrevention() !void {
    try expect(pathIsSafe("photo.jpg"));
    try expect(pathIsSafe("subdir/file.txt"));
    try expect(!pathIsSafe("../../etc/passwd"));
    try expect(!pathIsSafe("../secret"));
    try expect(!pathIsSafe("/etc/passwd"));
    try expect(!pathIsSafe("normal/../../escape"));
}

// ── Secure random generation ──────────────────────────────────────────
fn testSecureRandom() !void {
    // Zig's std.crypto.random uses OS entropy (getrandom/urandom)
    var token1: [32]u8 = undefined;
    var token2: [32]u8 = undefined;
    std.crypto.random.bytes(&token1);
    std.crypto.random.bytes(&token2);

    // Two random tokens should differ
    try expect(!mem.eql(u8, &token1, &token2));

    // Should not be all zeros
    var all_zero = true;
    for (token1) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try expect(!all_zero);
}

// ── Allowlist validation ──────────────────────────────────────────────
fn isAlphanumeric(input: []const u8, max_len: usize) bool {
    if (input.len == 0 or input.len > max_len) return false;
    for (input) |c| {
        const valid = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            (c == ' ') or (c == '.') or (c == ',') or
            (c == '!') or (c == '?');
        if (!valid) return false;
    }
    return true;
}

fn testAllowlistValidation() !void {
    try expect(isAlphanumeric("Hello, world!", 200));
    try expect(isAlphanumeric("Test 123.", 200));
    try expect(!isAlphanumeric("", 200));
    try expect(!isAlphanumeric("<script>", 200));
    try expect(!isAlphanumeric("a" ** 201, 200));
}
