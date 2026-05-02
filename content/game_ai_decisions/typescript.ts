// Vidya — Game AI Decision Making in TypeScript
//
// Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting, and
// weighted action selection. JS `number` is float64 — too narrow to hold
// the full 64-bit PCG state without precision loss past 2^53. We use
// `BigInt` for the state update, then narrow back to `number` (i32) for
// the bit-mixed return value, which is safely under 2^31. const enums
// give zero-cost Action variants that match the Cyrius integer encoding.

const enum Action {
    SHOOT = 0,
    DUNK = 1,
    PASS = 2,
    DRIVE = 3,
    STEAL = 4,
}

interface Stats {
    speed: number;
    shooting: number;
    dunking: number;
    passing: number;
    stealing: number;
    blocking: number;
    clutch: number;
    rebounding: number;
}

const PCG_MULT = 6364136223846793005n;
const PCG_INC = 1442695040888963407n;
const MASK64 = (1n << 64n) - 1n;

let rngState = 12345n;

function rngSeed(s: bigint | number): void {
    rngState = (typeof s === "number" ? BigInt(s) : s) & MASK64;
}

function rngNext(): number {
    rngState = (rngState * PCG_MULT + PCG_INC) & MASK64;
    return Number((rngState >> 33n) & 0x7fffffffn);
}

function rngRange(max: number): number {
    if (max <= 0) return 0;
    return rngNext() % max;
}

function probCheck(stat: number): boolean {
    return rngRange(100) < stat * 10;
}

function evaluateShoot(shooting: number, distFx: number): number {
    const base = shooting * 10;
    const distUnits = distFx >> 16;
    const score = base - distUnits;
    return score < 0 ? 0 : score;
}

function evaluateDunk(dunking: number, distFx: number): number {
    if ((distFx >> 16) > 3) return 0;
    return dunking * 15;
}

function evaluatePass(passing: number): number { return passing * 8; }
function evaluateDrive(speed: number): number { return speed * 6; }

function applyUrgency(score: number, shotClock: number): number {
    let urgency = Math.trunc((24 - shotClock) / 4);
    if (urgency < 1) urgency = 1;
    return score * urgency;
}

function addNoise(score: number): number {
    const noise = rngRange(21) - 10;
    const r = score + noise;
    return r < 0 ? 0 : r;
}

function aiDecideOffense(s: Stats, distFx: number, shotClock: number): Action {
    const shoot = addNoise(applyUrgency(evaluateShoot(s.shooting, distFx), shotClock));
    const dunk = addNoise(evaluateDunk(s.dunking, distFx));
    const pass = addNoise(evaluatePass(s.passing));
    const drive = addNoise(evaluateDrive(s.speed));

    let best: Action = Action.SHOOT;
    let bestScore = shoot;
    if (dunk > bestScore) { best = Action.DUNK; bestScore = dunk; }
    if (pass > bestScore) { best = Action.PASS; bestScore = pass; }
    if (drive > bestScore) { best = Action.DRIVE; bestScore = drive; }
    return best;
}

function mustEq<T>(got: T, want: T, msg: string): void {
    if (got !== want) throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
}

function mustTrue(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

function main(): void {
    // evaluate_shoot
    mustEq(evaluateShoot(9, 3 << 16), 87, "shoot: 9*10 - 3");
    mustEq(evaluateShoot(1, 20 << 16), 0, "low stat + far = 0");
    mustEq(evaluateShoot(10, 0), 100, "stat 10 at rim");

    // evaluate_dunk
    mustEq(evaluateDunk(8, 2 << 16), 120, "dunk: stat 8 * 15");
    mustEq(evaluateDunk(10, 10 << 16), 0, "too far to dunk");

    // urgency
    mustEq(applyUrgency(50, 24), 50, "full clock");
    mustEq(applyUrgency(50, 2), 250, "low clock x5");
    mustEq(applyUrgency(50, 0), 300, "empty clock x6");

    // prob_check
    rngSeed(42);
    for (let i = 0; i < 20; i++) mustTrue(probCheck(10), "stat 10 always passes");
    rngSeed(99);
    for (let i = 0; i < 20; i++) mustTrue(!probCheck(0), "stat 0 always fails");

    // PRNG determinism
    rngSeed(77777);
    const a1 = rngNext();
    const a2 = rngNext();
    rngSeed(77777);
    const b1 = rngNext();
    const b2 = rngNext();
    mustEq(a1, b1, "same seed first");
    mustEq(a2, b2, "same seed second");

    // PRNG variation
    rngSeed(42);
    const v1 = rngNext();
    const v2 = rngNext();
    mustTrue(v1 !== v2, "consecutive PRNG values differ");

    // Difficulty scaling
    mustTrue(evaluateShoot(9, 5 << 16) > evaluateShoot(3, 5 << 16), "hard shoots better");
    mustTrue(evaluateDunk(9, 2 << 16) > evaluateDunk(2, 2 << 16), "hard dunks better");

    // ai_decide_offense: high dunk stat at close range -> DUNK
    rngSeed(100);
    const stats: Stats = {
        speed: 5, shooting: 5, dunking: 10, passing: 3,
        stealing: 3, blocking: 3, clutch: 3, rebounding: 3,
    };
    const act = aiDecideOffense(stats, 1 << 16, 20);
    mustEq(act, Action.DUNK, "high dunk at close range -> DUNK");

    console.log("All game_ai_decisions examples passed.");
}

main();
