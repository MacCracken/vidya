// Vidya — Package Resolution — TypeScript port.
//
// Semantic versioning, caret constraint matching, range intersection
// for diamond dependencies, highest-version selection, bounded
// backtracking, and dependency-cycle detection — the core of a
// dependency resolver (npm, cargo, cyrius.cyml's own resolver).
//
// A semver major.minor.patch is encoded as one number
//   enc = major*1_000_000 + minor*1_000 + patch
// so version comparison IS numeric comparison. All components stay
// below 1e7, so encodings are exact in f64 — no BigInt needed. A
// constraint is a half-open range [lo, hi). A caret ^X.Y.Z allows
// everything from X.Y.Z up to (but not including) the next major:
// [X.Y.Z, (X+1).0.0).

const VMAJ = 1_000_000;
const VMIN = 1_000;

// --- Semver encode / inspect ---
function sv(maj: number, min: number, pat: number): number {
    return maj * VMAJ + min * VMIN + pat;
}
function svMajor(v: number): number {
    return Math.floor(v / VMAJ);
}

// --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---
function caretLo(v: number): number {
    return v;
}
function caretHi(v: number): number {
    return (svMajor(v) + 1) * VMAJ;
}

// --- Constraint satisfaction over a half-open range ---
function satisfies(v: number, lo: number, hi: number): boolean {
    return lo <= v && v < hi;
}

// --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---
function rangeLoMax(a: number, b: number): number {
    return a > b ? a : b;
}
function rangeHiMin(a: number, b: number): number {
    return a < b ? a : b;
}
function rangeEmpty(lo: number, hi: number): boolean {
    return lo >= hi;
}

// --- Highest version in vers that lies in [lo, hi); -1 if none ---
function bestMatch(vers: number[], lo: number, hi: number): number {
    let best = -1;
    for (const v of vers) {
        if (satisfies(v, lo, hi) && v > best) best = v;
    }
    return best;
}

// --- Available versions of the shared dependency C ---
const C_VERS: number[] = [sv(1, 0, 0), sv(1, 5, 0), sv(2, 0, 0)];

// --- Diamond resolution: A requires C ^aBase, B requires C ^bBase.
//     Intersect the two carets and pick the highest C that fits.
//     Returns chosen C version, or -1 if the constraints conflict. ---
function resolveShared(aBase: number, bBase: number): number {
    const lo = rangeLoMax(caretLo(aBase), caretLo(bBase));
    const hi = rangeHiMin(caretHi(aBase), caretHi(bBase));
    if (rangeEmpty(lo, hi)) return -1;
    return bestMatch(C_VERS, lo, hi);
}

// --- Bounded backtracking: A has candidate versions (aVers), each of
//     which requires a different caret on C (aCreq). B requires C
//     ^bBase. The absolute-highest A may force a C constraint that
//     conflicts with B; choose the HIGHEST A for which some C still
//     satisfies both. Returns [chosenA, chosenC]; [-1, -1] if none. ---
function resolveBacktrack(
    aVers: number[],
    aCreq: number[],
    bBase: number,
): [number, number] {
    let bestA = -1;
    let bestC = -1;
    for (let i = 0; i < aVers.length; i++) {
        const aver = aVers[i];
        const creq = aCreq[i];
        const lo = rangeLoMax(caretLo(creq), caretLo(bBase));
        const hi = rangeHiMin(caretHi(creq), caretHi(bBase));
        if (!rangeEmpty(lo, hi)) {
            const c = bestMatch(C_VERS, lo, hi);
            if (c !== -1 && aver > bestA) {
                bestA = aver;
                bestC = c;
            }
        }
    }
    return [bestA, bestC];
}

// --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
//     some package permanently unplaceable). ---
class DepGraph {
    private deps: number[][];

    constructor(n: number) {
        this.deps = Array.from({ length: n }, () => []);
    }
    addDep(p: number, d: number): void {
        this.deps[p].push(d);
    }
    hasCycle(): boolean {
        const n = this.deps.length;
        const placed = new Array<boolean>(n).fill(false);
        let placedCount = 0;
        while (placedCount < n) {
            let progress = false;
            for (let p = 0; p < n; p++) {
                if (placed[p]) continue;
                const ready = this.deps[p].every((d) => placed[d]);
                if (ready) {
                    placed[p] = true;
                    placedCount++;
                    progress = true;
                }
            }
            if (!progress) return true; // stuck ⇒ cycle
        }
        return false;
    }
}

// === Tests ===

function assert(cond: boolean, name: string): void {
    if (!cond) throw new Error(`assertion failed: ${name}`);
}

// semver
assert(sv(1, 2, 3) > sv(1, 2, 0), "patch ordering");
assert(sv(2, 0, 0) > sv(1, 9, 9), "major dominates minor/patch");
assert(svMajor(sv(1, 5, 2)) === 1, "extract major");

// caret
assert(caretLo(sv(1, 2, 0)) === sv(1, 2, 0), "caret lower = base");
assert(caretHi(sv(1, 2, 0)) === sv(2, 0, 0), "caret upper = next major");
assert(satisfies(sv(1, 4, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "1.4.0 in ^1.2.0");
assert(!satisfies(sv(2, 0, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "2.0.0 not in ^1.2.0");
assert(!satisfies(sv(1, 1, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "1.1.0 below ^1.2.0");

// intersect
assert(rangeLoMax(sv(1, 0, 0), sv(1, 3, 0)) === sv(1, 3, 0), "intersect lo = max");
assert(rangeHiMin(sv(2, 0, 0), sv(3, 0, 0)) === sv(2, 0, 0), "intersect hi = min");
{
    const lo = rangeLoMax(caretLo(sv(1, 0, 0)), caretLo(sv(2, 0, 0)));
    const hi = rangeHiMin(caretHi(sv(1, 0, 0)), caretHi(sv(2, 0, 0)));
    assert(rangeEmpty(lo, hi), "^1.0.0 and ^2.0.0 are disjoint");
}

// best match
assert(bestMatch(C_VERS, caretLo(sv(1, 0, 0)), caretHi(sv(1, 0, 0))) === sv(1, 5, 0), "highest C in ^1.0.0 = 1.5.0");
assert(bestMatch(C_VERS, caretLo(sv(3, 0, 0)), caretHi(sv(3, 0, 0))) === -1, "no C in ^3.0.0");

// diamond resolution
assert(resolveShared(sv(1, 0, 0), sv(1, 0, 0)) === sv(1, 5, 0), "A^1 ∩ B^1 picks C 1.5.0");
assert(resolveShared(sv(1, 0, 0), sv(2, 0, 0)) === -1, "A^1 vs B^2 is unresolvable");

// backtracking
{
    // A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
    // The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
    const aVers = [sv(1, 1, 0), sv(1, 0, 0)];
    const aCreq = [sv(2, 0, 0), sv(1, 0, 0)];
    const [chosenA, chosenC] = resolveBacktrack(aVers, aCreq, sv(1, 0, 0));
    assert(chosenA === sv(1, 0, 0), "backtrack picks A 1.0.0, not 1.1.0");
    assert(chosenC === sv(1, 5, 0), "and resolves C to 1.5.0");
}

// cycle detection
{
    const g = new DepGraph(2);
    g.addDep(0, 1);
    g.addDep(1, 0);
    assert(g.hasCycle(), "A↔B is a dependency cycle");
}
{
    const g = new DepGraph(3);
    g.addDep(2, 0);
    g.addDep(2, 1); // app → A, B (diamond, acyclic)
    assert(!g.hasCycle(), "diamond graph is acyclic");
}

console.log("All package_resolution examples passed.");
process.exit(0);
