// Vidya — Bindless Resources in Zig
//
// In-memory descriptor table — "one global table per frame" pattern.
//
// A handle is (generation << 8) | slot. The shader indexes by slot; the
// application keeps the whole handle. Freeing a slot bumps its
// generation, so a handle kept past free() no longer matches and is
// rejected instead of silently reading whatever descriptor reused the
// slot. The same check rejects a double free, which would otherwise link
// the slot into the free list twice and hand one slot to two owners.

const std = @import("std");

const TABLE_CAP: u32 = 64;
const SLOT_BITS: u5 = 8;
const SLOT_MASK: u32 = (1 << SLOT_BITS) - 1;
const GEN_MASK: u32 = std.math.maxInt(u32) >> SLOT_BITS; // 24-bit generation

const Table = struct {
    slots: [TABLE_CAP]u64 = @splat(0),
    free_links: [TABLE_CAP]u32 = @splat(0),
    gens: [TABLE_CAP]u32 = @splat(0),
    live: [TABLE_CAP]bool = @splat(false),
    next_id: u32 = 1,
    free_head: u32 = 0,

    fn handle(self: *const Table, idx: u32) u32 {
        return (self.gens[idx] << SLOT_BITS) | idx;
    }

    /// Slot index for a handle that is still live, else null.
    fn liveIndex(self: *const Table, h: u32) ?u32 {
        const idx = h & SLOT_MASK;
        if (idx == 0 or idx >= TABLE_CAP) return null;
        if (!self.live[idx] or self.gens[idx] != h >> SLOT_BITS) return null;
        return idx;
    }

    fn alloc(self: *Table, desc: u64) u32 {
        var idx: u32 = 0;
        if (self.free_head != 0) {
            idx = self.free_head;
            self.free_head = self.free_links[idx];
        } else {
            if (self.next_id >= TABLE_CAP) return 0;
            idx = self.next_id;
            self.next_id += 1;
        }
        self.slots[idx] = desc;
        self.live[idx] = true;
        return self.handle(idx);
    }

    fn lookup(self: *const Table, h: u32) u64 {
        const idx = self.liveIndex(h) orelse return 0;
        return self.slots[idx];
    }

    fn update(self: *Table, h: u32, desc: u64) bool {
        const idx = self.liveIndex(h) orelse return false;
        self.slots[idx] = desc;
        return true;
    }

    fn free(self: *Table, h: u32) bool {
        const idx = self.liveIndex(h) orelse return false; // stale or double free
        self.live[idx] = false;
        self.gens[idx] = (self.gens[idx] + 1) & GEN_MASK;
        self.free_links[idx] = self.free_head;
        self.free_head = idx;
        self.slots[idx] = 0;
        return true;
    }
};

pub fn main() !void {
    var t = Table{};

    const id1 = t.alloc(0x1111111111111111);
    const id2 = t.alloc(0x2222222222222222);
    const id3 = t.alloc(0x3333333333333333);
    if (id1 != 1) return error.Id1;
    if (id2 != 2) return error.Id2;
    if (id3 != 3) return error.Id3;

    if (t.lookup(0) != 0) return error.Slot0;
    if (t.lookup(id1) != 0x1111111111111111) return error.L1;
    if (t.lookup(id2) != 0x2222222222222222) return error.L2;
    if (t.lookup(id3) != 0x3333333333333333) return error.L3;

    if (!t.update(id2, 0xAAAAAAAAAAAAAAAA)) return error.U2;
    if (t.lookup(id2) != 0xAAAAAAAAAAAAAAAA) return error.U2v;
    if (t.lookup(id1) != 0x1111111111111111) return error.U1u;
    if (t.lookup(id3) != 0x3333333333333333) return error.U3u;

    if (!t.free(id2)) return error.Free2;
    if (t.lookup(id2) != 0) return error.Freed;
    const id4 = t.alloc(0x4444444444444444);
    if (id4 & SLOT_MASK != id2 & SLOT_MASK) return error.Reuse; // same slot ...
    if (id4 == id2) return error.SameGeneration; // ... new generation
    if (t.lookup(id4) != 0x4444444444444444) return error.ReuseDesc;
    if (t.lookup(id2) != 0) return error.StaleHandleResolved; // old handle stays dead
    if (t.free(id2)) return error.DoubleFreeAccepted;

    var t2 = Table{};
    var i: u32 = 1;
    while (i < TABLE_CAP) : (i += 1) _ = t2.alloc(@as(u64, i));
    if (t2.alloc(0xDEADBEEF) != 0) return error.Exhausted;

    std.debug.print("bindless_resources: 19/19 ok\n", .{});
}
