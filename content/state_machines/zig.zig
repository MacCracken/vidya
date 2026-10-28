// Vidya — State Machines in Zig
//
// Finite state machines with enum dispatch, committed states, timers,
// and transition validation. Zig's exhaustive `switch` over an enum is
// checked at compile time — every variant must be handled. Zig has no
// implicit lossy conversions, so input/output types are explicit at every
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

// Game-level transition table: only listed edges are legal. The switch is
// exhaustive, so adding a GameState variant fails to compile until its
// edges are written down.
fn gameCanTransition(from: GameState, to: GameState) bool {
    return switch (from) {
        .Menu => to == .Select or to == .Attract,
        .Attract => to == .Menu,
        .Select => to == .Tipoff or to == .Menu,
        .Tipoff => to == .Playing,
        .Playing => to == .Halftime or to == .Overtime or to == .GameOver,
        .Halftime => to == .Playing,
        .Overtime => to == .GameOver or to == .Overtime,
        .GameOver => to == .Menu,
    };
}

fn gameTransition(from: GameState, to: GameState) GameState {
    return if (gameCanTransition(from, to)) to else from; // reject = stay put
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

    // (Assigning g = .X and asserting g == .X tests nothing; go through
    // the transition table so an illegal edge can actually be rejected.)
    var g: GameState = .Menu;
    g = gameTransition(g, .Select);   assert(g == .Select);
    g = gameTransition(g, .Tipoff);   assert(g == .Tipoff);
    g = gameTransition(g, .Playing);  assert(g == .Playing);
    g = gameTransition(g, .Halftime); assert(g == .Halftime);
    g = gameTransition(g, .GameOver); assert(g == .Halftime); // rejected
    g = gameTransition(g, .Playing);  assert(g == .Playing);
    g = gameTransition(g, .GameOver); assert(g == .GameOver);
    assert(!gameCanTransition(.Menu, .Playing)); // can't skip tipoff

    p = newPlayer();
    _ = transition(&p, .Shoot);
    i = 0;
    while (i < SHOOT_FRAMES) : (i += 1) tick(&p);
    _ = transition(&p, .Move);
    assert(p.state == .Run);

    print("All state_machines examples passed.\n", .{});
}
