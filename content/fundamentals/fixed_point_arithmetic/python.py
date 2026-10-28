#!/usr/bin/env python3
# Vidya — Fixed-Point Arithmetic in Python
#
# 16.16 fixed-point: integer carries fractional value in lower 16 bits.
# Python ints are arbitrary precision (no overflow), so the "safe mul"
# guard is illustrative rather than necessary. Right-shift on negative
# ints in Python is arithmetic and rounds toward -infinity, so the
# `asr` helper in Cyrius isn't needed here either, but `fx_to_int`
# must still handle truncation explicitly to match the Cyrius semantics.

import math

FX_SHIFT = 16
FX_ONE = 1 << FX_SHIFT
FX_HALF = 1 << (FX_SHIFT - 1)


def fx_from_int(n: int) -> int:
    return n << FX_SHIFT


def fx_to_int(v: int) -> int:
    """Truncate toward zero (matches C / Rust / Cyrius semantics)."""
    if v < 0:
        return -((-v) >> FX_SHIFT)
    return v >> FX_SHIFT


def fx_to_int_round(v: int) -> int:
    if v < 0:
        return -((-v + FX_HALF) >> FX_SHIFT)
    return (v + FX_HALF) >> FX_SHIFT


def fx_mul(a: int, b: int) -> int:
    return (a * b) >> FX_SHIFT


def fx_mul_safe(a: int, b: int) -> int:
    """Pre-shift both inputs to avoid overflow on fixed-width ints.
    On Python this is illustrative — ints don't overflow."""
    return (a >> 8) * (b >> 8)


def fx_div(a: int, b: int) -> int:
    if b == 0:
        return 0
    # Use C-style truncation toward zero, not Python's floor division.
    num = a << FX_SHIFT
    q = abs(num) // abs(b)
    return q if (num < 0) == (b < 0) else -q


# ── Sine table — quarter-wave, 257 entries (0 .. π/2 INCLUSIVE) ───────
# The mirror sin(π - x) = sin(x) needs index 512 - a, which reaches 256,
# so the table needs its π/2 endpoint. Mirroring with 511 - a instead (to
# fit a 256-entry table) puts quadrants 2 and 4 one step out of phase:
# max error 0.0061 there vs 0.000015 in quadrant 1.
def build_sin_table() -> list[int]:
    return [int(math.sin(i * math.pi / 2 / 256) * FX_ONE) for i in range(257)]


def sin_lookup(table: list[int], angle: int) -> int:
    a = angle & 1023
    if a < 256:
        return table[a]
    if a < 512:
        return table[512 - a]
    if a < 768:
        return -table[a - 512]
    return -table[1024 - a]


# ── Tests ─────────────────────────────────────────────────────────────

def main() -> None:
    assert fx_from_int(1) == 65536
    assert fx_from_int(10) == 655360
    assert fx_from_int(0) == 0

    three = fx_from_int(3)
    two_half = 163840  # 2.5 in 16.16
    assert fx_mul(three, two_half) == 491520, "3.0 * 2.5 == 7.5"
    assert fx_mul(FX_ONE, FX_ONE) == FX_ONE, "1.0 * 1.0 == 1.0"
    assert fx_mul(FX_HALF, FX_HALF) == 16384, "0.5 * 0.5 == 0.25"

    big = fx_from_int(1000)
    # "> 0" could never fail here (Python ints do not wrap); check the value.
    # Pre-shifting drops 8 fraction bits per operand, exact for integers.
    assert fx_mul_safe(big, big) == fx_from_int(1_000_000), "safe mul 1000*1000"

    assert fx_div(fx_from_int(10), fx_from_int(4)) == 163840, "10/4 == 2.5"
    assert fx_div(FX_ONE, 0) == 0, "div-by-zero returns 0"

    assert fx_to_int(-fx_from_int(3)) == -3, "fx_to_int(-3.0)"
    assert fx_to_int(-(FX_ONE + FX_HALF)) == -1, "fx_to_int(-1.5) truncates to -1"
    assert fx_to_int_round(-(FX_ONE + FX_HALF)) == -2, "round(-1.5) == -2"

    table = build_sin_table()
    assert sin_lookup(table, 0) == 0
    assert sin_lookup(table, 256) > 60000, "sin(π/2) near 1.0"
    assert sin_lookup(table, 512) == 0
    assert sin_lookup(table, 768) < -60000, "sin(3π/2) near -1.0"
    worst = max(abs(sin_lookup(table, a) / FX_ONE - math.sin(a * math.pi / 512))
                for a in range(1024))
    assert worst < 0.0001, f"every quadrant within table precision (worst {worst})"

    for i in range(100):
        assert fx_to_int(fx_from_int(i)) == i

    print("All fixed_point_arithmetic examples passed.")


if __name__ == "__main__":
    main()
