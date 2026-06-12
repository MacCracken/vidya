// Vidya — Concurrency in Zig
//
// Zig provides std.Thread for OS threads and std.atomic for lock-free
// operations. No async/await runtime in the standard library (removed
// in 0.14+). Concurrency is explicit: spawn threads, use atomics or
// mutexes, join when done. No hidden allocations or GC pauses.

const std = @import("std");
const expect = std.testing.expect;
const Thread = std.Thread;
const Atomic = std.atomic;

// ── Thread function ────────────────────────────────────────────────

fn sumRange(result: *usize, start: usize, end: usize) void {
    var total: usize = 0;
    var i = start;
    while (i < end) : (i += 1) {
        total += i;
    }
    result.* = total;
}

// ── Shared atomic counter ──────────────────────────────────────────

const AtomicCounter = struct {
    value: Atomic.Value(u64) = Atomic.Value(u64).init(0),

    fn increment(self: *AtomicCounter, n: u64) void {
        _ = self.value.fetchAdd(n, .monotonic);
    }

    fn load(self: *const AtomicCounter) u64 {
        return self.value.load(.seq_cst);
    }
};

// ── Mutex-protected data ───────────────────────────────────────────

const SharedList = struct {
    items: std.ArrayListUnmanaged(i32) = .empty,
    mutex: std.Io.Mutex = .init,
    allocator: std.mem.Allocator,
    io: std.Io,

    fn init(allocator: std.mem.Allocator, io: std.Io) SharedList {
        return .{ .allocator = allocator, .io = io };
    }

    fn deinit(self: *SharedList) void {
        self.items.deinit(self.allocator);
    }

    fn append(self: *SharedList, value: i32) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.items.append(self.allocator, value);
    }

    fn len(self: *SharedList) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.items.items.len;
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // std.Io.Mutex/Condition replaced Thread.Mutex in 0.16: they block via
    // an Io implementation. Threaded is the OS-thread-backed Io.
    var io_threaded: std.Io.Threaded = .init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    // ── Spawn and join threads ─────────────────────────────────────
    var r1: usize = 0;
    var r2: usize = 0;
    const t1 = try Thread.spawn(.{}, sumRange, .{ &r1, 0, 50 });
    const t2 = try Thread.spawn(.{}, sumRange, .{ &r2, 50, 100 });

    t1.join();
    t2.join();
    try expect(r1 + r2 == 4950); // sum 0..99

    // ── Atomic operations ──────────────────────────────────────────
    var counter = AtomicCounter{};

    // Spawn 4 threads, each incrementing 1000 times
    var threads: [4]Thread = undefined;
    for (&threads) |*t| {
        t.* = try Thread.spawn(.{}, struct {
            fn run(c: *AtomicCounter) void {
                for (0..1000) |_| {
                    c.increment(1);
                }
            }
        }.run, .{&counter});
    }
    for (&threads) |*t| {
        t.join();
    }
    try expect(counter.load() == 4000);

    // ── Atomic compare-and-swap ────────────────────────────────────
    var cas_val = Atomic.Value(u32).init(42);

    // Successful CAS
    const result = cas_val.cmpxchgStrong(42, 99, .seq_cst, .seq_cst);
    try expect(result == null); // success
    try expect(cas_val.load(.seq_cst) == 99);

    // Failed CAS
    const failed = cas_val.cmpxchgStrong(42, 200, .seq_cst, .seq_cst);
    try expect(failed.? == 99); // actual value returned

    // ── Mutex-protected shared data ────────────────────────────────
    var list = SharedList.init(allocator, io);
    defer list.deinit();

    var list_threads: [4]Thread = undefined;
    for (&list_threads, 0..) |*t, i| {
        t.* = try Thread.spawn(.{}, struct {
            fn run(l: *SharedList, val: i32) void {
                l.append(val) catch {};
            }
        }.run, .{ &list, @as(i32, @intCast(i)) });
    }
    for (&list_threads) |*t| {
        t.join();
    }
    try expect(list.len() == 4);

    // ── std.Io.Mutex: basic locking ────────────────────────────────
    var mutex: std.Io.Mutex = .init;
    var protected: u32 = 0;

    mutex.lockUncancelable(io);
    protected += 1;
    mutex.unlock(io);
    try expect(protected == 1);

    // defer pattern for lock
    {
        mutex.lockUncancelable(io);
        defer mutex.unlock(io);
        protected += 1;
    }
    try expect(protected == 2);

    // ── Ordering levels ────────────────────────────────────────────
    // .unordered    — no ordering guarantees
    // .monotonic    — per-variable ordering only
    // .acquire      — subsequent reads see prior writes
    // .release      — prior writes visible to acquire loads
    // .acq_rel      — both acquire and release
    // .seq_cst      — total order across all threads

    var ordered = Atomic.Value(u32).init(0);
    ordered.store(1, .release);
    const val = ordered.load(.acquire);
    try expect(val == 1);

    std.debug.print("All concurrency examples passed.\n", .{});
}
