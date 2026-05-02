#!/usr/bin/env python3
"""Vidya — Projectile Physics in Python

Semi-implicit Euler integration in 16.16 fixed-point. Python ints are
arbitrary precision, so the bounce-restitution intermediate (vy *
RESTITUTION ≈ 3.6e10 worst case) can't overflow — no __int128 dance
required. Right-shift on negative ints is arithmetic (floors toward
-infinity), so we use the same explicit-sign asr() helper Cyrius does
to match truncate-toward-zero semantics across languages.
"""

FX_SHIFT = 16
GRAVITY = 6554           # 0.1 per frame
FLOOR_Y = 14745600       # 225.0
RESTITUTION = 45875      # 0.7 in 16.16


def asr(v: int, n: int) -> int:
    """Truncate-toward-zero arithmetic shift right (matches Cyrius)."""
    if v < 0:
        return -((-v) >> n)
    return v >> n


class Ball:
    __slots__ = ("x", "y", "vx", "vy")

    def __init__(self, x: int, y: int, vx: int, vy: int) -> None:
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy


def physics_step(b: Ball) -> None:
    """Semi-implicit Euler: velocity first, then position."""
    b.vy += GRAVITY
    b.y += b.vy
    b.x += b.vx


def bounce_check(b: Ball) -> None:
    if b.y > FLOOR_Y:
        b.y = FLOOR_Y
        b.vy = -asr(b.vy * RESTITUTION, FX_SHIFT)


# ── Tests ─────────────────────────────────────────────────────────────

def test_gravity() -> None:
    b = Ball(0, 0, 0, 0)
    physics_step(b)
    assert b.vy == GRAVITY, "vy == gravity after 1 step"
    assert b.y == GRAVITY, "y == gravity after 1 step (semi-implicit)"


def test_parabolic_arc() -> None:
    b = Ball(0, 6553600, 0, -1310720)  # y=100.0, vy=-20.0
    initial_y = b.y

    for _ in range(50):
        physics_step(b)
    assert b.y < initial_y, "ball rises in first 50 frames"

    for _ in range(400):
        physics_step(b)
    assert b.y > initial_y, "ball falls below start after 450 frames"


def test_bounce() -> None:
    b = Ball(0, FLOOR_Y + 1, 0, 655360)  # vy=10.0 down, just past floor
    bounce_check(b)
    assert b.vy < 0, "vy is negative after bounce"
    assert -b.vy < 655360, "bounce reduces velocity magnitude"
    assert b.y == FLOOR_Y, "position reset to floor on bounce"


def test_horizontal_unchanged() -> None:
    vx_initial = 131072  # 2.0
    b = Ball(0, 0, vx_initial, 0)
    physics_step(b)
    physics_step(b)
    physics_step(b)
    assert b.vx == vx_initial, "vx unchanged after 3 frames of gravity"
    assert b.x == 3 * vx_initial, "x = 3 * vx after 3 frames"


def test_energy_decay() -> None:
    b = Ball(0, 0, 0, 655360)  # vy=10.0 down

    # 1000 frames; |vy| plateaus around 2700 — well under 2 * GRAVITY = 13108.
    for _ in range(1000):
        physics_step(b)
        bounce_check(b)

    abs_vy = -b.vy if b.vy < 0 else b.vy
    assert abs_vy < GRAVITY * 2, "vy near zero after 1000 bouncing frames"


def test_semi_implicit_stability() -> None:
    start_y = FLOOR_Y - 655360  # 10.0 above floor
    b = Ball(0, start_y, 0, -655360)  # vy=-10.0 upward
    min_y = start_y

    for _ in range(500):
        physics_step(b)
        bounce_check(b)
        if b.y < min_y:
            min_y = b.y

    max_rise = 1000 * 65536
    assert min_y > start_y - max_rise, "semi-implicit euler does not explode"


def main() -> None:
    test_gravity()
    test_parabolic_arc()
    test_bounce()
    test_horizontal_unchanged()
    test_energy_decay()
    test_semi_implicit_stability()
    print("All projectile_physics examples passed.")


if __name__ == "__main__":
    main()
