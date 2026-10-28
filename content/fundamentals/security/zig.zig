// Vidya — Security Practices in Zig
//
// Zig's safety features — bounds checking, overflow / null / bad-cast
// traps in safe modes, explicit error handling — prevent many C-style
// bugs. Safe mode is not "no undefined behavior": use-after-free (a read
// after free goes unnoticed), data races, and slices into a stack frame
// that has returned (only a direct `return &local` is a compile error)
// are still not caught.
// Security still requires: constant-time comparison, secret zeroing,
// input validation, and safe integer arithmetic.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const linux = std.os.linux;

pub fn main() !void {
    // Zig 0.16 moved randomness behind the std.Io interface — construct a
    // Threaded I/O instance to obtain a CSPRNG seeded from OS entropy.
    var threaded: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try testInputValidation();
    try testConstantTimeComparison();
    try testSecureZeroing();
    try testBoundsChecking();
    try testIntegerOverflow();
    try testPathTraversalPrevention(io);
    try testSecureRandom(io);
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
    try expect(validateUsername(&@as([33]u8, @splat('a'))) == error.UsernameTooLong);
    try expect(validateUsername("alice; DROP") == error.InvalidCharacter);
    try expect(validateUsername("../etc") == error.InvalidCharacter);
    try expect(validateUsername("<script>") == error.InvalidCharacter);
}

// ── Constant-time comparison ──────────────────────────────────────────
// Zig's std.crypto.timing_safe provides constant-time operations
// (it was `std.crypto.utils` before 0.16; that path is gone)
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
// A string check is a first filter, not containment. "escape/passwd" has
// no ".." and is not absolute, yet when base/escape is a symlink to /etc,
// opening base/escape/passwd reads /etc/passwd. What counts is what the
// filesystem resolves.
fn pathIsSafe(user_input: []const u8) bool {
    // Reject absolute paths
    if (user_input.len > 0 and user_input[0] == '/') return false;
    // Reject ".." components ("photo..jpg" is a name, not traversal)
    var it = mem.splitScalar(u8, user_input, '/');
    while (it.next()) |part| {
        if (mem.eql(u8, part, "..")) return false;
    }
    return true;
}

// openat2(2) with RESOLVE_BENEATH (Linux 5.6+) makes the kernel refuse,
// during the open itself, any resolution that leaves `base`, whether
// through "..", an absolute path or a symlink: it fails with EXDEV.
// There is no gap between a check and the open for a swapped symlink to
// use. std.Io.Dir's `resolve_beneath` option does not help here: it maps
// to O_RESOLVE_BENEATH, which Linux lacks, and "if unsupported, this
// option is ignored", so the escape above still reads /etc/passwd.
const OpenHow = extern struct { flags: u64, mode: u64, resolve: u64 };
const RESOLVE_BENEATH: u64 = 0x08; // <linux/openat2.h>

fn openBeneath(base: std.Io.Dir, sub_path: [*:0]const u8) !linux.fd_t {
    var how: OpenHow = .{
        .flags = @as(u32, @bitCast(linux.O{ .ACCMODE = .RDONLY, .CLOEXEC = true })),
        .mode = 0,
        .resolve = RESOLVE_BENEATH,
    };
    const rc = linux.syscall4(
        .openat2,
        @as(usize, @bitCast(@as(isize, base.handle))),
        @intFromPtr(sub_path),
        @intFromPtr(&how),
        @sizeOf(OpenHow),
    );
    return switch (linux.errno(rc)) {
        .SUCCESS => @intCast(rc),
        .XDEV => error.PathEscapesBase,
        else => error.OpenFailed,
    };
}

fn testPathTraversalPrevention(io: std.Io) !void {
    try expect(pathIsSafe("photo.jpg"));
    try expect(pathIsSafe("subdir/file.txt"));
    try expect(pathIsSafe("photo..jpg"));
    try expect(!pathIsSafe("../../etc/passwd"));
    try expect(!pathIsSafe("../secret"));
    try expect(!pathIsSafe("/etc/passwd"));
    try expect(!pathIsSafe("normal/../../escape"));

    // A scratch base with a symlink inside it that points outside it.
    var tmp = try std.Io.Dir.openDirAbsolute(io, "/tmp", .{});
    defer tmp.close(io);
    var name_buf: [32]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "vidya-sec-{d}", .{linux.getpid()});
    try tmp.createDir(io, name, .default_dir);
    defer tmp.deleteTree(io, name) catch {};
    var base = try tmp.openDir(io, name, .{});
    defer base.close(io);
    try base.symLink(io, "/etc", "escape", .{});
    try base.createDir(io, "subdir", .default_dir);
    (try base.createFile(io, "subdir/file.txt", .{})).close(io);

    // The string filter is fooled; the kernel is not.
    try expect(pathIsSafe("escape/passwd"));
    try expect(openBeneath(base, "escape/passwd") == error.PathEscapesBase);
    try expect(openBeneath(base, "../secret") == error.PathEscapesBase);
    try expect(openBeneath(base, "/etc/passwd") == error.PathEscapesBase);
    const fd = try openBeneath(base, "subdir/file.txt");
    _ = linux.close(fd);
}

// ── Secure random generation ──────────────────────────────────────────
fn testSecureRandom(io: std.Io) !void {
    // Zig 0.16: randomness is obtained via the std.Io interface. io.random
    // fills the buffer from a CSPRNG seeded with OS entropy (getrandom).
    var token1: [32]u8 = undefined;
    var token2: [32]u8 = undefined;
    io.random(&token1);
    io.random(&token2);

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
    try expect(!isAlphanumeric(&@as([201]u8, @splat('a')), 200));
}
