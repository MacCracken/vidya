// Vidya — Direct DRM GPU Compute in Zig
//
// In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

const std = @import("std");

const BO_CAP: u32 = 32;
const VA_CAP: usize = 32;

const Device = struct {
    fd: i64 = 0,
    bo_size: [BO_CAP]u64 = [_]u64{0} ** BO_CAP,
    next_bo: u32 = 1,
    va_addr: [VA_CAP]u64 = [_]u64{0} ** VA_CAP,
    va_bo: [VA_CAP]u32 = [_]u32{0} ** VA_CAP,
    va_count: usize = 0,
    next_seq: u64 = 1,
    completed_seq: u64 = 0,

    fn openRenderNode(self: *Device) i64 { self.fd = 42; return self.fd; }

    fn gemCreate(self: *Device, size: u64) u32 {
        if (self.next_bo >= BO_CAP) return 0;
        const h = self.next_bo;
        self.next_bo += 1;
        self.bo_size[h] = size;
        return h;
    }

    fn gemDestroy(self: *Device, handle: u32) bool {
        if (handle == 0 or handle >= BO_CAP) return false;
        if (self.bo_size[handle] == 0) return false;
        self.bo_size[handle] = 0;
        var i: usize = 0;
        while (i < self.va_count) : (i += 1) {
            if (self.va_bo[i] == handle) self.va_bo[i] = 0;
        }
        return true;
    }

    fn gemVaMap(self: *Device, handle: u32, va: u64) bool {
        if (handle == 0 or handle >= BO_CAP) return false;
        if (self.bo_size[handle] == 0) return false;
        if (self.va_count >= VA_CAP) return false;
        self.va_addr[self.va_count] = va;
        self.va_bo[self.va_count] = handle;
        self.va_count += 1;
        return true;
    }

    fn vaLookup(self: *const Device, va: u64) u32 {
        var i: usize = 0;
        while (i < self.va_count) : (i += 1) {
            if (self.va_addr[i] == va and self.va_bo[i] != 0) return self.va_bo[i];
        }
        return 0;
    }

    fn submit(self: *Device, handle: u32) u64 {
        if (handle == 0 or handle >= BO_CAP) return 0;
        if (self.bo_size[handle] == 0) return 0;
        const seq = self.next_seq;
        self.next_seq += 1;
        self.completed_seq = seq;
        return seq;
    }

    fn syncobjWait(self: *const Device, seq: u64) bool {
        return self.completed_seq >= seq;
    }
};

pub fn main() !void {
    var d = Device{};

    if (d.openRenderNode() == 0) return error.Fd;

    const b1 = d.gemCreate(4096);
    const b2 = d.gemCreate(8192);
    const b3 = d.gemCreate(16384);
    if (b1 != 1 or b2 != 2 or b3 != 3) return error.BoIds;

    if (!d.gemVaMap(b1, 0x1000)) return error.MapB1;
    if (!d.gemVaMap(b2, 0x2000)) return error.MapB2;

    if (d.vaLookup(0x1000) != b1) return error.LookupB1;
    if (d.vaLookup(0x2000) != b2) return error.LookupB2;
    if (d.vaLookup(0x9000) != 0) return error.LookupUnmapped;

    if (d.gemVaMap(99, 0x3000)) return error.MapInvalid;
    if (d.gemVaMap(0, 0x3000)) return error.MapZero;

    if (d.submit(b1) != 1) return error.Seq1;
    if (d.submit(b2) != 2) return error.Seq2;
    if (d.submit(b3) != 3) return error.Seq3;

    if (!d.syncobjWait(1)) return error.Wait1;
    if (!d.syncobjWait(3)) return error.Wait3;
    if (d.syncobjWait(99)) return error.WaitFuture;

    _ = d.gemDestroy(b1);
    if (d.vaLookup(0x1000) != 0) return error.DestroyedVa;

    if (d.submit(b1) != 0) return error.SubmitDestroyed;
    if (d.submit(b2) != 4) return error.NextValid;

    std.debug.print("direct_drm_gpu_compute: 20/20 ok\n", .{});
}
