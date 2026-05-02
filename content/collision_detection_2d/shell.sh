#!/usr/bin/env bash
# Vidya — 2D Collision Detection in Shell (Bash)
#
# Bash $((...)) is signed 64-bit on every platform Vidya runs on.
# `>>` is arithmetic on negatives (sign-preserving), and integer
# overflow wraps silently — so we mirror the Cyrius reference's
# >>4 pre-shift on deltas to keep squared sums inside an i64.
# No `bc` is used (or available); pure integer arithmetic only.
# Squared-distance comparisons avoid sqrt — the central trick.

set -euo pipefail

readonly FX_SHIFT=16
readonly FX_ONE=$((1 << FX_SHIFT))

assert_true() {
    local got="$1" msg="$2"
    if [[ "$got" != "1" ]]; then
        echo "FAIL: $msg: expected true, got '$got'" >&2
        exit 1
    fi
}
assert_false() {
    local got="$1" msg="$2"
    if [[ "$got" != "0" ]]; then
        echo "FAIL: $msg: expected false, got '$got'" >&2
        exit 1
    fi
}

fx() { echo $(( $1 << FX_SHIFT )); }

dist_sq() {
    local dx=$(( ($3 - $1) >> 4 ))
    local dy=$(( ($4 - $2) >> 4 ))
    echo $(( dx * dx + dy * dy ))
}

circle_circle() {
    local d2; d2=$(dist_sq "$1" "$2" "$4" "$5")
    local sum_r=$(( ($3 + $6) >> 4 ))
    if (( d2 <= sum_r * sum_r )); then echo 1; else echo 0; fi
}

aabb_overlap() {
    if (( $1 >= $7 )); then echo 0; return; fi
    if (( $3 <= $5 )); then echo 0; return; fi
    if (( $2 >= $8 )); then echo 0; return; fi
    if (( $4 <= $6 )); then echo 0; return; fi
    echo 1
}

point_in_rect() {
    if (( $1 < $3 || $1 >= $5 || $2 < $4 || $2 >= $6 )); then
        echo 0
    else
        echo 1
    fi
}

clamp() {
    if   (( $1 < $2 )); then echo "$2"
    elif (( $1 > $3 )); then echo "$3"
    else echo "$1"
    fi
}

circle_aabb() {
    local cx=$1 cy=$2 cr=$3 left=$4 top=$5 right=$6 bottom=$7
    local closest_x; closest_x=$(clamp "$cx" "$left" "$right")
    local closest_y; closest_y=$(clamp "$cy" "$top" "$bottom")
    local d2; d2=$(dist_sq "$cx" "$cy" "$closest_x" "$closest_y")
    local r=$(( cr >> 4 ))
    if (( d2 <= r * r )); then echo 1; else echo 0; fi
}

point_in_circle() {
    local d2; d2=$(dist_sq "$1" "$2" "$3" "$4")
    local r=$(( $5 >> 4 ))
    if (( d2 <= r * r )); then echo 1; else echo 0; fi
}

push_apart_x() {
    local dx=$(( $2 - $1 ))
    local half=$(( $3 >> 1 ))
    if (( dx > 0 )); then echo $(( -half )); else echo "$half"; fi
}

iabs() { if (( $1 < 0 )); then echo $(( -$1 )); else echo "$1"; fi; }

swept_aabb_x() {
    local al=$1 ar=$2 vx=$3 bl=$4 br=$5
    if (( vx == 0 )); then echo "$FX_ONE"; return; fi
    local enter_dist exit_dist
    if (( vx > 0 )); then
        enter_dist=$(( bl - ar )); exit_dist=$(( br - al ))
    else
        enter_dist=$(( br - al )); exit_dist=$(( bl - ar ))
    fi
    local abs_v abs_ed abs_xd enter exit_
    abs_v=$(iabs "$vx")
    abs_ed=$(iabs "$enter_dist")
    abs_xd=$(iabs "$exit_dist")
    enter=$(( (abs_ed << FX_SHIFT) / abs_v ))
    exit_=$(( (abs_xd << FX_SHIFT) / abs_v ))
    if (( enter > exit_ || enter > FX_ONE )); then
        echo "$FX_ONE"
    else
        echo "$enter"
    fi
}

# ── Tests ─────────────────────────────────────────────────────────────

assert_true  "$(circle_circle "$(fx 10)" "$(fx 10)" "$(fx 5)" "$(fx 13)" "$(fx 10)" "$(fx 5)")" "overlapping circles"
assert_false "$(circle_circle "$(fx 0)" "$(fx 0)" "$(fx 1)" "$(fx 100)" "$(fx 100)" "$(fx 1)")" "distant circles"
assert_true  "$(circle_circle "$(fx 0)" "$(fx 0)" "$(fx 5)" "$(fx 10)" "$(fx 0)" "$(fx 5)")" "touching circles"

assert_true  "$(aabb_overlap "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)" "$(fx 5)" "$(fx 5)" "$(fx 15)" "$(fx 15)")" "overlapping AABBs"
assert_false "$(aabb_overlap "$(fx 0)" "$(fx 0)" "$(fx 5)" "$(fx 5)" "$(fx 10)" "$(fx 10)" "$(fx 20)" "$(fx 20)")" "separated AABBs"
assert_false "$(aabb_overlap "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)" "$(fx 10)" "$(fx 0)" "$(fx 20)" "$(fx 10)")" "edge-adjacent AABBs"

assert_true  "$(point_in_rect "$(fx 5)" "$(fx 5)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "inside"
assert_false "$(point_in_rect "$(fx 15)" "$(fx 5)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "outside"
assert_true  "$(point_in_rect "$(fx 0)" "$(fx 5)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "left edge"
assert_false "$(point_in_rect "$(fx 10)" "$(fx 5)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "right edge"

assert_true  "$(circle_aabb "$(fx 5)" "$(fx 5)" "$(fx 3)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "circle inside AABB"
assert_false "$(circle_aabb "$(fx 20)" "$(fx 20)" "$(fx 3)" "$(fx 0)" "$(fx 0)" "$(fx 10)" "$(fx 10)")" "circle far from AABB"

assert_true  "$(point_in_circle "$(fx 1)" "$(fx 1)" "$(fx 0)" "$(fx 0)" "$(fx 5)")" "point inside circle"
assert_false "$(point_in_circle "$(fx 100)" "$(fx 100)" "$(fx 0)" "$(fx 0)" "$(fx 5)")" "point outside circle"

d2=$(dist_sq "$(fx 0)" "$(fx 0)" "$(fx 3)" "$(fx 4)")
(( d2 > 0 )) || { echo "FAIL: 3-4-5 dist²" >&2; exit 1; }

push=$(push_apart_x "$(fx 0)" "$(fx 4)" "$(fx 2)")
(( push < 0 )) || { echo "FAIL: push-apart direction" >&2; exit 1; }

toi=$(swept_aabb_x "$(fx 0)" "$(fx 2)" "$(fx 8)" "$(fx 6)" "$(fx 10)")
(( toi > 0 && toi < FX_ONE )) || { echo "FAIL: swept AABB TOI ($toi)" >&2; exit 1; }
neg_v=$(( -$(fx 1) ))
toi2=$(swept_aabb_x "$(fx 0)" "$(fx 2)" "$neg_v" "$(fx 6)" "$(fx 10)")
(( toi2 == FX_ONE )) || { echo "FAIL: moving-away yields no impact ($toi2)" >&2; exit 1; }

echo "All collision_detection_2d examples passed."
