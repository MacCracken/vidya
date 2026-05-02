#!/usr/bin/env bash
# Vidya — Sprite Rendering in Shell (Bash)
#
# Bash treats every value as a string; a 76,800-element associative-
# array framebuffer is achievable but pathologically slow. We compress
# the demo to a 16x16 (256-byte) logical framebuffer stored as a single
# indexed array of integers, indexed `fb[y*W + x]`. The blit/clip/scale
# logic is bit-for-bit identical to the C/Cyrius port — only the
# canvas size differs. Constants SCREEN_W/SCREEN_H/FB_SIZE are scaled
# down accordingly. Tests still cover clear/blit/transparency/clipping/
# scaled/depth-sort/scaled-shrink.

set -euo pipefail

# Scaled-down framebuffer for tractable bash performance.
readonly SCREEN_W=16
readonly SCREEN_H=16
readonly FB_SIZE=$(( SCREEN_W * SCREEN_H ))   # 256
readonly COLOR_KEY=0
readonly FX_SHIFT=16

# Framebuffer: indexed array of integers (one per pixel).
declare -a FB
for ((i = 0; i < FB_SIZE; i++)); do FB[i]=0; done

# Test sprite (4x4) flattened into an indexed array.
SPRITE_W=4
SPRITE_H=4
SPRITE=(
    0 1 1 0
    1 2 2 1
    1 2 2 1
    0 1 1 0
)

fb_clear() {
    local color=$1
    for ((i = 0; i < FB_SIZE; i++)); do FB[i]=$color; done
}

fb_get() {
    local x=$1 y=$2
    if (( x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H )); then
        echo 0; return
    fi
    echo "${FB[y*SCREEN_W + x]}"
}

fb_set() {
    local x=$1 y=$2 color=$3
    if (( x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H )); then
        return
    fi
    FB[y*SCREEN_W + x]=$color
}

blit() {
    local dst_x=$1 dst_y=$2
    local start_x=0 start_y=0
    local end_x=$SPRITE_W end_y=$SPRITE_H
    if (( dst_x < 0 )); then start_x=$((-dst_x)); dst_x=0; fi
    if (( dst_y < 0 )); then start_y=$((-dst_y)); dst_y=0; fi
    if (( dst_x + (end_x - start_x) > SCREEN_W )); then
        end_x=$(( start_x + (SCREEN_W - dst_x) ))
    fi
    if (( dst_y + (end_y - start_y) > SCREEN_H )); then
        end_y=$(( start_y + (SCREEN_H - dst_y) ))
    fi
    local sy sx pixel dx dy
    for ((sy = start_y; sy < end_y; sy++)); do
        for ((sx = start_x; sx < end_x; sx++)); do
            pixel=${SPRITE[sy*SPRITE_W + sx]}
            if (( pixel != COLOR_KEY )); then
                dx=$(( dst_x + (sx - start_x) ))
                dy=$(( dst_y + (sy - start_y) ))
                FB[dy*SCREEN_W + dx]=$pixel
            fi
        done
    done
}

blit_scaled() {
    local dst_x=$1 dst_y=$2 dst_w=$3 dst_h=$4
    if (( dst_w <= 0 || dst_h <= 0 )); then return; fi
    local step_x=$(( (SPRITE_W << FX_SHIFT) / dst_w ))
    local step_y=$(( (SPRITE_H << FX_SHIFT) / dst_h ))
    local src_y=0
    local dy screen_y row_base src_x dx screen_x pixel
    for ((dy = 0; dy < dst_h; dy++)); do
        screen_y=$(( dst_y + dy ))
        if (( screen_y >= 0 && screen_y < SCREEN_H )); then
            row_base=$(( (src_y >> FX_SHIFT) * SPRITE_W ))
            src_x=0
            for ((dx = 0; dx < dst_w; dx++)); do
                screen_x=$(( dst_x + dx ))
                if (( screen_x >= 0 && screen_x < SCREEN_W )); then
                    pixel=${SPRITE[row_base + (src_x >> FX_SHIFT)]}
                    if (( pixel != COLOR_KEY )); then
                        FB[screen_y*SCREEN_W + screen_x]=$pixel
                    fi
                fi
                src_x=$(( src_x + step_x ))
            done
        fi
        src_y=$(( src_y + step_y ))
    done
}

assert_eq() {
    local got=$1 want=$2 msg=$3
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got' want '$want'" >&2
        exit 1
    fi
}

# ── Tests ─────────────────────────────────────────────────────────────

# clear
fb_clear 42
assert_eq "$(fb_get 5 5)"   42 "clear fills framebuffer"
assert_eq "$(fb_get 0 0)"   42 "clear fills corner"
assert_eq "$(fb_get $((SCREEN_W-1)) $((SCREEN_H-1)))" 42 "clear fills last pixel"

# blit opaque
fb_clear 0
blit 4 4
assert_eq "$(fb_get 5 5)" 2 "blit center"
assert_eq "$(fb_get 6 5)" 2 "blit adjacent center"

# transparency
fb_clear 99
blit 4 4
assert_eq "$(fb_get 4 4)" 99 "transparent corner preserves bg"
assert_eq "$(fb_get 7 4)" 99 "top-right transparent"
assert_eq "$(fb_get 5 4)" 1  "non-transparent written"

# clipping right (sprite at x=14, only 2 cols visible)
fb_clear 0
blit 14 0
assert_eq "$(fb_get 15 1)" 2 "clipped sprite visible at right edge"
assert_eq "$(fb_get 14 0)" 0 "clipped transparent pixel"

# clipping left (sprite at x=-2, right 2 cols visible)
fb_clear 0
blit -2 0
assert_eq "$(fb_get 0 1)" 2 "left-clipped sprite visible"

# scaled blit (4x4 → 8x8)
fb_clear 0
blit_scaled 2 2 8 8
assert_eq "$(fb_get 4 4)" 2 "2x scaled center pixel"
assert_eq "$(fb_get 5 5)" 2 "2x scaled adjacent center"

# depth sort (painter's algorithm)
fb_clear 0
blit 6 6
assert_eq "$(fb_get 7 7)" 2 "first sprite drawn"
fb_set 7 7 7
assert_eq "$(fb_get 7 7)" 7 "later draw overwrites"

# scaled shrink (4x4 → 2x2)
fb_clear 0
blit_scaled 10 10 2 2
any_drawn=0
[[ "$(fb_get 10 10)" != "0" ]] && any_drawn=1
[[ "$(fb_get 11 10)" != "0" ]] && any_drawn=1
[[ "$(fb_get 10 11)" != "0" ]] && any_drawn=1
[[ "$(fb_get 11 11)" != "0" ]] && any_drawn=1
assert_eq "$any_drawn" "1" "shrunk sprite has visible pixels"

echo "All sprite_rendering examples passed."
