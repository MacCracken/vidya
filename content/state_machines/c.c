// Vidya — State Machines in C
//
// Finite state machines with enum dispatch, committed states, timers, and
// transition validation. C enums are int constants with no scoping; we
// prefix variants (PS_, GS_, INPUT_) to avoid collisions.

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

typedef enum {
    PS_IDLE = 0, PS_RUN, PS_SHOOT, PS_DUNK, PS_PASS,
    PS_STEAL, PS_BLOCK, PS_FALL, PS_REBOUND,
} PlayerState;

typedef enum {
    GS_MENU = 0, GS_SELECT, GS_TIPOFF, GS_PLAYING,
    GS_HALFTIME, GS_OVERTIME, GS_GAMEOVER, GS_ATTRACT,
} GameState;

typedef enum {
    INPUT_NONE = 0, INPUT_MOVE, INPUT_SHOOT, INPUT_PASS, INPUT_STEAL,
} Input;

#define SHOOT_FRAMES 30
#define DUNK_FRAMES  45

typedef struct {
    PlayerState state;
    PlayerState prev_state;
    int timer;
} Player;

static Player player_new(void) {
    return (Player){ .state = PS_IDLE, .prev_state = PS_IDLE, .timer = 0 };
}

static bool is_committed(PlayerState s) {
    return s == PS_SHOOT || s == PS_DUNK || s == PS_FALL;
}

static PlayerState transition(Player *p, Input input) {
    if (is_committed(p->state) && p->timer > 0) return p->state;
    p->prev_state = p->state;
    switch (input) {
        case INPUT_MOVE:  p->state = PS_RUN;   break;
        case INPUT_SHOOT: p->state = PS_SHOOT; p->timer = SHOOT_FRAMES; break;
        case INPUT_PASS:  p->state = PS_PASS;  break;
        case INPUT_STEAL: p->state = PS_STEAL; break;
        case INPUT_NONE:  p->state = PS_IDLE;  break;
    }
    return p->state;
}

static void tick(Player *p) {
    if (p->timer > 0) {
        p->timer--;
        if (p->timer == 0) {
            p->prev_state = p->state;
            p->state = PS_IDLE;
        }
    }
}

static bool did_transition(const Player *p) {
    return p->state != p->prev_state;
}

int main(void) {
    Player p = player_new();
    transition(&p, INPUT_MOVE);
    assert(p.state == PS_RUN);

    p = player_new();
    transition(&p, INPUT_SHOOT);
    assert(p.state == PS_SHOOT);
    transition(&p, INPUT_MOVE);
    assert(p.state == PS_SHOOT);   // shoot rejects move (committed)
    transition(&p, INPUT_PASS);
    assert(p.state == PS_SHOOT);   // shoot rejects pass (committed)

    p = player_new();
    transition(&p, INPUT_SHOOT);
    for (int i = 0; i < SHOOT_FRAMES; i++) tick(&p);
    assert(p.state == PS_IDLE);
    assert(p.timer == 0);

    p = player_new();
    p.state = PS_DUNK;
    p.timer = DUNK_FRAMES;
    transition(&p, INPUT_MOVE);
    assert(p.state == PS_DUNK);
    for (int i = 0; i < DUNK_FRAMES; i++) tick(&p);
    assert(p.state == PS_IDLE);

    p = player_new();
    assert(!did_transition(&p));
    transition(&p, INPUT_MOVE);
    assert(did_transition(&p));
    assert(p.prev_state == PS_IDLE);
    transition(&p, INPUT_MOVE);
    assert(!did_transition(&p));   // run->run is not a transition

    GameState g = GS_MENU;
    g = GS_SELECT;   assert(g == GS_SELECT);
    g = GS_TIPOFF;   assert(g == GS_TIPOFF);
    g = GS_PLAYING;  assert(g == GS_PLAYING);
    g = GS_HALFTIME; assert(g == GS_HALFTIME);
    g = GS_PLAYING;  assert(g == GS_PLAYING);
    g = GS_GAMEOVER; assert(g == GS_GAMEOVER);
    (void)g;

    p = player_new();
    transition(&p, INPUT_SHOOT);
    for (int i = 0; i < SHOOT_FRAMES; i++) tick(&p);
    transition(&p, INPUT_MOVE);
    assert(p.state == PS_RUN);

    puts("All state_machines examples passed.");
    return 0;
}
