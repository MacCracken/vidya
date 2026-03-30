// Vidya — Error Handling in TypeScript
//
// TypeScript uses exceptions (try/catch/finally) inherited from JS,
// plus discriminated unions and Result-like patterns for type-safe
// error handling. Custom error classes enable structured matching.

// ── Custom error classes ───────────────────────────────────────────

class AppError extends Error {
    constructor(message: string) {
        super(message);
        this.name = "AppError";
    }
}

class MissingKeyError extends AppError {
    constructor(public readonly key: string) {
        super(`missing key: ${key}`);
        this.name = "MissingKeyError";
    }
}

class ParseError extends AppError {
    constructor(
        public readonly key: string,
        public readonly value: string,
        public readonly reason: string,
    ) {
        super(`cannot parse '${key}=${value}': ${reason}`);
        this.name = "ParseError";
    }
}

// ── Functions that throw ───────────────────────────────────────────

function readPort(configText: string): number {
    for (const line of configText.split("\n")) {
        if (line.startsWith("port=")) {
            const value = line.slice(5).trim();
            const port = parseInt(value, 10);
            if (isNaN(port)) {
                throw new ParseError("port", value, "not a number");
            }
            return port;
        }
    }
    throw new MissingKeyError("port");
}

// ── Result type: type-safe alternative to exceptions ───────────────

type Result<T, E = Error> =
    | { ok: true; value: T }
    | { ok: false; error: E };

function ok<T>(value: T): Result<T, never> {
    return { ok: true, value };
}

function err<E>(error: E): Result<never, E> {
    return { ok: false, error };
}

function safeReadPort(configText: string): Result<number, AppError> {
    try {
        return ok(readPort(configText));
    } catch (e) {
        if (e instanceof AppError) return err(e);
        return err(new AppError(String(e)));
    }
}

// ── Option type: explicit absence ──────────────────────────────────

function findUser(id: number): string | undefined {
    const users: Record<number, string> = { 1: "alice", 2: "bob" };
    return users[id];
}

// ── Discriminated unions for error states ──────────────────────────

type LoadState<T> =
    | { status: "loading" }
    | { status: "success"; data: T }
    | { status: "error"; message: string };

function describeState<T>(state: LoadState<T>): string {
    switch (state.status) {
        case "loading": return "loading...";
        case "success": return `got data`;
        case "error": return `error: ${state.message}`;
    }
}

function main(): void {
    // ── Basic try/catch ────────────────────────────────────────────
    const port = readPort("host=localhost\nport=3000\n");
    assert(port === 3000, "parse port");

    // ── Catching specific error types ──────────────────────────────
    try {
        readPort("host=localhost\n");
        assert(false, "should have thrown");
    } catch (e) {
        assert(e instanceof MissingKeyError, "is MissingKeyError");
        assert((e as MissingKeyError).key === "port", "error key");
    }

    try {
        readPort("port=abc\n");
        assert(false, "should have thrown");
    } catch (e) {
        assert(e instanceof ParseError, "is ParseError");
        assert((e as ParseError).value === "abc", "error value");
    }

    // ── finally: always runs ───────────────────────────────────────
    let cleanupRan = false;
    try {
        readPort("host=localhost\nport=8080\n");
    } finally {
        cleanupRan = true;
    }
    assert(cleanupRan, "finally ran");

    // ── Result type: no exceptions ─────────────────────────────────
    const good = safeReadPort("port=3000\n");
    assert(good.ok === true, "result ok");
    if (good.ok) {
        assert(good.value === 3000, "result value");
    }

    const bad = safeReadPort("port=abc\n");
    assert(bad.ok === false, "result err");
    if (!bad.ok) {
        assert(bad.error instanceof ParseError, "result error type");
    }

    // ── Optional chaining ──────────────────────────────────────────
    const alice = findUser(1);
    assert(alice === "alice", "found user");

    const missing = findUser(999);
    assert(missing === undefined, "missing user");

    // Nullish coalescing
    const name = findUser(999) ?? "anonymous";
    assert(name === "anonymous", "nullish coalescing");

    // Optional chaining on methods
    const upper = findUser(1)?.toUpperCase();
    assert(upper === "ALICE", "optional chaining");

    const noUpper = findUser(999)?.toUpperCase();
    assert(noUpper === undefined, "optional chain on undefined");

    // ── Discriminated unions ───────────────────────────────────────
    const loading: LoadState<string> = { status: "loading" };
    assert(describeState(loading) === "loading...", "loading state");

    const success: LoadState<string> = { status: "success", data: "hello" };
    assert(describeState(success) === "got data", "success state");

    const error: LoadState<string> = { status: "error", message: "timeout" };
    assert(describeState(error) === "error: timeout", "error state");

    // ── Type guards for narrowing ──────────────────────────────────
    function isAppError(e: unknown): e is AppError {
        return e instanceof AppError;
    }

    try {
        readPort("bad");
    } catch (e) {
        if (isAppError(e)) {
            assert(e.name === "MissingKeyError", "type guard");
        }
    }

    console.log("All error handling examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
