// Vidya — B+ Tree Indexing in Zig
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the layout declared by cyrius.cyr. Zig uses a single `Node` struct
// with an `is_leaf` bool and inline fixed-size arrays:
//   keys:     [CAP]i64        (CAP = MAX+1, allows transient overflow)
//   vals:     [CAP]i64        (used when is_leaf)
//   children: [CAP+1]?*Node   (used when !is_leaf)
// Allocation is explicit through a passed-in `std.mem.Allocator`. Lookup
// of a missing key returns -1 (matches bt_search). Tests cover insert
// + sorted-order, hit/miss search, and a single root split.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const BT_MAX: usize = 7;
const CAP: usize = BT_MAX + 1;

const Node = struct {
    is_leaf: bool,
    nkeys: usize,
    keys: [CAP]i64,
    vals: [CAP]i64,
    children: [CAP + 1]?*Node,

    fn newLeaf(allocator: std.mem.Allocator) !*Node {
        const n = try allocator.create(Node);
        n.* = .{
            .is_leaf = true,
            .nkeys = 0,
            .keys = [_]i64{0} ** CAP,
            .vals = [_]i64{0} ** CAP,
            .children = [_]?*Node{null} ** (CAP + 1),
        };
        return n;
    }

    fn newInternal(allocator: std.mem.Allocator) !*Node {
        const n = try allocator.create(Node);
        n.* = .{
            .is_leaf = false,
            .nkeys = 0,
            .keys = [_]i64{0} ** CAP,
            .vals = [_]i64{0} ** CAP,
            .children = [_]?*Node{null} ** (CAP + 1),
        };
        return n;
    }
};

fn freeTree(allocator: std.mem.Allocator, n: *Node) void {
    if (!n.is_leaf) {
        var i: usize = 0;
        while (i <= n.nkeys) : (i += 1) {
            if (n.children[i]) |child| freeTree(allocator, child);
        }
    }
    allocator.destroy(n);
}

fn leafInsert(leaf: *Node, key: i64, val: i64) void {
    const nk = leaf.nkeys;
    var pos: usize = nk;
    var i: usize = 0;
    while (i < nk) : (i += 1) {
        if (key <= leaf.keys[i]) { pos = i; break; }
    }
    var j: usize = nk;
    while (j > pos) : (j -= 1) {
        leaf.keys[j] = leaf.keys[j - 1];
        leaf.vals[j] = leaf.vals[j - 1];
    }
    leaf.keys[pos] = key;
    leaf.vals[pos] = val;
    leaf.nkeys = nk + 1;
}

fn findLeaf(root: *Node, key: i64) *Node {
    var node: *Node = root;
    while (!node.is_leaf) {
        var ci: usize = node.nkeys;
        var i: usize = 0;
        while (i < node.nkeys) : (i += 1) {
            if (key < node.keys[i]) { ci = i; break; }
        }
        node = node.children[ci].?;
    }
    return node;
}

fn btSearch(root: *Node, key: i64) i64 {
    const leaf = findLeaf(root, key);
    var i: usize = 0;
    while (i < leaf.nkeys) : (i += 1) {
        if (leaf.keys[i] == key) return leaf.vals[i];
    }
    return -1;
}

fn splitRootLeaf(allocator: std.mem.Allocator, old: *Node) !*Node {
    const nk = old.nkeys;
    const mid = nk / 2;
    const median = old.keys[mid];

    const left = try Node.newLeaf(allocator);
    const right = try Node.newLeaf(allocator);

    var i: usize = 0;
    while (i < mid) : (i += 1) {
        left.keys[i] = old.keys[i];
        left.vals[i] = old.vals[i];
    }
    left.nkeys = mid;

    i = mid;
    while (i < nk) : (i += 1) {
        right.keys[i - mid] = old.keys[i];
        right.vals[i - mid] = old.vals[i];
    }
    right.nkeys = nk - mid;

    const new_root = try Node.newInternal(allocator);
    new_root.keys[0] = median;
    new_root.children[0] = left;
    new_root.children[1] = right;
    new_root.nkeys = 1;

    allocator.destroy(old);
    return new_root;
}

fn btInsert(allocator: std.mem.Allocator, root: *Node, key: i64, val: i64) !*Node {
    if (root.is_leaf) {
        leafInsert(root, key, val);
        if (root.nkeys > BT_MAX) return splitRootLeaf(allocator, root);
        return root;
    }
    var ci: usize = root.nkeys;
    var i: usize = 0;
    while (i < root.nkeys) : (i += 1) {
        if (key < root.keys[i]) { ci = i; break; }
    }
    const child = root.children[ci].?;
    if (!child.is_leaf) @panic("multi-level split not implemented");
    leafInsert(child, key, val);
    if (child.nkeys > BT_MAX) @panic("multi-level split not implemented");
    return root;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // ── Test 1: basic insert and search ──
    {
        var t = try Node.newLeaf(alloc);
        defer freeTree(alloc, t);
        t = try btInsert(alloc, t, 10, 100);
        t = try btInsert(alloc, t, 5, 50);
        t = try btInsert(alloc, t, 20, 200);
        t = try btInsert(alloc, t, 15, 150);
        t = try btInsert(alloc, t, 3, 30);
        assert(btSearch(t, 10) == 100);
        assert(btSearch(t, 5) == 50);
        assert(btSearch(t, 3) == 30);
        assert(btSearch(t, 99) == -1);
    }

    // ── Test 2: keys sorted in leaf ──
    {
        var t = try Node.newLeaf(alloc);
        defer freeTree(alloc, t);
        t = try btInsert(alloc, t, 10, 100);
        t = try btInsert(alloc, t, 5, 50);
        t = try btInsert(alloc, t, 20, 200);
        t = try btInsert(alloc, t, 15, 150);
        t = try btInsert(alloc, t, 3, 30);
        assert(t.is_leaf);
        assert(t.nkeys == 5);
        assert(t.keys[0] == 3);
        assert(t.keys[4] == 20);
    }

    // ── Test 3: split on overflow ──
    {
        var t = try Node.newLeaf(alloc);
        defer freeTree(alloc, t);
        var i: i64 = 0;
        while (i <= @as(i64, BT_MAX)) : (i += 1) {
            t = try btInsert(alloc, t, i, i * 10);
        }
        assert(!t.is_leaf);
        i = 0;
        while (i <= @as(i64, BT_MAX)) : (i += 1) {
            assert(btSearch(t, i) == i * 10);
        }
        assert(btSearch(t, 999) == -1);
    }

    // ── Test 4: descending inserts are sorted ──
    {
        var t = try Node.newLeaf(alloc);
        defer freeTree(alloc, t);
        const keys = [_]i64{ 50, 40, 30, 20, 10 };
        for (keys) |k| {
            t = try btInsert(alloc, t, k, k * 2);
        }
        assert(t.is_leaf);
        assert(t.nkeys == 5);
        assert(t.keys[0] == 10);
        assert(t.keys[4] == 50);
        for (keys) |k| {
            assert(btSearch(t, k) == k * 2);
        }
    }

    print("All btree_indexing examples passed.\n", .{});
}
