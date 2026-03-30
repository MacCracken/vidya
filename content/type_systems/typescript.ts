// Vidya — Type Systems in TypeScript
//
// TypeScript adds a structural type system on top of JavaScript.
// Types are erased at runtime — they exist only for compile-time checking.
// Generics, union/intersection types, mapped types, and conditional types
// make it one of the most expressive type systems in mainstream use.

// ── Interfaces: structural typing ──────────────────────────────────

interface Printable {
    toString(): string;
}

// Any object with toString() satisfies Printable — no explicit implements needed
const point = { x: 3, y: 4, toString() { return `(${this.x}, ${this.y})`; } };

function print(item: Printable): string {
    return item.toString();
}

// ── Generics ───────────────────────────────────────────────────────

function first<T>(items: T[]): T | undefined {
    return items[0];
}

function largest<T>(items: T[], compare: (a: T, b: T) => number): T {
    return items.reduce((max, item) => compare(item, max) > 0 ? item : max);
}

// ── Generic class ──────────────────────────────────────────────────

class Stack<T> {
    private items: T[] = [];

    push(item: T): void { this.items.push(item); }

    pop(): T | undefined { return this.items.pop(); }

    peek(): T | undefined { return this.items[this.items.length - 1]; }

    get length(): number { return this.items.length; }
}

// ── Union and intersection types ───────────────────────────────────

type StringOrNumber = string | number;

type HasName = { name: string };
type HasAge = { age: number };
type Person = HasName & HasAge; // intersection: must have both

// ── Literal types and exhaustive checking ──────────────────────────

type Direction = "north" | "south" | "east" | "west";

function move(dir: Direction): string {
    switch (dir) {
        case "north": return "up";
        case "south": return "down";
        case "east": return "right";
        case "west": return "left";
    }
}

// ── Mapped types: transform types ──────────────────────────────────

type ReadonlyPoint = Readonly<{ x: number; y: number }>;
// equivalent to: { readonly x: number; readonly y: number }

type PartialConfig = Partial<{ host: string; port: number }>;
// equivalent to: { host?: string; port?: number }

type Required<T> = { [K in keyof T]-?: T[K] };

// ── Conditional types ──────────────────────────────────────────────

type IsString<T> = T extends string ? "yes" : "no";

// Type-level tests
type Test1 = IsString<string>;  // "yes"
type Test2 = IsString<number>;  // "no"

// Extract specific types from unions
type ExtractStrings<T> = T extends string ? T : never;
type OnlyStrings = ExtractStrings<string | number | boolean>; // string

// ── Template literal types ─────────────────────────────────────────

type EventName = `on${Capitalize<"click" | "hover" | "focus">}`;
// "onClick" | "onHover" | "onFocus"

// ── Branded types (newtype pattern) ────────────────────────────────

type Meters = number & { __brand: "meters" };
type Seconds = number & { __brand: "seconds" };

function meters(n: number): Meters { return n as Meters; }
function seconds(n: number): Seconds { return n as Seconds; }

function speed(distance: Meters, time: Seconds): number {
    return distance / time;
}

function main(): void {
    // ── Structural typing ──────────────────────────────────────────
    assert(print(point) === "(3, 4)", "structural typing");
    // Any object with toString() works — no interface declaration needed
    assert(print({ toString: () => "hello" }) === "hello", "ad-hoc structural");

    // ── Generics ───────────────────────────────────────────────────
    assert(first([1, 2, 3]) === 1, "generic first int");
    assert(first(["a", "b"]) === "a", "generic first string");
    assert(first([]) === undefined, "generic first empty");

    const biggest = largest([3, 1, 4, 1, 5], (a, b) => a - b);
    assert(biggest === 5, "generic largest");

    // ── Generic class ──────────────────────────────────────────────
    const stack = new Stack<number>();
    stack.push(1);
    stack.push(2);
    stack.push(3);
    assert(stack.peek() === 3, "stack peek");
    assert(stack.pop() === 3, "stack pop");
    assert(stack.length === 2, "stack length");

    // ── Union types ────────────────────────────────────────────────
    function format(value: StringOrNumber): string {
        if (typeof value === "string") return value.toUpperCase();
        return value.toFixed(2);
    }
    assert(format("hello") === "HELLO", "union string");
    assert(format(3.14) === "3.14", "union number");

    // ── Intersection types ─────────────────────────────────────────
    const person: Person = { name: "Alice", age: 30 };
    assert(person.name === "Alice" && person.age === 30, "intersection");

    // ── Literal types ──────────────────────────────────────────────
    assert(move("north") === "up", "literal north");
    assert(move("east") === "right", "literal east");

    // ── Branded types (newtypes) ───────────────────────────────────
    const d = meters(100);
    const t = seconds(9.58);
    const v = speed(d, t);
    assert(v > 10, "branded types");
    // speed(t, d); // ← TypeScript error: Seconds is not Meters

    // ── Readonly ───────────────────────────────────────────────────
    const ro: ReadonlyPoint = { x: 1, y: 2 };
    // ro.x = 3; // ← TypeScript error: readonly
    assert(ro.x === 1, "readonly");

    // ── Partial ────────────────────────────────────────────────────
    const partial: PartialConfig = { host: "localhost" }; // port is optional
    assert(partial.host === "localhost", "partial");
    assert(partial.port === undefined, "partial missing");

    // ── Record utility type ────────────────────────────────────────
    const scores: Record<string, number> = { alice: 95, bob: 87 };
    assert(scores["alice"] === 95, "record");

    // ── Pick and Omit ──────────────────────────────────────────────
    type Full = { name: string; age: number; email: string };
    type NameOnly = Pick<Full, "name">;
    type NoEmail = Omit<Full, "email">;

    const nameOnly: NameOnly = { name: "Alice" };
    const noEmail: NoEmail = { name: "Bob", age: 25 };
    assert(nameOnly.name === "Alice", "pick");
    assert(noEmail.age === 25, "omit");

    // ── Type guards ────────────────────────────────────────────────
    function isString(x: unknown): x is string {
        return typeof x === "string";
    }

    const val: unknown = "hello";
    if (isString(val)) {
        assert(val.toUpperCase() === "HELLO", "type guard");
    }

    // ── as const: literal inference ────────────────────────────────
    const config = { host: "localhost", port: 3000 } as const;
    // config.host is type "localhost", not string
    // config.port is type 3000, not number
    assert(config.host === "localhost", "as const");

    // ── Satisfies: check type without widening ─────────────────────
    const palette = {
        red: [255, 0, 0],
        green: "#00ff00",
    } satisfies Record<string, string | number[]>;

    // palette.red is still number[], not string | number[]
    assert(Array.isArray(palette.red), "satisfies preserves type");

    console.log("All type system examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
