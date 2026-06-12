// Vidya — Reproducible Builds in Zig
//
// A reproducible build is a pure function of its inputs: the same
// sources produce a byte-identical artifact, on any machine, at any
// time. Three classic sources of non-determinism, and their fixes:
//
//   1. Embedded wall-clock timestamps  → clamp every timestamp to
//      SOURCE_DATE_EPOCH (a fixed build time taken from the sources,
//      e.g. the last commit date) so "now" never leaks in.
//   2. Filesystem iteration order      → readdir() returns entries in
//      inode/hash order, which varies; SORT filenames before processing
//      so the output doesn't depend on directory layout.
//   3. Non-deterministic artifact names → name artifacts by the HASH of
//      their content (content-addressing), so identical inputs map to
//      identical paths — the build becomes idempotent.
//
// The verification is simple: build twice and compare digests. This
// models that pipeline over an in-memory set of files (name key +
// content signature) and shows a deterministic build staying identical
// across runs that differ in input order AND wall-clock time, while a
// naive build drifts.
//
// Zig: fixed-size arrays, no allocator. All arithmetic is i64 with
// @mod so the fold/hash matches the Cyrius reference exactly.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const HB: i64 = 131;
const HM: i64 = 1000003;
const HSEED: i64 = 7;

fn fold(h: i64, v: i64) i64 {
    return @mod(h * HB + v, HM);
}

// --- 1. Deterministic timestamps: clamp "now" to SOURCE_DATE_EPOCH ---
fn normalize_ts(now: i64, sde: i64) i64 {
    return if (now > sde) sde else now;
}

// --- 3. Content-addressed artifact path: a pure function of content ---
fn cas_path(content: i64) i64 {
    return @mod(content * HB + 7, HM);
}

// --- File set: parallel fixed arrays (name sort-key, content signature) ---
const MAX_FILES: usize = 128;

const FileSet = struct {
    name: [MAX_FILES]i64 = [_]i64{0} ** MAX_FILES,
    content: [MAX_FILES]i64 = [_]i64{0} ** MAX_FILES,
    n: usize = 0,

    fn set(self: *FileSet, i: usize, name: i64, content: i64) void {
        self.name[i] = name;
        self.content[i] = content;
    }

    // --- 2. Sorted iteration: insertion-sort files by name key,
    //     ascending, reordering content alongside so the pairing is
    //     preserved. ---
    fn sort(self: *FileSet) void {
        var i: usize = 1;
        while (i < self.n) : (i += 1) {
            const kn = self.name[i];
            const kc = self.content[i];
            var j: isize = @as(isize, @intCast(i)) - 1;
            while (j >= 0 and self.name[@intCast(j)] > kn) : (j -= 1) {
                self.name[@intCast(j + 1)] = self.name[@intCast(j)];
                self.content[@intCast(j + 1)] = self.content[@intCast(j)];
            }
            self.name[@intCast(j + 1)] = kn;
            self.content[@intCast(j + 1)] = kc;
        }
    }

    // --- The build: fold the (normalized) timestamp and every file's
    //     (name, content) into one artifact digest. Flags toggle the two
    //     determinism fixes so we can contrast a correct vs naive
    //     pipeline. ---
    fn build_digest(self: *FileSet, do_sort: bool, do_norm: bool, now: i64, sde: i64) i64 {
        if (do_sort) self.sort();
        const ts = if (do_norm) normalize_ts(now, sde) else now;
        var h = fold(HSEED, ts);
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            h = fold(h, self.name[i]);
            h = fold(h, self.content[i]);
        }
        return h;
    }
};

// Same SET of three files, presented in two different input orders.
fn order_a() FileSet {
    var fs = FileSet{};
    fs.n = 3;
    fs.set(0, 30, 111);
    fs.set(1, 10, 222);
    fs.set(2, 20, 333);
    return fs;
}

fn order_b() FileSet {
    var fs = FileSet{};
    fs.n = 3;
    fs.set(0, 20, 333);
    fs.set(1, 30, 111);
    fs.set(2, 10, 222);
    return fs;
}

pub fn main() !void {
    // 1. Deterministic timestamps
    assert(normalize_ts(9999, 5000) == 5000); // clamp future now to SDE
    assert(normalize_ts(3000, 5000) == 3000); // keep timestamp already <= SDE

    // 2. Sorted iteration: names ascending, content stays paired
    {
        var fs = order_a();
        fs.sort();
        assert(fs.name[0] == 10);
        assert(fs.name[1] == 20);
        assert(fs.name[2] == 30);
        assert(fs.content[0] == 222); // content followed name 10
    }

    // 3. Content-addressed path: pure function of content
    assert(cas_path(111) == cas_path(111)); // same content → same path
    assert(cas_path(111) != cas_path(222)); // different content → different path

    // Deterministic pipeline (sort + normalize): two builds that differ
    // in BOTH input order and wall-clock "now" must produce equal digests.
    {
        var a = order_a();
        var b = order_b();
        const d1 = a.build_digest(true, true, 9999, 5000);
        const d2 = b.build_digest(true, true, 8888, 5000);
        assert(d1 == d2); // deterministic build is byte-identical across runs
    }

    // Naive pipeline (no sort, raw now): the same source set yields
    // different digests when order or clock differ.
    {
        var a = order_a();
        var b = order_b();
        const d1 = a.build_digest(false, false, 9999, 5000);
        const d2 = b.build_digest(false, false, 8888, 5000);
        assert(d1 != d2); // naive build drifts with order + timestamp
    }

    // Normalization alone kills clock drift: same order, differing clock,
    // both clamp to SDE → identical digests.
    {
        var a1 = order_a();
        var a2 = order_a();
        const norm1 = a1.build_digest(true, true, 9999, 5000); // 9999 → 5000
        const norm2 = a2.build_digest(true, true, 7777, 5000); // 7777 → 5000
        assert(norm1 == norm2); // normalized timestamp removes clock dependence
    }

    print("All reproducible_builds examples passed.\n", .{});
}
