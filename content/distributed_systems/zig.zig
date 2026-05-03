// Vidya — Distributed Systems Foundations — Zig port.

const std = @import("std");

const N_NODES: usize = 3;
const W: usize = 2;
const R: usize = 2;

const VCOrder = enum { less, equal, greater, concurrent };

const VClock = struct {
    c: [N_NODES]i64 = [_]i64{0} ** N_NODES,

    fn tick(self: *VClock, node: usize) void { self.c[node] += 1; }
    fn merge(self: *VClock, from: *const VClock) void {
        var i: usize = 0;
        while (i < N_NODES) : (i += 1) {
            if (from.c[i] > self.c[i]) self.c[i] = from.c[i];
        }
    }
    fn compare(self: *const VClock, other: *const VClock) VCOrder {
        var any_lt = false;
        var any_gt = false;
        var i: usize = 0;
        while (i < N_NODES) : (i += 1) {
            if (self.c[i] < other.c[i]) any_lt = true;
            if (self.c[i] > other.c[i]) any_gt = true;
        }
        if (!any_lt and !any_gt) return .equal;
        if (!any_lt) return .greater;
        if (!any_gt) return .less;
        return .concurrent;
    }
};

const QCluster = struct {
    accounts: [N_NODES]i64 = [_]i64{0} ** N_NODES,
    write_seq: [N_NODES]i64 = [_]i64{0} ** N_NODES,
    alive: [N_NODES]bool = [_]bool{true} ** N_NODES,
    global_seq: i64 = 0,

    fn partition(self: *QCluster, n: usize) void { self.alive[n] = false; }
    fn heal(self: *QCluster, n: usize) void { self.alive[n] = true; }
    fn aliveCount(self: *const QCluster) usize {
        var c: usize = 0;
        for (self.alive) |a| if (a) { c += 1; };
        return c;
    }
    fn write(self: *QCluster, value: i64) bool {
        if (self.aliveCount() < W) return false;
        self.global_seq += 1;
        var i: usize = 0;
        while (i < N_NODES) : (i += 1) {
            if (self.alive[i]) {
                self.accounts[i] = value;
                self.write_seq[i] = self.global_seq;
            }
        }
        return true;
    }
    fn read(self: *const QCluster) ?i64 {
        if (self.aliveCount() < R) return null;
        var best_seq: i64 = 0;
        var best_value: i64 = 0;
        var i: usize = 0;
        while (i < N_NODES) : (i += 1) {
            if (self.alive[i] and self.write_seq[i] > best_seq) {
                best_seq = self.write_seq[i];
                best_value = self.accounts[i];
            }
        }
        return best_value;
    }
};

var pass_count: i32 = 0;
var fail_count: i32 = 0;
fn check(cond: bool, name: []const u8) void {
    if (cond) {
        pass_count += 1;
    } else {
        fail_count += 1;
        std.debug.print("  FAIL: {s}\n", .{name});
    }
}

fn arrEq(a: [N_NODES]i64, b: [N_NODES]i64) bool {
    var i: usize = 0;
    while (i < N_NODES) : (i += 1) if (a[i] != b[i]) return false;
    return true;
}

pub fn main() !void {
    {
        const v = VClock{};
        check(arrEq(v.c, [_]i64{0, 0, 0}), "vc init");
    }
    {
        var v = VClock{};
        v.tick(1); v.tick(1); v.tick(2);
        check(arrEq(v.c, [_]i64{0, 2, 1}), "tick");
    }
    {
        var a = VClock{};
        var b = VClock{};
        a.tick(0); a.tick(0);
        b.tick(1); b.tick(2);
        a.merge(&b);
        check(arrEq(a.c, [_]i64{2, 1, 1}), "merge max");
    }
    {
        const a = VClock{};
        var b = VClock{};
        b.tick(0);
        check(a.compare(&b) == .less, "less");
    }
    {
        var a = VClock{};
        var b = VClock{};
        a.tick(0); a.tick(0); b.tick(0);
        check(a.compare(&b) == .greater, "greater");
    }
    {
        var a = VClock{};
        var b = VClock{};
        a.tick(1); b.tick(1);
        check(a.compare(&b) == .equal, "equal");
    }
    {
        var a = VClock{};
        var b = VClock{};
        a.tick(0); b.tick(1);
        check(a.compare(&b) == .concurrent, "concurrent");
        check(b.compare(&a) == .concurrent, "concurrent symmetric");
    }
    {
        var c = QCluster{};
        check(c.write(100), "write ok full");
        check(arrEq(c.accounts, [_]i64{100, 100, 100}), "all wrote");
    }
    {
        var c = QCluster{};
        c.partition(2);
        check(c.write(200), "write ok 2 alive");
        check(c.accounts[0] == 200 and c.accounts[1] == 200, "0,1 wrote");
        check(c.accounts[2] == 0, "2 untouched");
    }
    {
        var c = QCluster{};
        c.partition(1); c.partition(2);
        check(!c.write(300), "write fails 1 alive");
        check(c.accounts[0] == 0, "no replica wrote");
    }
    {
        var c = QCluster{};
        c.partition(2);
        _ = c.write(500);
        c.heal(2);
        c.partition(0);
        check(c.read().? == 500, "intersection: read sees latest");
    }
    {
        var c = QCluster{};
        _ = c.write(700);
        c.partition(0); c.partition(1);
        check(c.read() == null, "read null below R");
    }

    std.debug.print("=== distributed_systems ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
