// Vidya — Performance in TypeScript
//
// TypeScript compiles to JavaScript, so performance characteristics
// come from the JS engine (V8, SpiderMonkey, JSC). Key levers: avoid
// deoptimization, use typed arrays for numeric work, minimize GC
// pressure, and understand the hidden class system.

function main(): void {
    // ── Monomorphic functions: keep types consistent ───────────────
    // V8 optimizes functions that always receive the same types.
    // Polymorphic calls (different shapes) cause deoptimization.

    // GOOD: always called with same shape
    function addNumbers(a: number, b: number): number {
        return a + b;
    }
    assert(addNumbers(1, 2) === 3, "monomorphic");

    // BAD: calling with different types forces V8 to deoptimize
    // function add(a: any, b: any) { return a + b; }
    // add(1, 2); add("a", "b"); add(1.0, 2.0); // deopt!

    // ── Hidden classes: consistent object shapes ───────────────────
    // V8 assigns hidden classes to objects based on property order.
    // Objects with the same properties in the same order share a hidden class.

    // GOOD: consistent shape — shared hidden class
    function makePoint(x: number, y: number) {
        return { x, y }; // always x then y
    }
    const p1 = makePoint(1, 2);
    const p2 = makePoint(3, 4);
    assert(p1.x + p2.x === 4, "consistent shape");

    // BAD: different property order = different hidden class
    // const a = { x: 1, y: 2 };
    // const b = { y: 2, x: 1 }; // different hidden class!

    // ── TypedArrays: fast numeric operations ───────────────────────
    // TypedArrays store numbers in contiguous memory — cache friendly,
    // no boxing overhead, SIMD-friendly.

    const n = 10_000;
    const float64 = new Float64Array(n);
    for (let i = 0; i < n; i++) {
        float64[i] = i * 0.1;
    }

    let sum = 0;
    for (let i = 0; i < n; i++) {
        sum += float64[i]; // fast: no boxing, sequential access
    }
    assert(sum > 0, "typed array sum");

    // Regular array of numbers: each number may be boxed
    // const regular = Array.from({length: n}, (_, i) => i * 0.1);

    // ── Avoid creating objects in hot loops ─────────────────────────
    // GOOD: reuse objects / use primitives
    let totalX = 0;
    let totalY = 0;
    for (let i = 0; i < 1000; i++) {
        totalX += i;
        totalY += i * 2;
    }
    assert(totalX === 499500, "no object allocation in loop");

    // BAD: creating objects per iteration
    // for (let i = 0; i < 1000; i++) {
    //     const point = { x: i, y: i * 2 }; // GC pressure
    //     totalX += point.x;
    // }

    // ── Map vs Object for dynamic keys ─────────────────────────────
    // Map is faster than Object for frequent add/delete of keys

    const map = new Map<number, number>();
    for (let i = 0; i < 1000; i++) {
        map.set(i, i * i);
    }
    assert(map.get(500) === 250000, "map lookup");
    assert(map.size === 1000, "map size");

    // Object: slower for dynamic keys, triggers hidden class transitions
    // const obj: Record<string, number> = {};
    // for (let i = 0; i < 1000; i++) obj[i] = i * i;

    // ── Set for membership testing ─────────────────────────────────
    const set = new Set<number>();
    for (let i = 0; i < 10000; i++) set.add(i);
    assert(set.has(5000), "set lookup O(1)");

    // Array.includes is O(n):
    // const arr = Array.from({length: 10000}, (_, i) => i);
    // arr.includes(5000); // linear scan

    // ── String concatenation: template literals vs + ───────────────
    // Template literals are optimized in modern engines
    const parts: string[] = [];
    for (let i = 0; i < 100; i++) {
        parts.push(`item${i}`);
    }
    const joined = parts.join(","); // O(n), one allocation
    assert(joined.startsWith("item0,item1"), "join");

    // BAD: string += in a loop
    // let s = "";
    // for (let i = 0; i < 100; i++) s += `item${i},`; // O(n²)

    // ── Array pre-allocation ───────────────────────────────────────
    // new Array(n) creates a holey array — fill or use Array.from
    const preallocated = new Array<number>(1000);
    for (let i = 0; i < 1000; i++) {
        preallocated[i] = i;
    }
    assert(preallocated[999] === 999, "preallocated");

    // Array.from with mapper — no holes
    const fromMapper = Array.from({ length: 5 }, (_, i) => i * 2);
    assertArrayEq(fromMapper, [0, 2, 4, 6, 8], "Array.from");

    // ── Avoid delete: use Map or set to undefined ──────────────────
    // delete triggers hidden class transition (slow)
    // obj.prop = undefined is faster but keeps the key

    // GOOD: use Map for dynamic key sets
    const cache = new Map<string, number>();
    cache.set("key", 42);
    cache.delete("key"); // O(1), no deopt

    // ── for loop vs forEach vs for-of ──────────────────────────────
    // Plain for loop is fastest (no function call overhead)
    // for-of is nearly as fast
    // forEach has function call overhead per element

    const data = Array.from({ length: 100 }, (_, i) => i);
    let forSum = 0;
    for (let i = 0; i < data.length; i++) {
        forSum += data[i]; // fastest
    }
    assert(forSum === 4950, "for loop");

    // ── Measuring performance ──────────────────────────────────────
    const start = performance.now();
    let _dummy = 0;
    for (let i = 0; i < 100000; i++) _dummy += i;
    const elapsed = performance.now() - start;
    assert(elapsed >= 0, "performance.now timing");

    console.log("All performance examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function assertArrayEq<T>(got: T[], expected: T[], msg: string): void {
    assert(
        got.length === expected.length && got.every((v, i) => v === expected[i]),
        `${msg}: got [${got}], expected [${expected}]`,
    );
}

main();
