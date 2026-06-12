// Vidya — Concurrent File Access (flock) in Zig
//
// Single-process exercise via two opens of the same path. flock is
// per-OPEN; the two fds have independent lock state. Direct linux
// flock syscall (SYS_flock = 73 on x86_64). EWOULDBLOCK = 11.

const std = @import("std");
const linux = std.os.linux;

const LOCK_SH: i32 = 1;
const LOCK_EX: i32 = 2;
const LOCK_UN: i32 = 8;
const LOCK_NB: i32 = 4;

fn flock(fd: i32, op: i32) i32 {
    const r = linux.syscall2(.flock, @as(usize, @intCast(fd)), @as(usize, @intCast(op)));
    return @as(i32, @bitCast(@as(u32, @truncate(r))));
}

pub fn main() !void {
    // Zig 0.16 routes filesystem calls through an explicit `Io` interface.
    // `Threaded` is the standard blocking backend; we never use async here,
    // so `Allocator.failing` is a valid (unused) general-purpose allocator.
    var threaded: std.Io.Threaded = .init(std.mem.Allocator.failing, .{});
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    const path = "/tmp/vidya_cfa_zig.bin";
    cwd.deleteFile(io, path) catch {};

    // Test 1: exclusive write
    const f1 = try cwd.createFile(io, path, .{ .read = true });
    defer f1.close(io);
    if (flock(f1.handle, LOCK_EX) != 0) return error.LockEx;

    const val: u64 = 0xDEADBEEF12345678;
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, val, .little);
    try f1.writePositionalAll(io, &buf, 0);
    if (flock(f1.handle, LOCK_UN) != 0) return error.UnlockEx;

    // Test 2: shared read with roundtrip
    if (flock(f1.handle, LOCK_SH) != 0) return error.LockSh;
    var rb: [8]u8 = undefined;
    _ = try f1.readPositionalAll(io, &rb, 0);
    const got = std.mem.readInt(u64, &rb, .little);
    if (got != val) return error.BadRoundtrip;
    _ = flock(f1.handle, LOCK_UN);

    // Test 3: exclusive contention
    const f2 = try cwd.openFile(io, path, .{ .mode = .read_write });
    defer f2.close(io);
    if (flock(f1.handle, LOCK_EX) != 0) return error.ReLockEx;
    const nb = flock(f2.handle, LOCK_EX | LOCK_NB);
    if (nb >= 0) return error.ContentionNotDetected;

    // Test 4: release fd1, fd2 acquires
    _ = flock(f1.handle, LOCK_UN);
    if (flock(f2.handle, LOCK_EX | LOCK_NB) != 0) return error.AcquireAfterRelease;
    _ = flock(f2.handle, LOCK_UN);

    // Test 5: shared locks coexist
    if (flock(f1.handle, LOCK_SH | LOCK_NB) != 0) return error.SharedNB;
    if (flock(f2.handle, LOCK_SH | LOCK_NB) != 0) return error.SharedCoexist;
    _ = flock(f1.handle, LOCK_UN);
    _ = flock(f2.handle, LOCK_UN);

    cwd.deleteFile(io, path) catch {};
    std.debug.print("concurrent_file_access: 12/12 ok\n", .{});
}
