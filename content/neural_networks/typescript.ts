// Vidya — Neural Network Forward Pass — TypeScript port. Q15 fixed-point.

const SCALE = 15;
const ONE = 32768;
const N_IN = 2;
const N_HIDDEN = 3;
const N_OUT = 2;

function qMul(a: number, b: number): number {
    const p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

const W_HIDDEN = [16384, -16384, -16384, 16384, 16384, 16384];
const B_HIDDEN = [0, 0, 0];
const W_OUTPUT = [16384, 0, 0, 0, 16384, 0];
const B_OUTPUT = [0, 0];

function dense(W: number[], b: number[], x: number[], nIn: number, nOut: number): number[] {
    const out: number[] = new Array(nOut);
    for (let j = 0; j < nOut; j++) {
        let acc = b[j];
        for (let i = 0; i < nIn; i++) {
            acc += qMul(W[j * nIn + i], x[i]);
        }
        out[j] = acc;
    }
    return out;
}

function relu(x: number[]): number[] {
    return x.map(v => Math.max(0, v));
}

function argmax(x: number[]): number {
    let bestIdx = 0;
    let bestVal = x[0];
    for (let i = 1; i < x.length; i++) {
        if (x[i] > bestVal) {
            bestVal = x[i];
            bestIdx = i;
        }
    }
    return bestIdx;
}

let lastHidden: number[] = [];
let lastOutput: number[] = [];

function forward(input: number[]): number {
    const hidden = relu(dense(W_HIDDEN, B_HIDDEN, input, N_IN, N_HIDDEN));
    lastHidden = hidden;
    const output = dense(W_OUTPUT, B_OUTPUT, hidden, N_HIDDEN, N_OUT);
    lastOutput = output;
    return argmax(output);
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

check(qMul(ONE, 100) === 100, "ONE * 100 = 100");
check(qMul(16384, 16384) === 8192, "0.5 * 0.5 = 0.25");
check(qMul(-16384, 16384) === -8192, "-0.5 * 0.5 = -0.25");

{
    const W = [16384, 16384, 8192, 24576];
    const b = [0, 0];
    const x = [32767, 32767];
    const y = dense(W, b, x, 2, 2);
    check(y[0] >= 32765 && y[0] <= 32769, "dense y[0] ~= 1.0");
    check(y[1] >= 32765 && y[1] <= 32769, "dense y[1] ~= 1.0");
}
{
    const y = dense([0, 0], [12345], [32767, 32767], 2, 1);
    check(y[0] === 12345, "bias passes through");
}
check(arrEq(relu([-100, 200, -300, 400]), [0, 200, 0, 400]), "relu clips");
check(relu([0])[0] === 0, "relu(0) = 0");
check(argmax([100, 500, 200, 300]) === 1, "argmax picks 1");
check(argmax([100, 500, 500]) === 1, "first-found wins");

check(forward([26214, 6553]) === 0, "x=[0.8,0.2] → class 0");
check(forward([6553, 26214]) === 1, "x=[0.2,0.8] → class 1");
check(forward([32767, 0]) === 0, "x=[1.0,0.0] → class 0");
check(forward([0, 32767]) === 1, "x=[0.0,1.0] → class 1");
{
    forward([32767, 0]);
    check(lastHidden[1] === 0, "relu zeroed hidden[1]");
    check(lastHidden[0] > 0, "hidden[0] passed through");
}

console.log("=== neural_networks ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
