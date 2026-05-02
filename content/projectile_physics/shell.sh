#!/usr/bin/env bash
# Vidya — Projectile Physics in Shell (Bash)
#
# Semi-implicit Euler in 16.16 fixed-point. Bash's $((...)) is signed
# 64-bit on every platform Vidya runs on, `>>` is arithmetic on
# negatives, and overflow wraps silently — the bounce intermediate
# (vy * RESTITUTION ≈ 3.6e10) fits comfortably. No `bc` or `awk` is
# needed: the entire simulation is integer arithmetic. Shell is the
# wrong tool for serious physics; this exists to show the patterns
# translate without floating-point primitives.

set -euo pipefail

readonly FX_SHIFT=16
readonly GRAVITY=6554            # 0.1 per frame
readonly FLOOR_Y=14745600        # 225.0
readonly RESTITUTION=45875       # 0.7 in 16.16

# Ball state — globals (bash structs would just be associative arrays).
ball_x=0
ball_y=0
ball_vx=0
ball_vy=0

asr() {
    local v=$1 n=$2
    if (( v < 0 )); then
        echo $(( -((-v) >> n) ))
    else
        echo $(( v >> n ))
    fi
}

physics_step() {
    # Semi-implicit Euler: velocity first, then position.
    ball_vy=$(( ball_vy + GRAVITY ))
    ball_y=$((  ball_y  + ball_vy ))
    ball_x=$((  ball_x  + ball_vx ))
}

bounce_check() {
    if (( ball_y > FLOOR_Y )); then
        ball_y=$FLOOR_Y
        # vy = -(vy * restitution) >> 16
        local prod=$(( ball_vy * RESTITUTION ))
        local shifted
        shifted=$(asr "$prod" "$FX_SHIFT")
        ball_vy=$(( -shifted ))
    fi
}

assert_true() {
    if (( ! $1 )); then
        echo "FAIL: $2" >&2
        exit 1
    fi
}

assert_eq() {
    if (( $1 != $2 )); then
        echo "FAIL: $3: got $1, want $2" >&2
        exit 1
    fi
}

# ── Tests ─────────────────────────────────────────────────────────────

test_gravity() {
    ball_x=0; ball_y=0; ball_vx=0; ball_vy=0
    physics_step
    assert_eq "$ball_vy" "$GRAVITY" "vy == gravity after 1 step"
    assert_eq "$ball_y"  "$GRAVITY" "y == gravity after 1 step (semi-implicit)"
}

test_parabolic_arc() {
    ball_x=0; ball_y=6553600; ball_vx=0; ball_vy=-1310720
    local initial_y=$ball_y

    for ((i = 0; i < 50; i++)); do physics_step; done
    assert_true "$(( ball_y < initial_y ))" "ball rises in first 50 frames"

    for ((i = 0; i < 400; i++)); do physics_step; done
    assert_true "$(( ball_y > initial_y ))" "ball falls below start after 450 frames"
}

test_bounce() {
    ball_x=0; ball_y=$(( FLOOR_Y + 1 )); ball_vx=0; ball_vy=655360
    bounce_check
    assert_true "$(( ball_vy < 0 ))"          "vy is negative after bounce"
    assert_true "$(( -ball_vy < 655360 ))"    "bounce reduces velocity magnitude"
    assert_eq   "$ball_y" "$FLOOR_Y"          "position reset to floor on bounce"
}

test_horizontal_unchanged() {
    local vx_initial=131072  # 2.0
    ball_x=0; ball_y=0; ball_vx=$vx_initial; ball_vy=0
    physics_step
    physics_step
    physics_step
    assert_eq "$ball_vx" "$vx_initial"        "vx unchanged after 3 frames of gravity"
    assert_eq "$ball_x"  "$(( 3 * vx_initial ))" "x = 3 * vx after 3 frames"
}

test_energy_decay() {
    ball_x=0; ball_y=0; ball_vx=0; ball_vy=655360

    # 1000 frames — |vy| plateaus around 2700, well under 2*GRAVITY=13108.
    for ((i = 0; i < 1000; i++)); do
        physics_step
        bounce_check
    done

    local abs_vy=$ball_vy
    (( abs_vy < 0 )) && abs_vy=$(( -abs_vy ))
    assert_true "$(( abs_vy < GRAVITY * 2 ))" "vy near zero after 1000 bouncing frames"
}

test_semi_implicit_stability() {
    local start_y=$(( FLOOR_Y - 655360 ))
    ball_x=0; ball_y=$start_y; ball_vx=0; ball_vy=-655360
    local min_y=$start_y

    for ((i = 0; i < 500; i++)); do
        physics_step
        bounce_check
        (( ball_y < min_y )) && min_y=$ball_y
    done

    local max_rise=$(( 1000 * 65536 ))
    assert_true "$(( min_y > start_y - max_rise ))" "semi-implicit euler does not explode"
}

test_gravity
test_parabolic_arc
test_bounce
test_horizontal_unchanged
test_energy_decay
test_semi_implicit_stability

echo "All projectile_physics examples passed."
