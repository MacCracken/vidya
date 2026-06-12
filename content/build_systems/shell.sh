#!/usr/bin/env bash
# Build Systems — Bash port.
#
# A minimal build-system core: a DAG of targets, topological build order,
# content-signature dirty-tracking, and ninja-style incremental rebuild
# (only dirty targets run), plus cycle detection.
#
# No real files or compilers: each target carries a source "content
# signature" (an integer). A target's INPUT signature mixes its own source
# with the OUTPUT signatures of its dependencies; if that differs from the
# signature it was last built against, the target is dirty and rebuilds.
# Editing a source changes its signature, which transitively re-dirties
# everything downstream — exactly how mtime/hash-based tools (make, ninja,
# bazel) decide what to redo.
#
# Bash integer arithmetic is 64-bit; HB=131, HM=1000003 keep values tiny.

set -euo pipefail

# --- Signature params ---
HB=131            # signature polynomial base
HM=1000003        # signature modulus (prime; keeps values tiny)

# --- Target table (parallel arrays) ---
declare -a t_src      # source content signature
declare -a t_deps     # space-separated dep id list, e.g. t_deps[2]="0 1"
declare -a t_built    # signature last built against (-1 = never)
declare -a t_out      # current output signature
declare -a t_order    # topological order (target ids)
declare -a t_placed   # topo scratch: placed flag
n_targets=0

# Helpers return via _RET (subshells from $(...) would discard array writes).
_RET=0

# --- Construction ---
bs_reset() {
    local n=$1 i
    n_targets=$n
    for (( i=0; i<n; i++ )); do
        t_src[i]=0
        t_deps[i]=""
        t_built[i]=-1     # never built
        t_out[i]=0
    done
}

bs_set_src() { t_src[$1]=$2; }

# bs_set_deps target "d0 d1 ..."
bs_set_deps() { t_deps[$1]=$2; }

# --- Topological sort (Kahn-style ready-scan). Writes target ids into
#     t_order and sets _RET to how many were ordered; < n_targets ⇒ a cycle
#     left some targets unreachable. ---
bs_topo() {
    local i placed=0 progress t ready k d dc
    for (( i=0; i<n_targets; i++ )); do t_placed[i]=0; done
    while [[ $placed -lt $n_targets ]]; do
        progress=0
        for (( t=0; t<n_targets; t++ )); do
            if [[ ${t_placed[t]} -eq 0 ]]; then
                # ready iff every dependency is already placed
                ready=1
                for d in ${t_deps[t]}; do
                    if [[ ${t_placed[d]} -eq 0 ]]; then ready=0; fi
                done
                if [[ $ready -eq 1 ]]; then
                    t_order[placed]=$t
                    t_placed[t]=1
                    placed=$(( placed + 1 ))
                    progress=1
                fi
            fi
        done
        if [[ $progress -eq 0 ]]; then _RET=$placed; return; fi  # stuck ⇒ cycle
    done
    _RET=$placed
}

# --- Input signature: mix this target's source with deps' outputs. ---
bs_sig() {
    local t=$1 sig d
    sig=$(( t_src[t] % HM ))
    for d in ${t_deps[t]}; do
        sig=$(( (sig * HB + t_out[d]) % HM ))
    done
    _RET=$sig
}

# --- Incremental build: walk topo order, rebuild only dirty targets.
#     Output is content-addressed (out == input signature), so a target
#     whose inputs are unchanged keeps its output and its dependents stay
#     clean. Sets _RET to the number of targets rebuilt. ---
bs_build() {
    local ordered i t sig rebuilt=0
    bs_topo; ordered=$_RET
    for (( i=0; i<ordered; i++ )); do
        t=${t_order[i]}
        bs_sig "$t"; sig=$_RET
        if [[ $sig -ne ${t_built[t]} ]]; then
            t_out[t]=$sig       # produce output
            t_built[t]=$sig     # remember what we built
            rebuilt=$(( rebuilt + 1 ))
        fi
    done
    _RET=$rebuilt
}

# === Test harness ===
pass_count=0
fail_count=0
assert_eq() {
    # assert_eq actual expected message
    if [[ $1 -eq $2 ]]; then
        pass_count=$(( pass_count + 1 ))
    else
        fail_count=$(( fail_count + 1 ))
        echo "  FAIL: $3 (got $1, want $2)" >&2
    fi
}

# Classic C build graph: app(2) <- util.o(0), main.o(1)
build_graph() {
    bs_reset 3
    bs_set_src 0 1001     # util.c
    bs_set_src 1 2002     # main.c
    bs_set_src 2 3003     # link recipe
    bs_set_deps 2 "0 1"
}

# Position of a target within t_order (-1 if absent).
order_pos() {
    local target=$1 i
    for (( i=0; i<n_targets; i++ )); do
        if [[ ${t_order[i]} -eq $target ]]; then _RET=$i; return; fi
    done
    _RET=-1
}

# Test 1: topological order
build_graph
bs_topo; assert_eq "$_RET" 3 "topo orders all 3 targets"
order_pos 2; p2=$_RET
order_pos 0; p0=$_RET
order_pos 1; p1=$_RET
[[ $p2 -gt $p0 ]] && assert_eq 1 1 "app built after util.o" || assert_eq 0 1 "app built after util.o"
[[ $p2 -gt $p1 ]] && assert_eq 1 1 "app built after main.o" || assert_eq 0 1 "app built after main.o"

# Test 2: cold build rebuilds all
build_graph
bs_build; assert_eq "$_RET" 3 "cold build rebuilds all 3"

# Test 3: no-op build rebuilds none
build_graph
bs_build                       # cold
bs_build; assert_eq "$_RET" 0 "second build (no edits) rebuilds nothing"

# Test 4: edit leaf rebuilds transitively
build_graph
bs_build                       # cold: all up to date
bs_set_src 1 2999              # edit main.c
bs_build; assert_eq "$_RET" 2 "edit main.c rebuilds main.o + app"

# Test 5: edit other leaf skips sibling
build_graph
bs_build
main_built=${t_built[1]}
bs_set_src 0 1999              # edit util.c
bs_build; assert_eq "$_RET" 2 "edit util.c rebuilds util.o + app"
assert_eq "${t_built[1]}" "$main_built" "main.o left untouched"

# Test 6: cycle detection (0 <-> 1)
bs_reset 2
bs_set_deps 0 "1"
bs_set_deps 1 "0"
bs_topo
[[ $_RET -lt 2 ]] && assert_eq 1 1 "cycle leaves targets unordered" || assert_eq 0 1 "cycle leaves targets unordered"

echo "=== build_systems ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
echo "All build_systems examples passed."
exit 0
