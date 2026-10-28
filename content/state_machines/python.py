#!/usr/bin/env python3
"""Vidya — State Machines in Python

Finite state machines with enum dispatch, committed states, timers, and
transition validation. Python's `enum.IntEnum` gives readable names with
integer round-trip for parity with the other-language ports. Dataclasses
keep the Player struct compact and mutable.
"""

from dataclasses import dataclass
from enum import IntEnum


class PlayerState(IntEnum):
    IDLE = 0; RUN = 1; SHOOT = 2; DUNK = 3; PASS_ = 4
    STEAL = 5; BLOCK = 6; FALL = 7; REBOUND = 8


class GameState(IntEnum):
    MENU = 0; SELECT = 1; TIPOFF = 2; PLAYING = 3
    HALFTIME = 4; OVERTIME = 5; GAMEOVER = 6; ATTRACT = 7


class Input(IntEnum):
    NONE = 0; MOVE = 1; SHOOT = 2; PASS_ = 3; STEAL = 4


SHOOT_FRAMES = 30
DUNK_FRAMES = 45

# Legal game-flow edges. Anything else is a bug in the caller.
GAME_NEXT = {
    GameState.MENU: {GameState.SELECT, GameState.ATTRACT},
    GameState.ATTRACT: {GameState.MENU},
    GameState.SELECT: {GameState.TIPOFF},
    GameState.TIPOFF: {GameState.PLAYING},
    GameState.PLAYING: {GameState.HALFTIME, GameState.OVERTIME, GameState.GAMEOVER},
    GameState.HALFTIME: {GameState.PLAYING},
    GameState.OVERTIME: {GameState.GAMEOVER},
    GameState.GAMEOVER: {GameState.MENU},
}


def game_advance(g: GameState, nxt: GameState) -> GameState:
    if nxt not in GAME_NEXT[g]:
        raise ValueError(f"illegal game transition {g.name} -> {nxt.name}")
    return nxt


@dataclass
class Player:
    state: PlayerState = PlayerState.IDLE
    prev_state: PlayerState = PlayerState.IDLE
    timer: int = 0


def is_committed(s: PlayerState) -> bool:
    return s in (PlayerState.SHOOT, PlayerState.DUNK, PlayerState.FALL)


def transition(p: Player, inp: Input) -> PlayerState:
    if is_committed(p.state) and p.timer > 0:
        return p.state
    p.prev_state = p.state
    if inp == Input.MOVE:
        p.state = PlayerState.RUN
    elif inp == Input.SHOOT:
        p.state = PlayerState.SHOOT
        p.timer = SHOOT_FRAMES
    elif inp == Input.PASS_:
        p.state = PlayerState.PASS_
    elif inp == Input.STEAL:
        p.state = PlayerState.STEAL
    else:
        p.state = PlayerState.IDLE
    return p.state


def tick(p: Player) -> None:
    if p.timer > 0:
        p.timer -= 1
        if p.timer == 0:
            p.prev_state = p.state
            p.state = PlayerState.IDLE


def did_transition(p: Player) -> bool:
    return p.state != p.prev_state


def main() -> None:
    # idle -> run on move
    p = Player()
    transition(p, Input.MOVE)
    assert p.state == PlayerState.RUN

    # shoot is committed
    p = Player()
    transition(p, Input.SHOOT)
    assert p.state == PlayerState.SHOOT
    transition(p, Input.MOVE)
    assert p.state == PlayerState.SHOOT, "shoot rejects move (committed)"
    transition(p, Input.PASS_)
    assert p.state == PlayerState.SHOOT, "shoot rejects pass (committed)"

    # timer expiry
    p = Player()
    transition(p, Input.SHOOT)
    for _ in range(SHOOT_FRAMES):
        tick(p)
    assert p.state == PlayerState.IDLE
    assert p.timer == 0

    # dunk committed (manually set; normally driven by game logic)
    p = Player()
    p.state = PlayerState.DUNK
    p.timer = DUNK_FRAMES
    transition(p, Input.MOVE)
    assert p.state == PlayerState.DUNK
    for _ in range(DUNK_FRAMES):
        tick(p)
    assert p.state == PlayerState.IDLE

    # transition detection
    p = Player()
    assert not did_transition(p)
    transition(p, Input.MOVE)
    assert did_transition(p)
    assert p.prev_state == PlayerState.IDLE
    transition(p, Input.MOVE)
    assert not did_transition(p), "run->run is not a transition"

    # game state progression: every step goes through the validator
    # (plain `g = GameState.X; assert g == GameState.X` checks nothing)
    g = GameState.MENU
    for nxt in (GameState.SELECT, GameState.TIPOFF, GameState.PLAYING,
                GameState.HALFTIME, GameState.PLAYING, GameState.GAMEOVER):
        g = game_advance(g, nxt)
    assert g == GameState.GAMEOVER
    try:
        game_advance(GameState.MENU, GameState.GAMEOVER)  # skips the game
        assert False, "should have raised"
    except ValueError:
        pass

    # committed-then-free
    p = Player()
    transition(p, Input.SHOOT)
    for _ in range(SHOOT_FRAMES):
        tick(p)
    transition(p, Input.MOVE)
    assert p.state == PlayerState.RUN

    print("All state_machines examples passed.")


if __name__ == "__main__":
    main()
