// Vidya — Allocators in Zig
//
// Three allocation strategies implemented over fixed buffers:
//   1. Bump allocator (arena) — pointer increment, batch free
//   2. Slab allocator — fixed-size slots with index-based free list
//   3. Bitmap allocator — one bit per page, next-free hint
//
// Zig's standard library has std.mem.Allocator and arena allocators,
// but here we implement the algorithms from scratch to show how they
// work at the lowest level — the same logic that runs in kernels and
// firmware where no standard library exists.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

// ── Bump Allocator (Arena) ────────────────────────────────────────────
//
// A pointer advances with each allocation. Individual frees are
// impossible — reset frees everything at once. O(1) alloc.
// Use for: compiler AST nodes, per-request scratch space, parsing.

fn BumpAllocator(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        memory: [capacity]u8 = [_]u8{0} ** capacity,
        offset: usize = 0,
        alloc_count: usize = 0,

        /// Allocate size bytes with given alignment. Returns a slice or null.
        pub fn alloc(self: *Self, size: usize, alignment: usize) ?[*]u8 {
            const aligned = (self.offset + alignment - 1) & ~(alignment - 1);
            const end = aligned + size;
            if (end > capacity) return null;
            self.offset = end;
            self.alloc_count += 1;
            return @as([*]u8, @ptrCast(&self.memory[aligned]));
        }

        /// Reset the arena — free all allocations at once.
        pub fn reset(self: *Self) void {
            self.offset = 0;
            self.alloc_count = 0;
        }
    };
}

// ── Slab Allocator ────────────────────────────────────────────────────
//
// Pre-divides memory into fixed-size slots. Free slots are tracked with
// an index-based free list. Alloc = pop head. Free = push head. Both
// O(1). Zero external fragmentation. Used by the Linux kernel for
// task_struct, inode, dentry.

fn SlabAllocator(comptime slot_size: usize, comptime count: usize) type {
    return struct {
        const Self = @This();
        const sentinel: usize = std.math.maxInt(usize);

        memory: [slot_size * count]u8 = [_]u8{0} ** (slot_size * count),
        free_head: usize = 0,
        next: [count]usize = init_next(),
        allocated: usize = 0,

        fn init_next() [count]usize {
            var n: [count]usize = undefined;
            for (0..count) |i| {
                n[i] = if (i + 1 < count) i + 1 else sentinel;
            }
            return n;
        }

        /// Allocate one slot. Returns slot index or null.
        pub fn alloc(self: *Self) ?usize {
            if (self.free_head == sentinel) return null;
            const index = self.free_head;
            self.free_head = self.next[index];
            self.next[index] = sentinel;
            self.allocated += 1;
            // Zero the slot
            const offset = index * slot_size;
            @memset(self.memory[offset .. offset + slot_size], 0);
            return index;
        }

        /// Free a slot by index.
        pub fn free(self: *Self, index: usize) void {
            self.next[index] = self.free_head;
            self.free_head = index;
            self.allocated -= 1;
        }

        /// Get a pointer to a slot's memory.
        pub fn ptr(self: *Self, index: usize) [*]u8 {
            const offset = index * slot_size;
            return @as([*]u8, @ptrCast(&self.memory[offset]));
        }
    };
}

// ── Bitmap Allocator ──────────────────────────────────────────────────
//
// One bit per page. Set = allocated, clear = free. A next_free hint
// accelerates sequential allocation by skipping known-allocated pages.
// Used by physical memory managers (PMMs) in kernels.

fn BitmapAllocator(comptime num_pages: usize) type {
    const bitmap_bytes = (num_pages + 7) / 8;

    return struct {
        const Self = @This();

        bitmap: [bitmap_bytes]u8 = [_]u8{0} ** bitmap_bytes,
        next_free: usize = 0,
        allocated: usize = 0,

        fn testBit(self: *const Self, page: usize) bool {
            return (self.bitmap[page / 8] >> @intCast(page % 8)) & 1 != 0;
        }

        fn setBit(self: *Self, page: usize) void {
            self.bitmap[page / 8] |= @as(u8, 1) << @intCast(page % 8);
        }

        fn clearBit(self: *Self, page: usize) void {
            self.bitmap[page / 8] &= ~(@as(u8, 1) << @intCast(page % 8));
        }

        /// Allocate one page. Returns page index or null.
        pub fn alloc(self: *Self) ?usize {
            // Search from hint
            for (self.next_free..num_pages) |i| {
                if (!self.testBit(i)) {
                    self.setBit(i);
                    self.next_free = i + 1;
                    self.allocated += 1;
                    return i;
                }
            }
            // Wrap around
            for (0..self.next_free) |i| {
                if (!self.testBit(i)) {
                    self.setBit(i);
                    self.next_free = i + 1;
                    self.allocated += 1;
                    return i;
                }
            }
            return null;
        }

        /// Free a page and retract hint if appropriate.
        pub fn free(self: *Self, page: usize) void {
            self.clearBit(page);
            self.allocated -= 1;
            if (page < self.next_free) {
                self.next_free = page;
            }
        }
    };
}

// ── Main ──────────────────────────────────────────────────────────────

pub fn main() void {
    print("Allocators — three strategies for different patterns:\n\n", .{});

    // Bump allocator
    print("1. Bump Allocator (arena):\n", .{});
    var bump: BumpAllocator(4096) = .{};

    for (0..10) |_| {
        const p = bump.alloc(24, 8);
        assert(p != null);
        // Verify 8-byte alignment
        assert(@intFromPtr(p.?) % 8 == 0);
    }
    print("   Allocated 10 x 24 bytes, all 8-byte aligned\n", .{});
    print("   Bump[{d}/{d} bytes, {d} allocs]\n", .{ bump.offset, @as(usize, 4096), bump.alloc_count });

    // Alignment after odd-size alloc
    _ = bump.alloc(3, 1);
    const aligned_ptr = bump.alloc(8, 8);
    assert(aligned_ptr != null);
    assert(@intFromPtr(aligned_ptr.?) % 8 == 0);
    print("   After 3-byte + 8-byte: aligned = true\n", .{});

    bump.reset();
    assert(bump.offset == 0);
    print("   After reset: Bump[{d}/{d} bytes, {d} allocs]\n\n", .{ bump.offset, @as(usize, 4096), bump.alloc_count });

    // Slab allocator
    print("2. Slab Allocator (fixed-size objects):\n", .{});
    var slab: SlabAllocator(64, 16) = .{};

    var slots: [5]usize = undefined;
    for (0..5) |i| {
        slots[i] = slab.alloc() orelse unreachable;
    }
    print("   Allocated 5 slots: [{d}, {d}, {d}, {d}, {d}]\n", .{ slots[0], slots[1], slots[2], slots[3], slots[4] });
    print("   Slab[{d}/{d} slots]\n", .{ slab.allocated, @as(usize, 16) });

    slab.free(slots[1]);
    slab.free(slots[3]);
    print("   Freed slots {d} and {d}\n", .{ slots[1], slots[3] });
    print("   Slab[{d}/{d} slots]\n", .{ slab.allocated, @as(usize, 16) });

    const reused1 = slab.alloc() orelse unreachable;
    const reused2 = slab.alloc() orelse unreachable;
    assert(reused1 == slots[3]); // LIFO
    assert(reused2 == slots[1]);
    print("   Reallocated: slots {d} and {d} (reused)\n", .{ reused1, reused2 });

    // Write and read back
    const p = slab.ptr(reused1);
    p[0] = 0xDE;
    p[1] = 0xAD;
    p[2] = 0xBE;
    p[3] = 0xEF;
    assert(p[0] == 0xDE and p[1] == 0xAD and p[2] == 0xBE and p[3] == 0xEF);
    print("   Write/read: {x:0>2}{x:0>2}{x:0>2}{x:0>2}\n\n", .{ p[0], p[1], p[2], p[3] });

    // Bitmap allocator
    print("3. Bitmap Allocator (page frames):\n", .{});
    var bmp: BitmapAllocator(64) = .{};

    const p0 = bmp.alloc() orelse unreachable;
    const p1 = bmp.alloc() orelse unreachable;
    const p2 = bmp.alloc() orelse unreachable;
    assert(p0 == 0 and p1 == 1 and p2 == 2);
    print("   Allocated pages: {d}, {d}, {d}\n", .{ p0, p1, p2 });
    print("   Bitmap[{d}/{d} pages]\n", .{ bmp.allocated, @as(usize, 64) });

    bmp.free(1);
    print("   Freed page 1\n", .{});
    const reused_page = bmp.alloc() orelse unreachable;
    assert(reused_page == 1);
    print("   Reallocated: page {d} (reused via hint retraction)\n", .{reused_page});

    const p3 = bmp.alloc() orelse unreachable;
    assert(p3 == 3);
    print("   Next alloc: page {d}\n", .{p3});
    print("   Bitmap[{d}/{d} pages]\n", .{ bmp.allocated, @as(usize, 64) });

    // Fill all remaining
    while (bmp.alloc()) |_| {}
    assert(bmp.allocated == 64);
    assert(bmp.alloc() == null);
    print("   Filled all 64 pages, next alloc = null: true\n", .{});

    print("\nAll tests passed.\n", .{});
}
