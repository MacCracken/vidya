// Vidya — 2D Collision Detection in TypeScript
//
// All coordinates in 16.16 fixed-point on bigint. JavaScript's
// `number` is a double — past 2^53 the squared-distance product
// silently loses bits, so we use bigint for true 64-bit (and beyond)
// arithmetic. `>>` on bigint is arithmetic and safe for negatives.
// Squared-distance comparisons avoid sqrt; we keep the >>4 pre-shift
// pattern from the Cyrius reference for parity with the fixed-width
// integer ports.

const FX_SHIFT = 16n;
const FX_ONE: bigint = 1n << FX_SHIFT;

function fx(n: bigint): bigint { return n << FX_SHIFT; }

function distSq(x1: bigint, y1: bigint, x2: bigint, y2: bigint): bigint {
    const dx = (x2 - x1) >> 4n;
    const dy = (y2 - y1) >> 4n;
    return dx * dx + dy * dy;
}

function circleCircle(x1: bigint, y1: bigint, r1: bigint,
                      x2: bigint, y2: bigint, r2: bigint): boolean {
    const d2 = distSq(x1, y1, x2, y2);
    const sumR = (r1 + r2) >> 4n;
    return d2 <= sumR * sumR;
}

function aabbOverlap(l1: bigint, t1: bigint, r1: bigint, b1: bigint,
                     l2: bigint, t2: bigint, r2: bigint, b2: bigint): boolean {
    if (l1 >= r2) return false;
    if (r1 <= l2) return false;
    if (t1 >= b2) return false;
    if (b1 <= t2) return false;
    return true;
}

function pointInRect(px: bigint, py: bigint,
                     left: bigint, top: bigint,
                     right: bigint, bottom: bigint): boolean {
    return px >= left && px < right && py >= top && py < bottom;
}

function clampB(v: bigint, lo: bigint, hi: bigint): bigint {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

function circleAabb(cx: bigint, cy: bigint, cr: bigint,
                    left: bigint, top: bigint,
                    right: bigint, bottom: bigint): boolean {
    const closestX = clampB(cx, left, right);
    const closestY = clampB(cy, top, bottom);
    const d2 = distSq(cx, cy, closestX, closestY);
    const r = cr >> 4n;
    return d2 <= r * r;
}

function pointInCircle(px: bigint, py: bigint,
                       cx: bigint, cy: bigint, cr: bigint): boolean {
    const d2 = distSq(px, py, cx, cy);
    const r = cr >> 4n;
    return d2 <= r * r;
}

function pushApartX(x1: bigint, x2: bigint, overlap: bigint): bigint {
    const dx = x2 - x1;
    const half = overlap >> 1n;
    return dx > 0n ? -half : half;
}

function absB(v: bigint): bigint { return v < 0n ? -v : v; }

function sweptAabbX(al: bigint, ar: bigint, vx: bigint,
                    bl: bigint, br: bigint): bigint {
    if (vx === 0n) return FX_ONE;
    let enterDist: bigint, exitDist: bigint;
    if (vx > 0n) { enterDist = bl - ar; exitDist = br - al; }
    else         { enterDist = br - al; exitDist = bl - ar; }
    const absV = absB(vx);
    const enter = (absB(enterDist) << FX_SHIFT) / absV;
    const exit_ = (absB(exitDist)  << FX_SHIFT) / absV;
    if (enter > exit_ || enter > FX_ONE) return FX_ONE;
    return enter;
}

// ── Tests ─────────────────────────────────────────────────────────────

function mustTrue(b: boolean, msg: string): void {
    if (!b) throw new Error(`FAIL: ${msg}`);
}
function mustFalse(b: boolean, msg: string): void {
    if (b) throw new Error(`FAIL: ${msg}`);
}

function main(): void {
    mustTrue(circleCircle(fx(10n), fx(10n), fx(5n), fx(13n), fx(10n), fx(5n)),
        "overlapping circles");
    mustFalse(circleCircle(fx(0n), fx(0n), fx(1n), fx(100n), fx(100n), fx(1n)),
        "distant circles");
    mustTrue(circleCircle(fx(0n), fx(0n), fx(5n), fx(10n), fx(0n), fx(5n)),
        "touching circles");

    mustTrue(aabbOverlap(fx(0n), fx(0n), fx(10n), fx(10n),
                         fx(5n), fx(5n), fx(15n), fx(15n)), "overlapping AABBs");
    mustFalse(aabbOverlap(fx(0n), fx(0n), fx(5n), fx(5n),
                          fx(10n), fx(10n), fx(20n), fx(20n)), "separated AABBs");
    mustFalse(aabbOverlap(fx(0n), fx(0n), fx(10n), fx(10n),
                          fx(10n), fx(0n), fx(20n), fx(10n)), "edge-adjacent AABBs");

    mustTrue(pointInRect(fx(5n), fx(5n), fx(0n), fx(0n), fx(10n), fx(10n)), "inside");
    mustFalse(pointInRect(fx(15n), fx(5n), fx(0n), fx(0n), fx(10n), fx(10n)), "outside");
    mustTrue(pointInRect(fx(0n), fx(5n), fx(0n), fx(0n), fx(10n), fx(10n)), "left edge");
    mustFalse(pointInRect(fx(10n), fx(5n), fx(0n), fx(0n), fx(10n), fx(10n)), "right edge");

    mustTrue(circleAabb(fx(5n), fx(5n), fx(3n), fx(0n), fx(0n), fx(10n), fx(10n)),
        "circle inside AABB");
    mustFalse(circleAabb(fx(20n), fx(20n), fx(3n), fx(0n), fx(0n), fx(10n), fx(10n)),
        "circle far from AABB");

    mustTrue(pointInCircle(fx(1n), fx(1n), fx(0n), fx(0n), fx(5n)),
        "point inside circle");
    mustFalse(pointInCircle(fx(100n), fx(100n), fx(0n), fx(0n), fx(5n)),
        "point outside circle");

    if (distSq(fx(0n), fx(0n), fx(3n), fx(4n)) <= 0n)
        throw new Error("FAIL: 3-4-5 dist²");

    if (pushApartX(fx(0n), fx(4n), fx(2n)) >= 0n)
        throw new Error("FAIL: push-apart direction");

    const toi = sweptAabbX(fx(0n), fx(2n), fx(8n), fx(6n), fx(10n));
    if (toi <= 0n || toi >= FX_ONE) throw new Error("FAIL: swept AABB TOI");
    const toi2 = sweptAabbX(fx(0n), fx(2n), -fx(1n), fx(6n), fx(10n));
    if (toi2 !== FX_ONE) throw new Error("FAIL: moving away yields no impact");

    console.log("All collision_detection_2d examples passed.");
}

main();
