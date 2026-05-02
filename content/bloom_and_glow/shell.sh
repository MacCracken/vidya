#!/usr/bin/env bash
# Vidya — Bloom and Glow in Shell (Bash)
#
# 1-pixel additive bloom on a 16x16 single-channel intensity buffer.

set -uo pipefail

readonly FB_W=16
readonly FB_H=16
readonly FB_BYTES=$(( FB_W * FB_H ))
readonly THRESHOLD=128
readonly GLOW_FRAC=2

declare -a SRC DST

init_fb() {
    local -n fb=$1
    local i
    for (( i = 0; i < FB_BYTES; i++ )); do fb[i]=0; done
}

fb_set() {
    local -n fb=$1
    local x=$2 y=$3 v=$4
    (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )) && return
    fb[y * FB_W + x]=$v
}

# fb_get NAME X Y -> sets FB_OUT
fb_get() {
    local -n fb=$1
    local x=$2 y=$3
    if (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )); then FB_OUT=0; return; fi
    FB_OUT=${fb[y * FB_W + x]}
}

fb_add() {
    local -n fb=$1
    local x=$2 y=$3 delta=$4
    (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )) && return
    local idx=$(( y * FB_W + x ))
    local s=$(( fb[idx] + delta ))
    (( s > 255 )) && s=255
    fb[idx]=$s
}

apply_bloom() {
    local i x y v glow
    for (( i = 0; i < FB_BYTES; i++ )); do DST[i]=${SRC[i]}; done
    for (( y = 0; y < FB_H; y++ )); do
        for (( x = 0; x < FB_W; x++ )); do
            v=${SRC[y * FB_W + x]}
            if (( v >= THRESHOLD )); then
                glow=$(( v / GLOW_FRAC ))
                fb_add DST $((x - 1)) $y       $glow
                fb_add DST $((x + 1)) $y       $glow
                fb_add DST $x         $((y - 1)) $glow
                fb_add DST $x         $((y + 1)) $glow
            fi
        done
    done
}

count_lit() {
    local n=0 i
    for (( i = 0; i < FB_BYTES; i++ )); do
        (( DST[i] != 0 )) && n=$((n + 1))
    done
    LIT_OUT=$n
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

init_fb SRC; init_fb DST

# 1
apply_bloom; count_lit; check $LIT_OUT 0 "empty"

# 2
init_fb SRC; fb_set SRC 8 8 200
apply_bloom
fb_get DST 8 8; check $FB_OUT 200 "src"
fb_get DST 7 8; check $FB_OUT 100 "L"
fb_get DST 9 8; check $FB_OUT 100 "R"
fb_get DST 8 7; check $FB_OUT 100 "U"
fb_get DST 8 9; check $FB_OUT 100 "D"
fb_get DST 7 7; check $FB_OUT 0 "diag"
count_lit; check $LIT_OUT 5 "count 5"

# 3
init_fb SRC; fb_set SRC 8 8 200; fb_set SRC 9 8 250
apply_bloom
fb_get DST 9 8; check $FB_OUT 255 "clamp"
fb_get DST 8 8; check $FB_OUT 255 "sum clamp"

# 4
init_fb SRC; fb_set SRC 8 8 100
apply_bloom
fb_get DST 8 8; check $FB_OUT 100 "dim"
fb_get DST 7 8; check $FB_OUT 0 "dim no glow"
count_lit; check $LIT_OUT 1 "dim count"

# 5
init_fb SRC; fb_set SRC 0 0 200
apply_bloom
fb_get DST 0 0; check $FB_OUT 200 "corner"
fb_get DST 1 0; check $FB_OUT 100 "corner R"
fb_get DST 0 1; check $FB_OUT 100 "corner D"
count_lit; check $LIT_OUT 3 "corner count"

# 6
init_fb SRC; fb_set SRC 4 8 200; fb_set SRC 6 8 200
apply_bloom
fb_get DST 5 8; check $FB_OUT 200 "mid"
fb_get DST 3 8; check $FB_OUT 100 "outer L"
fb_get DST 7 8; check $FB_OUT 100 "outer R"

echo "bloom_and_glow: $PASS/20 ok"
