#!/usr/bin/env bash
# Vidya — Consensus and Raft — Bash port.
# All helpers return via the `_RET` global, never via stdout, because
# `$(...)` runs in a subshell and discards array mutations on exit
# (cyrius field-note "subshell_clobbers_stateful_helpers").

set -euo pipefail

N_NODES=3
MAX_LOG=8
QUORUM=2

ROLE_FOLLOWER=0
ROLE_CANDIDATE=1
ROLE_LEADER=2

declare -a role term voted_for log_count commit_idx
declare -a log_terms log_values    # flat: n * MAX_LOG + i

_RET=0

cluster_init() {
    local i
    for (( i=0; i<N_NODES; i++ )); do
        role[i]=$ROLE_FOLLOWER
        term[i]=0
        voted_for[i]=-1
        log_count[i]=0
        commit_idx[i]=-1
    done
    # Zero log buffers (8 slots × 3 nodes = 24 slots)
    for (( i=0; i<24; i++ )); do
        log_terms[i]=0
        log_values[i]=0
    done
}

last_log_index() { _RET=$(( log_count[$1] - 1 )); }
last_log_term() {
    local n=$1
    if [[ ${log_count[n]} -eq 0 ]]; then _RET=0; return; fi
    local idx=$(( log_count[n] - 1 ))
    _RET=${log_terms[$(( n * MAX_LOG + idx ))]}
}

# log_up_to_date c_term c_idx v_term v_idx
log_up_to_date() {
    if [[ $1 -gt $3 ]]; then _RET=1; return; fi
    if [[ $1 -lt $3 ]]; then _RET=0; return; fi
    if [[ $2 -ge $4 ]]; then _RET=1; else _RET=0; fi
}

start_election() {
    local n=$1
    term[n]=$(( term[n] + 1 ))
    voted_for[n]=$n
    role[n]=$ROLE_CANDIDATE
    _RET=${term[n]}
}

# request_vote voter candidate c_term c_last_term c_last_idx
request_vote() {
    local voter=$1 cand=$2 cT=$3 cLT=$4 cLI=$5
    if [[ $cT -lt ${term[voter]} ]]; then _RET=0; return; fi
    if [[ $cT -gt ${term[voter]} ]]; then
        term[voter]=$cT
        voted_for[voter]=-1
        role[voter]=$ROLE_FOLLOWER
    fi
    if [[ ${voted_for[voter]} -ne -1 && ${voted_for[voter]} -ne $cand ]]; then
        _RET=0; return
    fi
    last_log_term "$voter"; local vLT=$_RET
    last_log_index "$voter"; local vLI=$_RET
    log_up_to_date "$cLT" "$cLI" "$vLT" "$vLI"
    if [[ $_RET -eq 0 ]]; then _RET=0; return; fi
    voted_for[voter]=$cand
    _RET=1
}

run_election() {
    local cand=$1 votes=1 v
    local cT=${term[cand]}
    last_log_term "$cand"; local cLT=$_RET
    last_log_index "$cand"; local cLI=$_RET
    for (( v=0; v<N_NODES; v++ )); do
        if [[ $v -eq $cand ]]; then continue; fi
        request_vote "$v" "$cand" "$cT" "$cLT" "$cLI"
        if [[ $_RET -eq 1 ]]; then votes=$(( votes + 1 )); fi
    done
    if [[ $votes -ge $QUORUM ]]; then role[cand]=$ROLE_LEADER; fi
    _RET=$votes
}

append_entry() {
    local leader=$1 value=$2
    if [[ ${log_count[leader]} -ge $MAX_LOG ]]; then _RET=-1; return; fi
    local idx=${log_count[leader]}
    local pos=$(( leader * MAX_LOG + idx ))
    log_terms[pos]=${term[leader]}
    log_values[pos]=$value
    log_count[leader]=$(( idx + 1 ))
    _RET=$idx
}

replicate() {
    local leader=$1 follower=$2 i lc
    lc=${log_count[leader]}
    for (( i=0; i<lc; i++ )); do
        local lt=${log_terms[$(( leader * MAX_LOG + i ))]}
        local lv=${log_values[$(( leader * MAX_LOG + i ))]}
        if [[ $i -lt ${log_count[follower]} ]]; then
            local ft=${log_terms[$(( follower * MAX_LOG + i ))]}
            if [[ $ft -ne $lt ]]; then log_count[follower]=$i; fi
        fi
        if [[ $i -ge ${log_count[follower]} ]]; then
            log_terms[$(( follower * MAX_LOG + i ))]=$lt
            log_values[$(( follower * MAX_LOG + i ))]=$lv
            log_count[follower]=$(( i + 1 ))
        fi
    done
    _RET=${log_count[follower]}
}

count_matching() {
    local leader=$1 idx=$2 n count=0
    local lt=${log_terms[$(( leader * MAX_LOG + idx ))]}
    for (( n=0; n<N_NODES; n++ )); do
        if [[ ${log_count[n]} -gt $idx ]]; then
            local t=${log_terms[$(( n * MAX_LOG + idx ))]}
            if [[ $t -eq $lt ]]; then count=$(( count + 1 )); fi
        fi
    done
    _RET=$count
}

advance_commit() {
    local leader=$1
    local cur=${term[leader]}
    local idx
    for (( idx=commit_idx[leader]+1; idx<log_count[leader]; idx++ )); do
        local t=${log_terms[$(( leader * MAX_LOG + idx ))]}
        if [[ $t -eq $cur ]]; then
            count_matching "$leader" "$idx"
            if [[ $_RET -ge $QUORUM ]]; then commit_idx[leader]=$idx; fi
        fi
    done
    _RET=${commit_idx[leader]}
}

pass_count=0
fail_count=0
check() {
    if [[ $1 -eq 1 ]]; then pass_count=$(( pass_count + 1 )); else
        fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2
    fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }

# Test 1: init state
cluster_init
for (( n=0; n<N_NODES; n++ )); do eq "${role[n]}" "$ROLE_FOLLOWER"; check $_RET "follower"; done
eq "${term[0]}" 0;       check $_RET "term=0"
eq "${voted_for[0]}" -1; check $_RET "voted_for=-1"
eq "${log_count[0]}" 0;  check $_RET "empty log"
eq "${commit_idx[0]}" -1; check $_RET "nothing committed"

# Test 2: single-node election
cluster_init
start_election 0;        eq $_RET 1; check $_RET "term=1"
run_election 0;          eq $_RET 3; check $_RET "3 votes"
eq "${role[0]}" "$ROLE_LEADER"; check $_RET "node 0 LEADER"
eq "${term[1]}" 1;       check $_RET "follower 1 term updated"
eq "${voted_for[1]}" 0;  check $_RET "follower 1 voted 0"

# Test 3: stale RPC
cluster_init
term[1]=5
request_vote 1 0 1 0 -1; eq $_RET 0; check $_RET "stale rejected"
eq "${term[1]}" 5;       check $_RET "voter term unchanged"

# Test 4: higher-term steps down
cluster_init
start_election 0
run_election 0
eq "${role[0]}" "$ROLE_LEADER"; check $_RET "leader"
request_vote 0 2 5 0 -1; eq $_RET 1; check $_RET "higher-term granted"
eq "${term[0]}" 5;       check $_RET "term=5"
eq "${role[0]}" "$ROLE_FOLLOWER"; check $_RET "stepped down"

# Test 5: vote uniqueness
cluster_init
request_vote 2 0 1 0 -1; eq $_RET 1; check $_RET "first vote"
request_vote 2 1 1 0 -1; eq $_RET 0; check $_RET "second denied"
eq "${voted_for[2]}" 0;  check $_RET "voted_for unchanged"

# Test 6: log replication and match
cluster_init
start_election 0; run_election 0
append_entry 0 100
append_entry 0 200
append_entry 0 300
replicate 0 1; eq $_RET 3; check $_RET "3 replicated"
for (( i=0; i<3; i++ )); do
    lt0=${log_terms[$(( 0 * MAX_LOG + i ))]}
    lt1=${log_terms[$(( 1 * MAX_LOG + i ))]}
    lv0=${log_values[$(( 0 * MAX_LOG + i ))]}
    lv1=${log_values[$(( 1 * MAX_LOG + i ))]}
    if [[ $lt0 -eq $lt1 && $lv0 -eq $lv1 ]]; then check 1 "match $i"; else check 0 "match $i"; fi
done

# Test 7: commit on majority
cluster_init
start_election 0; run_election 0
append_entry 0 42
replicate 0 1
advance_commit 0; eq $_RET 0; check $_RET "commit_idx → 0"
append_entry 0 99
advance_commit 0; eq $_RET 0; check $_RET "stays at 0"
replicate 0 2
advance_commit 0; eq $_RET 1; check $_RET "commit_idx → 1"

# Test 8: log up-to-date blocks stale candidate
cluster_init
start_election 0; run_election 0
append_entry 0 10
append_entry 0 20
term[1]=4
start_election 1; t=$_RET
request_vote 0 1 "$t" 0 -1; eq $_RET 0; check $_RET "shorter-log denied"
eq "${term[0]}" "$t";    check $_RET "term advanced"
eq "${role[0]}" "$ROLE_FOLLOWER"; check $_RET "stepped down"

# Test 9: indirect commit of prior term
cluster_init
start_election 0; run_election 0
append_entry 0 100
replicate 0 1
advance_commit 0
eq "${commit_idx[0]}" 0; check $_RET "term-1 committed"
start_election 1; t2=$_RET
eq "$t2" 2;              check $_RET "term=2"
run_election 1; votes=$_RET
[[ $votes -ge $QUORUM ]] && check 1 "node 1 wins" || check 0 "node 1 wins"
eq "${role[1]}" "$ROLE_LEADER"; check $_RET "leader"
append_entry 1 200
replicate 1 2
advance_commit 1
eq "${commit_idx[1]}" 1; check $_RET "term-2 commits and drags term-1 forward"
eq "${log_terms[$(( 1 * MAX_LOG + 0 ))]}" 1; check $_RET "idx 0 term-1"
eq "${log_terms[$(( 1 * MAX_LOG + 1 ))]}" 2; check $_RET "idx 1 term-2"

# Test 10: term monotonicity
cluster_init
start_election 0; t1=${term[0]}
start_election 0; t2=${term[0]}
[[ $t2 -gt $t1 ]] && check 1 "term increases" || check 0 "term increases"
request_vote 0 1 1 0 -1; eq $_RET 0; check $_RET "stale denied"
eq "${term[0]}" "$t2"; check $_RET "term not decremented"

echo "=== consensus ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
