// Vidya — Trait and Typeclass Systems in TypeScript
//
// TypeScript uses structural typing, not nominal typing. An object
// satisfies an interface if it has the right shape — no explicit
// "implements" declaration needed (though you can use one).
//
// Compare to Rust traits:
//   Rust trait       → TS interface (but structural, not nominal)
//   Rust impl T for S → TS class implements Interface (optional)
//   Rust dyn Trait   → TS interface as a parameter type
//   Rust generics    → TS generics with extends constraints
//   Rust enum + match → TS discriminated unions + switch
//   Rust associated types → TS has no direct equivalent
//   Rust coherence (orphan rule) → TS has none (structural, so no conflict)

// ── Interfaces as structural types ────────────────────────────────
// Unlike Rust traits, TS interfaces match on structure, not declaration.
// Anything with the right fields/methods satisfies the interface.

interface Printable {
    display(): string;
}

// No "implements Printable" needed — structural match is enough
const point = {
    x: 3,
    y: 4,
    display() { return `(${this.x}, ${this.y})`; },
};

function print(item: Printable): string {
    return item.display();
}

// ── Class implements: explicit trait implementation ────────────────
// You CAN declare implements for documentation and error checking.
// In Rust, this is mandatory: impl Trait for Type.

interface Shape {
    area(): number;
    perimeter(): number;
    name(): string;
}

class Circle implements Shape {
    constructor(private radius: number) {}

    area(): number { return Math.PI * this.radius ** 2; }
    perimeter(): number { return 2 * Math.PI * this.radius; }
    name(): string { return "Circle"; }
}

class Rectangle implements Shape {
    constructor(private width: number, private height: number) {}

    area(): number { return this.width * this.height; }
    perimeter(): number { return 2 * (this.width + this.height); }
    name(): string { return "Rectangle"; }
}

// ── Generics with constraints (bounded polymorphism) ──────────────
// In Rust: fn largest<T: Ord>(items: &[T]) -> &T
// In TS: T extends Comparable constrains the generic

interface Comparable {
    compareTo(other: this): number;
}

class Temperature implements Comparable {
    constructor(readonly celsius: number) {}

    compareTo(other: Temperature): number {
        return this.celsius - other.celsius;
    }

    display(): string { return `${this.celsius}°C`; }
}

function largest<T extends Comparable>(items: T[]): T {
    return items.reduce((max, item) => item.compareTo(max) > 0 ? item : max);
}

// ── Discriminated unions: Rust's enum + pattern matching ──────────
// Rust enums carry data and are matched exhaustively.
// TypeScript discriminated unions achieve the same thing.

type Result<T, E> =
    | { kind: "ok"; value: T }
    | { kind: "err"; error: E };

function ok<T>(value: T): Result<T, never> {
    return { kind: "ok", value };
}

function err<E>(error: E): Result<never, E> {
    return { kind: "err", error };
}

// Exhaustive matching — TypeScript narrows the type in each branch
function unwrapOrDefault<T>(result: Result<T, string>, defaultValue: T): T {
    switch (result.kind) {
        case "ok": return result.value;   // TS knows: result is { kind: "ok", value: T }
        case "err": return defaultValue;  // TS knows: result is { kind: "err", error: string }
    }
}

// ── Exhaustiveness checking with never ────────────────────────────

type Animal =
    | { species: "cat"; lives: number }
    | { species: "dog"; tricks: string[] }
    | { species: "fish"; freshwater: boolean };

function describeAnimal(animal: Animal): string {
    switch (animal.species) {
        case "cat": return `Cat with ${animal.lives} lives`;
        case "dog": return `Dog knows ${animal.tricks.join(", ")}`;
        case "fish": return `${animal.freshwater ? "Freshwater" : "Saltwater"} fish`;
        default: {
            // If we forget a case, TypeScript assigns `never` here
            // Adding a new variant to Animal would cause a compile error
            const _exhaustive: never = animal;
            return _exhaustive;
        }
    }
}

// ── Type guards: runtime type narrowing ───────────────────────────
// In Rust, pattern matching destructures and narrows.
// In TypeScript, type guards narrow within control flow.

interface Cat { species: "cat"; purr(): string; }
interface Dog { species: "dog"; bark(): string; }
type Pet = Cat | Dog;

function isCat(pet: Pet): pet is Cat {
    return pet.species === "cat";
}

function petSound(pet: Pet): string {
    if (isCat(pet)) {
        return pet.purr(); // TS knows pet is Cat here
    }
    return pet.bark(); // TS knows pet is Dog here
}

// ── in operator narrowing ─────────────────────────────────────────

interface Flyer { fly(): string; }
interface Swimmer { swim(): string; }

function move(creature: Flyer | Swimmer): string {
    if ("fly" in creature) {
        return creature.fly(); // narrowed to Flyer
    }
    return creature.swim(); // narrowed to Swimmer
}

// ── Generics with multiple constraints ────────────────────────────
// In Rust: fn process<T: Display + Serialize>(item: &T)
// In TS: T extends A & B

interface Serializable { serialize(): string; }
interface Loggable { log(): void; }

function processItem<T extends Serializable & Loggable>(item: T): string {
    item.log();
    return item.serialize();
}

class Config implements Serializable, Loggable {
    constructor(private data: Record<string, string>) {}

    serialize(): string { return JSON.stringify(this.data); }
    log(): void { /* logging would go here */ }
}

// ── Extending interfaces: supertrait equivalent ───────────────────
// In Rust: trait Error: Display + Debug
// In TS: interface extends

interface Displayable {
    display(): string;
}

interface Debuggable {
    debug(): string;
}

// AppError requires both Display and Debug — like Rust's trait Error: Display + Debug
interface AppError extends Displayable, Debuggable {
    code(): number;
}

class NotFoundError implements AppError {
    constructor(private resource: string) {}
    display(): string { return `${this.resource} not found`; }
    debug(): string { return `NotFoundError { resource: "${this.resource}" }`; }
    code(): number { return 404; }
}

// ── Generic interface with associated-type-like pattern ───────────
// Rust: trait Iterator { type Item; fn next(&mut self) -> Option<Self::Item>; }
// TS can't do associated types directly, but generics approximate it.

interface Iter<T> {
    next(): T | undefined;
}

class RangeIter implements Iter<number> {
    private current: number;
    constructor(private start: number, private end: number) {
        this.current = start;
    }

    next(): number | undefined {
        if (this.current >= this.end) return undefined;
        return this.current++;
    }
}

function collect<T>(iter: Iter<T>): T[] {
    const result: T[] = [];
    let val = iter.next();
    while (val !== undefined) {
        result.push(val);
        val = iter.next();
    }
    return result;
}

// ── Index signature: Rust's Index trait ────────────────────────────

interface Indexable<K extends string | number, V> {
    get(key: K): V | undefined;
    set(key: K, value: V): void;
}

class TypedMap<V> implements Indexable<string, V> {
    private data = new Map<string, V>();

    get(key: string): V | undefined { return this.data.get(key); }
    set(key: string, value: V): void { this.data.set(key, value); }
}

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    // ── Structural typing ─────────────────────────────────────────
    assert(print(point) === "(3, 4)", "structural typing");
    // Ad-hoc object satisfies interface without declaration
    assert(print({ display: () => "hello" }) === "hello", "ad-hoc structural");

    // ── Class implements ──────────────────────────────────────────
    const circle = new Circle(5);
    assertClose(circle.area(), 78.539, 0.01, "circle area");
    assertClose(circle.perimeter(), 31.415, 0.01, "circle perimeter");

    const rect = new Rectangle(3, 4);
    assert(rect.area() === 12, "rectangle area");
    assert(rect.perimeter() === 14, "rectangle perimeter");

    // ── Polymorphism through interface ────────────────────────────
    const shapes: Shape[] = [circle, rect];
    assert(shapes.every((s) => s.area() > 0), "polymorphic shapes");
    assert(shapes[0].name() === "Circle", "dynamic dispatch");
    assert(shapes[1].name() === "Rectangle", "dynamic dispatch");

    // ── Generics with constraints ─────────────────────────────────
    const temps = [
        new Temperature(20),
        new Temperature(35),
        new Temperature(15),
    ];
    const hottest = largest(temps);
    assert(hottest.celsius === 35, "generic largest");

    // ── Discriminated unions ──────────────────────────────────────
    const success = ok(42);
    const failure = err("not found");
    assert(unwrapOrDefault(success, 0) === 42, "result ok");
    assert(unwrapOrDefault(failure, -1) === -1, "result err");

    // ── Exhaustive matching ───────────────────────────────────────
    const cat: Animal = { species: "cat", lives: 9 };
    const dog: Animal = { species: "dog", tricks: ["sit", "shake"] };
    const fish: Animal = { species: "fish", freshwater: true };
    assert(describeAnimal(cat) === "Cat with 9 lives", "exhaustive cat");
    assert(describeAnimal(dog) === "Dog knows sit, shake", "exhaustive dog");
    assert(describeAnimal(fish) === "Freshwater fish", "exhaustive fish");

    // ── Type guards ───────────────────────────────────────────────
    const myCat: Pet = { species: "cat", purr: () => "purr" };
    const myDog: Pet = { species: "dog", bark: () => "woof" };
    assert(petSound(myCat) === "purr", "type guard cat");
    assert(petSound(myDog) === "woof", "type guard dog");

    // ── in operator narrowing ─────────────────────────────────────
    const bird: Flyer = { fly: () => "soaring" };
    const dolphin: Swimmer = { swim: () => "diving" };
    assert(move(bird) === "soaring", "in narrowing flyer");
    assert(move(dolphin) === "diving", "in narrowing swimmer");

    // ── Multiple constraints ──────────────────────────────────────
    const config = new Config({ key: "value" });
    const serialized = processItem(config);
    assert(serialized === '{"key":"value"}', "multiple constraints");

    // ── Supertrait interface ──────────────────────────────────────
    const notFound = new NotFoundError("user");
    assert(notFound.display() === "user not found", "supertrait display");
    assert(notFound.code() === 404, "supertrait code");
    assert(notFound.debug().includes("NotFoundError"), "supertrait debug");

    // ── Generic iterator ──────────────────────────────────────────
    const range = new RangeIter(0, 5);
    const collected = collect(range);
    assertArrayEq(collected, [0, 1, 2, 3, 4], "generic iterator");

    // ── Generic map ───────────────────────────────────────────────
    const map = new TypedMap<number>();
    map.set("a", 1);
    map.set("b", 2);
    assert(map.get("a") === 1, "typed map get");
    assert(map.get("c") === undefined, "typed map missing");

    // ── Structural typing: key difference from Rust ───────────────
    // In Rust, impl Shape for Circle is an explicit declaration.
    // In TS, any object with area/perimeter/name satisfies Shape.
    // This means:
    //   - No orphan rule needed (no coherence problem)
    //   - No blanket impls (no way to say "impl Shape for all T: X")
    //   - No monomorphization (JS is dynamically dispatched)
    //   - Type erasure is the default, not an opt-in like dyn Trait

    console.log("All trait and typeclass system examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function assertClose(got: number, expected: number, tolerance: number, msg: string): void {
    assert(Math.abs(got - expected) < tolerance, `${msg}: got ${got}, expected ~${expected}`);
}

function assertArrayEq<T>(got: T[], expected: T[], msg: string): void {
    assert(
        got.length === expected.length && got.every((v, i) => v === expected[i]),
        `${msg}: got [${got}], expected [${expected}]`,
    );
}

main();
