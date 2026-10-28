// Vidya — Render Graph Architecture in Zig
//
// Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

const std = @import("std");

const PASS_CAP: usize = 16;

const Graph = struct {
    pass_id: [PASS_CAP]u64 = @splat(0),
    reads: [PASS_CAP]u64 = @splat(0),
    writes: [PASS_CAP]u64 = @splat(0),
    count: usize = 0,
    topo_order: [PASS_CAP]usize = @splat(0),
    topo_len: usize = 0,
    culled: [PASS_CAP]bool = @splat(false),

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
        var in_degree: [PASS_CAP]i32 = @splat(0);
        var live: usize = 0;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            // A culled pass is never scheduled: mark it as already emitted
            if (self.culled[i]) { in_degree[i] = -1; continue; }
            live += 1;
            var j: usize = 0;
            while (j < self.count) : (j += 1) {
                if (i != j and !self.culled[j] and self.hasEdge(j, i)) in_degree[i] += 1;
            }
        }
        self.topo_len = 0;
        var emitted: usize = 0;
        while (emitted < live) {
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

    // Remove passes whose outputs no live pass reads. Passes that write
    // nothing are sinks (present / readback) and always stay. Iterates to
    // a fixed point: culling a pass can strand the producer that only fed
    // it, so a single sweep under-culls. Culled passes leave the schedule.
    fn cullDead(self: *Graph) usize {
        var culled: usize = 0;
        var changed = true;
        while (changed) {
            changed = false;
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                if (self.culled[i]) continue;
                const w = self.writes[i];
                if (w == 0) continue;
                var any_reader = false;
                var j: usize = 0;
                while (j < self.count) : (j += 1) {
                    if (i != j and !self.culled[j] and (w & self.reads[j]) != 0) { any_reader = true; break; }
                }
                if (!any_reader) {
                    self.culled[i] = true;
                    self.writes[i] = 0;
                    self.reads[i] = 0;
                    culled += 1;
                    changed = true;
                }
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
    // The culled pass is out of the schedule: 3 passes run, not 4
    if (g.topoSort() != 3) return error.CulledStillScheduled;
    for (g.topo_order[0..g.topo_len]) |p| if (p == 3) return error.CulledInOrder;
    if (g.barrierCount() != 2) return error.BarriersPost;

    // Transitive: P0 -> P1 -> (nobody); a sink P2 reads nothing.
    // P1 is dead, and then so is P0, whose only reader was P1.
    var g3 = Graph{};
    _ = g3.addPass(300, 0, 1);
    _ = g3.addPass(301, 1, 2);
    _ = g3.addPass(302, 0, 0);
    if (g3.cullDead() != 2) return error.CullTransitive;
    if (g3.topoSort() != 1) return error.TopoAfterTransitive;

    var g2 = Graph{};
    _ = g2.addPass(200, 1, 2);
    _ = g2.addPass(201, 2, 1);
    if (g2.topoSort() != 0) return error.Cycle;

    std.debug.print("render_graph_architecture: 17/17 ok\n", .{});
}
