#!/usr/bin/env bash
# Vidya — Direct DRM GPU Compute in Shell (Bash)
#
# In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

set -uo pipefail

readonly BO_CAP=32
readonly VA_CAP=32

declare -a BO_SIZE VA_ADDR VA_BO
FD=0
NEXT_BO=1
VA_COUNT=0
NEXT_SEQ=1
COMPLETED_SEQ=0

dev_init() {
    local i
    for (( i = 0; i < BO_CAP; i++ )); do BO_SIZE[i]=0; done
    for (( i = 0; i < VA_CAP; i++ )); do VA_ADDR[i]=0; VA_BO[i]=0; done
    FD=0; NEXT_BO=1; VA_COUNT=0; NEXT_SEQ=1; COMPLETED_SEQ=0
}

open_render_node() { FD=42; OUT=$FD; }

gem_create() {
    local size=$1
    if (( NEXT_BO >= BO_CAP )); then OUT=0; return; fi
    local h=$NEXT_BO
    NEXT_BO=$((NEXT_BO + 1))
    BO_SIZE[h]=$size
    OUT=$h
}

gem_destroy() {
    local h=$1
    if (( h == 0 || h >= BO_CAP )); then OUT=0; return; fi
    if (( BO_SIZE[h] == 0 )); then OUT=0; return; fi
    BO_SIZE[h]=0
    local i
    for (( i = 0; i < VA_COUNT; i++ )); do
        (( VA_BO[i] == h )) && VA_BO[i]=0
    done
    OUT=1
}

gem_va_map() {
    local h=$1 va=$2
    if (( h == 0 || h >= BO_CAP )); then OUT=0; return; fi
    if (( BO_SIZE[h] == 0 )); then OUT=0; return; fi
    if (( VA_COUNT >= VA_CAP )); then OUT=0; return; fi
    VA_ADDR[VA_COUNT]=$va
    VA_BO[VA_COUNT]=$h
    VA_COUNT=$((VA_COUNT + 1))
    OUT=1
}

va_lookup() {
    local va=$1 i
    for (( i = 0; i < VA_COUNT; i++ )); do
        if (( VA_ADDR[i] == va && VA_BO[i] != 0 )); then OUT=${VA_BO[i]}; return; fi
    done
    OUT=0
}

submit() {
    local h=$1
    if (( h == 0 || h >= BO_CAP )); then OUT=0; return; fi
    if (( BO_SIZE[h] == 0 )); then OUT=0; return; fi
    local seq=$NEXT_SEQ
    NEXT_SEQ=$((NEXT_SEQ + 1))
    COMPLETED_SEQ=$seq
    OUT=$seq
}

syncobj_wait() {
    local seq=$1
    if (( COMPLETED_SEQ >= seq )); then OUT=1; else OUT=0; fi
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

dev_init
open_render_node; [[ $OUT -ne 0 ]] && PASS=$((PASS+1)) || { echo "FAIL fd"; exit 1; }

gem_create 4096; b1=$OUT; check $b1 1 "b1"
gem_create 8192; b2=$OUT; check $b2 2 "b2"
gem_create 16384; b3=$OUT; check $b3 3 "b3"

gem_va_map $b1 4096; check $OUT 1 "map b1"
gem_va_map $b2 8192; check $OUT 1 "map b2"

va_lookup 4096; check $OUT $b1 "lookup b1"
va_lookup 8192; check $OUT $b2 "lookup b2"
va_lookup 36864; check $OUT 0 "unmapped"

gem_va_map 99 12288; check $OUT 0 "invalid"
gem_va_map 0 12288; check $OUT 0 "handle 0"

submit $b1; check $OUT 1 "seq 1"
submit $b2; check $OUT 2 "seq 2"
submit $b3; check $OUT 3 "seq 3"

syncobj_wait 1; check $OUT 1 "wait 1"
syncobj_wait 3; check $OUT 1 "wait 3"
syncobj_wait 99; check $OUT 0 "wait future"

gem_destroy $b1
va_lookup 4096; check $OUT 0 "destroyed va"

submit $b1; check $OUT 0 "submit destroyed"
submit $b2; check $OUT 4 "next valid"

echo "direct_drm_gpu_compute: $PASS/20 ok"
