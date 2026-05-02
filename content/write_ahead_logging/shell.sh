#!/usr/bin/env bash
# Vidya — Write-Ahead Logging in Shell (Bash)
#
# In-memory WAL: append a log record (op, key, val) BEFORE mutating the
# data store, then replay the durable prefix on recovery. Bash has no
# real byte buffer, but it does have flat indexed integer arrays — we
# treat `LOG[]` as a sequence of i64 fields, three per logical record,
# and track `LOG_OFFSET` in *bytes* exactly as the cyrius reference
# does (so the 256-record cap and the offset-monotonicity check both
# match). No real fsync — `LOG_COMMITTED` snapshots the durable prefix.

set -euo pipefail

readonly REC_SZ=24
readonly LOG_CAP_BYTES=6144
readonly OP_INVALID=0
readonly OP_SET=1
readonly OP_DEL=2
readonly STORE_KEYS=16

# Flat array of int64 fields: 3 per record (op, key, val).
declare -a LOG
LOG_OFFSET=0
LOG_COMMITTED=0

declare -a DATA_VALS
declare -a DATA_PRESENT

log_reset() {
    LOG_OFFSET=0
    LOG_COMMITTED=0
}

store_clear() {
    local i
    for (( i = 0; i < STORE_KEYS; i++ )); do
        DATA_VALS[i]=0
        DATA_PRESENT[i]=0
    done
}

reset_all() {
    log_reset
    store_clear
    # Wipe the buffer so leftover records from a prior test don't ghost
    # into a fresh replay. (Bash arrays are sparse but tests check the
    # offset, not the trailing slots.)
    LOG=()
}

# log_append op key val — sets OUT to 1 on success, 0 if buffer full.
log_append() {
    local op=$1 key=$2 val=$3
    if (( LOG_OFFSET + REC_SZ > LOG_CAP_BYTES )); then
        OUT=0
        return
    fi
    # 24 bytes = 3 fields. Index = byte_offset / 8.
    local base=$(( LOG_OFFSET / 8 ))
    LOG[base]=$op
    LOG[base + 1]=$key
    LOG[base + 2]=$val
    LOG_OFFSET=$(( LOG_OFFSET + REC_SZ ))
    OUT=1
}

log_commit() {
    # Real implementations call fsync(wal_fd); we model durability with
    # an offset snapshot.
    LOG_COMMITTED=$LOG_OFFSET
}

# load64 byte_offset — stores result in OUT (subshell would lose it).
load64() {
    local off=$1
    OUT=${LOG[$(( off / 8 ))]}
}

store_set() {
    local key=$1 val=$2
    if (( key < 0 || key >= STORE_KEYS )); then OUT=0; return; fi
    log_append "$OP_SET" "$key" "$val"
    if (( OUT == 0 )); then return; fi
    DATA_VALS[key]=$val
    DATA_PRESENT[key]=1
    OUT=1
}

store_del() {
    local key=$1
    if (( key < 0 || key >= STORE_KEYS )); then OUT=0; return; fi
    log_append "$OP_DEL" "$key" 0
    if (( OUT == 0 )); then return; fi
    DATA_VALS[key]=0
    DATA_PRESENT[key]=0
    OUT=1
}

store_get() {
    local key=$1
    if (( key < 0 || key >= STORE_KEYS )); then OUT=-1; return; fi
    if (( DATA_PRESENT[key] == 0 )); then OUT=-1; return; fi
    OUT=${DATA_VALS[key]}
}

replay() {
    store_clear
    local pos=0 applied=0 op key val base
    while (( pos < LOG_COMMITTED )); do
        base=$(( pos / 8 ))
        op=${LOG[base]}
        key=${LOG[base + 1]}
        val=${LOG[base + 2]}
        if (( op == OP_SET )); then
            DATA_VALS[key]=$val
            DATA_PRESENT[key]=1
            applied=$((applied + 1))
        elif (( op == OP_DEL )); then
            DATA_VALS[key]=0
            DATA_PRESENT[key]=0
            applied=$((applied + 1))
        fi
        pos=$(( pos + REC_SZ ))
    done
    OUT=$applied
}

assert_eq() {
    local got=$1 want=$2 msg=$3
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

# --- Tests ---

# test_append_and_replay
reset_all
store_set 0 100
store_set 1 200
store_set 2 300
log_commit
store_clear
replay
assert_eq "$OUT" "3" "replayed 3 records"
store_get 0; assert_eq "$OUT" "100" "key 0 = 100"
store_get 1; assert_eq "$OUT" "200" "key 1 = 200"
store_get 2; assert_eq "$OUT" "300" "key 2 = 300"

# test_log_before_data_invariant
reset_all
store_set 5 42
assert_eq "$OUT" "1" "first set succeeds"
load64 0;  assert_eq "$OUT" "$OP_SET" "log[0].op = SET"
load64 8;  assert_eq "$OUT" "5"       "log[0].key = 5"
load64 16; assert_eq "$OUT" "42"      "log[0].val = 42"
store_get 5; assert_eq "$OUT" "42"    "data has key 5 = 42"

# test_uncommitted_writes_lost_on_crash
reset_all
store_set 0 1
store_set 1 2
log_commit
store_set 2 3
store_set 3 4
store_clear
replay
assert_eq "$OUT" "2" "only 2 committed records replayed"
store_get 0; assert_eq "$OUT" "1"  "committed key 0 survived"
store_get 1; assert_eq "$OUT" "2"  "committed key 1 survived"
store_get 2; assert_eq "$OUT" "-1" "uncommitted key 2 lost"
store_get 3; assert_eq "$OUT" "-1" "uncommitted key 3 lost"

# test_delete_replays_correctly
reset_all
store_set 0 100
store_set 1 200
store_del 0
log_commit
store_clear
replay
store_get 0; assert_eq "$OUT" "-1"  "key 0 deleted"
store_get 1; assert_eq "$OUT" "200" "key 1 = 200"

# test_overwrite_uses_last_record
reset_all
store_set 7 100
store_set 7 200
store_set 7 300
log_commit
store_clear
replay
store_get 7; assert_eq "$OUT" "300" "last write wins on replay"

# test_sequential_offsets_monotonic
reset_all
PREV=$LOG_OFFSET
for (( i = 0; i < 5; i++ )); do
    store_set "$i" $(( i * 10 ))
    NOW=$LOG_OFFSET
    if (( NOW <= PREV )); then
        echo "FAIL: log offset did not advance ($NOW <= $PREV)" >&2
        exit 1
    fi
    PREV=$NOW
done

# test_log_capacity_limit
reset_all
FAILURES=0
for (( i = 0; i < 300; i++ )); do
    store_set 0 "$i"
    if (( OUT == 0 )); then FAILURES=$((FAILURES + 1)); fi
done
if (( FAILURES == 0 )); then
    echo "FAIL: log capacity is unbounded" >&2
    exit 1
fi

# Reference OP_INVALID so the readonly variable is not flagged unused.
: "$OP_INVALID"

echo "All write_ahead_logging examples passed."
