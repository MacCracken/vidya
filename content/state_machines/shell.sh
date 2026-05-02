#!/usr/bin/env bash
# Vidya — State Machines in Shell (Bash)
#
# Bash has no real enums, so we use readonly integer constants and
# parallel arrays for the Player state. Functions read/write three
# globals (P_STATE, P_PREV, P_TIMER) — a single Player only, but
# enough to demonstrate the pattern.

set -euo pipefail

# PlayerState
readonly PS_IDLE=0  PS_RUN=1  PS_SHOOT=2  PS_DUNK=3  PS_PASS=4
readonly PS_STEAL=5 PS_BLOCK=6 PS_FALL=7  PS_REBOUND=8

# GameState
readonly GS_MENU=0  GS_SELECT=1  GS_TIPOFF=2  GS_PLAYING=3
readonly GS_HALFTIME=4 GS_OVERTIME=5 GS_GAMEOVER=6 GS_ATTRACT=7

# Input
readonly IN_NONE=0 IN_MOVE=1 IN_SHOOT=2 IN_PASS=3 IN_STEAL=4

readonly SHOOT_FRAMES=30
readonly DUNK_FRAMES=45

P_STATE=$PS_IDLE
P_PREV=$PS_IDLE
P_TIMER=0

assert_eq() {
    local got="$1" want="$2" msg="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

player_reset() { P_STATE=$PS_IDLE; P_PREV=$PS_IDLE; P_TIMER=0; }

is_committed() {
    local s=$1
    (( s == PS_SHOOT || s == PS_DUNK || s == PS_FALL ))
}

transition() {
    local input=$1
    if is_committed "$P_STATE" && (( P_TIMER > 0 )); then
        return 0
    fi
    P_PREV=$P_STATE
    case "$input" in
        $IN_MOVE)  P_STATE=$PS_RUN ;;
        $IN_SHOOT) P_STATE=$PS_SHOOT; P_TIMER=$SHOOT_FRAMES ;;
        $IN_PASS)  P_STATE=$PS_PASS ;;
        $IN_STEAL) P_STATE=$PS_STEAL ;;
        *)         P_STATE=$PS_IDLE ;;
    esac
}

tick() {
    if (( P_TIMER > 0 )); then
        P_TIMER=$(( P_TIMER - 1 ))
        if (( P_TIMER == 0 )); then
            P_PREV=$P_STATE
            P_STATE=$PS_IDLE
        fi
    fi
}

did_transition() {
    if [[ "$P_STATE" != "$P_PREV" ]]; then echo 1; else echo 0; fi
}

# --- Tests ---

# idle -> run on move
player_reset
transition $IN_MOVE
assert_eq "$P_STATE" "$PS_RUN" "idle->run"

# shoot is committed
player_reset
transition $IN_SHOOT
assert_eq "$P_STATE" "$PS_SHOOT" "entered shoot"
transition $IN_MOVE
assert_eq "$P_STATE" "$PS_SHOOT" "shoot rejects move"
transition $IN_PASS
assert_eq "$P_STATE" "$PS_SHOOT" "shoot rejects pass"

# timer expiry
player_reset
transition $IN_SHOOT
for ((i = 0; i < SHOOT_FRAMES; i++)); do tick; done
assert_eq "$P_STATE" "$PS_IDLE" "timer expiry"
assert_eq "$P_TIMER" "0" "timer zero"

# dunk committed
player_reset
P_STATE=$PS_DUNK
P_TIMER=$DUNK_FRAMES
transition $IN_MOVE
assert_eq "$P_STATE" "$PS_DUNK" "dunk rejects input"
for ((i = 0; i < DUNK_FRAMES; i++)); do tick; done
assert_eq "$P_STATE" "$PS_IDLE" "dunk timer expiry"

# transition detection
player_reset
assert_eq "$(did_transition)" "0" "no transition initially"
transition $IN_MOVE
assert_eq "$(did_transition)" "1" "idle->run is a transition"
assert_eq "$P_PREV" "$PS_IDLE" "prev_state idle"
transition $IN_MOVE
assert_eq "$(did_transition)" "0" "run->run no transition"

# game state progression
g=$GS_MENU
g=$GS_SELECT;   assert_eq "$g" "$GS_SELECT"   "menu->select"
g=$GS_TIPOFF;   assert_eq "$g" "$GS_TIPOFF"   "select->tipoff"
g=$GS_PLAYING;  assert_eq "$g" "$GS_PLAYING"  "tipoff->playing"
g=$GS_HALFTIME; assert_eq "$g" "$GS_HALFTIME" "playing->halftime"
g=$GS_PLAYING;  assert_eq "$g" "$GS_PLAYING"  "halftime->playing"
g=$GS_GAMEOVER; assert_eq "$g" "$GS_GAMEOVER" "playing->gameover"

# committed-then-free
player_reset
transition $IN_SHOOT
for ((i = 0; i < SHOOT_FRAMES; i++)); do tick; done
transition $IN_MOVE
assert_eq "$P_STATE" "$PS_RUN" "accepts input after expiry"

echo "All state_machines examples passed."
