// Vidya — Concurrency in TypeScript
//
// JavaScript/TypeScript is single-threaded with an event loop. Concurrency
// is cooperative: async/await for I/O, Promises for composition, and
// Web Workers / worker_threads for true parallelism. There are no
// mutexes because there's no shared mutable state (by default).

// ── Promises: the foundation ───────────────────────────────────────

function delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function asyncCompute(n: number): Promise<number> {
    return new Promise((resolve) => {
        // Simulate async work
        resolve(n * n);
    });
}

// ── Async/await: sequential async code ─────────────────────────────

async function sequential(): Promise<number[]> {
    const a = await asyncCompute(2);
    const b = await asyncCompute(3);
    const c = await asyncCompute(4);
    return [a, b, c]; // runs one at a time
}

// ── Promise.all: concurrent execution ──────────────────────────────

async function concurrent(): Promise<number[]> {
    const results = await Promise.all([
        asyncCompute(2),
        asyncCompute(3),
        asyncCompute(4),
    ]);
    return results; // all three run concurrently
}

// ── Promise.allSettled: handle mixed success/failure ────────────────

async function mixedResults(): Promise<string[]> {
    const results = await Promise.allSettled([
        Promise.resolve("ok"),
        Promise.reject(new Error("fail")),
        Promise.resolve("also ok"),
    ]);

    return results.map((r) =>
        r.status === "fulfilled" ? r.value : `error: ${r.reason.message}`,
    );
}

// ── Promise.race: first to complete wins ───────────────────────────

async function raceExample(): Promise<string> {
    const fast = new Promise<string>((resolve) =>
        setTimeout(() => resolve("fast"), 10),
    );
    const slow = new Promise<string>((resolve) =>
        setTimeout(() => resolve("slow"), 100),
    );
    return Promise.race([fast, slow]);
}

// ── Async iteration ────────────────────────────────────────────────

async function* asyncRange(start: number, end: number): AsyncGenerator<number> {
    for (let i = start; i < end; i++) {
        yield i;
    }
}

// ── Semaphore: limit concurrency ───────────────────────────────────

class Semaphore {
    private queue: (() => void)[] = [];
    private running = 0;

    constructor(private maxConcurrency: number) {}

    async acquire(): Promise<void> {
        if (this.running < this.maxConcurrency) {
            this.running++;
            return;
        }
        return new Promise<void>((resolve) => {
            this.queue.push(resolve);
        });
    }

    release(): void {
        this.running--;
        const next = this.queue.shift();
        if (next) {
            this.running++;
            next();
        }
    }
}

async function withSemaphore<T>(
    sem: Semaphore,
    fn: () => Promise<T>,
): Promise<T> {
    await sem.acquire();
    try {
        return await fn();
    } finally {
        sem.release();
    }
}

// ── AbortController: cancellation ──────────────────────────────────

async function cancellableWork(signal: AbortSignal): Promise<string> {
    for (let i = 0; i < 10; i++) {
        if (signal.aborted) {
            return "cancelled";
        }
        await delay(1);
    }
    return "completed";
}

async function main(): Promise<void> {
    // ── Basic Promise ──────────────────────────────────────────────
    const result = await asyncCompute(5);
    assert(result === 25, "basic promise");

    // ── Sequential execution ───────────────────────────────────────
    const seqResults = await sequential();
    assertArrayEq(seqResults, [4, 9, 16], "sequential");

    // ── Concurrent execution ───────────────────────────────────────
    const conResults = await concurrent();
    assertArrayEq(conResults, [4, 9, 16], "concurrent");

    // ── Promise.allSettled ─────────────────────────────────────────
    const mixed = await mixedResults();
    assert(mixed[0] === "ok", "settled ok");
    assert(mixed[1] === "error: fail", "settled fail");
    assert(mixed[2] === "also ok", "settled also ok");

    // ── Promise.race ───────────────────────────────────────────────
    const winner = await raceExample();
    assert(winner === "fast", "race winner");

    // ── Error handling in async ────────────────────────────────────
    try {
        await Promise.reject(new Error("async error"));
        assert(false, "should have thrown");
    } catch (e) {
        assert(e instanceof Error, "caught async error");
        assert((e as Error).message === "async error", "error message");
    }

    // ── Async iteration ────────────────────────────────────────────
    const collected: number[] = [];
    for await (const n of asyncRange(0, 5)) {
        collected.push(n);
    }
    assertArrayEq(collected, [0, 1, 2, 3, 4], "async iteration");

    // ── Semaphore: controlled concurrency ──────────────────────────
    const sem = new Semaphore(2);
    let maxConcurrent = 0;
    let currentConcurrent = 0;

    const tasks = Array.from({ length: 6 }, (_, i) =>
        withSemaphore(sem, async () => {
            currentConcurrent++;
            if (currentConcurrent > maxConcurrent) {
                maxConcurrent = currentConcurrent;
            }
            await delay(5);
            currentConcurrent--;
            return i;
        }),
    );

    const semResults = await Promise.all(tasks);
    assert(semResults.length === 6, "semaphore all completed");
    assert(maxConcurrent <= 2, "semaphore limited concurrency");

    // ── AbortController: cancellation ──────────────────────────────
    const controller = new AbortController();
    const workPromise = cancellableWork(controller.signal);
    controller.abort(); // cancel immediately
    const cancelResult = await workPromise;
    assert(cancelResult === "cancelled", "abort controller");

    // ── Promise.withResolvers (ES2024) ─────────────────────────────
    // Externalizes resolve/reject for manual control
    // const { promise, resolve, reject } = Promise.withResolvers<number>();
    // resolve(42);
    // assert(await promise === 42);

    // ── Microtasks vs macrotasks ───────────────────────────────────
    // Promise callbacks (.then) run as microtasks (before next macrotask)
    // setTimeout callbacks run as macrotasks
    // Order: sync code → microtasks → macrotasks
    const order: string[] = [];
    order.push("sync");
    Promise.resolve().then(() => order.push("microtask"));
    setTimeout(() => order.push("macrotask"), 0);

    // Wait for both to complete
    await delay(10);
    assert(order[0] === "sync", "event loop: sync first");
    assert(order[1] === "microtask", "event loop: microtask second");
    assert(order[2] === "macrotask", "event loop: macrotask third");

    console.log("All concurrency examples passed.");
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
