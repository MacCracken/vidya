// Vidya — Tracing & Structured Logging in TypeScript
//
// TypeScript/Node.js has no zero-overhead tracing like Rust's tracing crate.
// Instead, it provides console.log levels, performance.mark/measure,
// and diagnostics_channel for structured observability.
//
// The key principle is the same across languages: filter at the source,
// not the sink. Check the log level BEFORE formatting the message.

// ── Log levels ────────────────────────────────────────────────────

const enum LogLevel {
    TRACE = 0,
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5,
    OFF = 6,
}

function levelName(level: LogLevel): string {
    switch (level) {
        case LogLevel.TRACE: return "TRACE";
        case LogLevel.DEBUG: return "DEBUG";
        case LogLevel.INFO:  return "INFO";
        case LogLevel.WARN:  return "WARN";
        case LogLevel.ERROR: return "ERROR";
        case LogLevel.FATAL: return "FATAL";
        case LogLevel.OFF:   return "OFF";
    }
}

// ── Structured log entry ──────────────────────────────────────────
// Structured logging encodes events as key-value pairs, not free text.
// This makes logs machine-parseable (JSON) while remaining human-readable.

interface LogEntry {
    timestamp: number;    // monotonic nanoseconds (not wall clock)
    level: LogLevel;
    message: string;
    fields: Record<string, unknown>;
    span?: string;        // parent span name, if any
}

// ── Logger with level filtering ───────────────────────────────────
// BEST PRACTICE: Filter BEFORE formatting. A filtered-out log call
// should cost one comparison, not a full format+write cycle.

class Logger {
    private entries: LogEntry[] = [];
    private currentSpan: string | undefined;

    constructor(private minLevel: LogLevel = LogLevel.INFO) {}

    private shouldLog(level: LogLevel): boolean {
        return level >= this.minLevel;
    }

    private emit(level: LogLevel, message: string, fields: Record<string, unknown> = {}): void {
        // CRITICAL: check level BEFORE doing any work
        if (!this.shouldLog(level)) return;

        const entry: LogEntry = {
            timestamp: this.monotonicNow(),
            level,
            message,
            fields,
            span: this.currentSpan,
        };

        this.entries.push(entry);
    }

    trace(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.TRACE, message, fields);
    }

    debug(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.DEBUG, message, fields);
    }

    info(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.INFO, message, fields);
    }

    warn(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.WARN, message, fields);
    }

    error(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.ERROR, message, fields);
    }

    fatal(message: string, fields?: Record<string, unknown>): void {
        this.emit(LogLevel.FATAL, message, fields);
    }

    // ── Spans: track execution context ────────────────────────────
    // Like Rust's tracing::span! — groups related log entries under
    // a named context with timing information.

    span<T>(name: string, fn: () => T): T {
        const previousSpan = this.currentSpan;
        this.currentSpan = name;
        const startTime = this.monotonicNow();

        try {
            const result = fn();
            const elapsed = this.monotonicNow() - startTime;
            this.emit(LogLevel.DEBUG, `span ${name} completed`, {
                elapsed_ms: elapsed,
            });
            return result;
        } catch (err) {
            this.emit(LogLevel.ERROR, `span ${name} failed`, {
                error: err instanceof Error ? err.message : String(err),
            });
            throw err;
        } finally {
            this.currentSpan = previousSpan;
        }
    }

    // ── Formatters ────────────────────────────────────────────────

    formatText(entry: LogEntry): string {
        const ts = entry.timestamp.toFixed(0);
        const lvl = levelName(entry.level).padEnd(5);
        const span = entry.span ? `[${entry.span}] ` : "";
        const fields = Object.keys(entry.fields).length > 0
            ? " " + Object.entries(entry.fields)
                .map(([k, v]) => `${k}=${JSON.stringify(v)}`)
                .join(" ")
            : "";
        return `${ts} ${lvl} ${span}${entry.message}${fields}`;
    }

    formatJson(entry: LogEntry): string {
        return JSON.stringify({
            ts: entry.timestamp,
            level: levelName(entry.level),
            msg: entry.message,
            ...entry.fields,
            ...(entry.span ? { span: entry.span } : {}),
        });
    }

    // ── Accessors for testing ─────────────────────────────────────
    getEntries(): readonly LogEntry[] { return this.entries; }
    setLevel(level: LogLevel): void { this.minLevel = level; }
    clear(): void { this.entries = []; }

    private monotonicNow(): number {
        // performance.now() returns milliseconds with sub-ms precision
        // This is the JS equivalent of CLOCK_MONOTONIC
        return performance.now();
    }
}

// ── Console log levels ────────────────────────────────────────────
// The built-in console has levels, but no filtering.
// console.log   → INFO
// console.debug → DEBUG (filtered in some browsers)
// console.warn  → WARN (yellow in browser/terminal)
// console.error → ERROR (red, goes to stderr in Node.js)
// console.trace → prints stack trace (NOT a log level!)

// ── Performance timing ────────────────────────────────────────────
// performance.mark() and performance.measure() provide built-in
// tracing with nanosecond precision. Like Rust's tracing spans.

function performanceTimingDemo(): { markDuration: number; computeResult: number } {
    // Mark the start of an operation
    performance.mark("compute-start");

    // Do some work
    let result = 0;
    for (let i = 0; i < 1000; i++) {
        result += Math.sqrt(i);
    }

    // Mark the end
    performance.mark("compute-end");

    // Measure the duration between marks
    const measure = performance.measure("compute", "compute-start", "compute-end");

    // Clean up marks
    performance.clearMarks("compute-start");
    performance.clearMarks("compute-end");
    performance.clearMeasures("compute");

    return { markDuration: measure.duration, computeResult: result };
}

// ── Structured logging patterns ───────────────────────────────────

// Pattern 1: Request-scoped logger (like tracing::Span in Rust)
interface RequestContext {
    requestId: string;
    userId?: string;
    path: string;
}

class RequestLogger {
    private logger: Logger;
    private context: RequestContext;

    constructor(logger: Logger, context: RequestContext) {
        this.logger = logger;
        this.context = context;
    }

    info(message: string, extra?: Record<string, unknown>): void {
        this.logger.info(message, { ...this.context, ...extra });
    }

    error(message: string, extra?: Record<string, unknown>): void {
        this.logger.error(message, { ...this.context, ...extra });
    }
}

// Pattern 2: Child logger (inherits context from parent)
class ChildLogger {
    constructor(
        private parent: Logger,
        private baseFields: Record<string, unknown>,
    ) {}

    info(message: string, fields?: Record<string, unknown>): void {
        this.parent.info(message, { ...this.baseFields, ...fields });
    }
}

// Pattern 3: Log sampling (emit 1 in N events for high-volume paths)
class SampledLogger {
    private count = 0;

    constructor(
        private logger: Logger,
        private sampleRate: number, // log 1 in N events
    ) {}

    info(message: string, fields?: Record<string, unknown>): void {
        this.count++;
        if (this.count % this.sampleRate === 0) {
            this.logger.info(message, { ...fields, sample: `1/${this.sampleRate}` });
        }
    }

    totalSeen(): number { return this.count; }
}

// ── Error codes: packed integers vs strings ───────────────────────
// BEST PRACTICE: Use numeric error codes for hot paths.
// String errors require allocation; numbers are free.

const enum ErrorCategory {
    NETWORK = 1,
    AUTH = 2,
    VALIDATION = 3,
    INTERNAL = 4,
}

function packError(category: ErrorCategory, code: number): number {
    return (category << 16) | (code & 0xFFFF);
}

function unpackCategory(packed: number): ErrorCategory {
    return (packed >> 16) as ErrorCategory;
}

function unpackCode(packed: number): number {
    return packed & 0xFFFF;
}

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    // ── Basic logging with level filtering ────────────────────────
    const logger = new Logger(LogLevel.INFO);

    logger.debug("this should be filtered", { key: "value" });
    logger.info("server started", { port: 8080 });
    logger.warn("disk usage high", { percent: 85 });
    logger.error("connection failed", { host: "db.local", retries: 3 });

    const entries = logger.getEntries();
    assert(entries.length === 3, "filtered: debug excluded");
    assert(entries[0].level === LogLevel.INFO, "first is info");
    assert(entries[1].level === LogLevel.WARN, "second is warn");
    assert(entries[2].level === LogLevel.ERROR, "third is error");

    // ── Fields are preserved ──────────────────────────────────────
    assert(entries[0].fields["port"] === 8080, "fields: port");
    assert(entries[2].fields["host"] === "db.local", "fields: host");
    assert(entries[2].fields["retries"] === 3, "fields: retries");

    // ── Level change at runtime ───────────────────────────────────
    logger.clear();
    logger.setLevel(LogLevel.TRACE);
    logger.trace("now visible");
    logger.debug("also visible");
    assert(logger.getEntries().length === 2, "trace level: all visible");

    logger.clear();
    logger.setLevel(LogLevel.ERROR);
    logger.info("filtered");
    logger.warn("filtered");
    logger.error("visible");
    assert(logger.getEntries().length === 1, "error level: only errors");
    assert(logger.getEntries()[0].message === "visible", "error message");

    // ── Spans: execution context ──────────────────────────────────
    logger.clear();
    logger.setLevel(LogLevel.DEBUG);

    const result = logger.span("parse", () => {
        logger.info("parsing input");
        return 42;
    });

    assert(result === 42, "span returns value");
    const spanEntries = logger.getEntries();
    assert(spanEntries.length === 2, "span: info + completion");
    assert(spanEntries[0].span === "parse", "span: context set");
    assert(spanEntries[0].message === "parsing input", "span: inner message");
    assert(spanEntries[1].message === "span parse completed", "span: completion");

    // ── Nested spans ──────────────────────────────────────────────
    logger.clear();
    logger.span("outer", () => {
        logger.info("in outer");
        logger.span("inner", () => {
            logger.info("in inner");
        });
        logger.info("back in outer");
    });

    const nested = logger.getEntries();
    assert(nested[0].span === "outer", "nested: outer span");
    assert(nested[1].span === "inner", "nested: inner span");
    assert(nested[2].message === "span inner completed", "nested: inner done");
    assert(nested[3].span === "outer", "nested: back to outer");

    // ── Span error handling ───────────────────────────────────────
    logger.clear();
    let caughtError = false;
    try {
        logger.span("failing", () => {
            throw new Error("boom");
        });
    } catch {
        caughtError = true;
    }
    assert(caughtError, "span: error propagated");
    const errorEntries = logger.getEntries();
    assert(errorEntries.length === 1, "span: error logged");
    assert(errorEntries[0].level === LogLevel.ERROR, "span: error level");
    assert(errorEntries[0].fields["error"] === "boom", "span: error message");

    // ── Text formatting ───────────────────────────────────────────
    logger.clear();
    logger.setLevel(LogLevel.INFO);
    logger.info("request handled", { method: "GET", status: 200 });

    const text = logger.formatText(logger.getEntries()[0]);
    assert(text.includes("INFO"), "format: has level");
    assert(text.includes("request handled"), "format: has message");
    assert(text.includes("method="), "format: has fields");

    // ── JSON formatting ───────────────────────────────────────────
    const json = logger.formatJson(logger.getEntries()[0]);
    const parsed = JSON.parse(json);
    assert(parsed.level === "INFO", "json: level");
    assert(parsed.msg === "request handled", "json: message");
    assert(parsed.method === "GET", "json: field");
    assert(parsed.status === 200, "json: field number");

    // ── Request-scoped logger ─────────────────────────────────────
    logger.clear();
    const reqLogger = new RequestLogger(logger, {
        requestId: "abc-123",
        userId: "user-42",
        path: "/api/users",
    });

    reqLogger.info("handling request");
    reqLogger.error("database timeout");

    const reqEntries = logger.getEntries();
    assert(reqEntries[0].fields["requestId"] === "abc-123", "request logger: id");
    assert(reqEntries[0].fields["path"] === "/api/users", "request logger: path");
    assert(reqEntries[1].level === LogLevel.ERROR, "request logger: error level");

    // ── Child logger ──────────────────────────────────────────────
    logger.clear();
    const child = new ChildLogger(logger, { service: "auth", version: "2.1" });
    child.info("token validated", { userId: "u-1" });

    const childEntries = logger.getEntries();
    assert(childEntries[0].fields["service"] === "auth", "child: inherited field");
    assert(childEntries[0].fields["userId"] === "u-1", "child: own field");

    // ── Sampled logger ────────────────────────────────────────────
    logger.clear();
    const sampled = new SampledLogger(logger, 10);
    for (let i = 0; i < 100; i++) {
        sampled.info("high-volume event");
    }
    assert(sampled.totalSeen() === 100, "sampled: counted all");
    assert(logger.getEntries().length === 10, "sampled: logged 1 in 10");

    // ── Performance timing ────────────────────────────────────────
    const timing = performanceTimingDemo();
    assert(timing.markDuration >= 0, "performance: non-negative duration");
    assert(timing.computeResult > 0, "performance: computation ran");

    // ── Packed error codes ────────────────────────────────────────
    const err = packError(ErrorCategory.AUTH, 42);
    assert(unpackCategory(err) === ErrorCategory.AUTH, "packed: category");
    assert(unpackCode(err) === 42, "packed: code");

    const netErr = packError(ErrorCategory.NETWORK, 1001);
    assert(unpackCategory(netErr) === ErrorCategory.NETWORK, "packed: network");
    assert(unpackCode(netErr) === 1001, "packed: network code");

    // Different categories produce different packed values
    assert(packError(ErrorCategory.AUTH, 1) !== packError(ErrorCategory.NETWORK, 1),
        "packed: different categories");

    // ── GOTCHA: formatting before filtering ───────────────────────
    // BAD:  const msg = `value=${expensive()}`; if (level <= max) log(msg);
    // GOOD: if (level > max) return; const msg = `value=${expensive()}`;
    // Our logger does this correctly — emit() checks shouldLog() first.

    // ── GOTCHA: wall clock vs monotonic ───────────────────────────
    // BAD:  Date.now() — can jump backwards (NTP correction)
    // GOOD: performance.now() — monotonic, sub-millisecond precision
    // Our logger uses performance.now() for timestamps.

    console.log("All tracing examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
