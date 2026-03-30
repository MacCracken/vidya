// Vidya — Design Patterns in TypeScript
//
// TypeScript patterns: builder with fluent API and type safety,
// strategy via first-class functions, observer with callbacks,
// state machine with discriminated unions, factory with runtime
// dispatch, and dependency injection via interfaces.

function main(): void {
    testBuilderPattern();
    testStrategyPattern();
    testObserverPattern();
    testStateMachine();
    testFactoryPattern();
    testDependencyInjection();

    console.log("All design patterns examples passed.");
}

// ── Builder pattern ──────────────────────────────────────────────────
// Fluent API with validation on build(). Required fields enforced at
// runtime via explicit checks. Returns the built object or throws.

interface Server {
    host: string;
    port: number;
    maxConnections: number;
    timeoutMs: number;
}

class ServerBuilder {
    private _host: string | null = null;
    private _port: number | null = null;
    private _maxConnections = 100;
    private _timeoutMs = 5000;

    host(h: string): this {
        this._host = h;
        return this;
    }

    port(p: number): this {
        this._port = p;
        return this;
    }

    maxConnections(n: number): this {
        this._maxConnections = n;
        return this;
    }

    timeoutMs(ms: number): this {
        this._timeoutMs = ms;
        return this;
    }

    build(): Server {
        if (this._host === null) throw new Error("host is required");
        if (this._port === null) throw new Error("port is required");
        return {
            host: this._host,
            port: this._port,
            maxConnections: this._maxConnections,
            timeoutMs: this._timeoutMs,
        };
    }
}

function testBuilderPattern(): void {
    const server = new ServerBuilder()
        .host("localhost")
        .port(8080)
        .maxConnections(200)
        .timeoutMs(3000)
        .build();

    assert(server.host === "localhost", "host");
    assert(server.port === 8080, "port");
    assert(server.maxConnections === 200, "max conns");
    assert(server.timeoutMs === 3000, "timeout");

    // Missing required field
    let threw = false;
    try {
        new ServerBuilder().host("localhost").build();
    } catch {
        threw = true;
    }
    assert(threw, "missing port throws");
}

// ── Strategy pattern ─────────────────────────────────────────────────
// First-class functions — no class hierarchy needed.

type DiscountStrategy = (price: number) => number;

function applyDiscount(price: number, strategy: DiscountStrategy): number {
    return strategy(price);
}

function testStrategyPattern(): void {
    const noDiscount: DiscountStrategy = (p) => p;
    const tenPercent: DiscountStrategy = (p) => p * 0.9;
    const flatFive: DiscountStrategy = (p) => Math.max(p - 5, 0);

    assert(applyDiscount(100, noDiscount) === 100, "no discount");
    assert(applyDiscount(100, tenPercent) === 90, "10%");
    assert(applyDiscount(100, flatFive) === 95, "$5 off");
    assert(applyDiscount(3, flatFive) === 0, "floor at 0");
}

// ── Observer pattern ─────────────────────────────────────────────────
// Callback-based event notification.

class EventEmitter {
    private listeners: Array<(event: string) => void> = [];

    on(callback: (event: string) => void): void {
        this.listeners.push(callback);
    }

    emit(event: string): void {
        for (const listener of this.listeners) {
            listener(event);
        }
    }
}

function testObserverPattern(): void {
    const log: string[] = [];
    const emitter = new EventEmitter();

    emitter.on((e) => log.push(`A:${e}`));
    emitter.on((e) => log.push(`B:${e}`));

    emitter.emit("click");
    emitter.emit("hover");

    assert(log.length === 4, "4 events");
    assert(log[0] === "A:click", "first");
    assert(log[1] === "B:click", "second");
    assert(log[2] === "A:hover", "third");
    assert(log[3] === "B:hover", "fourth");
}

// ── State machine ────────────────────────────────────────────────────
// Transition table maps (state, action) pairs to next states.

type DoorState = "locked" | "closed" | "open";
type DoorAction = "unlock" | "open" | "close" | "lock";

const TRANSITIONS: Record<string, DoorState> = {
    "locked:unlock": "closed",
    "closed:open": "open",
    "open:close": "closed",
    "closed:lock": "locked",
};

function doorTransition(state: DoorState, action: DoorAction): DoorState {
    const key = `${state}:${action}`;
    const next = TRANSITIONS[key];
    if (next === undefined) {
        throw new Error(`cannot ${action} when ${state}`);
    }
    return next;
}

function testStateMachine(): void {
    let door: DoorState = "locked";
    door = doorTransition(door, "unlock");
    assert(door === "closed", "unlocked");
    door = doorTransition(door, "open");
    assert(door === "open", "opened");
    door = doorTransition(door, "close");
    door = doorTransition(door, "lock");
    assert(door === "locked", "relocked");

    // Invalid transition
    let threw = false;
    try {
        doorTransition("locked", "open");
    } catch {
        threw = true;
    }
    assert(threw, "invalid transition throws");
}

// ── Factory pattern ──────────────────────────────────────────────────
// Create objects based on runtime parameters.

interface Shape {
    type: string;
    area(): number;
}

function shapeFactory(name: string, params: number[]): Shape {
    switch (name) {
        case "circle":
            return {
                type: "circle",
                area: () => Math.PI * params[0] * params[0],
            };
        case "rectangle":
            return {
                type: "rectangle",
                area: () => params[0] * params[1],
            };
        case "triangle":
            return {
                type: "triangle",
                area: () => 0.5 * params[0] * params[1],
            };
        default:
            throw new Error(`unknown shape: ${name}`);
    }
}

function testFactoryPattern(): void {
    const c = shapeFactory("circle", [5]);
    assert(Math.abs(c.area() - 78.539) < 0.001, "circle area");

    const r = shapeFactory("rectangle", [3, 4]);
    assert(r.area() === 12, "rect area");

    const t = shapeFactory("triangle", [6, 4]);
    assert(t.area() === 12, "triangle area");

    let threw = false;
    try {
        shapeFactory("hexagon", [1]);
    } catch {
        threw = true;
    }
    assert(threw, "unknown shape throws");
}

// ── Dependency injection ─────────────────────────────────────────────
// Pass dependencies via constructor, not global state.

interface Logger {
    log(msg: string): string;
}

class StdoutLogger implements Logger {
    log(msg: string): string {
        return `[stdout] ${msg}`;
    }
}

class TestLogger implements Logger {
    entries: string[] = [];

    log(msg: string): string {
        const entry = `[test] ${msg}`;
        this.entries.push(entry);
        return entry;
    }
}

class Service {
    constructor(private logger: Logger) {}

    process(item: string): string {
        return this.logger.log(`processing ${item}`);
    }
}

function testDependencyInjection(): void {
    const svc1 = new Service(new StdoutLogger());
    assert(svc1.process("order") === "[stdout] processing order", "prod logger");

    const testLog = new TestLogger();
    const svc2 = new Service(testLog);
    svc2.process("order-1");
    svc2.process("order-2");
    assert(testLog.entries.length === 2, "test logger count");
    assert(testLog.entries[0] === "[test] processing order-1", "first entry");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
