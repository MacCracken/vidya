#!/usr/bin/env bash
# Vidya — Maze Generation in Shell (Bash)
#
# Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell is a
# bitmask of present walls (N=1, S=2, E=4, W=8). Generation carves
# passages by clearing the wall bit on both the current and the
# neighbour cell.
#
# Bash arithmetic is signed 64-bit two's-complement with defined wrap
# on overflow — the PCG step `state = state*MULT + INC` produces the
# same byte-for-byte trajectory as cyrius. Indexed arrays hold cells,
# visited flags, and the DFS stack.

set -euo pipefail

readonly GW=8 GH=8 GN=64
readonly WN=1 WS=2 WE=4 WW=8 WALLS_ALL=15
readonly PCG_MULT=6364136223846793005
readonly PCG_INC=1442695040888963407

RNG_STATE=12345
RNG_OUT=0

rng_seed() { RNG_STATE=$1; }

# rng_next: mutates RNG_STATE in-place — a `$(rng_next)` form would
# fork a subshell and lose the mutation.
rng_next() {
    RNG_STATE=$(( RNG_STATE * PCG_MULT + PCG_INC ))
    RNG_OUT=$(( (RNG_STATE >> 33) & 2147483647 ))
}

rng_range() {
    local max=$1
    if (( max <= 0 )); then RNG_OUT=0; return; fi
    rng_next
    RNG_OUT=$(( RNG_OUT % max ))
}

declare -a maze_cells
declare -a visited
declare -a dfs_stack

idx() { echo $(( $2 * GW + $1 )); }

opposite() {
    case $1 in
        $WN) echo $WS ;;
        $WS) echo $WN ;;
        $WE) echo $WW ;;
        $WW) echo $WE ;;
        *)   echo 0 ;;
    esac
}

maze_init() {
    local i
    for (( i = 0; i < GN; i++ )); do
        maze_cells[i]=$WALLS_ALL
        visited[i]=0
    done
}

# carve x y dir nx ny — clears the wall bit on both cells
carve() {
    local x=$1 y=$2 d=$3 nx=$4 ny=$5
    local ci=$(( y * GW + x ))
    local ni=$(( ny * GW + nx ))
    local od
    od=$(opposite "$d")
    maze_cells[ci]=$(( maze_cells[ci] & (255 - d) ))
    maze_cells[ni]=$(( maze_cells[ni] & (255 - od) ))
}

# collect_unvisited x y -> writes encoded neighbours into NBR_OUT array
# Each neighbour is "dir nx ny" stored as 3 packed integers per slot.
declare -a NBR_OUT
collect_unvisited() {
    local x=$1 y=$2
    local n=0 ni
    NBR_OUT=()
    if (( y > 0 )); then
        ni=$(( (y - 1) * GW + x ))
        if (( visited[ni] == 0 )); then
            NBR_OUT[n]="$WN $x $((y - 1))"
            n=$((n + 1))
        fi
    fi
    if (( y < GH - 1 )); then
        ni=$(( (y + 1) * GW + x ))
        if (( visited[ni] == 0 )); then
            NBR_OUT[n]="$WS $x $((y + 1))"
            n=$((n + 1))
        fi
    fi
    if (( x > 0 )); then
        ni=$(( y * GW + (x - 1) ))
        if (( visited[ni] == 0 )); then
            NBR_OUT[n]="$WW $((x - 1)) $y"
            n=$((n + 1))
        fi
    fi
    if (( x < GW - 1 )); then
        ni=$(( y * GW + (x + 1) ))
        if (( visited[ni] == 0 )); then
            NBR_OUT[n]="$WE $((x + 1)) $y"
            n=$((n + 1))
        fi
    fi
    NBR_COUNT=$n
}

maze_generate() {
    local sx=$1 sy=$2
    maze_init
    dfs_stack=()
    local sp=0
    local start=$(( sy * GW + sx ))
    dfs_stack[sp]=$start
    sp=$((sp + 1))
    visited[start]=1

    local top tx ty pick d nx ny ni
    while (( sp > 0 )); do
        top=${dfs_stack[$((sp - 1))]}
        tx=$(( top % GW ))
        ty=$(( top / GW ))
        collect_unvisited "$tx" "$ty"
        if (( NBR_COUNT == 0 )); then
            sp=$((sp - 1))
        else
            rng_range "$NBR_COUNT"
            pick=$RNG_OUT
            read -r d nx ny <<< "${NBR_OUT[pick]}"
            carve "$tx" "$ty" "$d" "$nx" "$ny"
            ni=$(( ny * GW + nx ))
            visited[ni]=1
            dfs_stack[sp]=$ni
            sp=$((sp + 1))
        fi
    done
}

count_visited() {
    local i n=0
    for (( i = 0; i < GN; i++ )); do
        (( visited[i] != 0 )) && n=$((n + 1))
    done
    echo $n
}

count_removed_walls() {
    local removed=0 x y w
    for (( y = 0; y < GH; y++ )); do
        for (( x = 0; x < GW; x++ )); do
            w=${maze_cells[$((y * GW + x))]}
            if (( y > 0 && (w & WN) == 0 )); then removed=$((removed + 1)); fi
            if (( x > 0 && (w & WW) == 0 )); then removed=$((removed + 1)); fi
        done
    done
    echo $removed
}

walls_consistent() {
    local x y w nw sw eo wo so no
    for (( y = 0; y < GH; y++ )); do
        for (( x = 0; x < GW; x++ )); do
            w=${maze_cells[$((y * GW + x))]}
            if (( x < GW - 1 )); then
                nw=${maze_cells[$((y * GW + x + 1))]}
                eo=$(( (w & WE) == 0 ))
                wo=$(( (nw & WW) == 0 ))
                if (( eo != wo )); then echo 0; return; fi
            fi
            if (( y < GH - 1 )); then
                sw=${maze_cells[$(((y + 1) * GW + x))]}
                so=$(( (w & WS) == 0 ))
                no=$(( (sw & WN) == 0 ))
                if (( so != no )); then echo 0; return; fi
            fi
        done
    done
    echo 1
}

assert_eq() {
    local got=$1 want=$2 msg=$3
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

# --- Tests ---

# init state
maze_init
assert_eq "${maze_cells[0]}"  "$WALLS_ALL" "init: cell 0"
assert_eq "${maze_cells[63]}" "$WALLS_ALL" "init: cell 63"
assert_eq "${visited[0]}"     "0"          "init: cell 0 not visited"

# full coverage
rng_seed 42
maze_generate 0 0
assert_eq "$(count_visited)" "$GN" "all 64 cells visited"

# perfect maze wall count
rng_seed 42
maze_generate 0 0
assert_eq "$(count_removed_walls)" "$((GN - 1))" "perfect maze: GN-1 walls"

# wall consistency
rng_seed 42
maze_generate 0 0
assert_eq "$(walls_consistent)" "1" "wall pairs consistent"

# determinism
rng_seed 42
maze_generate 0 0
C0=${maze_cells[0]}
C27=${maze_cells[27]}
C63=${maze_cells[63]}

rng_seed 42
maze_generate 0 0
assert_eq "${maze_cells[0]}"  "$C0"  "deterministic: cell 0"
assert_eq "${maze_cells[27]}" "$C27" "deterministic: cell 27"
assert_eq "${maze_cells[63]}" "$C63" "deterministic: cell 63"

# different seeds differ
rng_seed 1
maze_generate 0 0
SUM1=0
for (( i = 0; i < GN; i++ )); do SUM1=$(( SUM1 + maze_cells[i] )); done
rng_seed 2
maze_generate 0 0
SUM2=0
for (( i = 0; i < GN; i++ )); do SUM2=$(( SUM2 + maze_cells[i] )); done
if (( SUM1 == SUM2 )); then
    echo "FAIL: different seeds produce same maze ($SUM1 == $SUM2)" >&2
    exit 1
fi

# starting cell visited
rng_seed 42
maze_generate 3 5
assert_eq "${visited[$((5 * GW + 3))]}" "1" "start cell marked visited"
assert_eq "$(count_visited)" "$GN" "all cells reachable"

# cross-language byte parity (matches cyrius reference)
rng_seed 42
maze_generate 0 0
assert_eq "${maze_cells[0]}"  "13" "parity: cell 0 == 13"
assert_eq "${maze_cells[27]}" "12" "parity: cell 27 == 12"
assert_eq "${maze_cells[63]}" "6"  "parity: cell 63 == 6"

echo "All maze_generation examples passed."
