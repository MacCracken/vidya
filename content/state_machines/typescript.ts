// Vidya — State Machines in TypeScript
//
// Finite state machines with const-enum dispatch, committed states,
// timers, and transition validation. `const enum` inlines to numeric
// literals at compile time — zero runtime cost. Discriminated unions
// can model richer state, but the integer-tag form keeps parity with
// the other-language ports.

const enum PlayerState {
    IDLE = 0, RUN, SHOOT, DUNK, PASS,
    STEAL, BLOCK, FALL, REBOUND,
}

const enum GameState {
    MENU = 0, SELECT, TIPOFF, PLAYING,
    HALFTIME, OVERTIME, GAMEOVER, ATTRACT,
}

const enum Input { NONE = 0, MOVE, SHOOT, PASS, STEAL }

const SHOOT_FRAMES = 30;
const DUNK_FRAMES = 45;

interface Player {
    state: PlayerState;
    prevState: PlayerState;
    timer: number;
}

function newPlayer(): Player {
    return { state: PlayerState.IDLE, prevState: PlayerState.IDLE, timer: 0 };
}

function isCommitted(s: PlayerState): boolean {
    return s === PlayerState.SHOOT || s === PlayerState.DUNK || s === PlayerState.FALL;
}

function transition(p: Player, input: Input): PlayerState {
    if (isCommitted(p.state) && p.timer > 0) return p.state;
    p.prevState = p.state;
    switch (input) {
        case Input.MOVE:  p.state = PlayerState.RUN; break;
        case Input.SHOOT: p.state = PlayerState.SHOOT; p.timer = SHOOT_FRAMES; break;
        case Input.PASS:  p.state = PlayerState.PASS; break;
        case Input.STEAL: p.state = PlayerState.STEAL; break;
        default:          p.state = PlayerState.IDLE;
    }
    return p.state;
}

function tick(p: Player): void {
    if (p.timer > 0) {
        p.timer--;
        if (p.timer === 0) {
            p.prevState = p.state;
            p.state = PlayerState.IDLE;
        }
    }
}

function didTransition(p: Player): boolean {
    return p.state !== p.prevState;
}

function mustEq<T>(got: T, want: T, msg: string): void {
    if (got !== want) throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
}

function main(): void {
    let p = newPlayer();
    transition(p, Input.MOVE);
    mustEq(p.state, PlayerState.RUN, "idle->run");

    p = newPlayer();
    transition(p, Input.SHOOT);
    mustEq(p.state, PlayerState.SHOOT, "entered shoot");
    transition(p, Input.MOVE);
    mustEq(p.state, PlayerState.SHOOT, "shoot rejects move");
    transition(p, Input.PASS);
    mustEq(p.state, PlayerState.SHOOT, "shoot rejects pass");

    p = newPlayer();
    transition(p, Input.SHOOT);
    for (let i = 0; i < SHOOT_FRAMES; i++) tick(p);
    mustEq(p.state, PlayerState.IDLE, "timer expiry");
    mustEq(p.timer, 0, "timer zero");

    p = newPlayer();
    p.state = PlayerState.DUNK;
    p.timer = DUNK_FRAMES;
    transition(p, Input.MOVE);
    mustEq(p.state, PlayerState.DUNK, "dunk rejects input");
    for (let i = 0; i < DUNK_FRAMES; i++) tick(p);
    mustEq(p.state, PlayerState.IDLE, "dunk timer expiry");

    p = newPlayer();
    mustEq(didTransition(p), false, "no transition initially");
    transition(p, Input.MOVE);
    mustEq(didTransition(p), true, "idle->run is a transition");
    mustEq(p.prevState, PlayerState.IDLE, "prev_state idle");
    transition(p, Input.MOVE);
    mustEq(didTransition(p), false, "run->run no transition");

    let g: GameState = GameState.MENU;
    g = GameState.SELECT;   mustEq(g, GameState.SELECT, "menu->select");
    g = GameState.TIPOFF;   mustEq(g, GameState.TIPOFF, "select->tipoff");
    g = GameState.PLAYING;  mustEq(g, GameState.PLAYING, "tipoff->playing");
    g = GameState.HALFTIME; mustEq(g, GameState.HALFTIME, "playing->halftime");
    g = GameState.PLAYING;  mustEq(g, GameState.PLAYING, "halftime->playing");
    g = GameState.GAMEOVER; mustEq(g, GameState.GAMEOVER, "playing->gameover");

    p = newPlayer();
    transition(p, Input.SHOOT);
    for (let i = 0; i < SHOOT_FRAMES; i++) tick(p);
    transition(p, Input.MOVE);
    mustEq(p.state, PlayerState.RUN, "accepts input after expiry");

    console.log("All state_machines examples passed.");
}

main();
