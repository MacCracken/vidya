// Vidya — Pattern Matching in TypeScript
//
// TypeScript doesn't have Rust-style match expressions (yet — TC39 pattern
// matching proposal exists). Instead, use: discriminated unions with switch,
// type narrowing, object destructuring, and exhaustive checking with never.

// ── Discriminated unions: TypeScript's best pattern matching ───────

type Shape =
    | { kind: "circle"; radius: number }
    | { kind: "rectangle"; width: number; height: number }
    | { kind: "triangle"; base: number; height: number };

function area(shape: Shape): number {
    switch (shape.kind) {
        case "circle":
            return Math.PI * shape.radius ** 2;
        case "rectangle":
            return shape.width * shape.height;
        case "triangle":
            return 0.5 * shape.base * shape.height;
    }
}

// Exhaustive check: compiler error if you miss a variant
function shapeLabel(shape: Shape): string {
    switch (shape.kind) {
        case "circle": return `circle r=${shape.radius}`;
        case "rectangle": return `rect ${shape.width}x${shape.height}`;
        case "triangle": return `tri base=${shape.base}`;
        default:
            // This line ensures exhaustiveness at compile time
            const _exhaustive: never = shape;
            return _exhaustive;
    }
}

// ── Type narrowing ─────────────────────────────────────────────────

function describe(value: string | number | boolean): string {
    if (typeof value === "string") {
        return `string: ${value.toUpperCase()}`; // narrowed to string
    } else if (typeof value === "number") {
        return `number: ${value.toFixed(2)}`; // narrowed to number
    } else {
        return `boolean: ${value}`; // narrowed to boolean
    }
}

// ── instanceof narrowing ───────────────────────────────────────────

class ApiError {
    constructor(public status: number, public message: string) {}
}

class NetworkError {
    constructor(public cause: string) {}
}

type AppError = ApiError | NetworkError;

function handleError(err: AppError): string {
    if (err instanceof ApiError) {
        return `API ${err.status}: ${err.message}`;
    } else {
        return `Network: ${err.cause}`;
    }
}

// ── Custom type guards ─────────────────────────────────────────────

interface Cat { kind: "cat"; meow(): string; }
interface Dog { kind: "dog"; bark(): string; }
type Pet = Cat | Dog;

function isCat(pet: Pet): pet is Cat {
    return pet.kind === "cat";
}

function main(): void {
    // ── Discriminated union matching ───────────────────────────────
    const circle: Shape = { kind: "circle", radius: 1 };
    assert(Math.abs(area(circle) - Math.PI) < 1e-10, "circle area");

    const rect: Shape = { kind: "rectangle", width: 3, height: 4 };
    assert(area(rect) === 12, "rect area");

    const tri: Shape = { kind: "triangle", base: 6, height: 4 };
    assert(area(tri) === 12, "tri area");

    assert(shapeLabel(circle) === "circle r=1", "circle label");

    // ── Type narrowing ─────────────────────────────────────────────
    assert(describe("hello") === "string: HELLO", "narrow string");
    assert(describe(3.14159) === "number: 3.14", "narrow number");
    assert(describe(true) === "boolean: true", "narrow boolean");

    // ── instanceof ─────────────────────────────────────────────────
    assert(handleError(new ApiError(404, "not found")) === "API 404: not found", "api error");
    assert(handleError(new NetworkError("timeout")) === "Network: timeout", "network error");

    // ── Destructuring: extract data by shape ───────────────────────
    const point = { x: 3, y: 4, z: 5 };
    const { x, y } = point; // extract only what you need
    assert(x === 3 && y === 4, "destructuring");

    // Nested destructuring
    const response = { data: { items: [1, 2, 3] }, status: 200 };
    const { data: { items: [first, ...rest] }, status } = response;
    assert(first === 1, "nested destructure first");
    assert(rest.length === 2, "nested destructure rest");
    assert(status === 200, "nested destructure status");

    // ── Array destructuring ────────────────────────────────────────
    const [a, b, ...tail] = [1, 2, 3, 4, 5];
    assert(a === 1 && b === 2, "array destructure");
    assert(tail.length === 3, "rest elements");

    // Swap without temp
    let p = 1, q = 2;
    [p, q] = [q, p];
    assert(p === 2 && q === 1, "swap destructure");

    // ── Optional chaining as pattern matching ──────────────────────
    type Config = {
        database?: {
            host?: string;
            port?: number;
        };
    };

    const config: Config = { database: { host: "localhost" } };
    assert(config.database?.host === "localhost", "optional chain hit");
    assert(config.database?.port === undefined, "optional chain miss");

    // ── Custom type guards ─────────────────────────────────────────
    const cat: Pet = { kind: "cat", meow: () => "meow!" };
    const dog: Pet = { kind: "dog", bark: () => "woof!" };

    if (isCat(cat)) {
        assert(cat.meow() === "meow!", "type guard cat");
    }

    // ── in operator for narrowing ──────────────────────────────────
    function getSound(pet: Pet): string {
        if ("meow" in pet) {
            return pet.meow();
        } else {
            return pet.bark();
        }
    }
    assert(getSound(cat) === "meow!", "in narrowing cat");
    assert(getSound(dog) === "woof!", "in narrowing dog");

    // ── Mapped types: compile-time pattern transformation ──────────
    type Readonly<T> = { readonly [K in keyof T]: T[K] };
    type Partial<T> = { [K in keyof T]?: T[K] };

    // These transform types at compile time — no runtime cost

    // ── String literal pattern matching ────────────────────────────
    type HttpMethod = "GET" | "POST" | "PUT" | "DELETE";

    function methodColor(method: HttpMethod): string {
        switch (method) {
            case "GET": return "green";
            case "POST": return "blue";
            case "PUT": return "yellow";
            case "DELETE": return "red";
        }
    }
    assert(methodColor("GET") === "green", "literal match");

    console.log("All pattern matching examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
