// Vidya — Render Graph Architecture in Zig
//
// Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

const std = @import("std");

const PASS_CAP: usize = 16;

const Graph = struct {
    pass_id: [PASS_CAP]u64 = [_]u64{0} ** PASS_CAP,
    reads: [PASS_CAP]u64 = [_]u64{0} ** PASS_CAP,
    writes: [PASS_CAP]u64 = [_]u64{0} ** PASS_CAP,
    count: usize = 0,
    topo_order: [PASS_CAP]usize = [_]usize{0} ** PASS_CAP,
    topo_len: usize = 0,

    fn addPass(self: *Graph, id: u64, r: u64, w: u64) i32 {
        if (self.count >= PASS_CAP) return -1;
        const idx = self.count;
        self.pass_id[idx] = id;
        self.reads[idx] = r;
        self.writes[idx] = w;
        self.count += 1;
        return @intCast(idx);
    }

    fn hasEdge(self: *const Graph, p: usize, c: usize) bool {
        return (self.writes[p] & self.reads[c]) != 0;
    }

    fn topoSort(self: *Graph) usize {
        var in_degree: [PASS_CAP]i32 = [_]i32{0} ** PASS_CAP;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            var j: usize = 0;
            while (j < self.count) : (j += 1) {
                if (i != j and self.hasEdge(j, i)) in_degree[i] += 1;
            }
        }
        self.topo_len = 0;
        var emitted: usize = 0;
        while (emitted < self.count) {
            var picked: i32 = -1;
            var k: usize = 0;
            while (k < self.count) : (k += 1) {
                if (in_degree[k] == 0) { picked = @intCast(k); break; }
            }
            if (picked < 0) return self.topo_len;
            const p: usize = @intCast(picked);
            self.topo_order[self.topo_len] = p;
            self.topo_len += 1;
            in_degree[p] = -1;
            var c: usize = 0;
            while (c < self.count) : (c += 1) {
                if (c != p and self.hasEdge(p, c) and in_degree[c] > 0) {
                    in_degree[c] -= 1;
                }
            }
            emitted += 1;
        }
        return self.topo_len;
    }

    fn barrierCount(self: *const Graph) usize {
        var count: usize = 0;
        var i: usize = 0;
        while (i < self.topo_len) : (i += 1) {
            var j: usize = i + 1;
            while (j < self.topo_len) : (j += 1) {
                if (self.hasEdge(self.topo_order[i], self.topo_order[j])) count += 1;
            }
        }
        return count;
    }

    fn cullDead(self: *Graph) usize {
        var culled: usize = 0;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const w = self.writes[i];
            if (w == 0) continue;
            var any_reader = false;
            var j: usize = 0;
            while (j < self.count) : (j += 1) {
                if (i != j and (w & self.reads[j]) != 0) { any_reader = true; break; }
            }
            if (!any_reader) {
                self.writes[i] = 0;
                self.reads[i] = 0;
                culled += 1;
            }
        }
        return culled;
    }
};

pub fn main() !void {
    var g = Graph{};

    if (g.addPass(100, 0, 1) != 0) return error.A;
    if (g.addPass(101, 1, 2) != 1) return error.B;
    if (g.addPass(102, 2, 0) != 2) return error.C;

    if (g.topoSort() != 3) return error.Topo3;
    if (g.topo_order[0] != 0) return error.T0;
    if (g.topo_order[1] != 1) return error.T1;
    if (g.topo_order[2] != 2) return error.T2;

    if (g.barrierCount() != 2) return error.Barriers;

    if (g.addPass(103, 0, 4) != 3) return error.D;
    if (g.cullDead() != 1) return error.Cull;
    if (g.writes[3] != 0) return error.WritesZeroed;
    if (g.topoSort() != 4) return error.Topo4;
    if (g.barrierCount() != 2) return error.BarriersPost;

    var g2 = Graph{};
    _ = g2.addPass(200, 1, 2);
    _ = g2.addPass(201, 2, 1);
    if (g2.topoSort() != 0) return error.Cycle;

    std.debug.print("render_graph_architecture: 14/14 ok\n", .{});
}
