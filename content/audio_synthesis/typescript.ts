// Vidya — Audio Synthesis — TypeScript port. Q15 fixed-point.

const SCALE = 15;
const ONE = 32768;
const PHASE_MASK = 65535;
const PHASE_HALF = 32768;

function qMul(a: number, b: number): number {
    const p = a * b;
    return p < 0 ? -((-p) >> SCALE) : (p >> SCALE);
}

function phaseAdvance(current: number, inc: number): number {
    return (current + inc) & PHASE_MASK;
}

const SINE_TABLE: number[] = [
    0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
    0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
];

function oscSine(phase: number): number { return SINE_TABLE[phase >> 12]; }
function oscSaw(phase: number): number { return phase - PHASE_HALF; }
function oscSquare(phase: number): number { return phase < PHASE_HALF ? 32767 : -32767; }

const enum EnvState { Idle = 0, Attack = 1, Decay = 2, Sustain = 3, Release = 4 }

class Adsr {
    state: EnvState = EnvState.Idle;
    level = 0;
    stageSamples = 0;
    releaseStart = 0;
    attackSamples = 0;
    decaySamples = 0;
    sustainLevel = 0;
    releaseSamples = 0;

    setParams(attack: number, decay: number, sustain: number, release: number): void {
        this.attackSamples = attack;
        this.decaySamples = decay;
        this.sustainLevel = sustain;
        this.releaseSamples = release;
    }
    gateOn(): void {
        this.state = EnvState.Attack;
        this.stageSamples = 0;
    }
    gateOff(): boolean {
        if (this.state === EnvState.Idle) return false;
        this.releaseStart = this.level;
        this.state = EnvState.Release;
        this.stageSamples = 0;
        return true;
    }
    step(): number {
        if (this.state === EnvState.Idle) { this.level = 0; return 0; }
        if (this.state === EnvState.Attack) {
            this.level += Math.floor(ONE / this.attackSamples);
            this.stageSamples += 1;
            if (this.stageSamples >= this.attackSamples) {
                this.level = ONE;
                this.state = EnvState.Decay;
                this.stageSamples = 0;
            }
            return this.level;
        }
        if (this.state === EnvState.Decay) {
            const dec = Math.floor((ONE - this.sustainLevel) / this.decaySamples);
            this.level -= dec;
            this.stageSamples += 1;
            if (this.stageSamples >= this.decaySamples) {
                this.level = this.sustainLevel;
                this.state = EnvState.Sustain;
                this.stageSamples = 0;
            }
            return this.level;
        }
        if (this.state === EnvState.Sustain) { this.level = this.sustainLevel; return this.level; }
        if (this.state === EnvState.Release) {
            const dec = Math.floor(this.releaseStart / this.releaseSamples);
            this.level -= dec;
            this.stageSamples += 1;
            if (this.stageSamples >= this.releaseSamples) {
                this.level = 0;
                this.state = EnvState.Idle;
                this.stageSamples = 0;
            }
            return this.level;
        }
        return 0;
    }
}

const enum Wave { Sine = 0, Saw = 1, Square = 2 }

class Voice {
    waveform: Wave;
    phase = 0;
    phaseInc: number;
    constructor(waveform: Wave, phaseInc: number) {
        this.waveform = waveform;
        this.phaseInc = phaseInc;
    }
    oscillator(phase: number): number {
        if (this.waveform === Wave.Sine) return oscSine(phase);
        if (this.waveform === Wave.Saw) return oscSaw(phase);
        if (this.waveform === Wave.Square) return oscSquare(phase);
        return 0;
    }
    step(env: Adsr): number {
        const osc = this.oscillator(this.phase);
        this.phase = phaseAdvance(this.phase, this.phaseInc);
        const e = env.step();
        return qMul(osc, e);
    }
}

let passCount = 0, failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

check(phaseAdvance(60000, 10000) === 4464, "phase wraps");
check(phaseAdvance(0, 1000) === 1000, "phase advances");

check(oscSine(0) === 0, "sin(0)");
check(oscSine(16384) === 32767, "sin(π/2)");
check(oscSine(32768) === 0, "sin(π)");
check(oscSine(49152) === -32767, "sin(3π/2)");

check(oscSaw(0) === -PHASE_HALF, "saw(0)");
check(oscSaw(PHASE_HALF) === 0, "saw(π)");
check(oscSaw(65535) === 32767, "saw(near max)");

check(oscSquare(0) === 32767, "square first half");
check(oscSquare(PHASE_HALF) === -32767, "square second half");
check(oscSquare(32767) === 32767, "square just before half");
check(oscSquare(65535) === -32767, "square at end");

{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4); e.gateOn();
    for (let i = 0; i < 4; i++) e.step();
    check(e.state === EnvState.Decay, "attack → decay");
    check(e.level === ONE, "level = ONE");
}
{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4); e.gateOn();
    for (let i = 0; i < 8; i++) e.step();
    check(e.state === EnvState.Sustain, "decay → sustain");
    check(e.level === 16384, "level = sustain");
}
{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4); e.gateOn();
    for (let i = 0; i < 8; i++) e.step();
    for (let i = 0; i < 100; i++) e.step();
    check(e.state === EnvState.Sustain, "sustain holds");
    check(e.level === 16384, "level held");
}
{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4); e.gateOn();
    for (let i = 0; i < 8; i++) e.step();
    e.gateOff();
    check(e.releaseStart === 16384, "release_start captured");
    for (let i = 0; i < 4; i++) e.step();
    check(e.state === EnvState.Idle, "release → idle");
    check(e.level === 0, "level = 0");
}
{
    const e = new Adsr(); e.setParams(8, 4, 16384, 4); e.gateOn();
    e.step(); e.step();
    e.gateOff();
    check(e.releaseStart === 8192, "release captures partial-attack level");
}
{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4);
    const v = new Voice(Wave.Sine, 8192);
    check(v.step(e) === 0, "voice silent when idle");
}
{
    const e = new Adsr(); e.setParams(4, 4, 16384, 4);
    const v = new Voice(Wave.Sine, 8192);
    e.gateOn();
    let anyNonzero = false;
    for (let i = 0; i < 16; i++) if (v.step(e) !== 0) anyNonzero = true;
    check(anyNonzero, "voice audible when gated");
}

console.log("=== audio_synthesis ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
