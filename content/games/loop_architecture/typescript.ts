// Vidya — Game Loop Architecture in TypeScript
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loopStep` takes an elapsed-microsecond delta and returns the number
// of fixed-step updates fired this frame. TypeScript's `number` is
// IEEE-754 double, which gives 53 bits of integer precision — enough
// for microseconds over a few hundred years. A real engine would prefer
// `bigint` for nanosecond timestamps from `process.hrtime.bigint()`,
// but for microsecond deltas the safe-integer range is plenty.

const DT_US = 16667;          // ~1/60 second
const MAX_ACCUM = 5 * DT_US;  // 83335 — spiral-of-death cap

interface GameLoop {
    accum: number;
    updateCount: number;
    renderCount: number;
}

function newLoop(): GameLoop {
    return { accum: 0, updateCount: 0, renderCount: 0 };
}

function loopStep(g: GameLoop, elapsedUs: number): number {
    let accum = g.accum + elapsedUs;
    // Spiral-of-death cap: never let the accumulator exceed MAX_ACCUM.
    if (accum > MAX_ACCUM) accum = MAX_ACCUM;
    let updates = 0;
    while (accum >= DT_US) {
        accum -= DT_US;
        updates++;
    }
    g.accum = accum;
    g.updateCount += updates;
    g.renderCount += 1;
    return updates;
}

function mustEq<T>(got: T, want: T, msg: string): void {
    if (got !== want) throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
}

function mustTrue(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

function testExactDtFiresOneUpdate(): void {
    const g = newLoop();
    const u = loopStep(g, DT_US);
    mustEq(u, 1, "exactly one update per dt");
    mustEq(g.updateCount, 1, "update_count = 1");
}

function testUnderDtNoUpdate(): void {
    const g = newLoop();
    const u = loopStep(g, Math.floor(DT_US / 2));
    mustEq(u, 0, "no update when elapsed < dt");
}

function testCatchup50ms(): void {
    const g = newLoop();
    const u = loopStep(g, 50000);
    mustEq(u, 2, "50ms produces 2 fixed-step updates");
}

function testSpiralOfDeathCap(): void {
    const g = newLoop();
    const u = loopStep(g, 1000000);
    mustEq(u, 5, "spiral cap: exactly 5 updates per call");
}

function testRenderPerFrame(): void {
    const g = newLoop();
    loopStep(g, DT_US);
    loopStep(g, DT_US);
    loopStep(g, DT_US);
    mustEq(g.renderCount, 3, "3 renders for 3 frames");
    mustEq(g.updateCount, 3, "3 updates total");
}

function testAccumulatorRemainder(): void {
    const g = newLoop();
    const oneAndHalf = DT_US + Math.floor(DT_US / 2);
    loopStep(g, oneAndHalf);
    mustTrue(g.accum > DT_US / 4, "remainder is positive");
    mustTrue(g.accum < DT_US, "remainder < full dt");
}

function testInputUpdateRenderSeparation(): void {
    const g = newLoop();
    loopStep(g, 30000);
    loopStep(g, 5000);
    loopStep(g, 30000);
    mustEq(g.updateCount, 3, "3 updates from 65ms total");
    mustEq(g.renderCount, 3, "3 renders from 3 frames");
}

function main(): void {
    testExactDtFiresOneUpdate();
    testUnderDtNoUpdate();
    testCatchup50ms();
    testSpiralOfDeathCap();
    testRenderPerFrame();
    testAccumulatorRemainder();
    testInputUpdateRenderSeparation();
    console.log("All game_loop_architecture examples passed.");
}

main();
