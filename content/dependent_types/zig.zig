// Vidya — Dependent Types in Zig
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// Zig is the strongest of the 11: a function can take a comptime value
// and return a type, so Vec(n) is one type per length and append returns
// Vec(n + m), the arithmetic done by the compiler. The limit is in the
// word comptime: a length known only at run time lives in a slice, refined
// by a checked constructor. And Zig fields are always public (section 5).

const std = @import("std");

var failures: usize = 0;

fn check(ok: bool, name: []const u8) void {
    if (!ok) {
        std.debug.print("FAIL: {s}\n", .{name});
        failures += 1;
    }
}

// --- 1. Length-indexed vector ---
// Vec(n) is a type computed from the value n. Each n gives a distinct
// type (Vec(2) and Vec(3) do not mix), the same n gives the same type
// (Vec(2 + 3) IS Vec(5)), and the length is stored nowhere: a Vec(3) is
// exactly its 3 elements.
fn Vec(comptime n: usize) type {
    return struct {
        items: [n]i64,
        pub const len = n;
    };
}

// The length, read from the TYPE of the argument.
fn vlen(v: anytype) usize {
    return @TypeOf(v).len;
}

// `comptime n` then `v: Vec(n)` is a Π type over compile-time values: the
// type of the second parameter depends on the value of the first. A call
// of head on an empty vector stops the build (the error is reported at the
// @compileError, with the call under "referenced by"):
//   _ = head(0, empty);
//   error: head of an empty vector
// and a Vec(2) where the signature says Vec(3) is a type error:
//   _ = head(3, a);
//   error: expected type 'zig.Vec(3)', found 'zig.Vec(2)'
fn head(comptime n: usize, v: Vec(n)) i64 {
    if (n == 0) @compileError("head of an empty vector");
    return v.items[0];
}

// The result type is computed from the arguments: Vec(n + m). Asking for
// the wrong length is refused:
//   const d: Vec(4) = append(2, 3, a, b);
//   error: expected type 'zig.Vec(4)', found 'zig.Vec(5)'
fn append(comptime n: usize, comptime m: usize, a: Vec(n), b: Vec(m)) Vec(n + m) {
    var out: Vec(n + m) = undefined;
    @memcpy(out.items[0..n], &a.items);
    @memcpy(out.items[n..], &b.items);
    return out;
}

// A length known only at run time cannot be a comptime argument. With
// n_rt the run-time length used in main:
//   const V = Vec(n_rt);
//   error: unable to resolve comptime value
//   note: argument to comptime parameter must be comptime-known
// So run-time data is a slice, which carries its length as a value, and
// head checks it when it runs: null for an empty slice.
fn sliceHead(items: []const i64) ?i64 {
    if (items.len == 0) return null;
    return items[0];
}

// The boundary between the two: the caller names the length it expects
// (comptime n), the run-time length is compared once, and what comes out
// is a Vec(n) that needs no further check.
fn toVec(comptime n: usize, items: []const i64) ?Vec(n) {
    if (items.len != n) return null;
    var v: Vec(n) = undefined;
    @memcpy(&v.items, items);
    return v;
}

// --- 2. Fin n: an index proven in range ---
// Fin(n) is made by init, which refuses anything outside 0..n-1, and
// index takes ONE n for both the vector and the index, so a Fin(2) used on
// a Vec(3) does not compile:
//   _ = index(3, b, Fin(2).init(1).?);
//   error: expected type 'zig.Fin(3)', found 'zig.Fin(2)'
// index has no check of its own: k.i < n was proved when k was built.
// (Zig's safe build modes, Debug and ReleaseSafe, still bounds-check
// items[k.i]; that is what catches the forged Fin of section 5.)
fn Fin(comptime n: usize) type {
    return struct {
        i: usize,
        const Self = @This();
        pub fn init(i: i64) ?Self {
            if (i < 0 or i >= n) return null;
            return .{ .i = @intCast(i) };
        }
    };
}

fn index(comptime n: usize, v: Vec(n), k: Fin(n)) i64 {
    return v.items[k.i];
}

const Vec2 = Vec(2);
const Vec3 = Vec(3);
const Fin2 = Fin(Vec2.len); // the bound IS the vector's length,
const Fin3 = Fin(Vec3.len); // not a second literal

// --- 3. Refinement at the boundary (parse, don't validate) ---
// Percent.init is the one place the range is checked; discount takes a
// Percent and trusts it. percent_checks counts validations.
var percent_checks: usize = 0;

const Percent = struct {
    v: i64,
    pub fn init(x: i64) ?Percent {
        percent_checks += 1;
        if (x < 0 or x > 100) return null;
        return .{ .v = x };
    }
};

fn discount(price: i64, p: Percent) i64 {
    return price - @divTrunc(price * p.v, 100);
}

// --- 4. Σ type (dependent pair) ---
// Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
// the first. With n known at compile time that is just Vec(n); with n
// known only at run time Zig cannot put it in a type, so Sized pairs a
// run-time n with a slice and init checks the dependency once. sizedSum
// then takes its loop bound from n alone. (A Zig slice is itself such a
// pair, pointer and length, kept consistent by the language for slices
// cut from arrays.)
const Sized = struct {
    n: usize,
    data: []const i64,
    pub fn init(n: usize, data: []const i64) ?Sized {
        if (data.len != n) return null;
        return .{ .n = n, .data = data };
    }
};

fn sizedSum(s: Sized) i64 {
    var total: i64 = 0;
    for (0..s.n) |i| total += s.data[i];
    return total;
}

// --- 5. The escape hatch ---
// Zig has no private fields: a struct literal is always allowed, so
// `Percent{ .v = 150 }` and `Fin3{ .i = 7 }` compile beside the checked
// constructors, and a field write rewrites a checked value in place.
// index(3, b, Fin3{ .i = 7 }) then compiles too; the Debug build stops it
// at run time ("panic: index out of bounds: index 7, len 3") and
// ReleaseFast removes that check. @bitCast is refused for this auto-layout
// struct ("cannot @bitCast to 'zig.Percent'"), but a @ptrCast of a
// *const i64 to a *const Percent compiles. What keeps the refinement
// honest is a rule that only init builds one, enforced by review (or a CI
// grep for `Percent{`).

pub fn main() void {
    // 1. Length-indexed vector
    const empty = Vec(0){ .items = .{} };
    const a = Vec2{ .items = .{ 1, 2 } };
    const b = Vec3{ .items = .{ 3, 4, 5 } };
    check(vlen(empty) == 0, "Vec(0)'s type says length 0");
    check(vlen(a) == 2, "Vec(2)'s type says length 2");
    check(vlen(b) == 3, "Vec(3)'s type says length 3");
    check(@sizeOf(Vec(0)) == 0, "a Vec(0) occupies 0 bytes");
    check(@sizeOf(Vec3) == 3 * @sizeOf(i64), "a Vec(3) is its 3 elements and no length field");
    check(head(2, a) == 1, "head([1, 2]) = 1");
    check(head(3, b) == 3, "head([3, 4, 5]) = 3");

    const c = append(2, 3, a, b);
    check(@TypeOf(c) == Vec(5), "append(Vec(2), Vec(3)) has type Vec(2 + 3) = Vec(5)");
    check(vlen(c) == 5, "append(Vec(2), Vec(3)) has length 5");
    var in_order = true;
    for (c.items, 0..) |x, i| {
        if (x != @as(i64, @intCast(i)) + 1) in_order = false;
    }
    check(in_order, "append(Vec(2), Vec(3)) reads [1, 2, 3, 4, 5]");

    // A run-time length: the empty case is refused when it happens.
    const buf = [_]i64{ 7, 8, 9 };
    var n_rt: usize = 0;
    _ = &n_rt;
    check(sliceHead(buf[0..n_rt]) == null, "run-time head of an empty slice is refused");
    n_rt = 1;
    check(sliceHead(buf[0..n_rt]) == 7, "run-time head of [7] = 7");
    check(toVec(3, buf[0..n_rt]) == null, "a run-time slice of length 1 is not a Vec(3)");
    n_rt = 3;
    const v3 = toVec(3, buf[0..n_rt]);
    check(v3 != null and head(3, v3.?) == 7, "a slice of length 3 becomes a Vec(3), head 7");

    // 2. Fin n
    check(Fin3.init(-1) == null, "Fin(3).init(-1) is refused");
    check(Fin3.init(3) == null, "Fin(3).init(3) is refused: 3 is not < 3");
    var accepted: usize = 0;
    var reads_ok = true;
    var i: i64 = -1;
    while (i <= 3) : (i += 1) {
        if (Fin3.init(i)) |k| {
            accepted += 1;
            if (index(3, b, k) != 3 + i) reads_ok = false;
        }
    }
    check(accepted == 3, "Fin(3) accepts exactly 0, 1, 2 out of -1..3");
    check(reads_ok, "index with each Fin(3) reads [3, 4, 5] in order");
    check(Fin2.init(2) == null, "Fin(2).init(2) is refused: 2 is not < 2");
    const k1 = Fin2.init(1);
    check(k1 != null and index(2, a, k1.?) == 2, "index([1, 2], Fin(2) 1) = 2");

    // 3. Refinement at the boundary
    percent_checks = 0;
    check(Percent.init(-1) == null, "Percent.init(-1) is refused");
    check(Percent.init(101) == null, "Percent.init(101) is refused");
    const p0 = Percent.init(0);
    const p100 = Percent.init(100);
    const p25 = Percent.init(25);
    check(p0 != null and p100 != null and p25 != null, "Percent.init accepts 0, 100 and 25");
    check(percent_checks == 5, "5 constructions, 5 validations");
    if (p0) |z| check(discount(200, z) == 200, "discount(200, 0%) = 200");
    if (p100) |h| check(discount(200, h) == 0, "discount(200, 100%) = 0");
    if (p25) |q| check(discount(200, q) == 150, "discount(200, 25%) = 150");
    check(percent_checks == 5, "discount never re-validated: still 5 checks after 3 calls");

    // 4. Σ type
    const two = [_]i64{ 1, 2 };
    const three = [_]i64{ 1, 2, 3 };
    check(Sized.init(3, &two) == null, "(3, [1, 2]) is refused: the length is 2");
    check(Sized.init(2, &three) == null, "(2, [1, 2, 3]) is refused: the length is 3");
    const s = Sized.init(3, &three);
    check(s != null, "(3, [1, 2, 3]) is built");
    if (s) |pair| {
        check(pair.n == 3, "the pair's n is 3");
        check(sizedSum(pair) == 6, "sizedSum reads n = 3 elements: 1 + 2 + 3 = 6");
    }

    // 5. The escape hatch
    check(Percent.init(150) == null, "the API refuses 150");
    const forged = Percent{ .v = 150 }; // a struct literal skips init
    check(forged.v == 150, "a struct literal makes a Percent of 150 anyway");
    check(discount(200, forged) == -100, "and discount trusts it: 200 - 300 = -100");
    if (Percent.init(30)) |checked| {
        var p = checked;
        p.v = 250; // a field write rewrites a checked Percent in place
        check(discount(100, p) == -150, "a field write breaks a checked Percent too: -150");
    } else check(false, "Percent.init(30) is accepted");

    if (failures != 0) std.process.exit(1);
    std.debug.print("All dependent type examples passed.\n", .{});
}
