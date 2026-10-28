#!/usr/bin/env bash
# Vidya — Distributed Systems Foundations — Bash port.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

N_NODES=3
W=2
R=2

VC_LESS=1
VC_EQUAL=2
VC_GREATER=3
VC_CONCURRENT=4

# Vector clocks are stored in named arrays passed as references via
# `declare -n`. Components: vc[0], vc[1], vc[2].

_RET=0

vc_init() {
    local -n vc=$1
    vc=(0 0 0)
}

vc_tick() {
    local -n vc=$1
    local node=$2
    vc[node]=$(( vc[node] + 1 ))
}

vc_merge() {
    local -n into=$1
    local -n from=$2
    local i
    for (( i=0; i<N_NODES; i++ )); do
        if [[ ${from[i]} -gt ${into[i]} ]]; then into[i]=${from[i]}; fi
    done
}

vc_compare() {
    local -n a=$1
    local -n b=$2
    local any_lt=0 any_gt=0 i
    for (( i=0; i<N_NODES; i++ )); do
        if [[ ${a[i]} -lt ${b[i]} ]]; then any_lt=1; fi
        if [[ ${a[i]} -gt ${b[i]} ]]; then any_gt=1; fi
    done
    if [[ $any_lt -eq 0 && $any_gt -eq 0 ]]; then _RET=$VC_EQUAL; return; fi
    if [[ $any_lt -eq 0 ]]; then _RET=$VC_GREATER; return; fi
    if [[ $any_gt -eq 0 ]]; then _RET=$VC_LESS; return; fi
    _RET=$VC_CONCURRENT
}

# Quorum cluster: flat globals, since `declare -n` for parallel
# arrays at struct-of-arrays scale gets unwieldy.
declare -a accounts write_seq alive
global_seq=0

qc_init() {
    local i
    for (( i=0; i<N_NODES; i++ )); do
        accounts[i]=0
        write_seq[i]=0
        alive[i]=1
    done
    global_seq=0
}

qc_partition() { alive[$1]=0; }
qc_heal()      { alive[$1]=1; }

qc_alive_count() {
    local c=0 i
    for (( i=0; i<N_NODES; i++ )); do c=$(( c + alive[i] )); done
    _RET=$c
}

qc_write() {
    local value=$1
    qc_alive_count
    if [[ $_RET -lt $W ]]; then _RET=0; return; fi
    global_seq=$(( global_seq + 1 ))
    local i
    for (( i=0; i<N_NODES; i++ )); do
        if [[ ${alive[i]} -eq 1 ]]; then
            accounts[i]=$value
            write_seq[i]=$global_seq
        fi
    done
    _RET=1
}

qc_read() {
    qc_alive_count
    if [[ $_RET -lt $R ]]; then _RET=-1; return; fi
    local best_seq=0 best_value=0 i
    for (( i=0; i<N_NODES; i++ )); do
        if [[ ${alive[i]} -eq 1 && ${write_seq[i]} -gt $best_seq ]]; then
            best_seq=${write_seq[i]}
            best_value=${accounts[i]}
        fi
    done
    _RET=$best_value
}

pass_count=0
fail_count=0
check() {
    if [[ $1 -eq 1 ]]; then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }

vc_eq3() {
    local -n vc=$1
    local a=$2 b=$3 c=$4
    if [[ ${vc[0]} -eq $a && ${vc[1]} -eq $b && ${vc[2]} -eq $c ]]; then _RET=1; else _RET=0; fi
}

# Test 1: vc init
declare -a vca vcb
vc_init vca
vc_eq3 vca 0 0 0; check $_RET "vc init zero"

# Test 2: vc tick
vc_init vca
vc_tick vca 1; vc_tick vca 1; vc_tick vca 2
vc_eq3 vca 0 2 1; check $_RET "tick"

# Test 3: vc merge
vc_init vca; vc_init vcb
vc_tick vca 0; vc_tick vca 0
vc_tick vcb 1; vc_tick vcb 2
vc_merge vca vcb
vc_eq3 vca 2 1 1; check $_RET "merge max"

# Test 4: less
vc_init vca; vc_init vcb
vc_tick vcb 0
vc_compare vca vcb; eq $_RET $VC_LESS; check $_RET "less"

# Test 5: greater
vc_init vca; vc_init vcb
vc_tick vca 0; vc_tick vca 0; vc_tick vcb 0
vc_compare vca vcb; eq $_RET $VC_GREATER; check $_RET "greater"

# Test 6: equal
vc_init vca; vc_init vcb
vc_tick vca 1; vc_tick vcb 1
vc_compare vca vcb; eq $_RET $VC_EQUAL; check $_RET "equal"

# Test 7: concurrent
vc_init vca; vc_init vcb
vc_tick vca 0; vc_tick vcb 1
vc_compare vca vcb; eq $_RET $VC_CONCURRENT; check $_RET "concurrent"
vc_compare vcb vca; eq $_RET $VC_CONCURRENT; check $_RET "concurrent symmetric"

# Test 8: write ok full
qc_init
qc_write 100; eq $_RET 1; check $_RET "write ok full"
[[ ${accounts[0]} -eq 100 && ${accounts[1]} -eq 100 && ${accounts[2]} -eq 100 ]] && check 1 "all wrote" || check 0 "all wrote"

# Test 9: write ok with 1 partitioned
qc_init
qc_partition 2
qc_write 200; eq $_RET 1; check $_RET "write ok 2 alive"
[[ ${accounts[0]} -eq 200 && ${accounts[1]} -eq 200 ]] && check 1 "0,1 wrote" || check 0 "0,1 wrote"
eq "${accounts[2]}" 0; check $_RET "2 untouched"

# Test 10: write fails with 2 partitioned
qc_init
qc_partition 1; qc_partition 2
qc_write 300; eq $_RET 0; check $_RET "write fails 1 alive"
eq "${accounts[0]}" 0; check $_RET "no replica wrote"

# Test 11: intersection guarantees latest
qc_init
qc_partition 2
qc_write 500
qc_heal 2
qc_partition 0
qc_read; eq $_RET 500; check $_RET "intersection: read sees latest"

# Test 12: read fails below R
qc_init
qc_write 700
qc_partition 0; qc_partition 1
qc_read; eq $_RET -1; check $_RET "read sentinel below R"

echo "=== distributed_systems ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
