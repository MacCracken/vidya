#!/usr/bin/env bash
# Vidya — GPU Memory Pooling in Shell (Bash)
#
# Bump allocator over a 1024-byte pool.

set -uo pipefail

readonly POOL_SIZE=1024
BUMP=0

pool_reset() { BUMP=0; }
pool_used() { echo $BUMP; }
pool_free() { echo $((POOL_SIZE - BUMP)); }

# pool_alloc SIZE -> sets ALLOC_OUT
pool_alloc() {
    local size=$1
    if (( size == 0 )); then ALLOC_OUT=$BUMP; return; fi
    if (( BUMP + size > POOL_SIZE )); then ALLOC_OUT=-1; return; fi
    ALLOC_OUT=$BUMP
    BUMP=$((BUMP + size))
}

# pool_alloc_aligned SIZE ALIGN
pool_alloc_aligned() {
    local size=$1 align=$2
    local mask=$((align - 1))
    local aligned=$(( (BUMP + mask) & ~mask ))
    if (( aligned + size > POOL_SIZE )); then ALLOC_OUT=-1; return; fi
    BUMP=$((aligned + size))
    ALLOC_OUT=$aligned
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

check $(pool_used) 0 "init used"
check $(pool_free) 1024 "init free"

pool_alloc 100; check $ALLOC_OUT 0 "alloc1"
check $(pool_used) 100 "used1"

pool_alloc 200; check $ALLOC_OUT 100 "alloc2"
check $(pool_used) 300 "used2"

pool_alloc 1000; check $ALLOC_OUT -1 "exhausted"
check $(pool_used) 300 "used unchanged"

pool_reset
check $(pool_used) 0 "reset used"
check $(pool_free) 1024 "reset free"
pool_alloc 50; check $ALLOC_OUT 0 "post reset"

pool_alloc_aligned 32 16; check $ALLOC_OUT 64 "aligned 64"
check $(pool_used) 96 "used 96"

pool_alloc 0; check $ALLOC_OUT 96 "noop"
check $(pool_used) 96 "noop used"

pool_reset
for i in {1..10}; do pool_alloc 8; done
check $(pool_used) 80 "10x8"

echo "gpu_memory_pooling: $PASS/16 ok"
