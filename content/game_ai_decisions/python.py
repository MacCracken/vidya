#!/usr/bin/env python3
"""Vidya — Game AI Decision Making in Python

Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting, and
weighted action selection. Python's ints are arbitrary-precision, so to
match the C/Rust 64-bit PCG state we mask explicitly with `& MASK64`.
The dataclass + IntEnum pair gives readable scoring and a self-
documenting Action enum that round-trips through int.
"""

from dataclasses import dataclass
from enum import IntEnum


class Action(IntEnum):
    SHOOT = 0
    DUNK = 1
    PASS_ = 2
    DRIVE = 3
    STEAL = 4


@dataclass
class Stats:
    speed: int = 5
    shooting: int = 5
    dunking: int = 5
    passing: int = 5
    stealing: int = 5
    blocking: int = 5
    clutch: int = 5
    rebounding: int = 5


PCG_MULT = 6364136223846793005
PCG_INC = 1442695040888963407
MASK64 = (1 << 64) - 1


class Rng:
    def __init__(self, seed: int = 12345) -> None:
        self.state = seed & MASK64

    def seed(self, s: int) -> None:
        self.state = s & MASK64

    def next(self) -> int:
        # Mask to 64 bits to mimic uint64 wraparound (Python ints are unbounded).
        self.state = (self.state * PCG_MULT + PCG_INC) & MASK64
        return (self.state >> 33) & 0x7FFFFFFF

    def range(self, max_: int) -> int:
        if max_ <= 0:
            return 0
        return self.next() % max_


def prob_check(rng: Rng, stat: int) -> bool:
    threshold = stat * 10
    return rng.range(100) < threshold


def evaluate_shoot(shooting: int, distance_fx: int) -> int:
    base = shooting * 10
    dist_units = distance_fx >> 16
    return max(0, base - dist_units)


def evaluate_dunk(dunking: int, distance_fx: int) -> int:
    if (distance_fx >> 16) > 3:
        return 0
    return dunking * 15


def evaluate_pass(passing: int) -> int:
    return passing * 8


def evaluate_drive(speed: int) -> int:
    return speed * 6


def apply_urgency(score: int, shot_clock: int) -> int:
    urgency = (24 - shot_clock) // 4
    if urgency < 1:
        urgency = 1
    return score * urgency


def add_noise(rng: Rng, score: int) -> int:
    noise = rng.range(21) - 10
    return max(0, score + noise)


def ai_decide_offense(rng: Rng, s: Stats, distance_fx: int, shot_clock: int) -> Action:
    shoot_score = add_noise(rng, apply_urgency(evaluate_shoot(s.shooting, distance_fx), shot_clock))
    dunk_score = add_noise(rng, evaluate_dunk(s.dunking, distance_fx))
    pass_score = add_noise(rng, evaluate_pass(s.passing))
    drive_score = add_noise(rng, evaluate_drive(s.speed))

    best = Action.SHOOT
    best_score = shoot_score
    if dunk_score > best_score:
        best, best_score = Action.DUNK, dunk_score
    if pass_score > best_score:
        best, best_score = Action.PASS_, pass_score
    if drive_score > best_score:
        best, best_score = Action.DRIVE, drive_score
    return best


def main() -> None:
    # evaluate_shoot
    assert evaluate_shoot(9, 3 << 16) == 87, "shoot: 9*10 - 3"
    assert evaluate_shoot(1, 20 << 16) == 0, "low stat + far = 0"
    assert evaluate_shoot(10, 0) == 100, "stat 10 at rim"

    # evaluate_dunk
    assert evaluate_dunk(8, 2 << 16) == 120, "dunk: stat 8 * 15"
    assert evaluate_dunk(10, 10 << 16) == 0, "too far to dunk"

    # urgency
    assert apply_urgency(50, 24) == 50, "full clock no urgency"
    assert apply_urgency(50, 2) == 250, "low clock x5"
    assert apply_urgency(50, 0) == 300, "empty clock x6"

    # prob_check
    rng = Rng(42)
    for _ in range(20):
        assert prob_check(rng, 10), "stat 10 always passes"
    rng.seed(99)
    for _ in range(20):
        assert not prob_check(rng, 0), "stat 0 always fails"

    # PRNG determinism
    a = Rng(77777)
    a1, a2 = a.next(), a.next()
    b = Rng(77777)
    b1, b2 = b.next(), b.next()
    assert a1 == b1, "same seed: first value matches"
    assert a2 == b2, "same seed: second value matches"

    # PRNG variation
    r = Rng(42)
    assert r.next() != r.next(), "consecutive PRNG values differ"

    # Difficulty scaling
    assert evaluate_shoot(9, 5 << 16) > evaluate_shoot(3, 5 << 16), "hard shoots better"
    assert evaluate_dunk(9, 2 << 16) > evaluate_dunk(2, 2 << 16), "hard dunks better"

    # ai_decide_offense: high dunk stat at close range -> DUNK
    rng = Rng(100)
    stats = Stats(speed=5, shooting=5, dunking=10, passing=3, stealing=3,
                  blocking=3, clutch=3, rebounding=3)
    action = ai_decide_offense(rng, stats, 1 << 16, 20)
    assert action == Action.DUNK, f"high dunk at close range -> DUNK, got {action}"

    print("All game_ai_decisions examples passed.")


if __name__ == "__main__":
    main()
