#!/usr/bin/env bash
# Vidya — Game Loop Architecture in Shell (Bash)
#
# Fixed-timestep accumulator loop with spiral-of-death cap. The driver
# `loop_step` takes an elapsed-microsecond delta in $1 and updates the
# global accumulator/counter state. Bash arithmetic via $((...)) is
# 64-bit signed integer on every supported platform — wraps at ~292
# years of microseconds, so the math discipline matches the C/Go ports.
# A real game would use $EPOCHREALTIME (bash 5+) for monotonic time;
# tests use deterministic deltas only.

set -euo pipefail

readonly DT_US=16667
readonly MAX_ACCUM=$(( 5 * DT_US ))   # 83335

# GameLoop globals (single instance — bash has no real structs)
G_ACCUM=0
G_UPDATE_COUNT=0
G_RENDER_COUNT=0
LAST_UPDATES=0

loop_reset() {
    G_ACCUM=0
    G_UPDATE_COUNT=0
    G_RENDER_COUNT=0
    LAST_UPDATES=0
}

loop_step() {
    local elapsed_us=$1
    local accum=$(( G_ACCUM + elapsed_us ))
    # Spiral-of-death cap.
    if (( accum > MAX_ACCUM )); then
        accum=$MAX_ACCUM
    fi
    local updates=0
    while (( accum >= DT_US )); do
        accum=$(( accum - DT_US ))
        updates=$(( updates + 1 ))
    done
    G_ACCUM=$accum
    G_UPDATE_COUNT=$(( G_UPDATE_COUNT + updates ))
    G_RENDER_COUNT=$(( G_RENDER_COUNT + 1 ))
    LAST_UPDATES=$updates
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

# test_exact_dt_fires_one_update
loop_reset
loop_step "$DT_US"
assert_eq "$LAST_UPDATES" "1" "exactly one update per dt"
assert_eq "$G_UPDATE_COUNT" "1" "update_count = 1"

# test_under_dt_no_update
loop_reset
loop_step $(( DT_US / 2 ))
assert_eq "$LAST_UPDATES" "0" "no update when elapsed < dt"

# test_catchup_50ms
loop_reset
loop_step 50000
assert_eq "$LAST_UPDATES" "2" "50ms produces 2 fixed-step updates"

# test_spiral_of_death_cap
loop_reset
loop_step 1000000
assert_eq "$LAST_UPDATES" "5" "spiral cap: exactly 5 updates per call"

# test_render_per_frame
loop_reset
loop_step "$DT_US"
loop_step "$DT_US"
loop_step "$DT_US"
assert_eq "$G_RENDER_COUNT" "3" "3 renders for 3 frames"
assert_eq "$G_UPDATE_COUNT" "3" "3 updates total"

# test_accumulator_remainder
loop_reset
loop_step $(( DT_US + DT_US / 2 ))
assert_true "$(( G_ACCUM > DT_US / 4 ))" "remainder is positive"
assert_true "$(( G_ACCUM < DT_US ))" "remainder < full dt"

# test_input_update_render_separation
loop_reset
loop_step 30000
loop_step 5000
loop_step 30000
assert_eq "$G_UPDATE_COUNT" "3" "3 updates from 65ms total"
assert_eq "$G_RENDER_COUNT" "3" "3 renders from 3 frames"

echo "All game_loop_architecture examples passed."
