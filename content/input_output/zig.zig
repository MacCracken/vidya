// Vidya — Input/Output in Zig
//
// Zig I/O uses the std.io.Reader and std.io.Writer interfaces.
// All I/O requires explicit error handling. No hidden buffering —
// wrap with BufferedReader/BufferedWriter when needed. File I/O
// goes through std.fs.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Writing to a buffer (ArrayList as writer) ──────────────────
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("hello ");
    try writer.writeAll("world");
    try expect(mem.eql(u8, buf.items, "hello world"));

    // ── Formatted writing ──────────────────────────────────────────
    buf.clearRetainingCapacity();
    try writer.print("value: {d}, name: {s}", .{ 42, "test" });
    try expect(mem.eql(u8, buf.items, "value: 42, name: test"));

    // ── Fixed buffer writer (no allocation) ────────────────────────
    var fixed: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&fixed);
    const fw = fbs.writer();
    try fw.writeAll("hello");
    try fw.writeAll(" fixed");
    const written = fbs.getWritten();
    try expect(mem.eql(u8, written, "hello fixed"));

    // ── Reading from fixed buffer ──────────────────────────────────
    var read_buf: [5]u8 = undefined;
    fbs.reset();
    const n = try fbs.reader().readAll(&read_buf);
    try expect(n == 5);
    try expect(mem.eql(u8, &read_buf, "hello"));

    // ── File I/O with temp file ────────────────────────────────────
    const tmp_path = "/tmp/vidya_zig_io_test.txt";

    // Write
    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll("line 1\nline 2\nline 3\n");
    }

    // Read back
    {
        const content = try std.fs.cwd().readFileAlloc(allocator, tmp_path, 1024 * 1024);
        defer allocator.free(content);
        try expect(mem.eql(u8, content, "line 1\nline 2\nline 3\n"));
    }

    // ── Line-by-line reading (manual split) ──────────────────────────
    {
        const content2 = try std.fs.cwd().readFileAlloc(allocator, tmp_path, 1024 * 1024);
        defer allocator.free(content2);

        var line_count: u32 = 0;
        var iter = mem.splitSequence(u8, content2, "\n");
        while (iter.next()) |line| {
            if (line.len > 0) line_count += 1;
        }
        try expect(line_count == 3);
    }

    // ── Seeking ────────────────────────────────────────────────────
    {
        const file = try std.fs.cwd().openFile(tmp_path, .{});
        defer file.close();
        try file.seekTo(7); // skip "line 1\n"
        var rest_buf: [100]u8 = undefined;
        const rest_n = try file.readAll(&rest_buf);
        try expect(mem.startsWith(u8, rest_buf[0..rest_n], "line 2"));
    }

    // ── Error handling on I/O ──────────────────────────────────────
    const bad_open = std.fs.cwd().openFile("/nonexistent/path.txt", .{});
    try expect(bad_open == error.FileNotFound);

    // Cleanup
    try std.fs.cwd().deleteFile(tmp_path);

    std.debug.print("All input/output examples passed.\n", .{});
}
