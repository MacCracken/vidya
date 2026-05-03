// Vidya — Transactions and ACID — Zig port.
// OCC store with read-set version snapshots.

const std = @import("std");

const N_ACCOUNTS: usize = 8;
const N_TX: usize = 2;
const TX_CAP: usize = 4;

const TxStatus = enum(u8) { free = 0, active = 1, committed = 2, aborted = 3 };

const Store = struct {
    accounts: [N_ACCOUNTS]i64 = [_]i64{0} ** N_ACCOUNTS,
    version: [N_ACCOUNTS]i64 = [_]i64{0} ** N_ACCOUNTS,
    status: [N_TX]TxStatus = [_]TxStatus{.free} ** N_TX,
    wcount: [N_TX]usize = [_]usize{0} ** N_TX,
    wkeys: [N_TX][TX_CAP]i32 = [_][TX_CAP]i32{[_]i32{0} ** TX_CAP} ** N_TX,
    wvals: [N_TX][TX_CAP]i64 = [_][TX_CAP]i64{[_]i64{0} ** TX_CAP} ** N_TX,
    rcount: [N_TX]usize = [_]usize{0} ** N_TX,
    rkeys: [N_TX][TX_CAP]i32 = [_][TX_CAP]i32{[_]i32{0} ** TX_CAP} ** N_TX,
    rsnaps: [N_TX][TX_CAP]i64 = [_][TX_CAP]i64{[_]i64{0} ** TX_CAP} ** N_TX,

    fn accountSetRaw(self: *Store, k: usize, v: i64) void {
        self.accounts[k] = v;
        self.version[k] += 1;
    }
    fn accountGetRaw(self: *const Store, k: usize) i64 { return self.accounts[k]; }
    fn total(self: *const Store) i64 {
        var sum: i64 = 0;
        for (self.accounts) |v| sum += v;
        return sum;
    }
    fn begin(self: *Store) i32 {
        var t: usize = 0;
        while (t < N_TX) : (t += 1) {
            if (self.status[t] == .free) {
                self.status[t] = .active;
                self.wcount[t] = 0;
                self.rcount[t] = 0;
                return @intCast(t);
            }
        }
        return -1;
    }
    fn findWrite(self: *const Store, tx: usize, k: i32) i32 {
        var i: usize = 0;
        while (i < self.wcount[tx]) : (i += 1) {
            if (self.wkeys[tx][i] == k) return @intCast(i);
        }
        return -1;
    }
    fn hasRead(self: *const Store, tx: usize, k: i32) bool {
        var i: usize = 0;
        while (i < self.rcount[tx]) : (i += 1) {
            if (self.rkeys[tx][i] == k) return true;
        }
        return false;
    }
    fn read(self: *Store, tx: usize, k: i32) i64 {
        std.debug.assert(self.status[tx] == .active);
        const widx = self.findWrite(tx, k);
        if (widx >= 0) return self.wvals[tx][@intCast(widx)];
        if (!self.hasRead(tx, k) and self.rcount[tx] < TX_CAP) {
            self.rkeys[tx][self.rcount[tx]] = k;
            self.rsnaps[tx][self.rcount[tx]] = self.version[@intCast(k)];
            self.rcount[tx] += 1;
        }
        return self.accounts[@intCast(k)];
    }
    fn write(self: *Store, tx: usize, k: i32, v: i64) i32 {
        if (self.status[tx] != .active) return 0;
        const widx = self.findWrite(tx, k);
        if (widx >= 0) {
            self.wvals[tx][@intCast(widx)] = v;
            return 1;
        }
        if (self.wcount[tx] >= TX_CAP) return 0;
        self.wkeys[tx][self.wcount[tx]] = k;
        self.wvals[tx][self.wcount[tx]] = v;
        self.wcount[tx] += 1;
        return 1;
    }
    fn validate(self: *const Store, tx: usize) bool {
        var i: usize = 0;
        while (i < self.rcount[tx]) : (i += 1) {
            const k: usize = @intCast(self.rkeys[tx][i]);
            if (self.version[k] != self.rsnaps[tx][i]) return false;
        }
        return true;
    }
    fn commit(self: *Store, tx: usize) i32 {
        if (self.status[tx] != .active) return 0;
        if (!self.validate(tx)) {
            self.status[tx] = .aborted;
            return 0;
        }
        var i: usize = 0;
        while (i < self.wcount[tx]) : (i += 1) {
            const k: usize = @intCast(self.wkeys[tx][i]);
            self.accounts[k] = self.wvals[tx][i];
            self.version[k] += 1;
        }
        self.status[tx] = .committed;
        return 1;
    }
    fn abort(self: *Store, tx: usize) i32 {
        if (self.status[tx] != .active) return 0;
        self.status[tx] = .aborted;
        return 1;
    }
    fn crashRecovery(self: *Store) void {
        var t: usize = 0;
        while (t < N_TX) : (t += 1) {
            self.status[t] = .free;
            self.wcount[t] = 0;
            self.rcount[t] = 0;
        }
    }
};

fn seed() Store {
    var s = Store{};
    s.accountSetRaw(0, 1000);
    s.accountSetRaw(1, 500);
    s.accountSetRaw(2, 200);
    return s;
}

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

pub fn main() !void {
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 9999);
        _ = s.write(tx, 1, 8888);
        _ = s.write(tx, 2, 7777);
        _ = s.abort(tx);
        check(s.accountGetRaw(0) == 1000, "abort: key 0 unchanged");
        check(s.accountGetRaw(1) == 500, "abort: key 1 unchanged");
        check(s.accountGetRaw(2) == 200, "abort: key 2 unchanged");
        check(s.status[tx] == .aborted, "tx status = ABORTED");
    }
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 100);
        _ = s.write(tx, 1, 200);
        _ = s.write(tx, 2, 300);
        check(s.commit(tx) == 1, "commit succeeded");
        check(s.accountGetRaw(0) == 100, "commit: key 0 installed");
        check(s.accountGetRaw(1) == 200, "commit: key 1 installed");
        check(s.accountGetRaw(2) == 300, "commit: key 2 installed");
        check(s.status[tx] == .committed, "tx status = COMMITTED");
    }
    {
        var s = seed();
        const initial = s.total();
        const tx: usize = @intCast(s.begin());
        const src = s.read(tx, 0);
        const dst = s.read(tx, 1);
        _ = s.write(tx, 0, src - 100);
        _ = s.write(tx, 1, dst + 100);
        _ = s.commit(tx);
        check(s.accountGetRaw(0) == 900, "src debited");
        check(s.accountGetRaw(1) == 600, "dst credited");
        check(s.total() == initial, "total preserved");
    }
    {
        var s = seed();
        const tx1: usize = @intCast(s.begin());
        const tx2: usize = @intCast(s.begin());
        _ = s.write(tx1, 0, 9999);
        check(s.read(tx2, 0) == 1000, "tx2 sees committed, not pending");
    }
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 4242);
        check(s.read(tx, 0) == 4242, "tx sees own write");
        check(s.accountGetRaw(0) == 1000, "durable unchanged before commit");
    }
    {
        var s = seed();
        const tx1: usize = @intCast(s.begin());
        const tx2: usize = @intCast(s.begin());
        const v1 = s.read(tx1, 0);
        _ = s.write(tx1, 0, v1 + 50);
        const v2 = s.read(tx2, 0);
        _ = s.write(tx2, 0, v2 + 100);
        const ok1 = s.commit(tx1);
        const ok2 = s.commit(tx2);
        check(ok1 == 1, "tx1 commits");
        check(ok2 == 0, "tx2 conflicts and aborts");
        check(s.status[tx2] == .aborted, "tx2 status = ABORTED");
        check(s.accountGetRaw(0) == 1050, "tx1 durable; tx2 lost");
    }
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 12345);
        _ = s.commit(tx);
        s.crashRecovery();
        check(s.accountGetRaw(0) == 12345, "committed survives crash");
    }
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 7);
        const ok1 = s.commit(tx);
        const ok2 = s.commit(tx);
        check(ok1 == 1, "first commit ok");
        check(ok2 == 0, "second commit rejected");
    }
    {
        var s = seed();
        const tx: usize = @intCast(s.begin());
        _ = s.write(tx, 0, 1);
        _ = s.write(tx, 1, 2);
        _ = s.write(tx, 2, 3);
        _ = s.write(tx, 3, 4);
        const fifth = s.write(tx, 4, 5);
        check(fifth == 0, "5th write rejected (cap=4)");
    }

    std.debug.print("=== transactions_and_acid ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
