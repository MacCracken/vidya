// Vidya — Macro Systems in TypeScript
//
// TypeScript has NO macro system. No textual substitution, no AST macros,
// no compile-time code generation. But TypeScript's type system is
// Turing-complete and provides metaprogramming at the type level:
//
//   Rust macro_rules!    → TS has nothing (no token transformation)
//   Rust proc_macro      → TS has nothing (no compile-time code execution)
//   Rust derive          → TS decorators (experimental, runtime only)
//   Rust cfg!            → TS conditional types (type-level only)
//   C #define            → TS const + as const (value-level constants)
//
// What TypeScript DOES have:
//   1. Template literal types — string manipulation at the type level
//   2. Conditional types — type-level if/else
//   3. Mapped types — transform type shapes systematically
//   4. Declaration merging — extend existing types
//   5. Decorators — runtime metaprogramming (TC39 stage 3)

// ── Template literal types: string macros at the type level ───────
// Rust macros generate code. TS template literal types generate types
// from string patterns — no runtime cost, purely compile-time.

type EventName<T extends string> = `on${Capitalize<T>}`;

// These are computed at compile time — like a macro that generates type aliases
type ClickEvent = EventName<"click">;     // "onClick"
type HoverEvent = EventName<"hover">;     // "onHover"
type FocusEvent = EventName<"focus">;     // "onFocus"

// Combine with unions for combinatorial type generation
type Method = "get" | "post" | "put" | "delete";
type Endpoint = "/users" | "/posts";
type Route = `${Uppercase<Method>} ${Endpoint}`;
// "GET /users" | "GET /posts" | "POST /users" | "POST /posts" | ...

// Parse strings at the type level
type ExtractParam<T extends string> =
    T extends `${string}:${infer Param}/${infer Rest}`
        ? Param | ExtractParam<Rest>
        : T extends `${string}:${infer Param}`
            ? Param
            : never;

type Params = ExtractParam<"/users/:userId/posts/:postId">;
// "userId" | "postId"

// ── Conditional types: type-level if/else ──────────────────────────
// In Rust, cfg! macros conditionally include code.
// In TS, conditional types conditionally resolve types.

type IsString<T> = T extends string ? true : false;
type IsArray<T> = T extends unknown[] ? true : false;

// Distributive conditional types — applies to each union member
type NonNullable<T> = T extends null | undefined ? never : T;
type Cleaned = NonNullable<string | null | number | undefined>; // string | number

// Infer keyword: extract types from patterns
type ReturnType<T> = T extends (...args: unknown[]) => infer R ? R : never;
type ArrayElement<T> = T extends (infer E)[] ? E : never;

// Recursive conditional types — type-level recursion (like recursive macros)
type Flatten<T> = T extends (infer U)[]
    ? Flatten<U> // recurse: flatten nested arrays
    : T;

type Deep = Flatten<number[][][]>; // number

// ── Mapped types: systematic type transformation ──────────────────
// Like Rust's derive macros but at the type level.
// A derive macro generates impl blocks. Mapped types generate new types.

// Make all properties optional (like Rust's Option-wrapping)
type MyPartial<T> = { [K in keyof T]?: T[K] };

// Make all properties required
type MyRequired<T> = { [K in keyof T]-?: T[K] };

// Make all properties readonly (like Rust's &T view)
type MyReadonly<T> = { readonly [K in keyof T]: T[K] };

// Pick specific properties
type MyPick<T, K extends keyof T> = { [P in K]: T[P] };

// Omit specific properties
type MyOmit<T, K extends keyof T> = { [P in Exclude<keyof T, K>]: T[P] };

// Transform property types (no Rust equivalent — Rust doesn't have this)
type Getters<T> = {
    [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

interface User {
    name: string;
    age: number;
    email: string;
}

// Getters<User> = { getName: () => string; getAge: () => number; getEmail: () => string }

// ── Declaration merging: extending existing types ─────────────────
// In Rust, you can't add methods to external types without newtypes.
// In TS, declaration merging lets you extend interfaces across files.

interface EventEmitter {
    on(event: string, handler: () => void): void;
}

// Later (or in another file), extend the same interface:
interface EventEmitter {
    off(event: string, handler: () => void): void;
    emit(event: string): void;
}

// Now EventEmitter has on, off, AND emit — all merged
// This is like Rust's extension traits, but without coherence rules

// Module augmentation: extend third-party types
// declare module "some-library" {
//     interface ExistingType {
//         newMethod(): void;
//     }
// }

// ── Decorators: runtime metaprogramming ───────────────────────────
// The closest thing TS has to Rust's proc macros.
// Decorators modify classes/methods at runtime, not compile time.
// Rust derive macros generate code at compile time.

// Note: Decorators require experimentalDecorators or the TC39 stage 3
// proposal. We demonstrate the pattern without depending on the flag.

// Simulating a decorator pattern without the @ syntax
function logged(
    _target: unknown,
    propertyKey: string,
    descriptor: PropertyDescriptor,
): PropertyDescriptor {
    const original = descriptor.value;
    descriptor.value = function (this: unknown, ...args: unknown[]) {
        const result = original.apply(this, args);
        return result;
    };
    return descriptor;
}

// ── Builder pattern: what Rust derive macros automate ──────────────
// Rust has #[derive(Builder)] to auto-generate builder code.
// TypeScript uses mapped types to create builder types generically.

type Builder<T> = {
    [K in keyof T as `set${Capitalize<string & K>}`]: (value: T[K]) => Builder<T>;
} & {
    build(): T;
};

function createBuilder<T>(defaults: T): Builder<T> {
    const state = { ...defaults };
    const builder: Record<string, unknown> = {};

    for (const key of Object.keys(defaults as object) as (keyof T & string)[]) {
        const setterName = `set${key.charAt(0).toUpperCase() + key.slice(1)}`;
        builder[setterName] = (value: T[typeof key]) => {
            state[key] = value;
            return builder as Builder<T>;
        };
    }

    builder.build = () => ({ ...state });
    return builder as Builder<T>;
}

// ── Const assertions: compile-time constant folding ───────────────
// In C, #define PI 3.14159 is a macro constant.
// In TS, as const produces literal types that survive type-checking.

const DIRECTIONS = ["north", "south", "east", "west"] as const;
type Direction = (typeof DIRECTIONS)[number]; // "north" | "south" | "east" | "west"

const ERROR_CODES = {
    NOT_FOUND: 404,
    FORBIDDEN: 403,
    INTERNAL: 500,
} as const;
type ErrorCode = (typeof ERROR_CODES)[keyof typeof ERROR_CODES]; // 404 | 403 | 500

// ── Satisfies: type-check without widening ────────────────────────
// Validates a value matches a type constraint without losing specificity

const palette = {
    red: [255, 0, 0],
    green: "#00ff00",
    blue: [0, 0, 255],
} satisfies Record<string, string | number[]>;
// palette.red is still number[] (not string | number[])

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    // ── Template literal types (runtime validation) ───────────────
    function makeEventName(base: string): string {
        return `on${base.charAt(0).toUpperCase() + base.slice(1)}`;
    }
    assert(makeEventName("click") === "onClick", "template literal");
    assert(makeEventName("hover") === "onHover", "template literal hover");

    // ── Conditional types (demonstrated at value level) ────────────
    function isStringValue(x: unknown): x is string {
        return typeof x === "string";
    }
    assert(isStringValue("hello") === true, "conditional: is string");
    assert(isStringValue(42) === false, "conditional: not string");

    // ── Mapped types (demonstrated at value level) ─────────────────
    const user: User = { name: "Alice", age: 30, email: "a@b.com" };

    // Partial: make all optional
    const partial: Partial<User> = { name: "Bob" };
    assert(partial.name === "Bob", "partial");
    assert(partial.age === undefined, "partial missing");

    // Readonly: prevent mutation
    const frozen: Readonly<User> = user;
    // frozen.name = "x"; // ← TypeScript error
    assert(frozen.name === "Alice", "readonly");

    // Pick: subset of properties
    const nameOnly: Pick<User, "name"> = { name: "Charlie" };
    assert(nameOnly.name === "Charlie", "pick");

    // Omit: exclude properties
    const noEmail: Omit<User, "email"> = { name: "Dave", age: 25 };
    assert(noEmail.name === "Dave", "omit");

    // Record: map keys to value types
    const scores: Record<string, number> = { alice: 95, bob: 87 };
    assert(scores["alice"] === 95, "record");

    // ── Getters mapped type ───────────────────────────────────────
    // Verify the pattern works at runtime
    function makeGetters<T extends object>(obj: T): Getters<T> {
        const getters: Record<string, unknown> = {};
        for (const key of Object.keys(obj)) {
            const getterName = `get${key.charAt(0).toUpperCase() + key.slice(1)}`;
            getters[getterName] = () => (obj as Record<string, unknown>)[key];
        }
        return getters as Getters<T>;
    }

    const userGetters = makeGetters({ name: "Alice", age: 30 });
    assert((userGetters as { getName: () => string }).getName() === "Alice", "mapped getter");

    // ── Declaration merging (verified structurally) ────────────────
    const emitter: EventEmitter = {
        on(_event: string, _handler: () => void) {},
        off(_event: string, _handler: () => void) {},
        emit(_event: string) {},
    };
    assert(typeof emitter.on === "function", "merged: on");
    assert(typeof emitter.off === "function", "merged: off");
    assert(typeof emitter.emit === "function", "merged: emit");

    // ── Builder pattern ───────────────────────────────────────────
    const built = createBuilder({ name: "", age: 0, active: false })
        .setName("Alice")
        .setAge(30)
        .setActive(true)
        .build();
    assert(built.name === "Alice", "builder name");
    assert(built.age === 30, "builder age");
    assert(built.active === true, "builder active");

    // ── Const assertions ──────────────────────────────────────────
    assert(DIRECTIONS.length === 4, "const array length");
    assert(DIRECTIONS[0] === "north", "const array value");
    assert(ERROR_CODES.NOT_FOUND === 404, "const object value");

    // ── Satisfies ─────────────────────────────────────────────────
    assert(Array.isArray(palette.red), "satisfies preserves array type");
    assert(typeof palette.green === "string", "satisfies preserves string type");

    // ── Decorator pattern (without @ syntax) ──────────────────────
    const descriptor: PropertyDescriptor = {
        value: (x: number) => x * 2,
        writable: true,
        configurable: true,
    };
    const modified = logged(null, "double", descriptor);
    assert(typeof modified.value === "function", "decorator wraps function");
    assert(modified.value(5) === 10, "decorator preserves behavior");

    // ── What TS CANNOT do (Rust macros can) ───────────────────────
    // 1. Generate new functions at compile time (proc_macro)
    // 2. Transform token streams (macro_rules!)
    // 3. Conditional compilation (cfg!)
    // 4. Compile-time string formatting (format!)
    // 5. Auto-derive trait impls (derive macros)
    //
    // TS compensates with:
    // - Type-level computation (conditional + mapped types)
    // - Runtime metaprogramming (decorators, Proxy, Reflect)
    // - Code generation tools (codegen, graphql-codegen)
    // - Build-time transforms (babel plugins, ts-patch)

    console.log("All macro system examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
