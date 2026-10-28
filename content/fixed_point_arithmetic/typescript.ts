// Vidya — Fixed-Point Arithmetic in TypeScript
//
// 16.16 fixed-point on bigint. JavaScript's `number` is a double,
// which silently loses precision past 2^53 — bigint gives true
// arbitrary-precision integer math at the cost of `n` literal
// suffixes everywhere.
//
// `>>` on bigint is arithmetic (sign-preserving) for negative
// values; `>>` on `number` works on 32-bit integer projections
// and would truncate the upper half of a 16.16 i64 silently.
// Never `>>` a `number` product in JS/TS: use bigint (exact at any
// size), or keep products under 2^53 and divide by 65536 instead.

const FX_SHIFT = 16n;
const FX_ONE: bigint = 1n << FX_SHIFT;
const FX_HALF: bigint = 1n << (FX_SHIFT - 1n);

function fxFromInt(n: bigint): bigint { return n << FX_SHIFT; }

function fxToInt(v: bigint): bigint {
    if (v < 0n) return -((-v) >> FX_SHIFT);
    return v >> FX_SHIFT;
}

function fxToIntRound(v: bigint): bigint {
    if (v < 0n) return -((-v + FX_HALF) >> FX_SHIFT);
    return (v + FX_HALF) >> FX_SHIFT;
}

function fxMul(a: bigint, b: bigint): bigint {
    return (a * b) >> FX_SHIFT;
}

// The fixed-width (i64) overflow workaround, kept to mirror the other ports.
// bigint never overflows, so here it buys nothing and only discards the low
// 8 bits of each operand.
function fxMulSafe(a: bigint, b: bigint): bigint {
    return (a >> 8n) * (b >> 8n);
}

function fxDiv(a: bigint, b: bigint): bigint {
    if (b === 0n) return 0n;
    return (a << FX_SHIFT) / b;
}

// ── Sine table — quarter-wave, 257 entries (0..π/2 inclusive) ─────────
// The 257th entry (sin π/2) is what lets quadrants 2 and 4 mirror with
// 512 - a and 1024 - a. With only 256 entries the tempting 511 - a /
// 1023 - a mirror is one step out of phase: sinLookup(511) gave 0, not
// sin(511·2π/1024) ≈ 0.0061, ~400x the quadrant-1 error.

function buildSinTable(): bigint[] {
    const t: bigint[] = new Array(257);
    for (let i = 0; i <= 256; i++) {
        const angle = i * (Math.PI / 2) / 256;
        t[i] = BigInt(Math.round(Math.sin(angle) * Number(FX_ONE)));
    }
    return t;
}

function sinLookup(table: bigint[], angle: bigint): bigint {
    const a = Number(angle & 1023n);
    if (a < 256) return table[a];
    if (a < 512) return table[512 - a];
    if (a < 768) return -table[a - 512];
    return -table[1024 - a];
}

// ── Tests ─────────────────────────────────────────────────────────────

function mustEq(got: bigint, want: bigint, msg: string): void {
    if (got !== want) {
        throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
    }
}

function main(): void {
    mustEq(fxFromInt(1n), 65536n, "1.0");
    mustEq(fxFromInt(10n), 655360n, "10.0");
    mustEq(fxFromInt(0n), 0n, "0.0");

    const three = fxFromInt(3n);
    const twoHalf = 163840n; // 2.5
    mustEq(fxMul(three, twoHalf), 491520n, "3.0 * 2.5");
    mustEq(fxMul(FX_ONE, FX_ONE), FX_ONE, "1.0 * 1.0");
    mustEq(fxMul(FX_HALF, FX_HALF), 16384n, "0.5 * 0.5");

    // On bigint the plain multiply is exact at any magnitude — no overflow to
    // guard against (and 1000.0 * 1000.0 = 2^52-ish raw fits even in i64).
    const big = fxFromInt(1000n);
    mustEq(fxMul(big, big), fxFromInt(1000000n), "1000.0 * 1000.0 exact");
    // The pre-shift is exact only when the dropped low bits are zero...
    mustEq(fxMulSafe(big, big), fxFromInt(1000000n), "pre-shift, low bits 0");
    // ...otherwise it costs precision: (1/3) * 3 is 65535 exact, 65280 pre-shifted.
    const oneThird = fxDiv(FX_ONE, three);
    mustEq(fxMul(oneThird, three), 65535n, "(1/3) * 3, full precision");
    mustEq(fxMulSafe(oneThird, three), 65280n, "(1/3) * 3, pre-shift loses 8 bits");

    mustEq(fxDiv(fxFromInt(10n), fxFromInt(4n)), 163840n, "10/4");
    mustEq(fxDiv(FX_ONE, 0n), 0n, "div-by-zero");

    mustEq(fxToInt(-fxFromInt(3n)), -3n, "fx_to_int(-3.0)");
    mustEq(fxToInt(-(FX_ONE + FX_HALF)), -1n, "fx_to_int(-1.5)");
    mustEq(fxToIntRound(-(FX_ONE + FX_HALF)), -2n, "round(-1.5)");

    const table = buildSinTable();
    mustEq(sinLookup(table, 0n), 0n, "sin(0)");
    if (sinLookup(table, 256n) <= 60000n) {
        throw new Error("sin(π/2) should be near 1.0");
    }
    mustEq(sinLookup(table, 512n), 0n, "sin(π)");
    if (sinLookup(table, 768n) >= -60000n) {
        throw new Error("sin(3π/2) should be near -1.0");
    }
    // Mirror symmetry: sin(π - x) = sin(x), sin(2π - x) = -sin(x)
    mustEq(sinLookup(table, 256n), FX_ONE, "sin(π/2) = 1.0 exactly");
    mustEq(sinLookup(table, 511n), sinLookup(table, 1n), "sin(511) = sin(1)");
    mustEq(sinLookup(table, 1023n), -sinLookup(table, 1n), "sin(1023) = -sin(1)");

    for (let i = 0n; i < 100n; i++) {
        mustEq(fxToInt(fxFromInt(i)), i, "roundtrip");
    }

    console.log("All fixed_point_arithmetic examples passed.");
}

main();
