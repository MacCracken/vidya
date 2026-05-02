// Vidya — State Machines in Zig
//
// Finite state machines with enum dispatch, committed states, timers,
// and transition validation. Zig's exhaustive `switch` over an enum is
// checked at compile time — every variant must be handled. Zig has no
// implicit conversions, so input/output types are explicit at every
// boundary (matches the Cyrius port's discipline).

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const PlayerState = enum(i64) {
    Idle = 0, Run = 1, Shoot = 2, Dunk = 3, Pass = 4,
    Steal = 5, Block = 6, Fall = 7, Rebound = 8,
};

const GameState = enum(i64) {
    Menu = 0, Select = 1, Tipoff = 2, Playing = 3,
    Halftime = 4, Overtime = 5, GameOver = 6, Attract = 7,
};

const Input = enum { None, Move, Shoot, Pass, Steal };

const SHOOT_FRAMES: i64 = 30;
const DUNK_FRAMES: i64 = 45;

const Player = struct {
    state: PlayerState,
    prev_state: PlayerState,
    timer: i64,
};

fn newPlayer() Player {
    return Player{ .state = .Idle, .prev_state = .Idle, .timer = 0 };
}

fn isCommitted(s: PlayerState) bool {
    return s == .Shoot or s == .Dunk or s == .Fall;
}

fn transition(p: *Player, input: Input) PlayerState {
    if (isCommitted(p.state) and p.timer > 0) return p.state;
    p.prev_state = p.state;
    switch (input) {
        .Move  => p.state = .Run,
        .Shoot => { p.state = .Shoot; p.timer = SHOOT_FRAMES; },
        .Pass  => p.state = .Pass,
        .Steal => p.state = .Steal,
        .None  => p.state = .Idle,
    }
    return p.state;
}

fn tick(p: *Player) void {
    if (p.timer > 0) {
        p.timer -= 1;
        if (p.timer == 0) {
            p.prev_state = p.state;
            p.state = .Idle;
        }
    }
}

fn didTransition(p: *const Player) bool {
    return p.state != p.prev_state;
}

pub fn main() !void {
    var p = newPlayer();
    _ = transition(&p, .Move);
    assert(p.state == .Run);

    p = newPlayer();
    _ = transition(&p, .Shoot);
    assert(p.state == .Shoot);
    _ = transition(&p, .Move);
    assert(p.state == .Shoot);
    _ = transition(&p, .Pass);
    assert(p.state == .Shoot);

    p = newPlayer();
    _ = transition(&p, .Shoot);
    var i: i64 = 0;
    while (i < SHOOT_FRAMES) : (i += 1) tick(&p);
    assert(p.state == .Idle);
    assert(p.timer == 0);

    p = newPlayer();
    p.state = .Dunk;
    p.timer = DUNK_FRAMES;
    _ = transition(&p, .Move);
    assert(p.state == .Dunk);
    i = 0;
    while (i < DUNK_FRAMES) : (i += 1) tick(&p);
    assert(p.state == .Idle);

    p = newPlayer();
    assert(!didTransition(&p));
    _ = transition(&p, .Move);
    assert(didTransition(&p));
    assert(p.prev_state == .Idle);
    _ = transition(&p, .Move);
    assert(!didTransition(&p));

    var g: GameState = .Menu;
    g = .Select;   assert(g == .Select);
    g = .Tipoff;   assert(g == .Tipoff);
    g = .Playing;  assert(g == .Playing);
    g = .Halftime; assert(g == .Halftime);
    g = .Playing;  assert(g == .Playing);
    g = .GameOver; assert(g == .GameOver);

    p = newPlayer();
    _ = transition(&p, .Shoot);
    i = 0;
    while (i < SHOOT_FRAMES) : (i += 1) tick(&p);
    _ = transition(&p, .Move);
    assert(p.state == .Run);

    print("All state_machines examples passed.\n", .{});
}
