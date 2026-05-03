// Vidya — Audio DSP — TypeScript port. Q15 fixed-point.

const SCALE = 15;
const ONE = 32768;
const SMAX = 32767;
const SMIN = -32767;

function qMul(a: number, b: number): number {
    const p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

function clip(s: number): number {
    if (s > SMAX) return SMAX;
    if (s < SMIN) return SMIN;
    return s;
}

class Biquad {
    b0 = 0; b1 = 0; b2 = 0; a1 = 0; a2 = 0;
    x1 = 0; x2 = 0; y1 = 0; y2 = 0;

    set(b0: number, b1: number, b2: number, a1: number, a2: number): void {
        this.b0 = b0; this.b1 = b1; this.b2 = b2; this.a1 = a1; this.a2 = a2;
        this.x1 = 0; this.x2 = 0; this.y1 = 0; this.y2 = 0;
    }
    lowpass1Pole(aQ15: number): void { this.set(aQ15, 0, 0, aQ15 - ONE, 0); }

    step(x: number): number {
        const y = qMul(this.b0, x) + qMul(this.b1, this.x1) + qMul(this.b2, this.x2)
                - qMul(this.a1, this.y1) - qMul(this.a2, this.y2);
        this.x2 = this.x1; this.x1 = x;
        this.y2 = this.y1; this.y1 = y;
        return y;
    }
}

function firStep(taps: number[], history: number[], xNew: number): number {
    for (let i = history.length - 1; i > 0; i--) history[i] = history[i - 1];
    history[0] = xNew;
    let acc = 0;
    for (let j = 0; j < taps.length; j++) acc += qMul(taps[j], history[j]);
    return acc;
}

function peak(buf: number[]): number {
    let p = 0;
    for (const s of buf) {
        const a = Math.abs(s);
        if (a > p) p = a;
    }
    return p;
}

function meanAbsolute(buf: number[]): number {
    let sum = 0;
    for (const s of buf) sum += Math.abs(s);
    return Math.floor(sum / buf.length);
}

let passCount = 0, failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

check(qMul(ONE, 100) === 100, "ONE * 100 = 100");
check(qMul(ONE / 2, ONE / 2) === ONE / 4, "0.5 * 0.5 = 0.25");
const r = qMul(ONE / 2, SMAX);
check(r >= 16383 && r <= 16384, "0.5 * SMAX in [16383,16384]");

check(clip(50000) === SMAX, "clip(50000) = SMAX");
check(clip(-50000) === SMIN, "clip(-50000) = SMIN");
check(clip(1234) === 1234, "clip(1234) unchanged");

{
    const b = new Biquad();
    b.lowpass1Pole(3277);
    for (let i = 0; i < 200; i++) b.step(30000);
    check(b.y1 >= 29900 && b.y1 <= 30100, "DC settled near 30000");
}
{
    const b = new Biquad();
    b.lowpass1Pole(3277);
    for (let i = 0; i < 200; i++) {
        b.step((i & 1) === 0 ? 20000 : -20000);
    }
    check(Math.abs(b.y1) < 2000, "Nyquist heavily attenuated");
}
{
    const taps = [ONE, 0, 0];
    const history = [0, 0, 0];
    check(firStep(taps, history, 1234) === 1234, "identity passes 1234");
    check(firStep(taps, history, 5678) === 5678, "identity passes 5678");
}
{
    const third = Math.floor(ONE / 3);
    const taps = [third, third, third];
    const history = [0, 0, 0];
    firStep(taps, history, 9000);
    firStep(taps, history, 9000);
    const y = firStep(taps, history, 9000);
    check(y >= 8990 && y <= 9010, "moving avg converges to 9000");
}
check(peak([100, -5000, 200, 3000, -1500]) === 5000, "peak = 5000");
{
    const buf = new Array(8).fill(4000);
    check(meanAbsolute(buf) === 4000, "mean-abs constant = constant");
}
{
    const buf: number[] = [];
    for (let i = 0; i < 8; i++) buf.push((i & 1) === 0 ? 4000 : -4000);
    check(meanAbsolute(buf) === 4000, "mean-abs alternating = 4000");
}

console.log("=== audio_dsp ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
