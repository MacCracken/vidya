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
// Always use bigint for fixed-point in JS/TS.

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

function fxMulSafe(a: bigint, b: bigint): bigint {
    return (a >> 8n) * (b >> 8n);
}

function fxDiv(a: bigint, b: bigint): bigint {
    if (b === 0n) return 0n;
    return (a << FX_SHIFT) / b;
}

// ── Sine table — quarter-wave, 256 entries ────────────────────────────

function buildSinTable(): bigint[] {
    const t: bigint[] = new Array(256);
    for (let i = 0; i < 256; i++) {
        const angle = i * (Math.PI / 2) / 256;
        t[i] = BigInt(Math.round(Math.sin(angle) * Number(FX_ONE)));
    }
    return t;
}

function sinLookup(table: bigint[], angle: bigint): bigint {
    const a = Number(angle & 1023n);
    if (a < 256) return table[a];
    if (a < 512) return table[511 - a];
    if (a < 768) return -table[a - 512];
    return -table[1023 - a];
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

    const big = fxFromInt(1000n);
    if (fxMulSafe(big, big) <= 0n) {
        throw new Error("safe mul of 1000*1000 should stay positive");
    }

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

    for (let i = 0n; i < 100n; i++) {
        mustEq(fxToInt(fxFromInt(i)), i, "roundtrip");
    }

    console.log("All fixed_point_arithmetic examples passed.");
}

main();
