// Vidya — Ownership and Borrowing in TypeScript
//
// TypeScript has garbage collection — there is no ownership system, no
// borrow checker, no lifetimes. Memory safety comes from the GC, not
// the type system. But TypeScript has tools that approximate some of
// Rust's ownership concepts:
//
//   Rust ownership → TS has GC (no manual ownership needed)
//   Rust &T        → TS Readonly<T> (shallow, compile-time only)
//   Rust &mut T    → TS normal reference (everything is mutable by default)
//   Rust move      → TS has no moves; references are always shared
//   Rust Drop      → TS FinalizationRegistry (non-deterministic)
//   Rust Weak<T>   → TS WeakRef<T>
//   Rust Clone     → TS structuredClone / spread operator
//
// This file shows what TypeScript does instead, and where it falls short.

// ── No dangling references: GC guarantees safety ──────────────────
// In Rust, this would be a lifetime error. In TypeScript, the GC
// keeps the object alive as long as any reference exists.

function noDanglingRefs(): void {
    function createRef(): { value: number } {
        const obj = { value: 42 };
        return obj; // In Rust: would need to prove obj outlives the return
        // In TS: GC keeps obj alive — no dangling reference possible
    }

    const ref = createRef();
    assert(ref.value === 42, "no dangling: GC keeps object alive");
}

// ── Readonly: compile-time immutability (like Rust's &T) ──────────
// Readonly<T> prevents mutation at the type level, but it's shallow
// and erased at runtime. Rust's &T is enforced at compile time AND
// prevents all aliased mutation.

interface Point {
    x: number;
    y: number;
}

function readonlyDemo(): void {
    const p: Point = { x: 1, y: 2 };
    const shared: Readonly<Point> = p;

    // shared.x = 10; // ← TypeScript error: readonly property
    assert(shared.x === 1, "readonly prevents mutation");

    // GOTCHA: Readonly is shallow — nested objects are still mutable
    interface Nested {
        inner: { value: number };
    }

    const obj: Readonly<Nested> = { inner: { value: 1 } };
    obj.inner.value = 99; // ← allowed! Readonly only protects top level
    assert(obj.inner.value === 99, "readonly is shallow");

    // Deep readonly requires a recursive type
    type DeepReadonly<T> = {
        readonly [K in keyof T]: T[K] extends object ? DeepReadonly<T[K]> : T[K];
    };

    const deep: DeepReadonly<Nested> = { inner: { value: 1 } };
    // deep.inner.value = 99; // ← TypeScript error with DeepReadonly
    assert(deep.inner.value === 1, "deep readonly works");
}

// ── Defensive copying: simulating Rust's Clone ────────────────────
// Rust requires explicit .clone() for deep copies. TypeScript has
// structuredClone (deep) and spread (shallow).

function defensiveCopyDemo(): void {
    // Shallow copy: spread operator — like Rust's Copy for flat structs
    const original = { x: 1, y: 2, label: "origin" };
    const shallow = { ...original };
    shallow.x = 99;
    assert(original.x === 1, "shallow copy: original unchanged");

    // Deep copy: structuredClone — like Rust's Clone
    const nested = { data: [1, 2, 3], meta: { count: 3 } };
    const deep = structuredClone(nested);
    deep.data.push(4);
    deep.meta.count = 99;
    assert(nested.data.length === 3, "deep copy: original array unchanged");
    assert(nested.meta.count === 3, "deep copy: original meta unchanged");

    // Object.freeze: runtime immutability (shallow)
    const frozen = Object.freeze({ x: 1, y: 2 });
    // frozen.x = 99; // ← TypeError at runtime in strict mode
    assert(frozen.x === 1, "freeze prevents mutation");

    // as const: compile-time deep readonly + literal types
    const config = { host: "localhost", port: 3000, flags: [true, false] } as const;
    // config.host = "x";       // ← error: readonly
    // config.flags.push(true); // ← error: readonly array
    assert(config.port === 3000, "as const");
}

// ── WeakRef: Rust's Weak<T> equivalent ────────────────────────────
// In Rust, Weak<T> is a non-owning reference to Arc<T>-managed data.
// upgrade() returns Option<Arc<T>> — None if the data was dropped.
// In TypeScript, WeakRef<T>.deref() returns T | undefined — undefined
// if the GC collected the object.

function weakRefDemo(): void {
    let strong: { data: string } | undefined = { data: "important" };
    const weak = new WeakRef(strong);

    // While the strong reference exists, deref succeeds
    assert(weak.deref()?.data === "important", "weakref: deref with strong ref");

    // Remove the strong reference — object becomes eligible for GC
    strong = undefined;

    // After GC, weak.deref() would return undefined
    // We can't force GC in a test, but the pattern is clear:
    // const obj = weak.deref();
    // if (obj === undefined) { /* object was collected */ }
}

// ── FinalizationRegistry: Rust's Drop equivalent (sort of) ────────
// Rust's Drop runs deterministically when a value goes out of scope.
// FinalizationRegistry runs a callback when the GC collects an object,
// but there is NO guarantee of timing. Never rely on it for correctness.

function finalizationDemo(): void {
    const cleanedUp: string[] = [];

    const registry = new FinalizationRegistry<string>((heldValue) => {
        cleanedUp.push(heldValue);
    });

    // Register an object with a cleanup label
    let obj: object | undefined = { resource: "file handle" };
    registry.register(obj, "file-handle-cleanup");

    // The registry holds a weak reference to obj.
    // When obj is GC'd, the callback runs with "file-handle-cleanup".
    // Unlike Rust's Drop, we can't test this deterministically.
    obj = undefined;

    // Key difference from Rust:
    // Rust Drop: runs immediately and predictably at scope exit
    // TS FinalizationRegistry: runs "eventually, maybe" after GC
    // For deterministic cleanup, use try/finally or explicit close() methods
}

// ── Deterministic cleanup: try/finally (the TS way) ───────────────
// Since FinalizationRegistry is unreliable, TypeScript uses try/finally
// and the Disposable pattern (TC39 proposal, supported in TS 5.2+).

interface Resource {
    readonly name: string;
    use(): string;
    close(): void;
}

function createResource(name: string): Resource {
    let closed = false;
    return {
        name,
        use() {
            if (closed) throw new Error(`${name} already closed`);
            return `using ${name}`;
        },
        close() {
            closed = true;
        },
    };
}

function deterministicCleanupDemo(): void {
    const r = createResource("connection");

    try {
        const result = r.use();
        assert(result === "using connection", "resource usable");
    } finally {
        r.close(); // deterministic cleanup — like Rust's Drop
    }

    // After close, use throws
    let closedError = false;
    try { r.use(); } catch { closedError = true; }
    assert(closedError, "resource closed");
}

// ── Ownership transfer pattern ────────────────────────────────────
// TypeScript can't enforce single ownership, but you can simulate it
// with a pattern: null the source after "moving" to the destination.

function ownershipTransferDemo(): void {
    class UniqueResource {
        private consumed = false;

        constructor(readonly id: number) {}

        take(): UniqueResource {
            if (this.consumed) throw new Error("Already consumed (double move)");
            this.consumed = true;
            return new UniqueResource(this.id); // "move" to new owner
        }

        value(): number {
            if (this.consumed) throw new Error("Use after move");
            return this.id;
        }
    }

    const original = new UniqueResource(42);
    assert(original.value() === 42, "before move");

    const moved = original.take();
    assert(moved.value() === 42, "after move: new owner works");

    // "Use after move" — Rust catches this at compile time,
    // TypeScript can only catch it at runtime
    let useAfterMove = false;
    try { original.value(); } catch { useAfterMove = true; }
    assert(useAfterMove, "use-after-move caught at runtime");
}

// ── Interior mutability: no Rust equivalent needed ────────────────
// Rust needs Cell/RefCell/Mutex because &T prevents mutation.
// TypeScript has no &T enforcement at runtime — everything is
// mutable through any reference. This is less safe but simpler.

function interiorMutabilityComparison(): void {
    // In Rust: let shared: &Vec<i32> = &v;
    //          shared.push(1); // ← ERROR: can't mutate through &
    //          Need: RefCell<Vec<i32>> for interior mutability

    // In TypeScript: all references are implicitly &mut
    const shared = [1, 2, 3];
    const alias = shared; // same array, no borrow checker
    alias.push(4);
    assert(shared.length === 4, "TS: all refs are mutable aliases");

    // This is exactly what Rust's borrow checker prevents.
    // TypeScript trades safety for convenience.
}

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    noDanglingRefs();
    readonlyDemo();
    defensiveCopyDemo();
    weakRefDemo();
    finalizationDemo();
    deterministicCleanupDemo();
    ownershipTransferDemo();
    interiorMutabilityComparison();

    console.log("All ownership and borrowing examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
