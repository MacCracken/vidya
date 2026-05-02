#!/usr/bin/env python3
"""Vidya — Game Loop Architecture in Python

Fixed-timestep accumulator loop with spiral-of-death cap. The driver
`loop_step` takes an elapsed-microsecond delta and returns the number
of fixed-step updates fired this frame. Python's `int` is arbitrary
precision, so monotonic-time math never overflows — even a 100-year
uptime stays exact. Tests use deterministic per-frame deltas (no real
clock) so behavior is reproducible across machines and CI.
"""

from dataclasses import dataclass


DT_US = 16667         # ~1/60 second
MAX_ACCUM = 5 * DT_US  # 83335 — spiral-of-death cap


@dataclass
class GameLoop:
    accum: int = 0
    update_count: int = 0
    render_count: int = 0


def loop_step(g: GameLoop, elapsed_us: int) -> int:
    accum = g.accum + elapsed_us
    # Spiral-of-death cap: never let the accumulator exceed MAX_ACCUM.
    if accum > MAX_ACCUM:
        accum = MAX_ACCUM
    updates = 0
    while accum >= DT_US:
        accum -= DT_US
        updates += 1
    g.accum = accum
    g.update_count += updates
    g.render_count += 1
    return updates


def test_exact_dt_fires_one_update() -> None:
    g = GameLoop()
    u = loop_step(g, DT_US)
    assert u == 1, "exactly one update per dt"
    assert g.update_count == 1, "update_count = 1"


def test_under_dt_no_update() -> None:
    g = GameLoop()
    u = loop_step(g, DT_US // 2)
    assert u == 0, "no update when elapsed < dt"


def test_catchup_50ms() -> None:
    # 50000us / 16667us = 2.999 → 2 fixed-step updates
    g = GameLoop()
    u = loop_step(g, 50_000)
    assert u == 2, "50ms produces 2 fixed-step updates"


def test_spiral_of_death_cap() -> None:
    # 1000ms (one full second) hang — capped at MAX_ACCUM (5 * dt).
    g = GameLoop()
    u = loop_step(g, 1_000_000)
    assert u == 5, "spiral cap: exactly 5 updates per call"


def test_render_per_frame() -> None:
    g = GameLoop()
    loop_step(g, DT_US)
    loop_step(g, DT_US)
    loop_step(g, DT_US)
    assert g.render_count == 3, "3 renders for 3 frames"
    assert g.update_count == 3, "3 updates total"


def test_accumulator_remainder() -> None:
    # 1.5 * dt → 1 update with ~0.5 * dt left in accumulator
    g = GameLoop()
    one_and_half = DT_US + (DT_US // 2)
    loop_step(g, one_and_half)
    assert g.accum > DT_US // 4, "remainder is positive"
    assert g.accum < DT_US, "remainder < full dt"


def test_input_update_render_separation() -> None:
    g = GameLoop()
    loop_step(g, 30_000)
    loop_step(g, 5_000)
    loop_step(g, 30_000)
    assert g.update_count == 3, "3 updates from 65ms total"
    assert g.render_count == 3, "3 renders from 3 frames"


def main() -> None:
    test_exact_dt_fires_one_update()
    test_under_dt_no_update()
    test_catchup_50ms()
    test_spiral_of_death_cap()
    test_render_per_frame()
    test_accumulator_remainder()
    test_input_update_render_separation()
    print("All game_loop_architecture examples passed.")


if __name__ == "__main__":
    main()
