// Vidya — Build Systems in Zig
//
// A minimal build-system core: a DAG of targets, topological build
// order, content-signature dirty-tracking, and ninja-style incremental
// rebuild (only dirty targets run), plus cycle detection.
//
// No real files or compilers: each target carries a source "content
// signature" (an i64). A target's INPUT signature mixes its own source
// with the OUTPUT signatures of its dependencies; if that differs from
// the signature it was last built against, the target is dirty and
// rebuilds. Editing a source re-dirties everything downstream — exactly
// how mtime/hash-based tools (make, ninja, bazel) decide what to redo.
//
// Zig uses parallel fixed-size arrays (no allocator needed) inside a
// BuildSystem struct; @mod gives the exact polynomial signature mix.

const std = @import("std");
const print = std.debug.print;

const MAXN: usize = 16; // max targets
const MAXD: usize = 8; //  max deps per target
const HB: i64 = 131; //    signature polynomial base
const HM: i64 = 1000003; // signature modulus (prime; keeps values < 2^53)

const BuildSystem = struct {
    n: usize = 0,
    src: [MAXN]i64 = undefined, //                 source content signature
    depcnt: [MAXN]usize = undefined, //            number of dependencies
    deps: [MAXN][MAXD]usize = undefined, //        per-target dep ids
    built: [MAXN]i64 = undefined, //               signature last built against (-1 = never)
    out: [MAXN]i64 = undefined, //                 current output signature
    order: [MAXN]usize = undefined, //             topological order (target ids)
    placed: [MAXN]bool = undefined, //             topo scratch: placed flag

    fn reset(self: *BuildSystem, n: usize) void {
        self.n = n;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.src[i] = 0;
            self.depcnt[i] = 0;
            self.built[i] = -1; // never built
            self.out[i] = 0;
        }
    }

    fn setSrc(self: *BuildSystem, t: usize, signature: i64) void {
        self.src[t] = signature;
    }

    fn addDep(self: *BuildSystem, t: usize, d: usize) void {
        const c = self.depcnt[t];
        self.deps[t][c] = d;
        self.depcnt[t] = c + 1;
    }

    // Topological sort (Kahn-style ready-scan). Writes target ids into
    // order and returns how many were ordered; < n ⇒ a cycle left some
    // targets unreachable.
    fn topo(self: *BuildSystem) usize {
        var i: usize = 0;
        while (i < self.n) : (i += 1) self.placed[i] = false;
        var placed: usize = 0;
        while (placed < self.n) {
            var progress = false;
            var t: usize = 0;
            while (t < self.n) : (t += 1) {
                if (!self.placed[t]) {
                    // ready iff every dependency is already placed
                    var ready = true;
                    var k: usize = 0;
                    while (k < self.depcnt[t]) : (k += 1) {
                        if (!self.placed[self.deps[t][k]]) ready = false;
                    }
                    if (ready) {
                        self.order[placed] = t;
                        self.placed[t] = true;
                        placed += 1;
                        progress = true;
                    }
                }
            }
            if (!progress) return placed; // stuck ⇒ cycle
        }
        return placed;
    }

    // Input signature: mix this target's source with deps' outputs.
    fn sig(self: *BuildSystem, t: usize) i64 {
        var s = @mod(self.src[t], HM);
        var k: usize = 0;
        while (k < self.depcnt[t]) : (k += 1) {
            const d = self.deps[t][k];
            s = @mod(s * HB + self.out[d], HM);
        }
        return s;
    }

    // Incremental build: walk topo order, rebuild only dirty targets.
    // Output is content-addressed (out == input signature), so a target
    // whose inputs are unchanged keeps its output and its dependents stay
    // clean. Returns the number of targets rebuilt.
    fn build(self: *BuildSystem) usize {
        const ordered = self.topo();
        var rebuilt: usize = 0;
        var i: usize = 0;
        while (i < ordered) : (i += 1) {
            const t = self.order[i];
            const s = self.sig(t);
            if (s != self.built[t]) {
                self.out[t] = s; //    produce output
                self.built[t] = s; //  remember what we built
                rebuilt += 1;
            }
        }
        return rebuilt;
    }

    fn orderPos(self: *BuildSystem, target: usize) i64 {
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            if (self.order[i] == target) return @as(i64, @intCast(i));
        }
        return -1;
    }
};

// Classic C build graph:  app(2) <- util.o(0), main.o(1)
fn buildGraph(bs: *BuildSystem) void {
    bs.reset(3);
    bs.setSrc(0, 1001); // util.c
    bs.setSrc(1, 2002); // main.c
    bs.setSrc(2, 3003); // link recipe
    bs.addDep(2, 0);
    bs.addDep(2, 1);
}

fn check(cond: bool) !void {
    if (!cond) return error.AssertionFailed;
}

pub fn main() !void {
    var bs: BuildSystem = .{};

    // topo orders all 3, app after both deps
    buildGraph(&bs);
    try check(bs.topo() == 3);
    try check(bs.orderPos(2) > bs.orderPos(0));
    try check(bs.orderPos(2) > bs.orderPos(1));

    // cold build rebuilds all 3
    buildGraph(&bs);
    try check(bs.build() == 3);

    // second build (no edits) rebuilds nothing
    buildGraph(&bs);
    _ = bs.build(); // cold
    try check(bs.build() == 0);

    // edit main.c rebuilds main.o + app
    buildGraph(&bs);
    _ = bs.build(); // cold
    bs.setSrc(1, 2999);
    try check(bs.build() == 2);

    // edit util.c rebuilds util.o + app, main.o left untouched
    buildGraph(&bs);
    _ = bs.build();
    const main_built = bs.built[1];
    bs.setSrc(0, 1999);
    try check(bs.build() == 2);
    try check(bs.built[1] == main_built);

    // 0 <-> 1 cycle leaves targets unordered
    bs.reset(2);
    bs.addDep(0, 1);
    bs.addDep(1, 0);
    try check(bs.topo() < 2);

    print("All build_systems examples passed.\n", .{});
}
