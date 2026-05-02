#!/usr/bin/env bash
# Vidya — Explicit GPU Synchronization in Shell (Bash)
#
# Timeline semaphores — monotonic counters with signal/wait/wait_all.

set -uo pipefail

SEM_COMPUTE=0
SEM_TRANSFER=0

sem_reset() { SEM_COMPUTE=0; SEM_TRANSFER=0; }

# signal SEM VALUE -> sets SIG_OUT
signal() {
    local sem=$1 value=$2
    if (( sem == 0 )); then
        if (( value <= SEM_COMPUTE )); then SIG_OUT=0; return; fi
        SEM_COMPUTE=$value; SIG_OUT=1; return
    fi
    if (( sem == 1 )); then
        if (( value <= SEM_TRANSFER )); then SIG_OUT=0; return; fi
        SEM_TRANSFER=$value; SIG_OUT=1; return
    fi
    SIG_OUT=0
}

# wait_for SEM TARGET -> sets WAIT_OUT
wait_for() {
    local sem=$1 target=$2
    if (( sem == 0 )); then
        if (( SEM_COMPUTE >= target )); then WAIT_OUT=1; else WAIT_OUT=0; fi
        return
    fi
    if (( sem == 1 )); then
        if (( SEM_TRANSFER >= target )); then WAIT_OUT=1; else WAIT_OUT=0; fi
        return
    fi
    WAIT_OUT=0
}

# wait_all C_TARGET T_TARGET -> sets WAIT_ALL_OUT
wait_all() {
    local c=$1 t=$2
    wait_for 0 $c; local cok=$WAIT_OUT
    wait_for 1 $t; local tok=$WAIT_OUT
    if (( cok == 1 && tok == 1 )); then WAIT_ALL_OUT=1; else WAIT_ALL_OUT=0; fi
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

# 1: init
check $SEM_COMPUTE 0 "init compute"
check $SEM_TRANSFER 0 "init transfer"
wait_for 0 0; check $WAIT_OUT 1 "wait(0,0)"

# 2: signal advances
signal 0 5; check $SIG_OUT 1 "signal 5"
check $SEM_COMPUTE 5 "compute=5"

# 3: past, current, future
wait_for 0 3; check $WAIT_OUT 1 "past"
wait_for 0 5; check $WAIT_OUT 1 "current"
wait_for 0 10; check $WAIT_OUT 0 "future"

# 4: regression rejected
signal 0 3; check $SIG_OUT 0 "regress 3"
check $SEM_COMPUTE 5 "after regress"
signal 0 5; check $SIG_OUT 0 "regress 5"

# 5: multi-sem
signal 1 3
check $SEM_TRANSFER 3 "transfer=3"
wait_all 5 3; check $WAIT_ALL_OUT 1 "all 5,3"
wait_all 5 4; check $WAIT_ALL_OUT 0 "all 5,4"
wait_all 6 3; check $WAIT_ALL_OUT 0 "all 6,3"
wait_all 0 0; check $WAIT_ALL_OUT 1 "all 0,0"

# 6: monotonic
sem_reset
for i in 1 2 3 4 5 6 7 8 9 10; do signal 0 $i; done
check $SEM_COMPUTE 10 "monotonic 10"
wait_for 0 10; check $WAIT_OUT 1 "final"
wait_for 0 11; check $WAIT_OUT 0 "beyond"

echo "explicit_gpu_synchronization: $PASS/19 ok"
