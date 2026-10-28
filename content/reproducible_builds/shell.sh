#!/usr/bin/env bash
# Vidya — Reproducible Builds — Bash port.
#
# A reproducible build is a pure function of its inputs: the same sources
# produce a byte-identical artifact, on any machine, at any time. Three
# classic sources of non-determinism, and their fixes:
#
#   1. Embedded wall-clock timestamps  → the build stamps
#      SOURCE_DATE_EPOCH (a fixed build time from the sources) instead of
#      "now", so the clock never reaches the output, fast or slow.
#      Clamping (min(t, SDE)) is for FILE mtimes: a fresh checkout's newer
#      mtimes are pinned down to SDE. Clamping the clock itself would still
#      leak any clock that runs behind SDE.
#   2. Filesystem iteration order      → readdir() order varies; SORT
#      filenames before processing so output ignores directory layout.
#   3. Non-deterministic artifact names → name artifacts by the HASH of
#      their content (content-addressing) so the build is idempotent.
#
# Verification is simple: build twice and compare digests. This models the
# pipeline over an in-memory file set (name key + content signature) and
# shows a deterministic build staying identical across runs that differ in
# input order AND wall-clock time, while a naive build drifts.
#
# Helpers return via the `_RET` global, never via stdout, because `$(...)`
# runs in a subshell and discards array mutations on exit (cyrius field-note
# "subshell_clobbers_stateful_helpers").

set -euo pipefail

HB=131
HM=1000003
HSEED=7

_RET=0

fold() { _RET=$(( ($1 * HB + $2) % HM )); }

# --- 1. Deterministic timestamps: the mtime clamp (tar --clamp-mtime).
#     normalize_ts MTIME SDE: a file mtime newer than SOURCE_DATE_EPOCH is
#     pinned down to it; an older one is kept. The build time itself is
#     SDE, not this. ---
normalize_ts() {
    if [[ $1 -gt $2 ]]; then _RET=$2; else _RET=$1; fi
}

# --- 3. Content-addressed artifact path: a pure function of content ---
cas_path() { _RET=$(( ($1 * HB + 7) % HM )); }

# --- File set: parallel arrays (name sort-key, content signature) ---
declare -a name_key content
f_n=0

files_reset() { f_n=$1; }
file_set() { name_key[$1]=$2; content[$1]=$3; }

# --- 2. Sorted iteration: insertion-sort files by name key, ascending,
#     reordering content alongside so the pairing is preserved. ---
files_sort() {
    local i j kn kc done
    for (( i=1; i<f_n; i++ )); do
        kn=${name_key[i]}
        kc=${content[i]}
        j=$(( i - 1 ))
        done=0
        while [[ $done -eq 0 ]]; do
            if [[ $j -lt 0 ]]; then
                done=1
            elif [[ ${name_key[j]} -gt $kn ]]; then
                name_key[$(( j + 1 ))]=${name_key[j]}
                content[$(( j + 1 ))]=${content[j]}
                j=$(( j - 1 ))
            else
                done=1
            fi
        done
        name_key[$(( j + 1 ))]=$kn
        content[$(( j + 1 ))]=$kc
    done
}

# --- The build: fold the (normalized) timestamp and every file's
#     (name, content) into one artifact digest. Flags toggle the two
#     determinism fixes so we can contrast a correct vs naive pipeline. ---
build_digest() {
    local do_sort=$1 do_norm=$2 now=$3 sde=$4 ts h i
    if [[ $do_sort -eq 1 ]]; then files_sort; fi
    ts=$now
    if [[ $do_norm -eq 1 ]]; then ts=$sde; fi  # build time comes from the sources
    fold "$HSEED" "$ts"; h=$_RET
    for (( i=0; i<f_n; i++ )); do
        fold "$h" "${name_key[i]}"; h=$_RET
        fold "$h" "${content[i]}";  h=$_RET
    done
    _RET=$h
}

# Same SET of three files, presented in two different input orders.
setup_order_a() {
    files_reset 3
    file_set 0 30 111
    file_set 1 10 222
    file_set 2 20 333
}
setup_order_b() {
    files_reset 3
    file_set 0 20 333
    file_set 1 30 111
    file_set 2 10 222
}

assert_eq() {
    if [[ $1 -ne $2 ]]; then
        echo "FAIL: $3 (expected $2, got $1)" >&2
        exit 1
    fi
}

# === Contract ===

# 1. The mtime clamp
normalize_ts 9999 5000; assert_eq "$_RET" 5000 "newer mtime clamped to SOURCE_DATE_EPOCH"
normalize_ts 3000 5000; assert_eq "$_RET" 3000 "older mtime kept"

# 2. Sorted iteration (content stays paired with its name)
setup_order_a
files_sort
assert_eq "${name_key[0]}" 10 "sorted name[0] = 10"
assert_eq "${name_key[1]}" 20 "sorted name[1] = 20"
assert_eq "${name_key[2]}" 30 "sorted name[2] = 30"
assert_eq "${content[0]}" 222 "content followed name 10"

# 3. Content-addressed paths: cas_path takes only the content, so equal
#    content maps to an equal path by construction (comparing cas_path 111
#    with itself could never fail). What can fail is distinct content
#    colliding on one path:
cas_path 111; c=$_RET
cas_path 222; d=$_RET
[[ $c -ne $d ]] && _RET=1 || _RET=0
assert_eq "$_RET" 1 "different content -> different path"

# Deterministic pipeline (sort + normalize): two builds differing in BOTH
# input order and wall-clock "now" must produce equal digests.
setup_order_a; build_digest 1 1 9999 5000; d1=$_RET
setup_order_b; build_digest 1 1 8888 5000; d2=$_RET
assert_eq "$d1" "$d2" "deterministic build is byte-identical across runs"

# Naive pipeline (no sort, raw now): same source set yields different
# digests when order or clock differ — the bug repro builds eliminate.
setup_order_a; build_digest 0 0 9999 5000; n1=$_RET
setup_order_b; build_digest 0 0 8888 5000; n2=$_RET
[[ $n1 -ne $n2 ]] && _RET=1 || _RET=0
assert_eq "$_RET" 1 "naive build drifts with order + timestamp"

# Normalization alone kills clock drift (sort on, only the clock differing).
setup_order_a; build_digest 1 1 9999 5000; norm1=$_RET
setup_order_a; build_digest 1 1 7777 5000; norm2=$_RET
assert_eq "$norm1" "$norm2" "normalized timestamp removes clock dependence"
# ...including a clock that runs BEHIND the epoch: min(now, sde) would stamp
# 3000 here and 5000 above, and the digests would differ.
setup_order_a; build_digest 1 1 3000 5000; slow=$_RET
assert_eq "$slow" "$norm1" "a slow clock does not leak into the build either"

echo "All reproducible_builds examples passed."
exit 0
