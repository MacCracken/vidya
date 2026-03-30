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
    mutex: Thread.Mutex = .{},
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) SharedList {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *SharedList) void {
        self.items.deinit(self.allocator);
    }

    fn append(self: *SharedList, value: i32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(self.allocator, value);
    }

    fn len(self: *SharedList) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.items.items.len;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
    var list = SharedList.init(allocator);
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

    // ── Thread.Mutex: basic locking ────────────────────────────────
    var mutex = Thread.Mutex{};
    var protected: u32 = 0;

    mutex.lock();
    protected += 1;
    mutex.unlock();
    try expect(protected == 1);

    // defer pattern for lock
    {
        mutex.lock();
        defer mutex.unlock();
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
