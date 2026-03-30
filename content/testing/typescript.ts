// Vidya — Testing in TypeScript
//
// TypeScript testing commonly uses Jest, Vitest, or Node's built-in
// test runner. This file demonstrates testing patterns using plain
// assertions — the same patterns work with any framework.

// ── Code under test ────────────────────────────────────────────────

function parseKV(line: string): [string, string] {
    const eqIdx = line.indexOf("=");
    if (eqIdx === -1) {
        throw new Error(`no '=' found in: ${line}`);
    }
    const key = line.slice(0, eqIdx).trim();
    const value = line.slice(eqIdx + 1).trim();
    if (key === "") {
        throw new Error("empty key");
    }
    return [key, value];
}

function clamp(value: number, min: number, max: number): number {
    if (min > max) {
        throw new RangeError(`min (${min}) must be <= max (${max})`);
    }
    return Math.max(min, Math.min(max, value));
}

class Counter {
    private count = 0;
    constructor(private readonly max: number) {}

    increment(): boolean {
        if (this.count < this.max) {
            this.count++;
            return true;
        }
        return false;
    }

    get value(): number { return this.count; }
}

// ── Test runner ────────────────────────────────────────────────────

let testsRun = 0;
let testsPassed = 0;
let testsFailed = 0;

function test(name: string, fn: () => void): void {
    testsRun++;
    try {
        fn();
        testsPassed++;
    } catch (e) {
        testsFailed++;
        console.error(`  FAIL: ${name}: ${e instanceof Error ? e.message : e}`);
    }
}

function assertEqual<T>(got: T, expected: T, msg: string): void {
    if (got !== expected) {
        throw new Error(`${msg}: got ${JSON.stringify(got)}, expected ${JSON.stringify(expected)}`);
    }
}

function assertThrows(fn: () => void, expectedMsg?: string): void {
    try {
        fn();
        throw new Error("expected function to throw");
    } catch (e) {
        if (expectedMsg && e instanceof Error) {
            if (!e.message.includes(expectedMsg)) {
                throw new Error(`expected error containing '${expectedMsg}', got '${e.message}'`);
            }
        }
    }
}

// ── Test suites ────────────────────────────────────────────────────

// parseKV tests
test("parseKV: valid input", () => {
    const [k, v] = parseKV("host=localhost");
    assertEqual(k, "host", "key");
    assertEqual(v, "localhost", "value");
});

test("parseKV: trims whitespace", () => {
    const [k, v] = parseKV("  port = 3000  ");
    assertEqual(k, "port", "trimmed key");
    assertEqual(v, "3000", "trimmed value");
});

test("parseKV: empty value is ok", () => {
    const [k, v] = parseKV("key=");
    assertEqual(k, "key", "key");
    assertEqual(v, "", "empty value");
});

test("parseKV: missing equals throws", () => {
    assertThrows(() => parseKV("no_equals"), "no '='");
});

test("parseKV: empty key throws", () => {
    assertThrows(() => parseKV("=value"), "empty key");
});

// clamp tests — table-driven
test("clamp: boundary cases", () => {
    const cases: [number, number, number, number, string][] = [
        [5,   0, 10, 5,  "in range"],
        [-1,  0, 10, 0,  "below min"],
        [100, 0, 10, 10, "above max"],
        [0,   0, 10, 0,  "at min"],
        [10,  0, 10, 10, "at max"],
        [5,   5, 5,  5,  "min equals max"],
    ];

    for (const [value, min, max, expected, name] of cases) {
        assertEqual(clamp(value, min, max), expected, name);
    }
});

test("clamp: invalid range throws", () => {
    assertThrows(() => clamp(5, 10, 0), "min (10) must be <= max (0)");
});

// Counter tests
test("counter: increments up to max", () => {
    const c = new Counter(3);
    assertEqual(c.value, 0, "initial");
    assertEqual(c.increment(), true, "inc 1");
    assertEqual(c.increment(), true, "inc 2");
    assertEqual(c.increment(), true, "inc 3");
    assertEqual(c.increment(), false, "inc at max");
    assertEqual(c.value, 3, "final value");
});

test("counter: zero max", () => {
    const c = new Counter(0);
    assertEqual(c.increment(), false, "zero max inc");
    assertEqual(c.value, 0, "zero max value");
});

// ── Async test support ─────────────────────────────────────────────

async function testAsync(name: string, fn: () => Promise<void>): Promise<void> {
    testsRun++;
    try {
        await fn();
        testsPassed++;
    } catch (e) {
        testsFailed++;
        console.error(`  FAIL: ${name}: ${e instanceof Error ? e.message : e}`);
    }
}

// ── Type-level testing ─────────────────────────────────────────────
// TypeScript can verify types at compile time

type Expect<T extends true> = T;
type Equal<X, Y> = (<T>() => T extends X ? 1 : 2) extends (<T>() => T extends Y ? 1 : 2) ? true : false;

// These produce compile errors if the types don't match:
type _TestParseKV = Expect<Equal<ReturnType<typeof parseKV>, [string, string]>>;
type _TestClamp = Expect<Equal<ReturnType<typeof clamp>, number>>;
type _TestCounterValue = Expect<Equal<Counter["value"], number>>;

// ── Report ─────────────────────────────────────────────────────────

if (testsFailed > 0) {
    console.error(`FAILED: ${testsPassed}/${testsRun} passed`);
    process.exit(1);
}

console.log("All testing examples passed.");
