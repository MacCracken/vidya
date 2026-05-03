// Vidya — LLM Inference (Decoding) — TypeScript port.

const VOCAB_SIZE = 8;
const TOK_EOS = 1;

function initBigram(): number[][] {
    const b: number[][] = Array.from({ length: VOCAB_SIZE }, () => new Array(VOCAB_SIZE).fill(0));
    b[2][3] = 1000;
    b[2][4] = 100;
    b[3][6] = 800;
    b[3][5] = 200;
    b[4][5] = 700;
    b[5][1] = 600;
    b[6][7] = 900;
    b[6][3] = 100;
    b[7][1] = 950;
    return b;
}

const BIGRAM = initBigram();

function argmaxLogits(logits: number[]): number {
    let bestIdx = 0;
    let bestVal = logits[0];
    for (let i = 1; i < logits.length; i++) {
        if (logits[i] > bestVal) {
            bestVal = logits[i];
            bestIdx = i;
        }
    }
    return bestIdx;
}

function topkFilter(logits: number[], k: number): number {
    const marks: boolean[] = new Array(logits.length).fill(false);
    let picked = 0;
    while (picked < k) {
        let bestIdx = -1;
        let bestVal = 0;
        let first = true;
        for (let j = 0; j < logits.length; j++) {
            if (!marks[j]) {
                if (first) { bestIdx = j; bestVal = logits[j]; first = false; }
                else if (logits[j] > bestVal) { bestIdx = j; bestVal = logits[j]; }
            }
        }
        if (bestIdx < 0) return picked;
        marks[bestIdx] = true;
        picked++;
    }
    for (let m = 0; m < logits.length; m++) {
        if (!marks[m]) logits[m] = 0;
    }
    return picked;
}

function bigramLogits(prev: number): number[] {
    return BIGRAM[prev].slice();
}

function decodeSequence(start: number, maxLen: number): number[] {
    const output: number[] = [];
    let current = start;
    while (output.length < maxLen) {
        const next = argmaxLogits(bigramLogits(current));
        output.push(next);
        if (next === TOK_EOS) return output;
        current = next;
    }
    return output;
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

check(argmaxLogits([100, 500, 200, 300]) === 1, "argmax picks 1");
check(argmaxLogits([100, 500, 500]) === 1, "first-found wins");
check(argmaxLogits([-100, -50, -200]) === 1, "argmax over negatives");

{
    const l = [10, 50, 30, 20, 40, 5, 60, 25];
    check(topkFilter(l, 3) === 3, "topk picked 3");
    check(l[6] === 60 && l[1] === 50 && l[4] === 40, "top 3 kept");
    for (const i of [0, 2, 3, 5, 7]) {
        check(l[i] === 0, `idx ${i} zeroed`);
    }
}
{
    const l = [1, 2, 3];
    check(topkFilter(l, 3) === 3, "topk(3,3) keeps all");
    check(arrEq(l, [1, 2, 3]), "all preserved");
}

check(argmaxLogits(bigramLogits(2)) === 3, "after hello → world");

check(arrEq(decodeSequence(2, 10), [3, 6, 7, 1]), "hello → world,the,end,EOS");
check(arrEq(decodeSequence(5, 10), [1]), "bar → EOS");
check(arrEq(decodeSequence(2, 2), [3, 6]), "capped at 2");
{
    const o1 = decodeSequence(2, 10);
    const o2 = decodeSequence(2, 10);
    check(arrEq(o1, o2), "deterministic");
}

console.log("=== inference ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
