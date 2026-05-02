#!/usr/bin/env bash
# Vidya — Line Rasterization (Bresenham) in Shell (Bash)
#
# All-octant integer Bresenham on a 16x16 byte framebuffer.

set -uo pipefail

readonly FB_W=16
readonly FB_H=16
readonly FB_BYTES=$(( FB_W * FB_H ))

declare -a FB
fb_init() { local i; for (( i = 0; i < FB_BYTES; i++ )); do FB[i]=0; done; }
fb_clear() { fb_init; }

fb_set() {
    local x=$1 y=$2 v=$3
    if (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )); then return; fi
    FB[y * FB_W + x]=$v
}

# fb_get X Y -> sets FB_OUT
fb_get() {
    local x=$1 y=$2
    if (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )); then FB_OUT=0; return; fi
    FB_OUT=${FB[y * FB_W + x]}
}

count_lit() {
    local n=0 i=0
    for (( i = 0; i < FB_BYTES; i++ )); do
        (( FB[i] != 0 )) && n=$((n + 1))
    done
    LIT_OUT=$n
}

iabs() { local v=$1; (( v < 0 )) && v=$((-v)); IABS_OUT=$v; }
sign() { local v=$1; if (( v > 0 )); then SIGN_OUT=1; elif (( v < 0 )); then SIGN_OUT=-1; else SIGN_OUT=0; fi; }

draw_line() {
    local x0=$1 y0=$2 x1=$3 y1=$4 v=$5
    iabs $((x1 - x0)); local dx=$IABS_OUT
    iabs $((y1 - y0)); local dy=$IABS_OUT
    sign $((x1 - x0)); local sx=$SIGN_OUT
    sign $((y1 - y0)); local sy=$SIGN_OUT
    local err=$((dx - dy))
    local x=$x0 y=$y0
    while true; do
        fb_set $x $y $v
        if (( x == x1 && y == y1 )); then return; fi
        local e2=$((err * 2))
        if (( e2 > -dy )); then err=$((err - dy)); x=$((x + sx)); fi
        if (( e2 < dx ));  then err=$((err + dx)); y=$((y + sy)); fi
    done
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

fb_init

fb_clear; draw_line 2 5 8 5 1
count_lit; check $LIT_OUT 7 "h count"
fb_get 2 5; check $FB_OUT 1 "h L"
fb_get 8 5; check $FB_OUT 1 "h R"
fb_get 5 5; check $FB_OUT 1 "h M"
fb_get 5 6; check $FB_OUT 0 "h off"

fb_clear; draw_line 5 2 5 8 1
count_lit; check $LIT_OUT 7 "v count"
fb_get 5 2; check $FB_OUT 1 "v T"
fb_get 5 8; check $FB_OUT 1 "v B"
fb_get 5 5; check $FB_OUT 1 "v M"
fb_get 6 5; check $FB_OUT 0 "v off"

fb_clear; draw_line 2 2 7 7 1
count_lit; check $LIT_OUT 6 "+d count"
fb_get 2 2; check $FB_OUT 1 "+d S"
fb_get 7 7; check $FB_OUT 1 "+d E"
fb_get 5 5; check $FB_OUT 1 "+d M"
fb_get 5 4; check $FB_OUT 0 "+d off"

fb_clear; draw_line 2 7 7 2 1
count_lit; check $LIT_OUT 6 "-d count"
fb_get 2 7; check $FB_OUT 1 "-d S"
fb_get 7 2; check $FB_OUT 1 "-d E"
fb_get 5 4; check $FB_OUT 1 "-d M"

fb_clear; draw_line 3 1 5 11 1
count_lit; check $LIT_OUT 11 "steep count"
fb_get 3 1; check $FB_OUT 1 "steep S"
fb_get 5 11; check $FB_OUT 1 "steep E"

fb_clear; draw_line 8 8 8 8 1
count_lit; check $LIT_OUT 1 "point count"
fb_get 8 8; check $FB_OUT 1 "point lit"

fb_clear; draw_line 8 5 2 5 1
count_lit; check $LIT_OUT 7 "rev count"
fb_get 2 5; check $FB_OUT 1 "rev L"
fb_get 8 5; check $FB_OUT 1 "rev R"

echo "line_rasterization: $PASS/27 ok"
