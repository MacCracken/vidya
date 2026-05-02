#!/usr/bin/env bash
# Vidya — Render Graph Architecture in Shell (Bash)
#
# Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

set -uo pipefail

readonly PASS_CAP=16

declare -a PASS_ID READS WRITES TOPO_ORDER
COUNT=0
TOPO_LEN=0

graph_init() {
    local i
    for (( i = 0; i < PASS_CAP; i++ )); do
        PASS_ID[i]=0; READS[i]=0; WRITES[i]=0; TOPO_ORDER[i]=0
    done
    COUNT=0
    TOPO_LEN=0
}

# add_pass ID READS WRITES -> sets ADD_OUT
add_pass() {
    if (( COUNT >= PASS_CAP )); then ADD_OUT=-1; return; fi
    local idx=$COUNT
    PASS_ID[idx]=$1
    READS[idx]=$2
    WRITES[idx]=$3
    COUNT=$((COUNT + 1))
    ADD_OUT=$idx
}

# has_edge PRODUCER CONSUMER -> sets EDGE_OUT (0 or 1)
has_edge() {
    local p=$1 c=$2
    if (( (WRITES[p] & READS[c]) != 0 )); then EDGE_OUT=1; else EDGE_OUT=0; fi
}

# topo_sort -> sets TOPO_LEN
topo_sort() {
    local -a in_degree
    local i j k c
    for (( i = 0; i < PASS_CAP; i++ )); do in_degree[i]=0; done
    for (( i = 0; i < COUNT; i++ )); do
        for (( j = 0; j < COUNT; j++ )); do
            if (( i != j )); then
                has_edge $j $i
                (( EDGE_OUT == 1 )) && in_degree[i]=$((in_degree[i] + 1))
            fi
        done
    done
    TOPO_LEN=0
    local emitted=0
    while (( emitted < COUNT )); do
        local picked=-1
        for (( k = 0; k < COUNT; k++ )); do
            if (( in_degree[k] == 0 )); then picked=$k; break; fi
        done
        if (( picked < 0 )); then return; fi
        TOPO_ORDER[TOPO_LEN]=$picked
        TOPO_LEN=$((TOPO_LEN + 1))
        in_degree[picked]=-1
        for (( c = 0; c < COUNT; c++ )); do
            if (( c != picked )); then
                has_edge $picked $c
                if (( EDGE_OUT == 1 && in_degree[c] > 0 )); then
                    in_degree[c]=$((in_degree[c] - 1))
                fi
            fi
        done
        emitted=$((emitted + 1))
    done
}

# barrier_count -> sets BARRIER_OUT
barrier_count() {
    local count=0 i j
    for (( i = 0; i < TOPO_LEN; i++ )); do
        for (( j = i + 1; j < TOPO_LEN; j++ )); do
            has_edge ${TOPO_ORDER[i]} ${TOPO_ORDER[j]}
            (( EDGE_OUT == 1 )) && count=$((count + 1))
        done
    done
    BARRIER_OUT=$count
}

# cull_dead -> sets CULL_OUT
cull_dead() {
    local culled=0 i j w any
    for (( i = 0; i < COUNT; i++ )); do
        w=${WRITES[i]}
        (( w == 0 )) && continue
        any=0
        for (( j = 0; j < COUNT; j++ )); do
            if (( i != j && (w & READS[j]) != 0 )); then any=1; break; fi
        done
        if (( any == 0 )); then
            WRITES[i]=0; READS[i]=0
            culled=$((culled + 1))
        fi
    done
    CULL_OUT=$culled
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

graph_init
add_pass 100 0 1; check $ADD_OUT 0 "a"
add_pass 101 1 2; check $ADD_OUT 1 "b"
add_pass 102 2 0; check $ADD_OUT 2 "c"

topo_sort
check $TOPO_LEN 3 "topo3"
check ${TOPO_ORDER[0]} 0 "topo[0]"
check ${TOPO_ORDER[1]} 1 "topo[1]"
check ${TOPO_ORDER[2]} 2 "topo[2]"

barrier_count
check $BARRIER_OUT 2 "barriers"

add_pass 103 0 4; check $ADD_OUT 3 "d"
cull_dead; check $CULL_OUT 1 "cull"
check ${WRITES[3]} 0 "writes zeroed"

topo_sort; check $TOPO_LEN 4 "topo4"
barrier_count; check $BARRIER_OUT 2 "barriers post-cull"

graph_init
add_pass 200 1 2
add_pass 201 2 1
topo_sort; check $TOPO_LEN 0 "cycle"

echo "render_graph_architecture: $PASS/14 ok"
