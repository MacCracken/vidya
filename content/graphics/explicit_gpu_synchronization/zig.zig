// Vidya — Explicit GPU Synchronization in Zig
//
// Timeline semaphores — monotonic counters with signal/wait/wait_all.

const std = @import("std");

const Timelines = struct {
    compute: u64 = 0,
    transfer: u64 = 0,

    fn signal(self: *Timelines, sem: u32, value: u64) bool {
        if (sem == 0) {
            if (value <= self.compute) return false;
            self.compute = value;
            return true;
        }
        if (sem == 1) {
            if (value <= self.transfer) return false;
            self.transfer = value;
            return true;
        }
        return false;
    }

    fn waitFor(self: *const Timelines, sem: u32, target: u64) bool {
        if (sem == 0) return self.compute >= target;
        if (sem == 1) return self.transfer >= target;
        return false;
    }

    fn waitAll(self: *const Timelines, c: u64, t: u64) bool {
        return self.waitFor(0, c) and self.waitFor(1, t);
    }
};

pub fn main() !void {
    var t = Timelines{};

    if (t.compute != 0) return error.InitC;
    if (t.transfer != 0) return error.InitT;
    if (!t.waitFor(0, 0)) return error.W00;

    if (!t.signal(0, 5)) return error.S5;
    if (t.compute != 5) return error.C5;

    if (!t.waitFor(0, 3)) return error.Past;
    if (!t.waitFor(0, 5)) return error.Cur;
    if (t.waitFor(0, 10)) return error.Future;

    if (t.signal(0, 3)) return error.R3;
    if (t.compute != 5) return error.AfterR;
    if (t.signal(0, 5)) return error.R5;

    _ = t.signal(1, 3);
    if (t.transfer != 3) return error.T3;
    if (!t.waitAll(5, 3)) return error.A53;
    if (t.waitAll(5, 4)) return error.A54;
    if (t.waitAll(6, 3)) return error.A63;
    if (!t.waitAll(0, 0)) return error.A00;

    var t2 = Timelines{};
    var i: u64 = 1;
    while (i <= 10) : (i += 1) _ = t2.signal(0, i);
    if (t2.compute != 10) return error.Mono;
    if (!t2.waitFor(0, 10)) return error.Final;
    if (t2.waitFor(0, 11)) return error.Beyond;

    std.debug.print("explicit_gpu_synchronization: 19/19 ok\n", .{});
}
