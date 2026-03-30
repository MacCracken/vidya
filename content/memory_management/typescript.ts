// Vidya — Memory Management in TypeScript
//
// TypeScript/JS uses garbage collection — you don't free memory manually.
// But understanding object references, closures, WeakRef, and the event
// loop helps avoid memory leaks in long-running applications.

function main(): void {
    // ── Reference semantics: objects are shared ────────────────────
    const a = { x: 1, y: 2 };
    const b = a; // b points to the same object
    b.x = 99;
    assert(a.x === 99, "shared reference");

    // ── Value semantics: primitives are copied ─────────────────────
    let num = 42;
    let copy = num;
    copy = 100;
    assert(num === 42, "primitive copy");

    // ── Shallow vs deep copy ───────────────────────────────────────
    const original = { nested: { value: 1 }, top: "hello" };

    // Shallow copy: spread operator
    const shallow = { ...original };
    shallow.top = "changed";
    assert(original.top === "hello", "shallow top independent");
    shallow.nested.value = 99;
    assert(original.nested.value === 99, "shallow nested shared!");

    // Deep copy: structuredClone (modern) or JSON roundtrip
    const deep = structuredClone({ nested: { value: 1 }, top: "hello" });
    deep.nested.value = 99;
    // original is not affected by deep copy

    // ── Array copying ──────────────────────────────────────────────
    const arr = [1, 2, 3];
    const arrCopy = [...arr]; // shallow copy
    arrCopy.push(4);
    assert(arr.length === 3, "array copy independent");

    // ── Closures capture references, not values ────────────────────
    function makeCounter(): () => number {
        let count = 0; // captured by closure — stays alive
        return () => ++count;
    }

    const counter = makeCounter();
    assert(counter() === 1, "closure 1");
    assert(counter() === 2, "closure 2");
    assert(counter() === 3, "closure 3");
    // `count` lives as long as `counter` exists

    // ── GOTCHA: closures in loops ──────────────────────────────────
    // BAD: var is function-scoped — all closures share same variable
    // for (var i = 0; i < 3; i++) { setTimeout(() => console.log(i)); }
    // prints 3, 3, 3

    // GOOD: let is block-scoped — each iteration gets its own binding
    const results: number[] = [];
    for (let i = 0; i < 3; i++) {
        results.push(i); // each i is a separate binding
    }
    assertArrayEq(results, [0, 1, 2], "let scoping");

    // ── WeakRef: reference that doesn't prevent GC ─────────────────
    let obj: { data: string } | undefined = { data: "hello" };
    const weak = new WeakRef(obj);
    assert(weak.deref()?.data === "hello", "weakref deref");

    // If we remove the strong reference, GC can collect the object
    obj = undefined;
    // weak.deref() may return undefined after GC runs

    // ── WeakMap: keys can be garbage collected ─────────────────────
    const cache = new WeakMap<object, string>();
    let key: object | undefined = { id: 1 };
    cache.set(key, "cached value");
    assert(cache.get(key) === "cached value", "weakmap get");

    key = undefined; // entry can be GC'd now
    // No way to iterate WeakMap — that's by design

    // ── WeakSet ────────────────────────────────────────────────────
    const seen = new WeakSet<object>();
    const item = { name: "test" };
    seen.add(item);
    assert(seen.has(item), "weakset has");

    // ── FinalizationRegistry: cleanup callback ─────────────────────
    // Runs when an object is garbage collected
    // const registry = new FinalizationRegistry((heldValue) => {
    //     console.log(`Object with ${heldValue} was collected`);
    // });
    // registry.register(someObject, "identifier");

    // ── Object.freeze: prevent mutation ────────────────────────────
    const frozen = Object.freeze({ x: 1, y: 2 });
    // frozen.x = 99; // ← TypeError in strict mode, silently fails otherwise
    assert(frozen.x === 1, "frozen immutable");

    // GOTCHA: freeze is shallow
    const shallowFrozen = Object.freeze({ inner: { value: 1 } });
    shallowFrozen.inner.value = 99; // inner object is NOT frozen
    assert(shallowFrozen.inner.value === 99, "shallow freeze gotcha");

    // ── Avoiding memory leaks ──────────────────────────────────────

    // Leak pattern 1: forgotten event listeners
    // element.addEventListener("click", handler);
    // Fix: element.removeEventListener("click", handler);
    // Or use AbortController:
    // const ctrl = new AbortController();
    // element.addEventListener("click", handler, { signal: ctrl.signal });
    // ctrl.abort(); // removes all listeners registered with this signal

    // Leak pattern 2: growing collections
    // const log: string[] = [];
    // setInterval(() => log.push(new Date().toString()), 1000);
    // Fix: cap the size or use a circular buffer

    // Leak pattern 3: closures holding references
    // function setup() {
    //     const largeData = new Uint8Array(1_000_000);
    //     return () => largeData.length; // closure keeps largeData alive
    // }

    // ── TypedArrays: efficient binary data ─────────────────────────
    const buffer = new ArrayBuffer(16); // 16 bytes
    const view = new Int32Array(buffer); // 4 x 32-bit ints
    view[0] = 42;
    view[1] = 100;
    assert(view.length === 4, "typed array length");
    assert(view[0] === 42, "typed array access");
    assert(view.byteLength === 16, "byte length");

    // ── Using const for immutable bindings ─────────────────────────
    // const prevents reassignment, not mutation
    const arr2 = [1, 2, 3];
    arr2.push(4); // allowed — mutates the array
    assert(arr2.length === 4, "const allows mutation");
    // arr2 = [5, 6]; // ← error: can't reassign const

    console.log("All memory management examples passed.");
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
