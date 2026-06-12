// Vidya — Input/Output in Zig
//
// Zig I/O uses the std.Io.Reader and std.Io.Writer interfaces. As of Zig
// 0.16 ("Writergate"), these are concrete structs driven by a vtable rather
// than the old generic comptime streams, and all OS-backed I/O takes an
// explicit `Io` instance so the same code runs blocking or async. No hidden
// buffering — writers buffer until you flush. File I/O goes through std.Io.Dir.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── The Io instance ────────────────────────────────────────────
    // 0.16 routes OS I/O through an Io interface. `Threaded` is the
    // standard blocking/multithreaded implementation.
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // ── Writing to a growable buffer (Allocating writer) ───────────
    // std.Io.Writer.Allocating owns an ArrayList and grows as you write.
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const writer = &aw.writer;

    try writer.writeAll("hello ");
    try writer.writeAll("world");
    try expect(mem.eql(u8, aw.written(), "hello world"));

    // ── Formatted writing ──────────────────────────────────────────
    aw.clearRetainingCapacity();
    try writer.print("value: {d}, name: {s}", .{ 42, "test" });
    try expect(mem.eql(u8, aw.written(), "value: 42, name: test"));

    // ── Fixed buffer writer (no allocation) ────────────────────────
    var fixed: [64]u8 = undefined;
    var fw: std.Io.Writer = .fixed(&fixed);
    try fw.writeAll("hello");
    try fw.writeAll(" fixed");
    const written = fw.buffered();
    try expect(mem.eql(u8, written, "hello fixed"));

    // ── Reading from a fixed buffer ────────────────────────────────
    var read_buf: [5]u8 = undefined;
    var fr: std.Io.Reader = .fixed(written);
    try fr.readSliceAll(&read_buf);
    try expect(mem.eql(u8, &read_buf, "hello"));

    // ── File I/O with temp file ────────────────────────────────────
    const tmp_path = "/tmp/vidya_zig_io_test.txt";
    const cwd = std.Io.Dir.cwd();

    // Write
    try cwd.writeFile(io, .{ .sub_path = tmp_path, .data = "line 1\nline 2\nline 3\n" });

    // Read back (readFileAlloc takes the Io, allocator, and a size Limit)
    {
        const content = try cwd.readFileAlloc(io, tmp_path, allocator, .limited(1024 * 1024));
        defer allocator.free(content);
        try expect(mem.eql(u8, content, "line 1\nline 2\nline 3\n"));
    }

    // ── Line-by-line reading (manual split) ──────────────────────────
    {
        const content2 = try cwd.readFileAlloc(io, tmp_path, allocator, .limited(1024 * 1024));
        defer allocator.free(content2);

        var line_count: u32 = 0;
        var iter = mem.splitSequence(u8, content2, "\n");
        while (iter.next()) |line| {
            if (line.len > 0) line_count += 1;
        }
        try expect(line_count == 3);
    }

    // ── Seeking (positional read at an offset) ─────────────────────
    {
        const file = try cwd.openFile(io, tmp_path, .{});
        defer file.close(io);
        var rest_buf: [100]u8 = undefined;
        const rest_n = try file.readPositionalAll(io, &rest_buf, 7); // skip "line 1\n"
        try expect(mem.startsWith(u8, rest_buf[0..rest_n], "line 2"));
    }

    // ── Error handling on I/O ──────────────────────────────────────
    const bad_open = cwd.openFile(io, "/nonexistent/path.txt", .{});
    try expect(bad_open == error.FileNotFound);

    // Cleanup
    try cwd.deleteFile(io, tmp_path);

    std.debug.print("All input/output examples passed.\n", .{});
}
