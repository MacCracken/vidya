// Vidya — Functional Patterns — TypeScript port.
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that
// shares structure instead of copying, folds as its recursion scheme, and
// stack depth without tail calls.
//
// JavaScript closures capture VARIABLES: a closure sees later
// assignments. A `var` is one variable for the whole function, so loop
// closures share it; `let` makes a fresh one per iteration. `readonly` is
// compile-time only (a cast, or a plain alias, gets past it), while
// Object.freeze refuses writes at run time. V8 has no tail calls.

function assert(cond: boolean, name: string): void {
    if (!cond) throw new Error("FAIL: " + name);
}

// --- 1. Purity ---
// A pure function's result depends only on its arguments, and calling it
// changes nothing. TypeScript cannot check that: no const fn, and nothing
// runs a function at compile time (`as const` only narrows literal types).
function pureAdd(a: number, b: number): number {
    return a + b;
}

let counter = 0; // hidden state impureNext reads and bumps

function impureNext(): number {
    counter += 1;
    return counter;
}

// countedAdd is pureAdd plus a call counter, so a check can see whether
// the underlying function ran (the counter is the test's probe; the value
// is still pureAdd's).
let addCalls = 0;

function countedAdd(a: number, b: number): number {
    addCalls += 1;
    return pureAdd(a, b);
}

// memoize2: cache results by argument. Sound only for a pure function,
// since a cached result must be what a fresh call would return. The key
// is BOTH arguments; a key of `a` alone would hand (2, 4) the result
// cached for (2, 3), and lodash's _.memoize does exactly that unless it
// is given a resolver. A Map keyed on the array [a, b] would never hit:
// arrays compare by identity, so the key is a string of both numbers.
type Fn2 = (a: number, b: number) => number;

function memoize2(f: Fn2): Fn2 {
    const table = new Map<string, number>();
    return (a, b) => {
        const key = `${a},${b}`;
        const hit = table.get(key);
        if (hit !== undefined) return hit;
        const v = f(a, b);
        table.set(key, v);
        return v;
    };
}

// --- 2. Higher-order functions and composition ---
// compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
// pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
// Generic over the types in between.
const addThree = (x: number): number => x + 3;
const timesTwo = (x: number): number => x * 2;

function compose<A, B, C>(f: (b: B) => C, g: (a: A) => B): (a: A) => C {
    return (x) => f(g(x));
}

function pipe<A, B, C>(f: (a: A) => B, g: (b: B) => C): (a: A) => C {
    return (x) => g(f(x));
}

// --- 3. Closures and partial application ---
// makeAdder(n) returns a function that remembers n.
function makeAdder(n: number): (x: number) => number {
    return (x) => x + n;
}

// Private mutable state: the closure captures n itself, so n += 1 inside
// it updates the one n, and nothing outside can reach it. Each
// makeCounter() call makes a new n, so two counters never share a count.
function makeCounter(): () => number {
    let n = 0;
    return () => {
        n += 1;
        return n;
    };
}

function add3(a: number, b: number, c: number): number {
    return a + b + c;
}

// partial(f, a, b) fixes the first two arguments of a 3-argument function.
// Function.prototype.bind is the built-in form; under --strict
// (strictBindCallApply) tsc types add3.bind(null, 1, 2) as (c: number) => number.
function partial(f: (a: number, b: number, c: number) => number, a: number, b: number): (c: number) => number {
    return (c) => f(a, b, c);
}

// --- 4. The capture gotcha (what a closure sees of a loop variable) ---
// A `var` is hoisted to the function: ONE i for the whole loop, which the
// loop leaves at 3 before any closure is called. `let` in a for header
// gets a new binding per iteration, copied forward, so each closure keeps
// its own. The fix for `var` code is `let`.
function closuresFromVarLoop(): number[] {
    const fs: Array<() => number> = [];
    for (var i = 0; i < 3; i++) {
        fs.push(() => i);
    }
    return fs.map((f) => f());
}

function closuresFromLetLoop(): number[] {
    const fs: Array<() => number> = [];
    for (let i = 0; i < 3; i++) {
        fs.push(() => i);
    }
    return fs.map((f) => f());
}

// --- 5. Persistent (immutable) list with structural sharing ---
// A cons cell is a head and a tail; null is the empty list. cons never
// copies its tail, so prepending is O(1) and the old list is still whole
// and unchanged. `readonly` stops `node.head = 99` at compile time
// (error TS2540: Cannot assign to 'head' because it is a read-only
// property), but it is erased from the emitted JavaScript and does not
// survive a cast, or even a plain assignment to a { head: number }
// variable, which tsc accepts. Object.freeze is the run-time guard (and is shallow).
interface Cons {
    readonly head: number;
    readonly tail: List;
}
type List = Cons | null;

const NIL: List = null;
let consAllocs = 0; // nodes allocated, so checks can count copying

function cons(head: number, tail: List): Cons {
    consAllocs += 1;
    return { head, tail };
}

function head(xs: List): number {
    if (xs === null) throw new Error("head of the empty list");
    return xs.head;
}

function tail(xs: List): List {
    if (xs === null) throw new Error("tail of the empty list");
    return xs.tail;
}

function listOf(...values: number[]): List {
    let xs: List = NIL;
    for (let k = values.length - 1; k >= 0; k--) xs = cons(values[k]!, xs);
    return xs;
}

function nth(xs: List, i: number): number {
    let p = xs;
    for (let k = 0; k < i; k++) p = tail(p);
    return head(p);
}

// Structural equality: same values in the same order (not the same nodes).
function listEq(a: List, b: List): boolean {
    let p = a;
    let q = b;
    while (p !== null && q !== null) {
        if (p.head !== q.head) return false;
        p = p.tail;
        q = q.tail;
    }
    return p === null && q === null;
}

// Functional update: a new list with element i replaced. It copies the i
// cells in front of i plus the replaced cell (i + 1 allocations) and
// shares everything after it. The original list is not touched.
function updateAt(xs: List, i: number, v: number): List {
    if (xs === null) return NIL;
    if (i === 0) return cons(v, xs.tail);
    return cons(xs.head, updateAt(xs.tail, i - 1, v));
}

// --- 6. Fold as the recursion scheme ---
// foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
// foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
// Array.prototype.reduce / reduceRight are the built-in folds over arrays.
function foldr<A>(f: (x: number, acc: A) => A, z: A, xs: List): A {
    if (xs === null) return z;
    return f(xs.head, foldr(f, z, xs.tail));
}

function foldl<A>(f: (acc: A, x: number) => A, z: A, xs: List): A {
    let acc = z;
    for (let p = xs; p !== null; p = p.tail) acc = f(acc, p.head);
    return acc;
}

const listLength = (xs: List): number => foldl((acc: number) => acc + 1, 0, xs);
const listSum = (xs: List): number => foldl((acc: number, x) => acc + x, 0, xs);
const listReverse = (xs: List): List => foldl((acc: List, x) => cons(x, acc), NIL, xs);
const listMap = (g: (x: number) => number, xs: List): List =>
    foldr((x, acc: List) => cons(g(x), acc), NIL, xs);

const sub = (a: number, b: number): number => a - b;

// --- 7. Tail recursion and stack depth ---
// ES2015 requires proper tail calls in strict code, but only
// JavaScriptCore (Safari) ships them; V8 (Node, Chrome) and SpiderMonkey
// do not, so in Node every call keeps its frame. Naive recursion,
// n + sum(n - 1), ran out at about 9,770 levels here (tsx on Node 26,
// V8's default stack of about 1 MB), with RangeError: Maximum call stack
// size exceeded, so 100,000 is ten times too deep. The accumulator loop
// needs no frames. 5000050000 < 2^53, so a number holds it exactly.
function sumToLoop(n: number): number {
    let acc = 0;
    for (let i = 1; i <= n; i++) acc += i;
    return acc;
}

// === Tests ===

function sameArray(a: readonly number[], b: readonly number[]): boolean {
    return a.length === b.length && a.every((v, k) => v === b[k]);
}

{
    // 1. Purity
    const r1 = pureAdd(2, 3);
    const r2 = pureAdd(2, 3);
    assert(r1 === r2, "pureAdd: same arguments, same result");
    assert(r1 === 5, "pureAdd(2, 3) = 5");

    counter = 0;
    const n1 = impureNext();
    const n2 = impureNext();
    assert(n1 !== n2, "impureNext: same call, different results (1, then 2)");
    assert(counter === 2, "impureNext left a trace: hidden state bumped twice");
}
{
    // 1. Memoization
    addCalls = 0;
    const madd = memoize2(countedAdd);
    const m1 = madd(2, 3);
    const m2 = madd(2, 3);
    assert(m1 === 5, "memo: first call computes 2 + 3 = 5");
    assert(m2 === 5, "memo: second call returns the cached 5");
    assert(addCalls === 1, "memo: second call is a cache hit (1 call, not 2)");
    assert(madd(2, 4) === 6, "memo: (2, 4) is a miss, the key is both arguments");
    assert(addCalls === 2, "memo: the miss ran the underlying function once more");
    assert(!new Map([[[2, 3], 5]]).has([2, 3]), "a Map keyed on arrays never hits: identity, not contents");
}
{
    // 2. Composition
    const c = compose(addThree, timesTwo);
    const p = pipe(addThree, timesTwo);
    assert(c(1) === 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5");
    assert(p(1) === 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8");
    assert(c(1) !== p(1), "order matters: compose != pipe at x = 1");

    // The laws, over a range of x: compose applies g first, and pipe is
    // compose with its arguments swapped.
    const cgf = compose(timesTwo, addThree);
    const xs = [-2, -1, 0, 1, 2];
    assert(xs.every((x) => c(x) === addThree(timesTwo(x))), "compose(f, g)(x) == f(g(x)) for x in -2..2");
    assert(xs.every((x) => p(x) === cgf(x)), "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2");
}
{
    // 3. Closures and partial application
    const add5 = makeAdder(5);
    const add10 = makeAdder(10);
    assert(add5(1) === 6, "makeAdder(5)(1) = 6");
    assert(add10(1) === 11, "makeAdder(10)(1) = 11: each adder keeps its own n");

    const c1 = makeCounter();
    const c2 = makeCounter();
    c1();
    c1();
    assert(c1() === 3, "counter 1 counted 1, 2, 3");
    assert(c2() === 1, "counter 2 starts at 1: its state is its own");
    assert(c1() === 4, "counter 1 carries on at 4, untouched by counter 2");

    assert(partial(add3, 1, 2)(3) === 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6");
    const bound = add3.bind(null, 1, 2);
    assert(bound(3) === 6, "add3.bind(null, 1, 2)(3) = 6: bind is built-in partial application");
}
{
    // 4. The capture gotcha
    assert(sameArray(closuresFromVarLoop(), [3, 3, 3]), "var: one i for the loop, every closure sees 3");
    assert(sameArray(closuresFromLetLoop(), [0, 1, 2]), "let: one i per iteration, closures see 0, 1, 2");

    // After the fact: the closure sees a later assignment, unless it
    // captured a copy made while the value was still 1.
    let base = 1;
    const g = (): number => base;
    const snapshot = base;
    const gEarly = (): number => snapshot;
    base = 99;
    assert(g() === 99, "captured the variable: g sees the later base = 99");
    assert(gEarly() === 1, "captured a const copy: gEarly kept 1");
}
{
    // 5. Persistent list
    const xs = listOf(1, 2, 3);
    const ys = cons(0, xs);
    assert(tail(ys) === xs, "cons shares: tail(ys) IS xs, the same node");
    assert(listEq(ys, listOf(0, 1, 2, 3)), "ys reads [0, 1, 2, 3]");
    assert(listEq(xs, listOf(1, 2, 3)), "xs still reads [1, 2, 3] after the cons");

    const before = consAllocs;
    const zs = updateAt(xs, 1, 20);
    assert(consAllocs - before === 2, "update at index 1 allocates i + 1 = 2 nodes, not 3");
    assert(listEq(zs, listOf(1, 20, 3)), "zs reads [1, 20, 3]");
    assert(tail(tail(zs)) === tail(tail(xs)), "the suffix after the updated cell is shared");
    assert(tail(zs) !== tail(xs), "the updated cell is new, not xs's");
    assert(listEq(xs, listOf(1, 2, 3)), "xs still reads [1, 2, 3] after the update");

    // The gotcha: write through a node two versions share and both change.
    // `tail(vs).head = 99` would not compile; the cast gets past readonly.
    const vs = listOf(1, 2, 3);
    const ws = updateAt(vs, 0, 7); // ws = [7, 2, 3], shares vs's [2, 3]
    (tail(vs) as { head: number }).head = 99; // in-place write to the shared cell
    assert(nth(ws, 1) === 99, "a write through a shared node changes the other version too");

    // Object.freeze refuses the same write at run time. Reflect.set
    // reports the refusal as false, in strict and sloppy code alike.
    const frozen = Object.freeze(cons(2, NIL));
    assert(!Reflect.set(frozen, "head", 99), "a frozen node refuses the write");
    assert(frozen.head === 2, "a frozen node still reads 2");
}
{
    // 6. Folds
    const xs = listOf(1, 2, 3);
    assert(listLength(xs) === 3, "length via foldl = 3");
    assert(listLength(NIL) === 0, "length of the empty list = 0");
    assert(listSum(xs) === 6, "sum via foldl = 1 + 2 + 3 = 6");
    assert(listEq(listReverse(xs), listOf(3, 2, 1)), "reverse via foldl = [3, 2, 1]");
    assert(listEq(listMap((x) => x * 10, xs), listOf(10, 20, 30)), "map via foldr keeps order: [10, 20, 30]");
    assert(listEq(xs, listOf(1, 2, 3)), "the folds left xs as [1, 2, 3]");

    // Subtraction is not associative, so the fold's direction shows.
    assert(foldl(sub, 0, xs) === -6, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6");
    assert(foldr(sub, 0, xs) === 2, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2");
}
{
    // 7. Tail calls
    assert(sumToLoop(100000) === 5000050000, "accumulator loop: sum 1..100000 = 5000050000");
}

console.log("All functional pattern examples passed.");
process.exit(0);
