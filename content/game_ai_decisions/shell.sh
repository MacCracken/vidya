#!/usr/bin/env bash
# Vidya — Game AI Decision Making in Shell (Bash)
#
# Stat-driven AI scoring with PCG PRNG and weighted action selection.
# Bash's `$(( ))` arithmetic uses 64-bit signed ints with two's-complement
# wrap on overflow (defined behavior in modern bash). For the PCG state,
# the bit pattern after `state*MULT + INC` is the same whether you call
# the type signed or unsigned — we then mask the high 31 bits for the
# return value, which fits comfortably in a positive int64.

set -euo pipefail

# Action enum
readonly ACT_SHOOT=0 ACT_DUNK=1 ACT_PASS=2 ACT_DRIVE=3 ACT_STEAL=4

# PCG constants
readonly PCG_MULT=6364136223846793005
readonly PCG_INC=1442695040888963407

RNG_STATE=12345
RNG_OUT=0   # output of rng_next / rng_range, set in the parent shell

rng_seed() { RNG_STATE=$1; }

# rng_next: updates RNG_STATE and writes the next value to RNG_OUT.
# We avoid `$(rng_next)` because command substitution forks a subshell
# and the state mutation would not persist into the parent.
rng_next() {
    RNG_STATE=$(( RNG_STATE * PCG_MULT + PCG_INC ))
    RNG_OUT=$(( (RNG_STATE >> 33) & 2147483647 ))
}

rng_range() {
    local max=$1
    if (( max <= 0 )); then
        RNG_OUT=0
        return
    fi
    rng_next
    RNG_OUT=$(( RNG_OUT % max ))
}

prob_check() {
    local stat=$1
    rng_range 100
    if (( RNG_OUT < stat * 10 )); then
        PROB_OUT=1
    else
        PROB_OUT=0
    fi
}

evaluate_shoot() {
    local shooting=$1 dist_fx=$2
    local base=$(( shooting * 10 ))
    local dist_units=$(( dist_fx >> 16 ))
    local score=$(( base - dist_units ))
    if (( score < 0 )); then score=0; fi
    echo "$score"
}

evaluate_dunk() {
    local dunking=$1 dist_fx=$2
    if (( (dist_fx >> 16) > 3 )); then
        echo 0
        return
    fi
    echo $(( dunking * 15 ))
}

evaluate_pass()  { echo $(( $1 * 8 )); }
evaluate_drive() { echo $(( $1 * 6 )); }

apply_urgency() {
    local score=$1 shot_clock=$2
    local urgency=$(( (24 - shot_clock) / 4 ))
    if (( urgency < 1 )); then urgency=1; fi
    echo $(( score * urgency ))
}

# add_noise: stateful — uses RNG. Writes result to NOISE_OUT in parent.
add_noise() {
    local score=$1
    rng_range 21
    local noise=$(( RNG_OUT - 10 ))
    local r=$(( score + noise ))
    if (( r < 0 )); then r=0; fi
    NOISE_OUT=$r
}

# ai_decide_offense speed shooting dunking passing dist_fx shot_clock
# Writes resulting Action to ACTION_OUT.
ai_decide_offense() {
    local speed=$1 shooting=$2 dunking=$3 passing=$4 dist_fx=$5 shot_clock=$6
    local s d p dr
    s=$(evaluate_shoot "$shooting" "$dist_fx")
    s=$(apply_urgency "$s" "$shot_clock")
    add_noise "$s"; s=$NOISE_OUT
    d=$(evaluate_dunk "$dunking" "$dist_fx")
    add_noise "$d"; d=$NOISE_OUT
    p=$(evaluate_pass "$passing")
    add_noise "$p"; p=$NOISE_OUT
    dr=$(evaluate_drive "$speed")
    add_noise "$dr"; dr=$NOISE_OUT

    local best=$ACT_SHOOT
    local best_score=$s
    if (( d > best_score )); then best=$ACT_DUNK; best_score=$d; fi
    if (( p > best_score )); then best=$ACT_PASS; best_score=$p; fi
    if (( dr > best_score )); then best=$ACT_DRIVE; best_score=$dr; fi
    ACTION_OUT=$best
}

assert_eq() {
    local got="$1" want="$2" msg="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

assert_true() {
    local cond=$1 msg=$2
    if (( ! cond )); then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

# --- Tests ---

# evaluate_shoot
assert_eq "$(evaluate_shoot 9 $((3 << 16)))" "87" "shoot: 9*10 - 3"
assert_eq "$(evaluate_shoot 1 $((20 << 16)))" "0" "low stat + far = 0"
assert_eq "$(evaluate_shoot 10 0)" "100" "stat 10 at rim"

# evaluate_dunk
assert_eq "$(evaluate_dunk 8 $((2 << 16)))" "120" "dunk: stat 8 * 15"
assert_eq "$(evaluate_dunk 10 $((10 << 16)))" "0" "too far to dunk"

# urgency
assert_eq "$(apply_urgency 50 24)" "50" "full clock"
assert_eq "$(apply_urgency 50 2)" "250" "low clock x5"
assert_eq "$(apply_urgency 50 0)" "300" "empty clock x6"

# prob_check
rng_seed 42
for ((i = 0; i < 20; i++)); do
    prob_check 10
    assert_eq "$PROB_OUT" "1" "stat 10 always passes"
done
rng_seed 99
for ((i = 0; i < 20; i++)); do
    prob_check 0
    assert_eq "$PROB_OUT" "0" "stat 0 always fails"
done

# PRNG determinism
rng_seed 77777; rng_next; A1=$RNG_OUT; rng_next; A2=$RNG_OUT
rng_seed 77777; rng_next; B1=$RNG_OUT; rng_next; B2=$RNG_OUT
assert_eq "$A1" "$B1" "same seed first"
assert_eq "$A2" "$B2" "same seed second"

# PRNG variation
rng_seed 42
rng_next; V1=$RNG_OUT
rng_next; V2=$RNG_OUT
assert_true "$(( V1 != V2 ))" "consecutive PRNG values differ"

# Difficulty scaling
EASY=$(evaluate_shoot 3 $((5 << 16)))
HARD=$(evaluate_shoot 9 $((5 << 16)))
assert_true "$(( HARD > EASY ))" "hard shoots better"
EASY_DUNK=$(evaluate_dunk 2 $((2 << 16)))
HARD_DUNK=$(evaluate_dunk 9 $((2 << 16)))
assert_true "$(( HARD_DUNK > EASY_DUNK ))" "hard dunks better"

# ai_decide_offense: speed=5 shooting=5 dunking=10 passing=3, dist=1.0, clock=20
rng_seed 100
ai_decide_offense 5 5 10 3 $((1 << 16)) 20
assert_eq "$ACTION_OUT" "$ACT_DUNK" "high dunk at close range -> DUNK"

echo "All game_ai_decisions examples passed."
