#!/usr/bin/env python3
"""Vidya — 2D Collision Detection in Python

All coordinates in 16.16 fixed-point. Python ints are arbitrary
precision, so squared distances never overflow — we still keep the
>>4 pre-shift pattern from the Cyrius reference because the rest of
this corpus relies on it (matching results across languages with
fixed-width integers). Squared-distance comparisons avoid sqrt on
every collision test, which is the central performance trick.
"""

FX_SHIFT = 16
FX_ONE = 1 << FX_SHIFT


def fx(n: int) -> int:
    return n << FX_SHIFT


def dist_sq(x1: int, y1: int, x2: int, y2: int) -> int:
    """Squared distance with deltas pre-shifted by 4 (Cyrius convention)."""
    dx = (x2 - x1) >> 4
    dy = (y2 - y1) >> 4
    return dx * dx + dy * dy


def circle_circle(x1, y1, r1, x2, y2, r2) -> bool:
    d2 = dist_sq(x1, y1, x2, y2)
    sum_r = (r1 + r2) >> 4
    return d2 <= sum_r * sum_r


def aabb_overlap(l1, t1, r1, b1, l2, t2, r2, b2) -> bool:
    if l1 >= r2: return False
    if r1 <= l2: return False
    if t1 >= b2: return False
    if b1 <= t2: return False
    return True


def point_in_rect(px, py, left, top, right, bottom) -> bool:
    return left <= px < right and top <= py < bottom


def circle_aabb(cx, cy, cr, left, top, right, bottom) -> bool:
    closest_x = min(max(cx, left), right)
    closest_y = min(max(cy, top), bottom)
    d2 = dist_sq(cx, cy, closest_x, closest_y)
    r = cr >> 4
    return d2 <= r * r


def point_in_circle(px, py, cx, cy, cr) -> bool:
    d2 = dist_sq(px, py, cx, cy)
    r = cr >> 4
    return d2 <= r * r


def push_apart_x(x1, y1, x2, y2, overlap) -> int:
    dx = x2 - x1
    half = overlap >> 1
    return -half if dx > 0 else half


def swept_aabb_x(al, ar, vx, bl, br) -> int:
    """1D swept AABB — returns time-of-impact in [0, FX_ONE]."""
    if vx == 0:
        return FX_ONE
    if vx > 0:
        enter_dist, exit_dist = bl - ar, br - al
    else:
        enter_dist, exit_dist = br - al, bl - ar
    abs_v = abs(vx)
    enter = (abs(enter_dist) << FX_SHIFT) // abs_v
    exit_ = (abs(exit_dist)  << FX_SHIFT) // abs_v
    if enter > exit_ or enter > FX_ONE:
        return FX_ONE
    return enter


# ── Tests ─────────────────────────────────────────────────────────────

def main() -> None:
    assert circle_circle(fx(10), fx(10), fx(5), fx(13), fx(10), fx(5)), \
        "overlapping circles collide"
    assert not circle_circle(fx(0), fx(0), fx(1), fx(100), fx(100), fx(1)), \
        "distant circles don't collide"
    assert circle_circle(fx(0), fx(0), fx(5), fx(10), fx(0), fx(5)), \
        "touching circles collide"

    assert aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                        fx(5), fx(5), fx(15), fx(15)), "overlapping AABBs"
    assert not aabb_overlap(fx(0), fx(0), fx(5), fx(5),
                            fx(10), fx(10), fx(20), fx(20)), "separated AABBs"
    assert not aabb_overlap(fx(0), fx(0), fx(10), fx(10),
                            fx(10), fx(0), fx(20), fx(10)), "edge-adjacent AABBs"

    assert point_in_rect(fx(5), fx(5), fx(0), fx(0), fx(10), fx(10)), \
        "point inside rect"
    assert not point_in_rect(fx(15), fx(5), fx(0), fx(0), fx(10), fx(10)), \
        "point outside rect"
    assert point_in_rect(fx(0), fx(5), fx(0), fx(0), fx(10), fx(10)), \
        "left edge is inside"
    assert not point_in_rect(fx(10), fx(5), fx(0), fx(0), fx(10), fx(10)), \
        "right edge is outside"

    assert circle_aabb(fx(5), fx(5), fx(3), fx(0), fx(0), fx(10), fx(10)), \
        "circle inside AABB"
    assert not circle_aabb(fx(20), fx(20), fx(3), fx(0), fx(0), fx(10), fx(10)), \
        "circle far from AABB"

    assert point_in_circle(fx(1), fx(1), fx(0), fx(0), fx(5)), \
        "point inside circle"
    assert not point_in_circle(fx(100), fx(100), fx(0), fx(0), fx(5)), \
        "point outside circle"

    assert dist_sq(fx(0), fx(0), fx(3), fx(4)) > 0, "3-4-5 triangle dist²"

    assert push_apart_x(fx(0), fx(0), fx(4), fx(0), fx(2)) < 0, \
        "entity 1 pushed left when entity 2 is right"

    toi = swept_aabb_x(fx(0), fx(2), fx(8), fx(6), fx(10))
    assert 0 < toi < FX_ONE, "swept AABB returns mid-frame TOI"
    toi2 = swept_aabb_x(fx(0), fx(2), -fx(1), fx(6), fx(10))
    assert toi2 == FX_ONE, "moving away yields no in-frame impact"

    print("All collision_detection_2d examples passed.")


if __name__ == "__main__":
    main()
