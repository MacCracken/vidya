// Vidya — GPU Memory Pooling in Zig
//
// Bump allocator over a 1024-byte pool.

const std = @import("std");

const POOL_SIZE: i64 = 1024;

const Pool = struct {
    bump: i64 = 0,

    fn reset(self: *Pool) void { self.bump = 0; }
    fn used(self: *const Pool) i64 { return self.bump; }
    fn free(self: *const Pool) i64 { return POOL_SIZE - self.bump; }

    fn alloc(self: *Pool, size: i64) i64 {
        if (size == 0) return self.bump;
        if (self.bump + size > POOL_SIZE) return -1;
        const off = self.bump;
        self.bump += size;
        return off;
    }

    fn allocAligned(self: *Pool, size: i64, align_: i64) i64 {
        const mask = align_ - 1;
        const aligned = (self.bump + mask) & ~mask;
        if (aligned + size > POOL_SIZE) return -1;
        self.bump = aligned + size;
        return aligned;
    }
};

pub fn main() !void {
    var p = Pool{};
    if (p.used() != 0) return error.InitUsed;
    if (p.free() != 1024) return error.InitFree;

    if (p.alloc(100) != 0) return error.A1;
    if (p.used() != 100) return error.U1;

    if (p.alloc(200) != 100) return error.A2;
    if (p.used() != 300) return error.U2;

    if (p.alloc(1000) != -1) return error.Exhausted;
    if (p.used() != 300) return error.UnchangedAfterFail;

    p.reset();
    if (p.used() != 0) return error.RU;
    if (p.free() != 1024) return error.RF;
    if (p.alloc(50) != 0) return error.PostReset;

    if (p.allocAligned(32, 16) != 64) return error.Aligned;
    if (p.used() != 96) return error.U96;

    if (p.alloc(0) != 96) return error.Noop;
    if (p.used() != 96) return error.NoopUsed;

    p.reset();
    var i: usize = 0;
    while (i < 10) : (i += 1) _ = p.alloc(8);
    if (p.used() != 80) return error.TenEights;

    std.debug.print("gpu_memory_pooling: 16/16 ok\n", .{});
}
