// Vidya — Projectile Physics in TypeScript
//
// Semi-implicit Euler integration in 16.16 fixed-point on bigint.
// JavaScript `number` is a double — silently imprecise above 2^53 —
// and `>>` on `number` works on 32-bit projections, which would
// truncate the upper half of any 16.16 intermediate. bigint gives
// arbitrary-precision arithmetic with arithmetic (sign-preserving)
// `>>` for negatives, at the cost of `n` literal suffixes everywhere.

const FX_SHIFT: bigint = 16n;
const GRAVITY: bigint = 6554n;          // 0.1 per frame
const FLOOR_Y: bigint = 14745600n;      // 225.0
const RESTITUTION: bigint = 45875n;     // 0.7 in 16.16

interface Ball {
    x: bigint;
    y: bigint;
    vx: bigint;
    vy: bigint;
}

function physicsStep(b: Ball): void {
    // Semi-implicit Euler: velocity first, then position.
    b.vy += GRAVITY;
    b.y  += b.vy;
    b.x  += b.vx;
}

function bounceCheck(b: Ball): void {
    if (b.y > FLOOR_Y) {
        b.y = FLOOR_Y;
        // vy = -(vy * restitution) >> 16
        b.vy = -((b.vy * RESTITUTION) >> FX_SHIFT);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

function mustEq(got: bigint, want: bigint, msg: string): void {
    if (got !== want) {
        throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
    }
}

function mustTrue(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

function testGravity(): void {
    const b: Ball = { x: 0n, y: 0n, vx: 0n, vy: 0n };
    physicsStep(b);
    mustEq(b.vy, GRAVITY, "vy == gravity after 1 step");
    mustEq(b.y,  GRAVITY, "y == gravity after 1 step (semi-implicit)");
}

function testParabolicArc(): void {
    const b: Ball = { x: 0n, y: 6553600n, vx: 0n, vy: -1310720n }; // y=100.0, vy=-20.0
    const initialY = b.y;

    for (let i = 0; i < 50; i++) physicsStep(b);
    mustTrue(b.y < initialY, "ball rises in first 50 frames");

    for (let i = 0; i < 400; i++) physicsStep(b);
    mustTrue(b.y > initialY, "ball falls below start after 450 frames");
}

function testBounce(): void {
    const b: Ball = { x: 0n, y: FLOOR_Y + 1n, vx: 0n, vy: 655360n }; // vy=10.0 down
    bounceCheck(b);
    mustTrue(b.vy < 0n, "vy is negative after bounce");
    mustTrue(-b.vy < 655360n, "bounce reduces velocity magnitude");
    mustEq(b.y, FLOOR_Y, "position reset to floor on bounce");
}

function testHorizontalUnchanged(): void {
    const vxInitial = 131072n; // 2.0
    const b: Ball = { x: 0n, y: 0n, vx: vxInitial, vy: 0n };
    physicsStep(b);
    physicsStep(b);
    physicsStep(b);
    mustEq(b.vx, vxInitial, "vx unchanged after 3 frames of gravity");
    mustEq(b.x,  3n * vxInitial, "x = 3 * vx after 3 frames");
}

function testEnergyDecay(): void {
    const b: Ball = { x: 0n, y: 0n, vx: 0n, vy: 655360n }; // vy=10.0 down

    // 1000 frames — |vy| plateaus around 2700, well under 2*GRAVITY=13108.
    for (let i = 0; i < 1000; i++) {
        physicsStep(b);
        bounceCheck(b);
    }

    const absVy = b.vy < 0n ? -b.vy : b.vy;
    mustTrue(absVy < GRAVITY * 2n, "vy near zero after 1000 bouncing frames");
}

function testSemiImplicitStability(): void {
    const startY = FLOOR_Y - 655360n;                               // 10.0 above floor
    const b: Ball = { x: 0n, y: startY, vx: 0n, vy: -655360n };     // vy=-10.0 upward
    let minY = startY;

    for (let i = 0; i < 500; i++) {
        physicsStep(b);
        bounceCheck(b);
        if (b.y < minY) minY = b.y;
    }

    const maxRise = 1000n * 65536n;
    mustTrue(minY > startY - maxRise, "semi-implicit euler does not explode");
}

function main(): void {
    testGravity();
    testParabolicArc();
    testBounce();
    testHorizontalUnchanged();
    testEnergyDecay();
    testSemiImplicitStability();
    console.log("All projectile_physics examples passed.");
}

main();
