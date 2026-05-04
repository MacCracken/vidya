// Vidya — Embeddings and Vector Search — TypeScript port. Q15 fixed-point.

const SCALE = 15;
const ONE = 32768;
const DIM = 4;
const N_CORPUS = 4;

function qMul(a: number, b: number): number {
    const p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

const CORPUS: number[][] = [
    [32767, 0, 0, 0],
    [0, 32767, 0, 0],
    [16384, 16384, 16384, 16384],
    [-32767, 0, 0, 0],
];

function dot(a: number[], b: number[]): number {
    let acc = 0;
    for (let i = 0; i < a.length; i++) acc += qMul(a[i], b[i]);
    return acc;
}

function corpusSim(query: number[], idx: number): number {
    return dot(query, CORPUS[idx]);
}

function nearest(query: number[]): number {
    let bestIdx = 0;
    let bestSim = corpusSim(query, 0);
    for (let i = 1; i < N_CORPUS; i++) {
        const s = corpusSim(query, i);
        if (s > bestSim) { bestSim = s; bestIdx = i; }
    }
    return bestIdx;
}

function topKNeighbors(query: number[], k: number): number[] {
    const marks: boolean[] = new Array(N_CORPUS).fill(false);
    const out: number[] = [];
    while (out.length < k) {
        let bestIdx = -1;
        let bestSim = 0;
        let first = true;
        for (let j = 0; j < N_CORPUS; j++) {
            if (!marks[j]) {
                const s = corpusSim(query, j);
                if (first) { bestIdx = j; bestSim = s; first = false; }
                else if (s > bestSim) { bestIdx = j; bestSim = s; }
            }
        }
        if (bestIdx < 0) return out;
        marks[bestIdx] = true;
        out.push(bestIdx);
    }
    return out;
}

let passCount = 0, failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

function arrEq(a: number[], b: number[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
}

for (let i = 0; i < N_CORPUS; i++) {
    const s = corpusSim(CORPUS[i], i);
    check(s >= 32760, `v${i} self-sim ≈ ONE`);
}

check(corpusSim(CORPUS[0], 1) === 0, "v0·v1 = 0");
{
    const s = corpusSim(CORPUS[0], 3);
    check(s >= -ONE && s <= -32760, "v0·v3 ≈ -ONE");
}
check(corpusSim(CORPUS[2], 2) === ONE, "v2 self-sim = ONE");
{
    const s = corpusSim(CORPUS[0], 2);
    check(s >= 16380 && s <= 16384, "v0·v2 ≈ 0.5");
}
check(dot(CORPUS[0], CORPUS[2]) === dot(CORPUS[2], CORPUS[0]), "dot symmetric");

check(nearest([29490, 0, 0, 0]) === 0, "near-x → v0");
check(nearest([0, 32767, 0, 0]) === 1, "y-axis → v1");
check(nearest([16384, 16384, 16384, 16384]) === 2, "diagonal → v2");
check(nearest([-29490, 0, 0, 0]) === 3, "negative-x → v3");

check(arrEq(topKNeighbors([32767, 0, 0, 0], 3), [0, 2, 1]), "top-3 ranked");
check(topKNeighbors([32767, 0, 0, 0], 10).length === 4, "top_k caps");

{
    const q = [29490, 0, 0, 0];
    check(nearest(q) === nearest(q), "deterministic");
}

console.log("=== embeddings ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
