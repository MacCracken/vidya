// Vidya — Package Resolution in Zig
//
// Semantic versioning, caret constraint matching, range intersection
// for diamond dependencies, highest-version selection, bounded
// backtracking, and dependency-cycle detection — the core of a
// dependency resolver (npm, cargo, cyrius.cyml's own resolver).
//
// A semver major.minor.patch is encoded as one i64
//   enc = major*1_000_000 + minor*1_000 + patch
// so version comparison IS integer comparison. A constraint is a
// half-open range [lo, hi). A caret ^X.Y.Z allows everything from
// X.Y.Z up to (but not including) the next major: [X.Y.Z, (X+1).0.0).
// Resolving a shared ("diamond") dependency means intersecting the
// ranges every requirer imposes and picking the highest version that
// survives — and backtracking on an earlier choice when the highest
// pick paints a later dependency into an impossible corner.
//
// No allocator: every collection is a fixed-size array.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const VMAJ: i64 = 1_000_000;
const VMIN: i64 = 1_000;

// --- Semver encode / inspect ---
fn sv(maj: i64, min: i64, pat: i64) i64 {
    return maj * VMAJ + min * VMIN + pat;
}
fn svMajor(v: i64) i64 {
    return @divTrunc(v, VMAJ);
}

// --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---
fn caretLo(v: i64) i64 {
    return v;
}
fn caretHi(v: i64) i64 {
    return (svMajor(v) + 1) * VMAJ;
}

// --- Constraint satisfaction over a half-open range ---
fn satisfies(v: i64, lo: i64, hi: i64) bool {
    return lo <= v and v < hi;
}

// --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---
fn rangeLoMax(a: i64, b: i64) i64 {
    return if (a > b) a else b;
}
fn rangeHiMin(a: i64, b: i64) i64 {
    return if (a < b) a else b;
}
fn rangeEmpty(lo: i64, hi: i64) bool {
    return lo >= hi;
}

// --- Highest version in vers[0..n) that lies in [lo, hi); -1 if none ---
fn bestMatch(vers: []const i64, lo: i64, hi: i64) i64 {
    var best: i64 = -1;
    for (vers) |v| {
        if (satisfies(v, lo, hi) and v > best) best = v;
    }
    return best;
}

// --- Available versions of the shared dependency C: {1.0.0, 1.5.0, 2.0.0} ---
fn cVersions() [3]i64 {
    return .{ sv(1, 0, 0), sv(1, 5, 0), sv(2, 0, 0) };
}

// --- Diamond resolution: A requires C ^a_base, B requires C ^b_base.
//     Intersect the two carets and pick the highest C that fits.
//     Returns chosen C version, or -1 if the constraints conflict. ---
fn resolveShared(c_vers: []const i64, a_base: i64, b_base: i64) i64 {
    const lo = rangeLoMax(caretLo(a_base), caretLo(b_base));
    const hi = rangeHiMin(caretHi(a_base), caretHi(b_base));
    if (rangeEmpty(lo, hi)) return -1;
    return bestMatch(c_vers, lo, hi);
}

// --- Bounded backtracking: A has candidate versions (a_vers), each of
//     which requires a different caret on C (a_creq). B requires C
//     ^b_base. The absolute-highest A may force a C constraint that
//     conflicts with B; choose the HIGHEST A for which some C still
//     satisfies both. Reports the chosen C alongside the chosen A. ---
const Backtrack = struct { a: i64, c: i64 };

fn resolveBacktrack(
    c_vers: []const i64,
    a_vers: []const i64,
    a_creq: []const i64,
    b_base: i64,
) Backtrack {
    var best_a: i64 = -1;
    var best_c: i64 = -1;
    for (a_vers, a_creq) |aver, creq| {
        const lo = rangeLoMax(caretLo(creq), caretLo(b_base));
        const hi = rangeHiMin(caretHi(creq), caretHi(b_base));
        if (!rangeEmpty(lo, hi)) {
            const c = bestMatch(c_vers, lo, hi);
            if (c != -1 and aver > best_a) {
                best_a = aver;
                best_c = c;
            }
        }
    }
    return .{ .a = best_a, .c = best_c };
}

// --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
//     some package permanently unplaceable). ---
const MAXP: usize = 128;
const MAXD: usize = 8;

const Graph = struct {
    n: usize = 0,
    depcnt: [MAXP]usize = [_]usize{0} ** MAXP,
    deps: [MAXP][MAXD]usize = [_][MAXD]usize{[_]usize{0} ** MAXD} ** MAXP,

    fn reset(self: *Graph, n: usize) void {
        self.n = n;
        var i: usize = 0;
        while (i < n) : (i += 1) self.depcnt[i] = 0;
    }
    fn addDep(self: *Graph, p: usize, d: usize) void {
        const c = self.depcnt[p];
        self.deps[p][c] = d;
        self.depcnt[p] = c + 1;
    }
    fn hasCycle(self: *const Graph) bool {
        var placed_flag = [_]bool{false} ** MAXP;
        var placed: usize = 0;
        while (placed < self.n) {
            var progress = false;
            var p: usize = 0;
            while (p < self.n) : (p += 1) {
                if (placed_flag[p]) continue;
                var ready = true;
                var k: usize = 0;
                while (k < self.depcnt[p]) : (k += 1) {
                    if (!placed_flag[self.deps[p][k]]) ready = false;
                }
                if (ready) {
                    placed_flag[p] = true;
                    placed += 1;
                    progress = true;
                }
            }
            if (!progress) return true; // stuck => cycle
        }
        return false;
    }
};

pub fn main() !void {
    // --- semver ---
    assert(sv(1, 2, 3) > sv(1, 2, 0));
    assert(sv(2, 0, 0) > sv(1, 9, 9));
    assert(svMajor(sv(1, 5, 2)) == 1);

    // --- caret ---
    assert(caretLo(sv(1, 2, 0)) == sv(1, 2, 0));
    assert(caretHi(sv(1, 2, 0)) == sv(2, 0, 0));
    assert(satisfies(sv(1, 4, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))));
    assert(!satisfies(sv(2, 0, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))));
    assert(!satisfies(sv(1, 1, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))));

    // --- intersect ---
    assert(rangeLoMax(sv(1, 0, 0), sv(1, 3, 0)) == sv(1, 3, 0));
    assert(rangeHiMin(sv(2, 0, 0), sv(3, 0, 0)) == sv(2, 0, 0));
    {
        const lo = rangeLoMax(caretLo(sv(1, 0, 0)), caretLo(sv(2, 0, 0)));
        const hi = rangeHiMin(caretHi(sv(1, 0, 0)), caretHi(sv(2, 0, 0)));
        assert(rangeEmpty(lo, hi)); // ^1.0.0 and ^2.0.0 are disjoint
    }

    const c_vers = cVersions();

    // --- best_match ---
    assert(bestMatch(&c_vers, caretLo(sv(1, 0, 0)), caretHi(sv(1, 0, 0))) == sv(1, 5, 0));
    assert(bestMatch(&c_vers, caretLo(sv(3, 0, 0)), caretHi(sv(3, 0, 0))) == -1);

    // --- diamond resolution ---
    assert(resolveShared(&c_vers, sv(1, 0, 0), sv(1, 0, 0)) == sv(1, 5, 0));
    assert(resolveShared(&c_vers, sv(1, 0, 0), sv(2, 0, 0)) == -1);

    // --- bounded backtracking ---
    // A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
    // The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
    {
        const a_vers = [_]i64{ sv(1, 1, 0), sv(1, 0, 0) };
        const a_creq = [_]i64{ sv(2, 0, 0), sv(1, 0, 0) };
        const r = resolveBacktrack(&c_vers, &a_vers, &a_creq, sv(1, 0, 0));
        assert(r.a == sv(1, 0, 0)); // backtrack picks A 1.0.0, not 1.1.0
        assert(r.c == sv(1, 5, 0)); // and resolves C to 1.5.0
    }

    // --- cycle detection ---
    {
        var g = Graph{};
        g.reset(2);
        g.addDep(0, 1);
        g.addDep(1, 0);
        assert(g.hasCycle()); // A<->B is a dependency cycle

        g.reset(3);
        g.addDep(2, 0);
        g.addDep(2, 1); // app -> A, B (diamond, acyclic)
        assert(!g.hasCycle());
    }

    print("All package_resolution examples passed.\n", .{});
}
