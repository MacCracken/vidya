#!/usr/bin/env bash
# Vidya — Framebuffer Rendering in Shell (Bash)
#
# 16x16 BGRA8888 framebuffer mirroring cyrius.cyr. Bash uses an
# indexed integer array as the byte buffer.

set -uo pipefail

readonly FB_W=16
readonly FB_H=16
readonly FB_BPP=4
readonly FB_BYTES=$(( FB_W * FB_H * FB_BPP ))

declare -a FB_BUF
fb_init() {
    local i
    for (( i = 0; i < FB_BYTES; i++ )); do FB_BUF[i]=0; done
}

fb_clear() {
    local i
    for (( i = 0; i < FB_BYTES; i++ )); do FB_BUF[i]=0; done
}

# fb_set X Y COLOR -> sets FB_SET_OUT to 1 (success) or 0 (OOB)
fb_set() {
    local x=$1 y=$2 color=$3
    if (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )); then
        FB_SET_OUT=0
        return 0
    fi
    local off=$(( (y * FB_W + x) * FB_BPP ))
    FB_BUF[off]=$(( color & 0xFF ))
    FB_BUF[off + 1]=$(( (color >> 8) & 0xFF ))
    FB_BUF[off + 2]=$(( (color >> 16) & 0xFF ))
    FB_BUF[off + 3]=255
    FB_SET_OUT=1
}

# fb_get X Y -> sets FB_GET_OUT
fb_get() {
    local x=$1 y=$2
    if (( x < 0 || x >= FB_W || y < 0 || y >= FB_H )); then
        FB_GET_OUT=0
        return 0
    fi
    local off=$(( (y * FB_W + x) * FB_BPP ))
    FB_GET_OUT=$(( (FB_BUF[off + 2] << 16) | (FB_BUF[off + 1] << 8) | FB_BUF[off] ))
}

draw_hline() {
    local x=$1 y=$2 len=$3 color=$4 i=0
    for (( i = 0; i < len; i++ )); do fb_set "$((x + i))" "$y" "$color"; done
}

draw_vline() {
    local x=$1 y=$2 len=$3 color=$4 i=0
    for (( i = 0; i < len; i++ )); do fb_set "$x" "$((y + i))" "$color"; done
}

count_lit() {
    local n=0 i=0
    for (( i = 0; i < FB_BYTES; i += FB_BPP )); do
        if (( FB_BUF[i] != 0 || FB_BUF[i + 1] != 0 || FB_BUF[i + 2] != 0 )); then
            n=$((n + 1))
        fi
    done
    COUNT_OUT=$n
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

fb_init

# 1
fb_clear
count_lit
check "$COUNT_OUT" 0 "clear"

# 2
fb_set 5 7 16711680  # 0xFF0000
off=$(( (7 * FB_W + 5) * FB_BPP ))
check "${FB_BUF[off]}" 0 "B"
check "${FB_BUF[off + 1]}" 0 "G"
check "${FB_BUF[off + 2]}" 255 "R"
check "${FB_BUF[off + 3]}" 255 "A"

# 3
fb_get 5 7
check "$FB_GET_OUT" 16711680 "get red"

# 4
count_lit; before=$COUNT_OUT
fb_set -1 5 65280
fb_set 16 5 65280
fb_set 5 -1 65280
fb_set 5 16 65280
count_lit
check "$COUNT_OUT" "$before" "OOB rejected"

# 5
fb_set 3 3 255
check "$FB_SET_OUT" 1 "in-bounds"
fb_set -5 3 255
check "$FB_SET_OUT" 0 "OOB false"

# 6
fb_clear
draw_hline 2 8 4 65280  # 0x00FF00
count_lit; check "$COUNT_OUT" 4 "hline count"
fb_get 2 8; check "$FB_GET_OUT" 65280 "hline (2,8)"
fb_get 5 8; check "$FB_GET_OUT" 65280 "hline (5,8)"
fb_get 6 8; check "$FB_GET_OUT" 0 "hline stops"

# 7
fb_clear
draw_vline 7 2 4 255  # 0x0000FF
count_lit; check "$COUNT_OUT" 4 "vline count"
fb_get 7 2; check "$FB_GET_OUT" 255 "vline (7,2)"
fb_get 7 5; check "$FB_GET_OUT" 255 "vline (7,5)"
fb_get 7 6; check "$FB_GET_OUT" 0 "vline stops"

# 8
fb_clear
draw_hline 14 5 4 16711680
count_lit; check "$COUNT_OUT" 2 "hline clipped"

echo "framebuffer_rendering: $PASS/18 ok"
