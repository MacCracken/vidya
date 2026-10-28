// Vidya — Functional Patterns in Zig
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that shares
// structure instead of copying, folds as its recursion scheme, and a tail
// call the language guarantees. Mirrors cyrius.cyr's checks; the two tail
// call ones run only where the backend can emit one (section 7).
//
// Zig has no closures: no function can capture a local. The two honest
// encodings are a struct whose fields are the captures and whose `call`
// method is the body (a value, so its env lives wherever the struct does,
// usually the stack), and a function built at comptime from comptime
// arguments, which needs no env at all (compose and pipe below). List
// nodes come from a FixedBufferAllocator over a static buffer.

const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;

const Error = std.mem.Allocator.Error;

fn check(ok: bool, what: []const u8) !void {
    if (!ok) {
        print("FAIL: {s}\n", .{what});
        return error.CheckFailed;
    }
}

// --- 1. Purity ---
// A pure fn's result depends only on its arguments, and calling it changes
// nothing. Zig does not check purity, but comptime evaluation runs only
// what needs no runtime state: the block below runs pureAdd inside the
// compiler, and `comptime impureNext()` is refused with "unable to evaluate
// comptime expression", "operation is runtime due to this operand" (the
// runtime global g_counter).
fn pureAdd(a: i64, b: i64) i64 {
    return a + b;
}

comptime {
    if (pureAdd(2, 3) != 5) @compileError("pureAdd(2, 3) runs at compile time and must be 5");
}

var g_counter: i64 = 0; // hidden state impureNext reads and bumps
fn impureNext() i64 {
    g_counter += 1;
    return g_counter;
}

// Memoization caches results by argument, so it is sound only for a pure
// fn. countedAdd is pureAdd plus a call counter, the test's probe for
// whether the underlying fn ran. The key is BOTH arguments; a key of `a`
// alone would hand (2, 4) the result cached for (2, 3).
var g_add_calls: i64 = 0;
fn countedAdd(a: i64, b: i64) i64 {
    g_add_calls += 1;
    return pureAdd(a, b);
}

const MEMO_CAP = 8;

// memoize2(f) returns a closure with f's call shape that owns its table.
const Memo2 = struct {
    f: *const fn (i64, i64) i64,
    n: usize = 0,
    keys: [MEMO_CAP][2]i64 = undefined,
    vals: [MEMO_CAP]i64 = undefined,

    fn call(self: *Memo2, a: i64, b: i64) i64 {
        for (self.keys[0..self.n], self.vals[0..self.n]) |k, v| {
            if (k[0] == a and k[1] == b) return v;
        }
        const v = self.f(a, b);
        if (self.n < MEMO_CAP) {
            self.keys[self.n] = .{ a, b };
            self.vals[self.n] = v;
            self.n += 1;
        }
        return v;
    }
};

fn memoize2(f: *const fn (i64, i64) i64) Memo2 {
    return .{ .f = f };
}

// --- 2. Higher-order functions and composition ---
// compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
// pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
// Both run in the compiler: given two comptime-known fns they return a new
// fn, an ordinary function with nothing captured at run time.
fn addThree(x: i64) i64 {
    return x + 3;
}

fn timesTwo(x: i64) i64 {
    return x * 2;
}

const Fn1 = fn (i64) i64;

fn compose(comptime f: Fn1, comptime g: Fn1) Fn1 {
    return struct {
        fn h(x: i64) i64 {
            return f(g(x));
        }
    }.h;
}

fn pipe(comptime f: Fn1, comptime g: Fn1) Fn1 {
    return struct {
        fn h(x: i64) i64 {
            return g(f(x));
        }
    }.h;
}

// --- 3. Closures and partial application ---
// makeAdder(n) returns a struct that copied n; makeCounter() one whose
// private state is a field. A counter is a value, so `var c3 = c1;` copies
// its count, and c3 then counts on from there, apart from c1.
const Adder = struct {
    n: i64,
    fn call(self: Adder, x: i64) i64 {
        return x + self.n;
    }
};

fn makeAdder(n: i64) Adder {
    return .{ .n = n };
}

const Counter = struct {
    count: i64 = 0,
    fn call(self: *Counter) i64 {
        self.count += 1;
        return self.count;
    }
};

fn makeCounter() Counter {
    return .{};
}

// partial(f, bound) fixes the leading arguments of any fn: comptime knows
// f's parameter list, and the call concatenates the bound tuple with the
// rest (`++` on tuples), so one helper serves every arity.
fn add3(a: i64, b: i64, c: i64) i64 {
    return a + b + c;
}

fn Partial(comptime f: anytype, comptime Bound: type) type {
    const R = @typeInfo(@TypeOf(f)).@"fn".return_type.?;
    return struct {
        bound: Bound,
        fn call(self: @This(), rest: anytype) R {
            return @call(.auto, f, self.bound ++ rest);
        }
    };
}

fn partial(comptime f: anytype, bound: anytype) Partial(f, @TypeOf(bound)) {
    return .{ .bound = bound };
}

// --- 4. The capture gotcha (what a closure sees of a loop variable) ---
// Python's `[lambda: i for i in range(3)]` gives [2, 2, 2] and a JS `var`
// loop [3, 3, 3]: those closures look the variable up when CALLED. In Zig
// the struct says which. ByValue copies the value when it is built (early
// binding); ByAddress holds a pointer to one variable and reads it when
// called (late binding). A `for (0..3) |i|` capture is a new constant each
// iteration, and its address dies with the iteration, so late binding
// needs a variable that outlives the loop.
const ByValue = struct {
    v: i64,
    fn call(self: ByValue) i64 {
        return self.v;
    }
};

const ByAddress = struct {
    p: *const i64,
    fn call(self: ByAddress) i64 {
        return self.p.*;
    }
};

// --- 5. Persistent (immutable) list with structural sharing ---
// A cons cell is {head, tail}; null is the empty list. cons never copies
// its tail, so prepending is O(1) and the old list is still a complete,
// unchanged list. `*const Node` makes a write through a list a compile
// error, unless @constCast takes the const away (see the gotcha). Nodes
// come from a fixed buffer and are never freed, so no version can free a
// node another one shares.
const Node = struct { head: i64, tail: List };
const List = ?*const Node;

const Pool = struct {
    fba: std.heap.FixedBufferAllocator,
    allocs: usize = 0, // nodes allocated, so checks can count copying

    fn cons(self: *Pool, h: i64, t: List) Error!List {
        const c = try self.fba.allocator().create(Node);
        c.* = .{ .head = h, .tail = t };
        self.allocs += 1;
        return c;
    }

    fn list3(self: *Pool, a: i64, b: i64, c: i64) Error!List {
        return self.cons(a, try self.cons(b, try self.cons(c, null)));
    }
};

// tail of the empty list is the empty list here (Clojure's `rest`), so a
// chain like tail(tail(xs)) needs no unwrapping.
fn tail(xs: List) List {
    return if (xs) |n| n.tail else null;
}

fn nth(xs: List, i: usize) ?i64 {
    var p = xs;
    var k = i;
    while (k > 0) : (k -= 1) p = tail(p);
    return if (p) |n| n.head else null;
}

// Structural equality: same values in the same order (not the same nodes).
fn listEq(a: List, b: List) bool {
    var p = a;
    var q = b;
    while (p != null and q != null) : ({
        p = p.?.tail;
        q = q.?.tail;
    }) {
        if (p.?.head != q.?.head) return false;
    }
    return p == null and q == null;
}

// Functional update: a new list with element i replaced. It copies the i
// cells in front of i plus the replaced cell (i + 1 allocations) and shares
// everything after it. The original list is not touched.
fn updateAt(pool: *Pool, xs: List, i: usize, v: i64) Error!List {
    const n = xs orelse return null;
    if (i == 0) return pool.cons(v, n.tail);
    return pool.cons(n.head, try updateAt(pool, n.tail, i - 1, v));
}

// --- 6. Fold as the recursion scheme ---
// foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
// foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
// A step is any value with a `call` method (anytype: comptime makes one
// copy of the fold per step type). Steps return Error!A because reverse
// and map allocate, and the allocator's failure stays visible in the type.
fn foldl(comptime A: type, z: A, xs: List, step: anytype) Error!A {
    var acc = z;
    var p = xs;
    while (p) |n| : (p = n.tail) acc = try step.call(acc, n.head);
    return acc;
}

fn foldr(comptime A: type, z: A, xs: List, step: anytype) Error!A {
    const n = xs orelse return z;
    return step.call(n.head, try foldr(A, z, n.tail, step));
}

const LenStep = struct {
    fn call(_: LenStep, acc: i64, _: i64) Error!i64 {
        return acc + 1;
    }
};

const SumStep = struct {
    fn call(_: SumStep, acc: i64, x: i64) Error!i64 {
        return acc + x;
    }
};

const RevStep = struct {
    pool: *Pool,
    fn call(self: RevStep, acc: List, x: i64) Error!List {
        return self.pool.cons(x, acc);
    }
};

fn MapStep(comptime G: type) type {
    return struct {
        g: G,
        pool: *Pool,
        fn call(self: @This(), x: i64, acc: List) Error!List {
            return self.pool.cons(self.g.call(x), acc);
        }
    };
}

// One subtraction serves both folds: foldl calls it as (acc, x) and foldr
// as (x, acc), and both are i64 here.
const Sub = struct {
    fn call(_: Sub, a: i64, b: i64) Error!i64 {
        return a - b;
    }
};

const TimesTen = struct {
    fn call(_: TimesTen, x: i64) i64 {
        return x * 10;
    }
};

fn listLength(xs: List) Error!i64 {
    return foldl(i64, 0, xs, LenStep{});
}

fn listSum(xs: List) Error!i64 {
    return foldl(i64, 0, xs, SumStep{});
}

fn listReverse(pool: *Pool, xs: List) Error!List {
    return foldl(List, null, xs, RevStep{ .pool = pool });
}

fn listMap(pool: *Pool, g: anytype, xs: List) Error!List {
    return foldr(List, null, xs, MapStep(@TypeOf(g)){ .g = g, .pool = pool });
}

// --- 7. Tail recursion and stack depth ---
// Zig is the one language of these whose tail calls are a promise:
// `@call(.always_tail, f, args)` is a jump, or the program does not
// compile; it never quietly becomes an ordinary call. Zig 0.17's own
// x86_64 backend, which Debug builds use, cannot emit one yet and stops
// with "unable to perform tail call: compiler backend 'stage2_x86_64'
// does not support tail calls". The LLVM backend (release builds, -fllvm,
// aarch64) can, so sumToTail is compiled and checked only there; under
// the self-hosted backend the guard below leaves it out and the loop
// carries the check. Naive recursion, `return n + sum(n - 1)`, needs one
// frame per level to do the `+` after the call returns.
fn sumToLoop(n: i64) i64 {
    var acc: i64 = 0;
    var i: i64 = 1;
    while (i <= n) : (i += 1) acc += i;
    return acc;
}

fn sumToTail(n: i64, acc: i64) i64 {
    if (n == 0) return acc;
    return @call(.always_tail, sumToTail, .{ n - 1, acc + n });
}

const backend_tail_calls = builtin.zig_backend == .stage2_llvm;

// === Tests ===

fn testPurity() !void {
    const r1 = pureAdd(2, 3);
    const r2 = pureAdd(2, 3);
    try check(r1 == r2, "pure_add: same arguments, same result");
    try check(r1 == 5, "pure_add(2, 3) = 5");

    g_counter = 0;
    const n1 = impureNext();
    const n2 = impureNext();
    try check(n1 != n2, "impure_next: same call, different results (1, then 2)");
    try check(g_counter == 2, "impure_next left a trace: hidden state bumped twice");
}

fn testMemoize() !void {
    g_add_calls = 0;
    var madd = memoize2(&countedAdd);
    const m1 = madd.call(2, 3);
    const m2 = madd.call(2, 3);
    try check(m1 == 5, "memo: first call computes 2 + 3 = 5");
    try check(m2 == 5, "memo: second call returns the cached 5");
    try check(g_add_calls == 1, "memo: second call is a cache hit (1 call, not 2)");
    try check(madd.call(2, 4) == 6, "memo: (2, 4) is a miss, the key is both arguments");
    try check(g_add_calls == 2, "memo: the miss ran the underlying fn once more");
}

fn testComposition() !void {
    const c = compose(addThree, timesTwo);
    const p = pipe(addThree, timesTwo);
    try check(c(1) == 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5");
    try check(p(1) == 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8");
    try check(c(1) != p(1), "order matters: compose != pipe at x = 1");

    // The laws, over a range of x: compose applies g first, and pipe is
    // compose with its arguments swapped.
    const cgf = compose(timesTwo, addThree);
    var ok_c = true;
    var ok_p = true;
    var x: i64 = -2;
    while (x <= 2) : (x += 1) {
        if (c(x) != addThree(timesTwo(x))) ok_c = false;
        if (p(x) != cgf(x)) ok_p = false;
    }
    try check(ok_c, "compose(f, g)(x) == f(g(x)) for x in -2..2");
    try check(ok_p, "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2");
}

fn testClosures() !void {
    const add5 = makeAdder(5);
    const add10 = makeAdder(10);
    try check(add5.call(1) == 6, "make_adder(5)(1) = 6");
    try check(add10.call(1) == 11, "make_adder(10)(1) = 11: each adder keeps its own n");

    var c1 = makeCounter();
    var c2 = makeCounter();
    _ = c1.call();
    _ = c1.call();
    try check(c1.call() == 3, "counter 1 counted 1, 2, 3");
    try check(c2.call() == 1, "counter 2 starts at 1: its state is its own");
    try check(c1.call() == 4, "counter 1 carries on at 4, untouched by counter 2");

    const add_1_2 = partial(add3, .{ 1, 2 });
    try check(add_1_2.call(.{3}) == 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6");
}

fn testCapture() !void {
    // By value: each closure copies i as it was when the closure was built.
    var fs: [3]ByValue = undefined;
    for (0..3) |i| fs[i] = .{ .v = @intCast(i) };
    try check(fs[0].call() == 0, "by value: closure 0 returns 0");
    try check(fs[1].call() == 1, "by value: closure 1 returns 1");
    try check(fs[2].call() == 2, "by value: closure 2 returns 2");

    // Early binding: a later assignment is not seen.
    var base: i64 = 1;
    const g = ByValue{ .v = base };
    base = 99;
    try check(g.call() == 1, "by value: captured 1, the later base = 99 is not seen");

    // Late binding on purpose: every closure points at the one j and reads
    // it when called, after the loop left it at 3: the JS `var` result.
    // The fix is to capture the value.
    var refs: [3]ByAddress = undefined;
    var j: i64 = 0;
    while (j < 3) : (j += 1) refs[@intCast(j)] = .{ .p = &j };
    try check(refs[0].call() == 3, "by address: closure 0 sees j's final 3");
    try check(refs[1].call() == 3, "by address: closure 1 sees j's final 3");
    try check(refs[2].call() == 3, "by address: closure 2 sees j's final 3");
}

fn testPersistentList(pool: *Pool) !void {
    const xs = try pool.list3(1, 2, 3);
    const ys = try pool.cons(0, xs);
    try check(tail(ys) == xs, "cons shares: tail(ys) IS xs, the same node");
    try check(listEq(ys, try pool.cons(0, try pool.list3(1, 2, 3))), "ys reads [0, 1, 2, 3]");
    try check(listEq(xs, try pool.list3(1, 2, 3)), "xs still reads [1, 2, 3] after the cons");

    const before = pool.allocs;
    const zs = try updateAt(pool, xs, 1, 20);
    try check(pool.allocs - before == 2, "update at index 1 allocates i + 1 = 2 nodes, not 3");
    try check(listEq(zs, try pool.list3(1, 20, 3)), "zs reads [1, 20, 3]");
    try check(tail(tail(zs)) == tail(tail(xs)), "the suffix after the updated cell is shared");
    try check(tail(zs) != tail(xs), "the updated cell is new, not xs's");
    try check(listEq(xs, try pool.list3(1, 2, 3)), "xs still reads [1, 2, 3] after the update");

    // The gotcha: write through a node two versions share and both change.
    // `tail(vs).?.head = 99` does not compile (the node is const); the
    // @constCast does, and is defined only because the nodes live in a
    // mutable buffer. Persistence is a rule the code keeps.
    const vs = try pool.list3(1, 2, 3);
    const ws = try updateAt(pool, vs, 0, 7); // ws = [7, 2, 3], shares vs's [2, 3]
    @constCast(tail(vs).?).head = 99; //          in-place write to the shared cell
    try check(nth(ws, 1) == 99, "a write through a shared node changes the other version too");
}

fn testFolds(pool: *Pool) !void {
    const xs = try pool.list3(1, 2, 3);
    try check(try listLength(xs) == 3, "length via foldl = 3");
    try check(try listLength(null) == 0, "length of the empty list = 0");
    try check(try listSum(xs) == 6, "sum via foldl = 1 + 2 + 3 = 6");
    try check(listEq(try listReverse(pool, xs), try pool.list3(3, 2, 1)), "reverse via foldl = [3, 2, 1]");
    try check(listEq(try listMap(pool, TimesTen{}, xs), try pool.list3(10, 20, 30)), "map via foldr keeps order: [10, 20, 30]");
    try check(listEq(xs, try pool.list3(1, 2, 3)), "the folds left xs as [1, 2, 3]");

    // Subtraction is not associative, so the fold's direction shows.
    try check(try foldl(i64, 0, xs, Sub{}) == -6, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6");
    try check(try foldr(i64, 0, xs, Sub{}) == 2, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2");
}

fn testTailCalls() !void {
    try check(sumToLoop(100_000) == 5_000_050_000, "accumulator loop: sum 1..100000 = 5000050000");
    if (comptime backend_tail_calls) {
        try check(sumToTail(100_000, 0) == 5_000_050_000, "tail call: sum 1..100000 = 5000050000");
        // 10,000,000 levels as real calls would need hundreds of MB of
        // stack, far past the default 8 MiB, so finishing at all shows each
        // level was a jump. The result is n(n + 1) / 2.
        try check(sumToTail(10_000_000, 0) == 50_000_005_000_000, "tail call 10,000,000 deep runs in constant stack");
    }
}

var node_buf: [128 * @sizeOf(Node)]u8 align(@alignOf(Node)) = undefined;

pub fn main() !void {
    var pool = Pool{ .fba = std.heap.FixedBufferAllocator.init(&node_buf) };
    try testPurity();
    try testMemoize();
    try testComposition();
    try testClosures();
    try testCapture();
    try testPersistentList(&pool);
    try testFolds(&pool);
    try testTailCalls();
    print("All functional pattern examples passed.\n", .{});
}
