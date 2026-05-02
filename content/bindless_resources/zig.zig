// Vidya — Bindless Resources in Zig
//
// In-memory descriptor table — "one global table per frame" pattern.

const std = @import("std");

const TABLE_CAP: u32 = 64;

const Table = struct {
    slots: [TABLE_CAP]u64 = [_]u64{0} ** TABLE_CAP,
    free_links: [TABLE_CAP]u32 = [_]u32{0} ** TABLE_CAP,
    next_id: u32 = 1,
    free_head: u32 = 0,

    fn alloc(self: *Table, desc: u64) u32 {
        if (self.free_head != 0) {
            const id = self.free_head;
            self.free_head = self.free_links[id];
            self.slots[id] = desc;
            return id;
        }
        if (self.next_id >= TABLE_CAP) return 0;
        const id = self.next_id;
        self.next_id += 1;
        self.slots[id] = desc;
        return id;
    }

    fn lookup(self: *const Table, id: u32) u64 {
        if (id == 0 or id >= TABLE_CAP) return 0;
        return self.slots[id];
    }

    fn update(self: *Table, id: u32, desc: u64) bool {
        if (id == 0 or id >= TABLE_CAP) return false;
        self.slots[id] = desc;
        return true;
    }

    fn free(self: *Table, id: u32) bool {
        if (id == 0 or id >= TABLE_CAP) return false;
        self.free_links[id] = self.free_head;
        self.free_head = id;
        self.slots[id] = 0;
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

    _ = t.free(id2);
    if (t.lookup(id2) != 0) return error.Freed;
    const id4 = t.alloc(0x4444444444444444);
    if (id4 != id2) return error.Reuse;
    if (t.lookup(id4) != 0x4444444444444444) return error.ReuseDesc;

    var t2 = Table{};
    var i: u32 = 1;
    while (i < TABLE_CAP) : (i += 1) _ = t2.alloc(@as(u64, i));
    if (t2.alloc(0xDEADBEEF) != 0) return error.Exhausted;

    std.debug.print("bindless_resources: 15/15 ok\n", .{});
}
