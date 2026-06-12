// Vidya — Page Management in Zig
//
// Fixed-size 4KB pages, single file. Header at offset 0; page 0 reserved
// as null sentinel; data pages at PAGE_SZ + num * PAGE_SZ. Free list is
// a stack with `next` pointer at byte offset 8 of each freed page.
// Mirrors the cyrius reference's test surface exactly.

const std = @import("std");

const PAGE_SZ: u64 = 4096;
const MAGIC: u32 = 0x50415452;
const H_PGCOUNT: usize = 8;
const H_FREEHEAD: usize = 16;
const FP_NEXT: usize = 8;

const Header = struct {
    page_count: u64,
    freehead: u64,
};

fn pageOffset(num: u64) u64 {
    return PAGE_SZ + num * PAGE_SZ;
}

fn hdrToBytes(h: Header, buf: []u8) void {
    @memset(buf, 0);
    std.mem.writeInt(u32, buf[0..4], MAGIC, .little);
    std.mem.writeInt(u64, buf[H_PGCOUNT..][0..8], h.page_count, .little);
    std.mem.writeInt(u64, buf[H_FREEHEAD..][0..8], h.freehead, .little);
}

fn hdrVerify(buf: []const u8) bool {
    return std.mem.readInt(u32, buf[0..4], .little) == MAGIC;
}

fn hdrLoad(buf: []const u8) Header {
    return .{
        .page_count = std.mem.readInt(u64, buf[H_PGCOUNT..][0..8], .little),
        .freehead = std.mem.readInt(u64, buf[H_FREEHEAD..][0..8], .little),
    };
}

fn pageRead(io: std.Io, f: std.Io.File, num: u64, buf: []u8) !void {
    // 0.16: positional reads replace seekTo + readAll (threadsafe, no shared cursor).
    _ = try f.readPositionalAll(io, buf, pageOffset(num));
}

fn pageWrite(io: std.Io, f: std.Io.File, num: u64, buf: []const u8) !void {
    try f.writePositionalAll(io, buf, pageOffset(num));
}

fn pageAlloc(io: std.Io, f: std.Io.File, h: *Header) !u64 {
    if (h.freehead != 0) {
        const fh = h.freehead;
        var buf: [PAGE_SZ]u8 = undefined;
        try pageRead(io, f, fh, &buf);
        h.freehead = std.mem.readInt(u64, buf[FP_NEXT..][0..8], .little);
        return fh;
    }
    const num = h.page_count;
    h.page_count += 1;
    const zero = [_]u8{0} ** PAGE_SZ;
    try pageWrite(io, f, num, &zero);
    return num;
}

fn pageFree(io: std.Io, f: std.Io.File, h: *Header, num: u64) !void {
    var buf = [_]u8{0} ** PAGE_SZ;
    std.mem.writeInt(u64, buf[FP_NEXT..][0..8], h.freehead, .little);
    try pageWrite(io, f, num, &buf);
    h.freehead = num;
}

pub fn main() !void {
    // 0.16: filesystem syscalls go through an explicit `Io` instance.
    var threaded: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const path = "/tmp/vidya_page_zig.bin";
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, path) catch {};
    const f = try cwd.createFile(io, path, .{ .read = true });

    var h: Header = .{ .page_count = 1, .freehead = 0 };
    var hbuf: [PAGE_SZ]u8 = undefined;
    hdrToBytes(h, &hbuf);
    try f.writePositionalAll(io, &hbuf, 0);

    // 1-2. header
    var rh: [PAGE_SZ]u8 = undefined;
    _ = try f.readPositionalAll(io, &rh, 0);
    if (!hdrVerify(&rh)) return error.BadMagic;
    const loaded = hdrLoad(&rh);
    if (loaded.page_count != 1) return error.BadCount;

    // 3-4. alloc
    const p1 = try pageAlloc(io, f, &h);
    if (p1 != 1) return error.BadAlloc1;
    const p2 = try pageAlloc(io, f, &h);
    if (p2 != 2) return error.BadAlloc2;

    // 5. roundtrip
    var buf: [PAGE_SZ]u8 = [_]u8{0} ** PAGE_SZ;
    std.mem.writeInt(u64, buf[0..8], 42, .little);
    try pageWrite(io, f, p1, &buf);
    var rb: [PAGE_SZ]u8 = undefined;
    try pageRead(io, f, p1, &rb);
    const got = std.mem.readInt(u64, rb[0..8], .little);
    if (got != 42) return error.BadRead;

    // 6. free + reuse
    try pageFree(io, f, &h, p2);
    const p3 = try pageAlloc(io, f, &h);
    if (p3 != 2) return error.BadReuse;

    f.close(io);
    cwd.deleteFile(io, path) catch {};
    std.debug.print("page_management: 6/6 ok\n", .{});
}
