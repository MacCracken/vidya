#!/usr/bin/env bash
# Vidya — Bindless Resources in Shell (Bash)
#
# In-memory descriptor table — "one global table per frame" pattern.
# Handles are (generation << 8) | slot, as concept.toml's "tagged opaque
# handles" best practice says: freeing a slot bumps its generation, so a
# stale handle (or a double free) is detected instead of silently resolving
# to whatever descriptor reused the slot. Slot 0 is the null handle.

set -uo pipefail

readonly TABLE_CAP=64

declare -a SLOTS FREE_LINKS GEN LIVE
NEXT_ID=1
FREE_HEAD=0

table_init() {
    local i
    for (( i = 0; i < TABLE_CAP; i++ )); do
        SLOTS[i]=0
        FREE_LINKS[i]=0
        GEN[i]=0
        LIVE[i]=0
    done
    NEXT_ID=1
    FREE_HEAD=0
}

# alloc DESC -> sets ALLOC_OUT (a handle; 0 = table full)
alloc_handle() {
    local desc=$1 id
    if (( FREE_HEAD != 0 )); then
        id=$FREE_HEAD
        FREE_HEAD=${FREE_LINKS[id]}
    elif (( NEXT_ID >= TABLE_CAP )); then
        ALLOC_OUT=0
        return 0
    else
        id=$NEXT_ID
        NEXT_ID=$((NEXT_ID + 1))
    fi
    SLOTS[id]=$desc
    LIVE[id]=1
    ALLOC_OUT=$(( (GEN[id] << 8) | id ))
}

# live_index HANDLE -> sets IDX_OUT to the slot, or 0 if the handle is null,
# out of range, freed, or from an older generation of its slot.
live_index() {
    local h=$1
    local id=$(( h & 0xFF )) gen=$(( h >> 8 ))
    if (( id == 0 || id >= TABLE_CAP || LIVE[id] == 0 || GEN[id] != gen )); then
        IDX_OUT=0; return
    fi
    IDX_OUT=$id
}

lookup_handle() {
    live_index "$1"
    if (( IDX_OUT == 0 )); then LOOKUP_OUT=0; return; fi
    LOOKUP_OUT=${SLOTS[IDX_OUT]}
}

update_handle() {
    local desc=$2
    live_index "$1"
    if (( IDX_OUT == 0 )); then UPDATE_OUT=0; return; fi
    SLOTS[IDX_OUT]=$desc
    UPDATE_OUT=1
}

free_handle() {
    live_index "$1"
    local id=$IDX_OUT
    if (( id == 0 )); then FREE_OUT=0; return; fi   # stale or double free
    LIVE[id]=0
    GEN[id]=$(( GEN[id] + 1 ))
    FREE_LINKS[id]=$FREE_HEAD
    FREE_HEAD=$id
    SLOTS[id]=0
    FREE_OUT=1
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

table_init

# Test 1
alloc_handle 11111; id1=$ALLOC_OUT
alloc_handle 22222; id2=$ALLOC_OUT
alloc_handle 33333; id3=$ALLOC_OUT
check $id1 1 "id1"
check $id2 2 "id2"
check $id3 3 "id3"

# Test 2
lookup_handle 0; check $LOOKUP_OUT 0 "slot 0"

# Test 3
lookup_handle $id1; check $LOOKUP_OUT 11111 "lookup1"
lookup_handle $id2; check $LOOKUP_OUT 22222 "lookup2"
lookup_handle $id3; check $LOOKUP_OUT 33333 "lookup3"

# Test 4
update_handle $id2 99999; check $UPDATE_OUT 1 "update"
lookup_handle $id2; check $LOOKUP_OUT 99999 "id2 new"
lookup_handle $id1; check $LOOKUP_OUT 11111 "id1 unchanged"
lookup_handle $id3; check $LOOKUP_OUT 33333 "id3 unchanged"

# Test 5: the slot is reused, but under a NEW handle; the old one stays dead
free_handle $id2
lookup_handle $id2; check $LOOKUP_OUT 0 "freed"
alloc_handle 44444; id4=$ALLOC_OUT
check $(( (id4 & 0xFF) == (id2 & 0xFF) && id4 != id2 )) 1 "slot reused under a new generation"
lookup_handle $id4; check $LOOKUP_OUT 44444 "reused desc"
lookup_handle $id2; check $LOOKUP_OUT 0 "stale handle rejected after reuse"
free_handle $id2; check $FREE_OUT 0 "double free rejected"

# Test 6
table_init
for (( i = 1; i < TABLE_CAP; i++ )); do alloc_handle $i; done
alloc_handle 55555; check $ALLOC_OUT 0 "exhausted"

echo "bindless_resources: $PASS/17 ok"
