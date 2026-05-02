#!/usr/bin/env bash
# Vidya — Grid Pathfinding in Shell (Bash)
#
# BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked). Bash
# uses parallel arrays for everything: indexed array `GRID` for cells,
# `VISITED` for the closed set, `DIST`/`G_SCORE`/`F_SCORE` for path
# bookkeeping, and a head/tail pair to drive a flat FIFO/open-set
# array. A* does linear-scan over the open set for the min-f cell —
# matching the structure of the Cyrius reference (a real heap is the
# right answer above ~512 cells, but for 64 the scan is instant).
# Manhattan distance is the heuristic.

set -euo pipefail

readonly GW=8
readonly GH=8
readonly GN=64
readonly INF=9999999

declare -a GRID VISITED DIST PARENT G_SCORE F_SCORE QUEUE OPEN

idx() { echo $(( $2 * GW + $1 )); }

abs_i() {
    local v=$1
    if (( v < 0 )); then echo $(( -v )); else echo "$v"; fi
}

manhattan() {
    local ax=$1 ay=$2 bx=$3 by=$4
    local dx=$(( ax - bx )); (( dx < 0 )) && dx=$(( -dx ))
    local dy=$(( ay - by )); (( dy < 0 )) && dy=$(( -dy ))
    echo $(( dx + dy ))
}

grid_clear() {
    local i
    for (( i = 0; i < GN; i++ )); do GRID[i]=0; done
}

grid_block() { local i; i=$(idx "$1" "$2"); GRID[i]=1; }

bfs() {
    local start=$1 goal=$2
    if (( start == goal )); then echo 0; return; fi
    local i
    for (( i = 0; i < GN; i++ )); do VISITED[i]=0; DIST[i]=-1; done
    local head=0 tail=0
    QUEUE[tail]=$start; tail=$(( tail + 1 ))
    VISITED[start]=1
    DIST[start]=0
    while (( head < tail )); do
        local curr=${QUEUE[head]}; head=$(( head + 1 ))
        if (( curr == goal )); then echo "${DIST[curr]}"; return; fi
        local cx=$(( curr % GW )) cy=$(( curr / GW ))
        local nbs=()
        (( cy > 0 ))      && nbs+=( $(( curr - GW )) )
        (( cy < GH - 1 )) && nbs+=( $(( curr + GW )) )
        (( cx > 0 ))      && nbs+=( $(( curr - 1 )) )
        (( cx < GW - 1 )) && nbs+=( $(( curr + 1 )) )
        local n
        for n in "${nbs[@]}"; do
            if (( VISITED[n] == 0 && GRID[n] == 0 )); then
                VISITED[n]=1
                DIST[n]=$(( DIST[curr] + 1 ))
                QUEUE[tail]=$n; tail=$(( tail + 1 ))
            fi
        done
    done
    echo -1
}

astar() {
    local sx=$1 sy=$2 gx=$3 gy=$4
    local start; start=$(idx "$sx" "$sy")
    local goal; goal=$(idx "$gx" "$gy")
    local i
    for (( i = 0; i < GN; i++ )); do
        VISITED[i]=0
        G_SCORE[i]=$INF
        F_SCORE[i]=$INF
    done
    G_SCORE[start]=0
    F_SCORE[start]=$(manhattan "$sx" "$sy" "$gx" "$gy")
    local open_n=0
    OPEN[open_n]=$start; open_n=$(( open_n + 1 ))

    while (( open_n > 0 )); do
        local best_i=0
        local best_f=${F_SCORE[${OPEN[0]}]}
        local k
        for (( k = 1; k < open_n; k++ )); do
            local node=${OPEN[k]}
            local fv=${F_SCORE[node]}
            if (( fv < best_f )); then best_f=$fv; best_i=$k; fi
        done
        local curr=${OPEN[best_i]}
        if (( curr == goal )); then echo "${G_SCORE[goal]}"; return; fi
        # swap-remove
        open_n=$(( open_n - 1 ))
        if (( best_i != open_n )); then
            OPEN[best_i]=${OPEN[open_n]}
        fi
        VISITED[curr]=1

        local cx=$(( curr % GW )) cy=$(( curr / GW ))
        local tg=$(( G_SCORE[curr] + 1 ))
        local nbs=()
        (( cy > 0 ))      && nbs+=( $(( curr - GW )) )
        (( cy < GH - 1 )) && nbs+=( $(( curr + GW )) )
        (( cx > 0 ))      && nbs+=( $(( curr - 1 )) )
        (( cx < GW - 1 )) && nbs+=( $(( curr + 1 )) )
        local n
        for n in "${nbs[@]}"; do
            if (( VISITED[n] == 0 && GRID[n] == 0 )); then
                if (( tg < G_SCORE[n] )); then
                    G_SCORE[n]=$tg
                    local nx=$(( n % GW )) ny=$(( n / GW ))
                    local h; h=$(manhattan "$nx" "$ny" "$gx" "$gy")
                    F_SCORE[n]=$(( tg + h ))
                    OPEN[open_n]=$n; open_n=$(( open_n + 1 ))
                fi
            fi
        done
    done
    echo -1
}

assert_eq() {
    local got="$1" want="$2" msg="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

# --- Tests ---

# manhattan
assert_eq "$(manhattan 0 0 0 0)" 0  "manhattan(0,0,0,0)"
assert_eq "$(manhattan 0 0 3 4)" 7  "manhattan(0,0,3,4)"
assert_eq "$(manhattan 7 7 0 0)" 14 "manhattan(7,7,0,0)"
assert_eq "$(manhattan 2 5 5 2)" 6  "manhattan(2,5,5,2)"

# bfs empty
grid_clear
assert_eq "$(bfs "$(idx 0 0)" "$(idx 7 7)")" 14 "bfs empty grid"

# bfs same
grid_clear
assert_eq "$(bfs "$(idx 3 3)" "$(idx 3 3)")" 0 "bfs same start/goal"

# bfs around wall
grid_clear
for (( y = 0; y < 7; y++ )); do grid_block 4 "$y"; done
assert_eq "$(bfs "$(idx 0 0)" "$(idx 7 0)")" 21 "bfs around wall"

# bfs unreachable
grid_clear
grid_block 6 7
grid_block 7 6
assert_eq "$(bfs "$(idx 0 0)" "$(idx 7 7)")" -1 "bfs unreachable"

# astar empty
grid_clear
assert_eq "$(astar 0 0 7 7)" 14 "astar empty grid"

# astar matches bfs around wall
grid_clear
for (( y = 0; y < 7; y++ )); do grid_block 4 "$y"; done
bfs_len=$(bfs "$(idx 0 0)" "$(idx 7 0)")
astar_len=$(astar 0 0 7 0)
assert_eq "$astar_len" "$bfs_len" "astar == bfs (wall)"
assert_eq "$astar_len" 21 "astar wall is 21"

# astar unreachable
grid_clear
grid_block 6 7
grid_block 7 6
assert_eq "$(astar 0 0 7 7)" -1 "astar unreachable"

echo "All grid_pathfinding examples passed."
