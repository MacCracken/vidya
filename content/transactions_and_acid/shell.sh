#!/usr/bin/env bash
# Vidya — Transactions and ACID — Bash port.
# OCC store with read-set version snapshots.
#
# All helpers return via the `_RET` global, never via stdout, because
# `$(...)` runs in a subshell and discards array mutations on exit.
# This is the cyrius field-note gotcha "subshell_clobbers_stateful_helpers".

set -euo pipefail

N_ACCOUNTS=8
N_TX=2
TX_CAP=4

TX_FREE=0
TX_ACTIVE=1
TX_COMMITTED=2
TX_ABORTED=3

declare -a accounts
declare -a version
declare -a status
declare -a tx_wcount
declare -a tx_wkeys
declare -a tx_wvals
declare -a tx_rcount
declare -a tx_rkeys
declare -a tx_rsnaps

_RET=0

store_init() {
    local i
    for (( i=0; i<N_ACCOUNTS; i++ )); do
        accounts[i]=0
        version[i]=0
    done
    for (( i=0; i<N_TX; i++ )); do
        status[i]=$TX_FREE
        tx_wcount[i]=0
        tx_rcount[i]=0
    done
}

account_set_raw() {
    accounts[$1]=$2
    version[$1]=$(( version[$1] + 1 ))
}

account_total() {
    local sum=0 i
    for (( i=0; i<N_ACCOUNTS; i++ )); do
        sum=$(( sum + accounts[i] ))
    done
    _RET=$sum
}

tx_begin() {
    local t
    for (( t=0; t<N_TX; t++ )); do
        if [[ ${status[t]} -eq $TX_FREE ]]; then
            status[t]=$TX_ACTIVE
            tx_wcount[t]=0
            tx_rcount[t]=0
            _RET=$t
            return
        fi
    done
    _RET=-1
}

# Sets _RET to write-set index, or -1.
tx_find_write() {
    local tx=$1 k=$2 n=${tx_wcount[$1]} i base
    base=$(( tx * TX_CAP ))
    for (( i=0; i<n; i++ )); do
        if [[ ${tx_wkeys[base+i]} -eq $k ]]; then
            _RET=$i
            return
        fi
    done
    _RET=-1
}

# Sets _RET to 1/0.
tx_has_read() {
    local tx=$1 k=$2 n=${tx_rcount[$1]} i base
    base=$(( tx * TX_CAP ))
    for (( i=0; i<n; i++ )); do
        if [[ ${tx_rkeys[base+i]} -eq $k ]]; then
            _RET=1
            return
        fi
    done
    _RET=0
}

tx_read() {
    local tx=$1 k=$2
    if [[ ${status[tx]} -ne $TX_ACTIVE ]]; then _RET=-1; return; fi
    tx_find_write "$tx" "$k"
    local widx=$_RET
    if [[ $widx -ge 0 ]]; then
        _RET=${tx_wvals[$(( tx * TX_CAP + widx ))]}
        return
    fi
    tx_has_read "$tx" "$k"
    if [[ $_RET -eq 0 ]]; then
        local rn=${tx_rcount[tx]}
        if [[ $rn -lt $TX_CAP ]]; then
            local pos=$(( tx * TX_CAP + rn ))
            tx_rkeys[pos]=$k
            tx_rsnaps[pos]=${version[k]}
            tx_rcount[tx]=$(( rn + 1 ))
        fi
    fi
    _RET=${accounts[k]}
}

tx_write() {
    local tx=$1 k=$2 v=$3
    if [[ ${status[tx]} -ne $TX_ACTIVE ]]; then _RET=0; return; fi
    tx_find_write "$tx" "$k"
    local widx=$_RET
    if [[ $widx -ge 0 ]]; then
        tx_wvals[$(( tx * TX_CAP + widx ))]=$v
        _RET=1; return
    fi
    local n=${tx_wcount[tx]}
    if [[ $n -ge $TX_CAP ]]; then _RET=0; return; fi
    local pos=$(( tx * TX_CAP + n ))
    tx_wkeys[pos]=$k
    tx_wvals[pos]=$v
    tx_wcount[tx]=$(( n + 1 ))
    _RET=1
}

tx_validate() {
    local tx=$1 n=${tx_rcount[$1]} i base k snap
    base=$(( tx * TX_CAP ))
    for (( i=0; i<n; i++ )); do
        k=${tx_rkeys[base+i]}
        snap=${tx_rsnaps[base+i]}
        if [[ ${version[k]} -ne $snap ]]; then _RET=0; return; fi
    done
    _RET=1
}

tx_commit() {
    local tx=$1
    if [[ ${status[tx]} -ne $TX_ACTIVE ]]; then _RET=0; return; fi
    tx_validate "$tx"
    if [[ $_RET -eq 0 ]]; then
        status[tx]=$TX_ABORTED
        _RET=0; return
    fi
    local n=${tx_wcount[tx]} i base k v
    base=$(( tx * TX_CAP ))
    for (( i=0; i<n; i++ )); do
        k=${tx_wkeys[base+i]}
        v=${tx_wvals[base+i]}
        accounts[k]=$v
        version[k]=$(( version[k] + 1 ))
    done
    status[tx]=$TX_COMMITTED
    _RET=1
}

tx_abort() {
    local tx=$1
    if [[ ${status[tx]} -ne $TX_ACTIVE ]]; then _RET=0; return; fi
    status[tx]=$TX_ABORTED
    _RET=1
}

crash_recovery() {
    local t
    for (( t=0; t<N_TX; t++ )); do
        status[t]=$TX_FREE
        tx_wcount[t]=0
        tx_rcount[t]=0
    done
}

seed() {
    store_init
    account_set_raw 0 1000
    account_set_raw 1 500
    account_set_raw 2 200
}

pass_count=0
fail_count=0
check() {
    if [[ $1 -eq 1 ]]; then
        pass_count=$(( pass_count + 1 ))
    else
        fail_count=$(( fail_count + 1 ))
        echo "  FAIL: $2" >&2
    fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }

# A — abort discards
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 9999
tx_write "$tx" 1 8888
tx_write "$tx" 2 7777
tx_abort "$tx"
eq "${accounts[0]}" 1000;  check $_RET "abort: key 0 unchanged"
eq "${accounts[1]}" 500;   check $_RET "abort: key 1 unchanged"
eq "${accounts[2]}" 200;   check $_RET "abort: key 2 unchanged"
eq "${status[tx]}" "$TX_ABORTED"; check $_RET "tx status = ABORTED"

# A — commit installs all
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 100
tx_write "$tx" 1 200
tx_write "$tx" 2 300
tx_commit "$tx"; ok=$_RET
eq "$ok" 1;                check $_RET "commit succeeded"
eq "${accounts[0]}" 100;   check $_RET "commit: key 0 installed"
eq "${accounts[1]}" 200;   check $_RET "commit: key 1 installed"
eq "${accounts[2]}" 300;   check $_RET "commit: key 2 installed"
eq "${status[tx]}" "$TX_COMMITTED"; check $_RET "tx status = COMMITTED"

# C — transfer preserves total
seed
account_total; initial=$_RET
tx_begin; tx=$_RET
tx_read "$tx" 0; src=$_RET
tx_read "$tx" 1; dst=$_RET
tx_write "$tx" 0 $(( src - 100 ))
tx_write "$tx" 1 $(( dst + 100 ))
tx_commit "$tx"
eq "${accounts[0]}" 900;   check $_RET "src debited"
eq "${accounts[1]}" 600;   check $_RET "dst credited"
account_total; eq "$_RET" "$initial"; check $_RET "total preserved"

# I — no dirty read
seed
tx_begin; tx1=$_RET
tx_begin; tx2=$_RET
tx_write "$tx1" 0 9999
tx_read "$tx2" 0; eq "$_RET" 1000; check $_RET "tx2 sees committed, not pending"

# I — read-your-own-writes
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 4242
tx_read "$tx" 0; eq "$_RET" 4242; check $_RET "tx sees own write"
eq "${accounts[0]}" 1000; check $_RET "durable unchanged before commit"

# I — write-write conflict
seed
tx_begin; tx1=$_RET
tx_begin; tx2=$_RET
tx_read "$tx1" 0; v1=$_RET
tx_write "$tx1" 0 $(( v1 + 50 ))
tx_read "$tx2" 0; v2=$_RET
tx_write "$tx2" 0 $(( v2 + 100 ))
tx_commit "$tx1"; ok1=$_RET
tx_commit "$tx2"; ok2=$_RET
eq "$ok1" 1;               check $_RET "tx1 commits"
eq "$ok2" 0;               check $_RET "tx2 conflicts and aborts"
eq "${status[tx2]}" "$TX_ABORTED"; check $_RET "tx2 status = ABORTED"
eq "${accounts[0]}" 1050;  check $_RET "tx1 durable; tx2 lost"

# D — committed survives crash
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 12345
tx_commit "$tx"
crash_recovery
eq "${accounts[0]}" 12345; check $_RET "committed survives crash"

# No double-commit
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 7
tx_commit "$tx"; ok1=$_RET
tx_commit "$tx"; ok2=$_RET
eq "$ok1" 1; check $_RET "first commit ok"
eq "$ok2" 0; check $_RET "second commit rejected"

# Write-set capacity bounded
seed
tx_begin; tx=$_RET
tx_write "$tx" 0 1
tx_write "$tx" 1 2
tx_write "$tx" 2 3
tx_write "$tx" 3 4
tx_write "$tx" 4 5; eq "$_RET" 0; check $_RET "5th write rejected (cap=4)"

echo "=== transactions_and_acid ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
