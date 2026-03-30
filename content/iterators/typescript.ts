// Vidya — Iterators in TypeScript
//
// TypeScript/JS iterators use the Symbol.iterator protocol, for-of loops,
// and array methods (map, filter, reduce). Generators (function*) create
// lazy sequences. Array methods are the idiomatic functional pipeline.

function main(): void {
    // ── Array methods: the primary iteration API ───────────────────
    const numbers: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    const evenSquares = numbers
        .filter((n) => n % 2 === 0)
        .map((n) => n * n);
    assertArrayEq(evenSquares, [4, 16, 36, 64, 100], "filter+map");

    // ── reduce: the universal accumulator ──────────────────────────
    const sum = numbers.reduce((acc, n) => acc + n, 0);
    assert(sum === 55, "reduce sum");

    const csv = numbers.reduce(
        (acc, n) => (acc ? `${acc},${n}` : `${n}`),
        "",
    );
    assert(csv === "1,2,3,4,5,6,7,8,9,10", "reduce csv");

    // ── for-of: iterate any iterable ───────────────────────────────
    let forOfSum = 0;
    for (const n of numbers) {
        forOfSum += n;
    }
    assert(forOfSum === 55, "for-of sum");

    // ── entries, keys, values ──────────────────────────────────────
    const words = ["hello", "world"];
    for (const [i, word] of words.entries()) {
        assert(typeof i === "number", "entry index");
        assert(typeof word === "string", "entry value");
    }

    // ── flatMap: flatten + map in one step ─────────────────────────
    const nested = [[1, 2], [3, 4], [5]];
    const flat = nested.flatMap((arr) => arr);
    assertArrayEq(flat, [1, 2, 3, 4, 5], "flatMap");

    // ── find, findIndex, some, every ───────────────────────────────
    assert(numbers.find((n) => n > 7) === 8, "find");
    assert(numbers.findIndex((n) => n === 5) === 4, "findIndex");
    assert(numbers.some((n) => n > 5), "some");
    assert(!numbers.every((n) => n > 5), "every");
    assert(numbers.includes(7), "includes");

    // ── Generators: lazy iteration ─────────────────────────────────
    function* countdown(n: number): Generator<number> {
        while (n > 0) {
            yield n;
            n--;
        }
    }

    assertArrayEq([...countdown(3)], [3, 2, 1], "generator");

    // Infinite generator with take
    function* naturals(): Generator<number> {
        let n = 0;
        while (true) {
            yield n++;
        }
    }

    function take<T>(iter: Iterable<T>, n: number): T[] {
        const result: T[] = [];
        for (const item of iter) {
            if (result.length >= n) break;
            result.push(item);
        }
        return result;
    }

    assertArrayEq(take(naturals(), 5), [0, 1, 2, 3, 4], "take from infinite");

    // ── Generator composition ──────────────────────────────────────
    function* filterGen<T>(iter: Iterable<T>, pred: (x: T) => boolean): Generator<T> {
        for (const item of iter) {
            if (pred(item)) yield item;
        }
    }

    function* mapGen<T, U>(iter: Iterable<T>, fn: (x: T) => U): Generator<U> {
        for (const item of iter) {
            yield fn(item);
        }
    }

    const squares = take(
        mapGen(
            filterGen(naturals(), (n) => n % 2 === 0),
            (n) => n * n,
        ),
        5,
    );
    assertArrayEq(squares, [0, 4, 16, 36, 64], "composed generators");

    // ── Custom iterable class ──────────────────────────────────────
    class Range {
        constructor(private start: number, private end: number) {}

        *[Symbol.iterator](): Generator<number> {
            for (let i = this.start; i < this.end; i++) {
                yield i;
            }
        }
    }

    assertArrayEq([...new Range(3, 7)], [3, 4, 5, 6], "custom iterable");

    // ── Map and Set iteration ──────────────────────────────────────
    const map = new Map<string, number>([
        ["a", 1],
        ["b", 2],
        ["c", 3],
    ]);

    const keys = [...map.keys()];
    assertArrayEq(keys, ["a", "b", "c"], "map keys");

    const values = [...map.values()];
    assertArrayEq(values, [1, 2, 3], "map values");

    const set = new Set([1, 2, 3, 2, 1]);
    assert(set.size === 3, "set dedup");
    assertArrayEq([...set], [1, 2, 3], "set iteration");

    // ── Object iteration ───────────────────────────────────────────
    const obj = { x: 1, y: 2, z: 3 };
    const objKeys = Object.keys(obj);
    assertArrayEq(objKeys, ["x", "y", "z"], "Object.keys");

    const objEntries = Object.entries(obj);
    assert(objEntries[0][0] === "x" && objEntries[0][1] === 1, "Object.entries");

    // ── Array.from: convert iterables to arrays ────────────────────
    const fromRange = Array.from({ length: 5 }, (_, i) => i * 2);
    assertArrayEq(fromRange, [0, 2, 4, 6, 8], "Array.from");

    // ── sort (mutates!) ────────────────────────────────────────────
    const unsorted = [3, 1, 4, 1, 5];
    const sorted = [...unsorted].sort((a, b) => a - b);
    assertArrayEq(sorted, [1, 1, 3, 4, 5], "sort");
    assert(unsorted[0] === 3, "original unchanged");

    console.log("All iterator examples passed.");
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
