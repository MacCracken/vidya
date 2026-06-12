#!/usr/bin/env bash
# Vidya — Package Resolution — Bash port.
#
# Semantic versioning, caret constraint matching, range intersection for
# diamond dependencies, highest-version selection, bounded backtracking,
# and dependency-cycle detection — the core of a dependency resolver
# (npm, cargo, cyrius.cyml's own resolver).
#
# A semver major.minor.patch is encoded as one integer
#   enc = major*1000000 + minor*1000 + patch
# so version comparison IS integer comparison. A constraint is a half-open
# range [lo, hi). A caret ^X.Y.Z allows [X.Y.Z, (X+1).0.0).
#
# Helpers return via the `_RET` global, never via stdout, because `$(...)`
# runs in a subshell and discards array mutations on exit (cyrius field-note
# "subshell_clobbers_stateful_helpers").

set -euo pipefail

VMAJ=1000000
VMIN=1000

_RET=0

# --- Semver encode / inspect ---
sv() { _RET=$(( $1 * VMAJ + $2 * VMIN + $3 )); }
sv_major() { _RET=$(( $1 / VMAJ )); }

# --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---
caret_lo() { _RET=$1; }
caret_hi() { sv_major "$1"; _RET=$(( (_RET + 1) * VMAJ )); }

# --- Constraint satisfaction over a half-open range ---
# satisfies v lo hi  -> _RET=1 if lo<=v<hi else 0
satisfies() {
    if [[ $1 -lt $2 ]]; then _RET=0; return; fi
    if [[ $1 -ge $3 ]]; then _RET=0; return; fi
    _RET=1
}

# --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---
range_lo_max() { if [[ $1 -gt $2 ]]; then _RET=$1; else _RET=$2; fi; }
range_hi_min() { if [[ $1 -lt $2 ]]; then _RET=$1; else _RET=$2; fi; }
range_empty()  { if [[ $1 -ge $2 ]]; then _RET=1; else _RET=0; fi; }

# --- Available versions of the shared dependency C (encoded ints) ---
declare -a c_vers
setup_c() {
    sv 1 0 0; c_vers[0]=$_RET
    sv 1 5 0; c_vers[1]=$_RET
    sv 2 0 0; c_vers[2]=$_RET
}

# --- Highest C version in [lo, hi); -1 if none ---
# best_match lo hi  (reads global c_vers)
best_match() {
    local lo=$1 hi=$2 best=-1 v
    for v in "${c_vers[@]}"; do
        satisfies "$v" "$lo" "$hi"
        if [[ $_RET -eq 1 && $v -gt $best ]]; then best=$v; fi
    done
    _RET=$best
}

# --- Diamond resolution: A requires C ^a_base, B requires C ^b_base.
#     Intersect the two carets, pick the highest C that fits; -1 on conflict. ---
# resolve_shared a_base b_base
resolve_shared() {
    local lo hi
    caret_lo "$1"; local alo=$_RET
    caret_lo "$2"; local blo=$_RET
    range_lo_max "$alo" "$blo"; lo=$_RET
    caret_hi "$1"; local ahi=$_RET
    caret_hi "$2"; local bhi=$_RET
    range_hi_min "$ahi" "$bhi"; hi=$_RET
    range_empty "$lo" "$hi"
    if [[ $_RET -eq 1 ]]; then _RET=-1; return; fi
    best_match "$lo" "$hi"
}

# --- Bounded backtracking: A has candidate versions (a_vers), each requiring
#     a caret on C (a_creq, parallel array). B requires C ^b_base. The highest
#     A may force a C constraint conflicting with B; choose the HIGHEST A for
#     which some C still satisfies both. Records the chosen C in g_chosen_c. ---
declare -a a_vers a_creq
g_chosen_c=-1
# resolve_backtrack b_base  (reads parallel globals a_vers / a_creq)
resolve_backtrack() {
    local b_base=$1 bestA=-1 bestC=-1 i n=${#a_vers[@]}
    for (( i=0; i<n; i++ )); do
        local aver=${a_vers[i]} creq=${a_creq[i]} lo hi
        caret_lo "$creq"; local clo=$_RET
        caret_lo "$b_base"; local blo=$_RET
        range_lo_max "$clo" "$blo"; lo=$_RET
        caret_hi "$creq"; local chi=$_RET
        caret_hi "$b_base"; local bhi=$_RET
        range_hi_min "$chi" "$bhi"; hi=$_RET
        range_empty "$lo" "$hi"
        if [[ $_RET -eq 0 ]]; then
            best_match "$lo" "$hi"; local c=$_RET
            if [[ $c -ne -1 && $aver -gt $bestA ]]; then bestA=$aver; bestC=$c; fi
        fi
    done
    g_chosen_c=$bestC
    _RET=$bestA
}

# --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves some
#     package permanently unplaceable). Deps stored as space-separated strings
#     in p_deps[p]. ---
declare -a p_deps p_placed
p_n=0
pkg_reset() {
    p_n=$1
    local i
    for (( i=0; i<p_n; i++ )); do p_deps[i]=""; done
}
pkg_add_dep() {
    local p=$1 d=$2
    if [[ -z ${p_deps[p]} ]]; then p_deps[p]=$d; else p_deps[p]="${p_deps[p]} $d"; fi
}
pkg_has_cycle() {
    local i p placed=0 progress
    for (( i=0; i<p_n; i++ )); do p_placed[i]=0; done
    while [[ $placed -lt $p_n ]]; do
        progress=0
        for (( p=0; p<p_n; p++ )); do
            if [[ ${p_placed[p]} -eq 0 ]]; then
                local ready=1 d
                for d in ${p_deps[p]}; do
                    if [[ ${p_placed[d]} -eq 0 ]]; then ready=0; fi
                done
                if [[ $ready -eq 1 ]]; then
                    p_placed[p]=1
                    placed=$(( placed + 1 ))
                    progress=1
                fi
            fi
        done
        if [[ $progress -eq 0 ]]; then _RET=1; return; fi  # stuck => cycle
    done
    _RET=0
}

# --- Test harness: assert_eq exits 1 on mismatch ---
assert_eq() {
    if [[ $1 -ne $2 ]]; then
        echo "ASSERT FAIL: $3 (got $1, want $2)" >&2
        exit 1
    fi
}

# === Tests ===

test_semver() {
    sv 1 2 3; local a=$_RET; sv 1 2 0; local b=$_RET
    assert_eq $(( a > b )) 1 "patch ordering"
    sv 2 0 0; a=$_RET; sv 1 9 9; b=$_RET
    assert_eq $(( a > b )) 1 "major dominates minor/patch"
    sv 1 5 2; sv_major "$_RET"
    assert_eq "$_RET" 1 "extract major"
}

test_caret() {
    sv 1 2 0; local base=$_RET
    caret_lo "$base"; assert_eq "$_RET" "$base" "caret lower = base"
    sv 2 0 0; local next=$_RET
    caret_hi "$base"; assert_eq "$_RET" "$next" "caret upper = next major"
    caret_lo "$base"; local lo=$_RET; caret_hi "$base"; local hi=$_RET
    sv 1 4 0; satisfies "$_RET" "$lo" "$hi"; assert_eq "$_RET" 1 "1.4.0 in ^1.2.0"
    sv 2 0 0; satisfies "$_RET" "$lo" "$hi"; assert_eq "$_RET" 0 "2.0.0 not in ^1.2.0"
    sv 1 1 0; satisfies "$_RET" "$lo" "$hi"; assert_eq "$_RET" 0 "1.1.0 below ^1.2.0"
}

test_intersect() {
    sv 1 0 0; local a=$_RET; sv 1 3 0; local b=$_RET
    range_lo_max "$a" "$b"; assert_eq "$_RET" "$b" "intersect lo = max"
    sv 2 0 0; a=$_RET; sv 3 0 0; b=$_RET
    range_hi_min "$a" "$b"; local hmin=$_RET; sv 2 0 0
    assert_eq "$hmin" "$_RET" "intersect hi = min"
    sv 1 0 0; caret_lo "$_RET"; local l1=$_RET
    sv 2 0 0; caret_lo "$_RET"; local l2=$_RET
    range_lo_max "$l1" "$l2"; local lo=$_RET
    sv 1 0 0; caret_hi "$_RET"; local h1=$_RET
    sv 2 0 0; caret_hi "$_RET"; local h2=$_RET
    range_hi_min "$h1" "$h2"; local hi=$_RET
    range_empty "$lo" "$hi"; assert_eq "$_RET" 1 "^1.0.0 and ^2.0.0 are disjoint"
}

test_best_match() {
    setup_c
    sv 1 0 0; caret_lo "$_RET"; local lo=$_RET; sv 1 0 0; caret_hi "$_RET"; local hi=$_RET
    best_match "$lo" "$hi"; local got=$_RET; sv 1 5 0
    assert_eq "$got" "$_RET" "highest C in ^1.0.0 = 1.5.0"
    sv 3 0 0; caret_lo "$_RET"; lo=$_RET; sv 3 0 0; caret_hi "$_RET"; hi=$_RET
    best_match "$lo" "$hi"; assert_eq "$_RET" -1 "no C in ^3.0.0"
}

test_resolve_diamond_ok() {
    setup_c
    sv 1 0 0; local one=$_RET
    resolve_shared "$one" "$one"; local got=$_RET; sv 1 5 0
    assert_eq "$got" "$_RET" "A^1 ∩ B^1 picks C 1.5.0"
}

test_resolve_conflict() {
    setup_c
    sv 1 0 0; local one=$_RET; sv 2 0 0; local two=$_RET
    resolve_shared "$one" "$two"; assert_eq "$_RET" -1 "A^1 vs B^2 is unresolvable"
}

test_resolve_backtrack() {
    setup_c
    # A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
    # The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
    sv 1 1 0; a_vers[0]=$_RET; sv 2 0 0; a_creq[0]=$_RET
    sv 1 0 0; a_vers[1]=$_RET; sv 1 0 0; a_creq[1]=$_RET
    sv 1 0 0; resolve_backtrack "$_RET"; local chosenA=$_RET
    sv 1 0 0; assert_eq "$chosenA" "$_RET" "backtrack picks A 1.0.0, not 1.1.0"
    sv 1 5 0; assert_eq "$g_chosen_c" "$_RET" "and resolves C to 1.5.0"
}

test_cycle() {
    pkg_reset 2
    pkg_add_dep 0 1
    pkg_add_dep 1 0
    pkg_has_cycle; assert_eq "$_RET" 1 "A<->B is a dependency cycle"
    pkg_reset 3
    pkg_add_dep 2 0
    pkg_add_dep 2 1            # app -> A, B (diamond, acyclic)
    pkg_has_cycle; assert_eq "$_RET" 0 "diamond graph is acyclic"
}

main() {
    test_semver
    test_caret
    test_intersect
    test_best_match
    test_resolve_diamond_ok
    test_resolve_conflict
    test_resolve_backtrack
    test_cycle
    echo "All package_resolution examples passed."
}

main
exit 0
