#!/usr/bin/env bash
# Vidya — B+ Tree Indexing in Shell (Bash)
#
# Simplified in-memory B+ tree (order 8, max 7 keys per node) emulated
# via global parallel arrays — bash has no struct support, so we flatten
# every node's fields into per-node-id arrays:
#   N_LEAF[id]     — 1 if leaf, 0 if internal
#   N_NK[id]       — number of keys in this node
#   K_<id>_<i>     — key i of node id (NS_KEY i d  / NS_GET i d)
#   V_<id>_<i>     — leaf value i of node id
#   C_<id>_<i>     — child pointer (id of child) for internal node
# This is heavy bookkeeping for bash — declared explicitly in the
# header comment as a known limitation. We only support a single
# split (matching the cyrius test set). Stateful helpers return values
# via the OUT global to avoid the `$( )` subshell trap.

set -euo pipefail

readonly BT_MAX=7

declare -ai N_LEAF N_NK
declare -A KEYS VALS CHILDREN
declare -i NEXT_ID=0
declare ROOT=0

# Per-script reset.
bt_reset() {
    N_LEAF=()
    N_NK=()
    KEYS=()
    VALS=()
    CHILDREN=()
    NEXT_ID=0
    node_new_leaf
    ROOT=$OUT
}

# Allocate a new leaf; returns its id via the global OUT (NOT echo —
# the caller can't run `$(node_new_leaf)` because that subshells away
# all the global mutations we just performed). This is the bash subshell
# trap called out in concept.toml.
node_new_leaf() {
    local id=$NEXT_ID
    NEXT_ID=$(( NEXT_ID + 1 ))
    N_LEAF[id]=1
    N_NK[id]=0
    OUT=$id
}

node_new_internal() {
    local id=$NEXT_ID
    NEXT_ID=$(( NEXT_ID + 1 ))
    N_LEAF[id]=0
    N_NK[id]=0
    OUT=$id
}

# leaf_insert <leaf_id> <key> <val> — keep keys sorted (insertion sort).
leaf_insert() {
    local leaf=$1 key=$2 val=$3
    local nk=${N_NK[leaf]}
    local pos=$nk
    local i
    for (( i = 0; i < nk; i++ )); do
        local kk=${KEYS[${leaf}_${i}]}
        if (( key <= kk )); then pos=$i; break; fi
    done
    # Shift right
    local j
    for (( j = nk; j > pos; j-- )); do
        KEYS[${leaf}_${j}]=${KEYS[${leaf}_$(( j - 1 ))]}
        VALS[${leaf}_${j}]=${VALS[${leaf}_$(( j - 1 ))]}
    done
    KEYS[${leaf}_${pos}]=$key
    VALS[${leaf}_${pos}]=$val
    N_NK[leaf]=$(( nk + 1 ))
}

# find_leaf <root_id> <key>  — returns leaf id via global $OUT
# (avoids the $( ) subshell trap — find_leaf does not mutate state but
# we're consistent with stateful helpers that do.)
find_leaf() {
    local node=$1 key=$2
    while (( N_LEAF[node] == 0 )); do
        local nk=${N_NK[node]}
        local ci=$nk
        local i
        for (( i = 0; i < nk; i++ )); do
            local kk=${KEYS[${node}_${i}]}
            if (( key < kk )); then ci=$i; break; fi
        done
        node=${CHILDREN[${node}_${ci}]}
    done
    OUT=$node
}

# bt_search <root> <key>  → echoes value or -1
bt_search() {
    local root=$1 key=$2
    find_leaf "$root" "$key"
    local leaf=$OUT
    local nk=${N_NK[leaf]}
    local i
    for (( i = 0; i < nk; i++ )); do
        if (( KEYS[${leaf}_${i}] == key )); then
            echo "${VALS[${leaf}_${i}]}"
            return
        fi
    done
    echo -1
}

# split_root_leaf — root must be a leaf with nkeys > MAX. Mutates ROOT.
split_root_leaf() {
    local old=$ROOT
    local nk=${N_NK[old]}
    local mid=$(( nk / 2 ))
    local median=${KEYS[${old}_${mid}]}

    local left right new_root
    node_new_leaf;     left=$OUT
    node_new_leaf;     right=$OUT

    local i
    for (( i = 0; i < mid; i++ )); do
        KEYS[${left}_${i}]=${KEYS[${old}_${i}]}
        VALS[${left}_${i}]=${VALS[${old}_${i}]}
    done
    N_NK[left]=$mid

    for (( i = mid; i < nk; i++ )); do
        KEYS[${right}_$(( i - mid ))]=${KEYS[${old}_${i}]}
        VALS[${right}_$(( i - mid ))]=${VALS[${old}_${i}]}
    done
    N_NK[right]=$(( nk - mid ))

    node_new_internal; new_root=$OUT
    KEYS[${new_root}_0]=$median
    CHILDREN[${new_root}_0]=$left
    CHILDREN[${new_root}_1]=$right
    N_NK[new_root]=1

    ROOT=$new_root
}

# bt_insert <key> <val> — mutates ROOT; cyrius test set forces only one split.
bt_insert() {
    local key=$1 val=$2
    if (( N_LEAF[ROOT] == 1 )); then
        leaf_insert "$ROOT" "$key" "$val"
        if (( N_NK[ROOT] > BT_MAX )); then
            split_root_leaf
        fi
        return
    fi

    local nk=${N_NK[ROOT]}
    local ci=$nk
    local i
    for (( i = 0; i < nk; i++ )); do
        local kk=${KEYS[${ROOT}_${i}]}
        if (( key < kk )); then ci=$i; break; fi
    done
    local leaf=${CHILDREN[${ROOT}_${ci}]}
    if (( N_LEAF[leaf] == 0 )); then
        echo "FAIL: multi-level split not implemented" >&2; exit 1
    fi
    leaf_insert "$leaf" "$key" "$val"
    if (( N_NK[leaf] > BT_MAX )); then
        echo "FAIL: multi-level split not implemented" >&2; exit 1
    fi
}

assert_eq() {
    local got=$1 want=$2 msg=$3
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

# --- Tests ---

# Basic insert and search
bt_reset
bt_insert 10 100
bt_insert 5  50
bt_insert 20 200
bt_insert 15 150
bt_insert 3  30
assert_eq "$(bt_search "$ROOT" 10)" 100 "find 10"
assert_eq "$(bt_search "$ROOT" 5)"  50  "find 5"
assert_eq "$(bt_search "$ROOT" 3)"  30  "find 3"
assert_eq "$(bt_search "$ROOT" 99)" -1  "miss 99"

# Keys sorted in leaf
bt_reset
bt_insert 10 100
bt_insert 5  50
bt_insert 20 200
bt_insert 15 150
bt_insert 3  30
assert_eq "${N_LEAF[ROOT]}" 1 "single leaf"
assert_eq "${N_NK[ROOT]}"   5 "5 keys in leaf"
assert_eq "${KEYS[${ROOT}_0]}" 3  "sorted: first=3"
assert_eq "${KEYS[${ROOT}_4]}" 20 "sorted: last=20"

# Split on overflow
bt_reset
for (( i = 0; i <= BT_MAX; i++ )); do
    bt_insert "$i" $(( i * 10 ))
done
assert_eq "${N_LEAF[ROOT]}" 0 "root became internal after split"
for (( i = 0; i <= BT_MAX; i++ )); do
    assert_eq "$(bt_search "$ROOT" "$i")" $(( i * 10 )) "find $i"
done
assert_eq "$(bt_search "$ROOT" 999)" -1 "miss 999"

# Descending inserts are sorted
bt_reset
for k in 50 40 30 20 10; do
    bt_insert "$k" $(( k * 2 ))
done
assert_eq "${N_LEAF[ROOT]}" 1 "single leaf"
assert_eq "${N_NK[ROOT]}"   5 "5 keys"
assert_eq "${KEYS[${ROOT}_0]}" 10 "sorted: first=10"
assert_eq "${KEYS[${ROOT}_4]}" 50 "sorted: last=50"
for k in 50 40 30 20 10; do
    assert_eq "$(bt_search "$ROOT" "$k")" $(( k * 2 )) "find $k"
done

echo "All btree_indexing examples passed."
