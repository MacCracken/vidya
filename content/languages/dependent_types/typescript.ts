// Vidya — Dependent Types — TypeScript port.
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// TypeScript has type-level encodings without values: a tuple's length is
// a literal type, variadic tuples compute append's length, a union of
// literals is a Fin, and a brand marks a refined number. tsc checks them;
// then they are erased, so at run time a Vec3 is an array and a Percent a
// number, and an `as` cast defeats any of them without a trace.

function check(cond: boolean, name: string): void {
    if (!cond) throw new Error(`check failed: ${name}`);
}

// --- 1. Length-indexed vector ---
// Vec<N> builds the tuple type of exactly N numbers by recursion on a
// literal N: Vec<3> is readonly [number, number, number]. A run-time
// length has no literal, so Vec<number> is a plain readonly number[].
type Tuple<N extends number, Acc extends number[] = []> =
    Acc["length"] extends N ? Acc : Tuple<N, [...Acc, number]>;
type Vec<N extends number> = number extends N ? readonly number[] : Readonly<Tuple<N>>;
type Vec0 = Vec<0>;
type Vec2 = Vec<2>;
type Vec3 = Vec<3>;

// The length, as a TYPE: vlen(b) has type 3 for a Vec3. The value still
// comes from the array at run time; the type is gone by then.
function vlen<V extends readonly number[]>(v: V): V["length"] {
    return v.length;
}

// head only on a tuple with at least one element. The empty one does not
// compile:
//   head([]);
//   error TS2345: Argument of type '[]' is not assignable to parameter of type 'NonEmpty<unknown>'.
// and a Vec2 is not a Vec3:
//   const b3: Vec3 = a;
//   error TS2322: Type 'readonly [number, number]' is not assignable to type 'readonly [number, number, number]'.
type NonEmpty<T> = readonly [T, ...T[]];
function head<T>(v: NonEmpty<T>): T {
    return v[0];
}

// The result type spreads both tuples, so its length is N + M in the type.
// Appending into the wrong length does not compile:
//   const d: Vec<4> = append(a, b);
//   error TS2322: Type '[number, number, number, number, number]' is not assignable to type 'readonly [number, number, number, number]'.
function append<A extends readonly number[], B extends readonly number[]>(a: A, b: B): [...A, ...B] {
    return [...a, ...b];
}

// A run-time length: the check is by hand. Indexing a number[] is typed
// `number` even when the array is empty (strict does not include
// noUncheckedIndexedAccess), so the type would not have caught it. The
// refusal is null, not undefined: undefined is what reading past the end
// gives, so it could not tell a refusal from a missing check.
function vecHead(v: readonly number[]): number | null {
    return v.length === 0 ? null : v[0];
}

// --- 2. Fin n: an index proven in range ---
// Fin<N> is the union of the literals below N: Fin<3> = 0 | 1 | 2. Its
// bound is read from Vec3's type, not written a second time. index3's
// parameter types are the proof, so it reads with no check of its own (and
// JavaScript has none to drop: an index past the end reads undefined).
//   index3(b, 3);
//   error TS2345: Argument of type '3' is not assignable to parameter of type '0 | 1 | 2'.
// A plain number is refused the same way ("Argument of type 'number' is not
// assignable to parameter of type '0 | 1 | 2'"), so a run-time index goes
// through a checked constructor. Literal unions are sets, so a Fin2 IS a
// Fin3 (0 | 1 is inside 0 | 1 | 2): a Fin2 on a Vec3 compiles, and is safe.
// The other way round does not:
//   index2(a, k3);
//   error TS2345: Argument of type '0 | 1 | 2' is not assignable to parameter of type '0 | 1'.
type Fin<N extends number, Acc extends number[] = []> =
    Acc["length"] extends N ? Acc[number] : Fin<N, [...Acc, Acc["length"]]>;
type Fin2 = Fin<Vec2["length"]>;
type Fin3 = Fin<Vec3["length"]>;

// The run-time bounds, typed by the vector types: if Vec3 changed length,
// `= 3` would stop compiling.
const VEC2_LEN: Vec2["length"] = 2;
const VEC3_LEN: Vec3["length"] = 3;

// A type predicate is trusted, not checked: tsc believes `i is Fin3` from
// the signature. These two bodies are the audited part.
function isFin2(i: number): i is Fin2 {
    return Number.isInteger(i) && i >= 0 && i < VEC2_LEN;
}
function isFin3(i: number): i is Fin3 {
    return Number.isInteger(i) && i >= 0 && i < VEC3_LEN;
}
function fin2(i: number): Fin2 | null {
    return isFin2(i) ? i : null;
}
function fin3(i: number): Fin3 | null {
    return isFin3(i) ? i : null;
}

function index2(v: Vec2, k: Fin2): number {
    return v[k];
}
function index3(v: Vec3, k: Fin3): number {
    return v[k];
}

// --- 3. Refinement at the boundary (parse, don't validate) ---
// A brand is a phantom property no value really has, so no plain number is
// a Percent:
//   discount(200, 150);
//   error TS2345: Argument of type 'number' is not assignable to parameter of type 'Percent'.
// percent() is the one place the range is checked and the one sanctioned
// cast. discount takes a Percent and trusts it; percentChecks counts
// validations so a check can see that.
declare const percentBrand: unique symbol;
type Percent = number & { readonly [percentBrand]: true };
let percentChecks = 0;

function percent(x: number): Percent | null {
    percentChecks++;
    if (!Number.isInteger(x) || x < 0 || x > 100) return null;
    return x as Percent;
}

function discount(price: number, p: Percent): number {
    return price - Math.trunc((price * p) / 100);
}

// --- 4. Σ type (dependent pair) ---
// Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
// the first. For a literal n TypeScript can say it: Sized<3> holds a
// Vec<3>. For a run-time n it cannot, so sized() checks the dependency
// once and the brand marks a pair that passed. After the check s.data is
// typed Vec<3>, so index3 accepts it. sizedSum takes its loop bound from
// n alone. A pair written by hand is refused:
//   const lit: Sized<3> = { n: 3, data: [1, 2, 3] };
//   error TS2322: Type '{ n: 3; data: [number, number, number]; }' is not assignable to type 'Sized<3>'.
declare const sizedBrand: unique symbol;
type SizedPair = { readonly n: number; readonly data: readonly number[]; readonly [sizedBrand]: true };
type Sized<N extends number> = SizedPair & { readonly n: N; readonly data: Vec<N> };

function sized<N extends number>(n: N, data: readonly number[]): Sized<N> | null {
    if (data.length !== n) return null;
    return { n, data } as unknown as Sized<N>; // the line above is the proof; tsc cannot follow it
}

function sizedSum(s: SizedPair): number {
    let total = 0;
    for (let i = 0; i < s.n; i++) total += s.data[i];
    return total;
}

// --- 5. The escape hatch ---
// Every type above is erased. `as` makes tsc believe anything that
// overlaps: `150 as Percent` compiles and is just the number 150, and
// `readonly` is erased too, so a cast lets a validated pair be rewritten:
//   s.n = 5;
//   error TS2540: Cannot assign to 'n' because it is a read-only property.
// compiles once written `(s as { n: number }).n = 5`. A branded number
// cannot be rewritten in place (numbers are values), only forged.
// What keeps a brand honest is review, or a lint rule, that allows `as
// Percent` only inside percent(). What survives erasure is a #private
// field: the engine checks it at run time. A plain `as` to SafePercent is
// refused (error TS2352: Conversion of type '{ v: number; }' to type
// 'SafePercent' may be a mistake ...), and the double cast that compiles
// throws a TypeError as soon as read() looks for the #v the fake lacks.
// The `private constructor` is erased, though: `new SafePercent(150)` is
// error TS2673 (Constructor of class 'SafePercent' is private and only
// accessible within the class declaration.), but a cast to a constructor
// type runs it and mints a real SafePercent of 150. #v proves an object
// came from the class, not that of() checked it.
class SafePercent {
    readonly #v: number;
    private constructor(v: number) {
        this.#v = v;
    }
    static of(x: number): SafePercent | null {
        return Number.isInteger(x) && x >= 0 && x <= 100 ? new SafePercent(x) : null;
    }
    static read(p: SafePercent): number {
        return p.#v;
    }
}

function safeDiscount(price: number, p: SafePercent): number {
    return price - Math.trunc((price * SafePercent.read(p)) / 100);
}

function throwsTypeError(f: () => unknown): boolean {
    try {
        f();
    } catch (e) {
        return e instanceof TypeError;
    }
    return false;
}

// === Tests ===

// 1. length-indexed vector
{
    const empty: Vec0 = [];
    const a: Vec2 = [1, 2];
    const b: Vec3 = [3, 4, 5];
    check(vlen(empty) === 0, "Vec0's length is 0");
    check(vlen(a) === 2, "Vec2's length is 2");
    check(vlen(b) === 3, "Vec3's length is 3");
    check(head(a) === 1, "head([1, 2]) = 1");
    check(head(b) === 3, "head([3, 4, 5]) = 3");

    const c = append(a, b);
    // Compile-time check: tsc accepts this only if append's TYPE has length 5.
    const len: 5 = vlen(c);
    check(len === vlen(a) + vlen(b), "append(Vec2, Vec3) has length 2 + 3 = 5");
    check(c.join(",") === "1,2,3,4,5", "append([1, 2], [3, 4, 5]) reads [1, 2, 3, 4, 5]");

    const none: number[] = [];
    const typedNumber: number = none[0];
    check(typedNumber === undefined, "none[0] is typed number but is undefined: the type did not check");
    check(vecHead(none) === null, "run-time head of an empty array is refused");
    check(vecHead([7]) === 7, "run-time head of [7] is allowed and = 7");
}

// 2. Fin n
{
    const a: Vec2 = [1, 2];
    const b: Vec3 = [3, 4, 5];
    check(fin3(-1) === null, "fin3(-1) is refused");
    check(fin3(3) === null, "fin3(3) is refused: 3 is not < 3");
    let accepted = 0;
    let ok = true;
    for (let i = -1; i <= 3; i++) {
        const k = fin3(i);
        if (k !== null) {
            accepted++;
            if (index3(b, k) !== 3 + i) ok = false;
        }
    }
    check(accepted === 3, "fin3 accepts exactly 0, 1, 2 out of -1..3");
    check(ok, "index3 with each Fin3 reads [3, 4, 5] in order");
    check(fin2(2) === null, "fin2(2) is refused: 2 is not < 2");
    const k1 = fin2(1);
    check(k1 !== null && index2(a, k1) === 2, "index2([1, 2], fin2(1)) = 2");
    check(k1 !== null && index3(b, k1) === 4, "a Fin2 is a Fin3 (0 | 1 is in 0 | 1 | 2): index3(b, fin2(1)) = 4");
}

// 3. refinement at the boundary
{
    percentChecks = 0;
    check(percent(-1) === null, "percent(-1) is refused");
    check(percent(101) === null, "percent(101) is refused");
    const p0 = percent(0);
    const p100 = percent(100);
    const p25 = percent(25);
    check(percentChecks === 5, "5 constructions, 5 validations");
    if (p0 === null || p100 === null || p25 === null) throw new Error("percent refused one of 0, 100, 25");
    check(discount(200, p25) === 150, "discount(200, 25%) = 150");
    check(discount(200, p0) === 200, "discount(200, 0%) = 200");
    check(discount(200, p100) === 0, "discount(200, 100%) = 0");
    check(percentChecks === 5, "discount never re-validated: still 5 checks after 3 calls");
}

// 4. Σ type
{
    const two = [1, 2];
    const three = [1, 2, 3];
    check(sized(3, two) === null, "(3, [1, 2]) is refused: the length is 2");
    check(sized(2, three) === null, "(2, [1, 2, 3]) is refused: the length is 3");
    const s = sized(3, three);
    if (s === null) throw new Error("(3, [1, 2, 3]) was refused");
    check(s.n === 3, "the pair's n is 3");
    check(sizedSum(s) === 6, "sizedSum reads n = 3 elements: 1 + 2 + 3 = 6");
    check(index3(s.data, 2) === 3, "after the check, s.data is a Vec<3>: index3(s.data, 2) = 3");
}

// 5. the escape hatch
{
    check(percent(150) === null, "the API refuses 150");
    const forged = 150 as Percent;
    check(typeof forged === "number" && forged === 150, "`150 as Percent` is the number 150 at run time");
    check(discount(200, forged) === -100, "and discount trusts it: 200 - 300 = -100");

    const s = sized(3, [1, 2, 3]);
    if (s === null) throw new Error("(3, [1, 2, 3]) was refused");
    (s as { n: number }).n = 5;
    // tsc still believes n is 3: `s.n === 5` is refused with error TS2367:
    // This comparison appears to be unintentional because the types '3' and '5' have no overlap.
    const seen: number = s.n;
    check(seen === 5, "a cast rewrites the validated pair's readonly n to 5");
    check(Number.isNaN(sizedSum(s)), "sizedSum trusts n = 5, reads past the data, and returns NaN");

    check(SafePercent.of(150) === null, "SafePercent.of(150) is refused too");
    const fake = { v: 150 } as unknown as SafePercent;
    check(throwsTypeError(() => safeDiscount(200, fake)), "a fake SafePercent has no #v: the engine throws TypeError");
    const real = SafePercent.of(25);
    check(real !== null && safeDiscount(200, real) === 150, "a real SafePercent reads its #v: 200 - 50 = 150");
    const Unchecked = SafePercent as unknown as new (v: number) => SafePercent;
    const minted = new Unchecked(150); // the erased private constructor, called without of()
    check(safeDiscount(200, minted) === -100, "the private constructor is erased: a cast mints a SafePercent of 150, -100");
}

// Compile-time checks: every line below must NOT compile (the messages are
// quoted in the sections above). `@ts-expect-error` makes that a check tsc
// runs: if one of these lines ever compiled, tsc would stop with "Unused
// '@ts-expect-error' directive." The function is never called.
function refusedAtCompileTime(a: Vec2, b: Vec3, k3: Fin3, i: number, s3: Sized<3>): void {
    // @ts-expect-error: head of an empty vector
    head([]);
    // @ts-expect-error: a Vec2 is not a Vec3
    const b3: Vec3 = a;
    // @ts-expect-error: append(Vec2, Vec3) has length 5, not 4
    const d: Vec<4> = append(a, b);
    // @ts-expect-error: 3 is not a Fin3
    index3(b, 3);
    // @ts-expect-error: a Fin3 is not a Fin2
    index2(a, k3);
    // @ts-expect-error: a plain number is not a Percent
    discount(200, 150);
    // @ts-expect-error: a hand-written pair has no brand
    const lit: Sized<3> = { n: 3, data: [1, 2, 3] };
    // @ts-expect-error: a plain number is not a Fin3
    index3(b, i);
    // @ts-expect-error: a validated pair's n is read-only
    s3.n = 5;
    // @ts-expect-error: tsc believes n is 3, so n === 5 has no overlap
    void (s3.n === 5);
    // @ts-expect-error: an object without #v is not a SafePercent
    void ({ v: 150 } as SafePercent);
    // @ts-expect-error: the constructor is private at compile time
    void new SafePercent(150);
    void [b3, d, lit];
}
void refusedAtCompileTime;

console.log("All dependent type examples passed.");
process.exit(0);
