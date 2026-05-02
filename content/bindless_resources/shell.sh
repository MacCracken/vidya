#!/usr/bin/env bash
# Vidya — Bindless Resources in Shell (Bash)
#
# In-memory descriptor table — "one global table per frame" pattern.

set -uo pipefail

readonly TABLE_CAP=64

declare -a SLOTS FREE_LINKS
NEXT_ID=1
FREE_HEAD=0

table_init() {
    local i
    for (( i = 0; i < TABLE_CAP; i++ )); do
        SLOTS[i]=0
        FREE_LINKS[i]=0
    done
    NEXT_ID=1
    FREE_HEAD=0
}

# alloc DESC -> sets ALLOC_OUT
alloc_handle() {
    local desc=$1
    if (( FREE_HEAD != 0 )); then
        local id=$FREE_HEAD
        FREE_HEAD=${FREE_LINKS[id]}
        SLOTS[id]=$desc
        ALLOC_OUT=$id
        return 0
    fi
    if (( NEXT_ID >= TABLE_CAP )); then
        ALLOC_OUT=0
        return 0
    fi
    local id=$NEXT_ID
    NEXT_ID=$((NEXT_ID + 1))
    SLOTS[id]=$desc
    ALLOC_OUT=$id
}

lookup_handle() {
    local id=$1
    if (( id == 0 || id >= TABLE_CAP )); then LOOKUP_OUT=0; return; fi
    LOOKUP_OUT=${SLOTS[id]}
}

update_handle() {
    local id=$1 desc=$2
    if (( id == 0 || id >= TABLE_CAP )); then UPDATE_OUT=0; return; fi
    SLOTS[id]=$desc
    UPDATE_OUT=1
}

free_handle() {
    local id=$1
    if (( id == 0 || id >= TABLE_CAP )); then FREE_OUT=0; return; fi
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

# Test 5
free_handle $id2
lookup_handle $id2; check $LOOKUP_OUT 0 "freed"
alloc_handle 44444; id4=$ALLOC_OUT
check $id4 $id2 "reused"
lookup_handle $id4; check $LOOKUP_OUT 44444 "reused desc"

# Test 6
table_init
for (( i = 1; i < TABLE_CAP; i++ )); do alloc_handle $i; done
alloc_handle 55555; check $ALLOC_OUT 0 "exhausted"

echo "bindless_resources: $PASS/15 ok"
