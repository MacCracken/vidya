#!/usr/bin/env bash
# Vidya — Embeddings and Vector Search — Bash port. Q15 fixed-point.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

SCALE=15
ONE=32768
DIM=4
N_CORPUS=4

_RET=0

q_mul() {
    local a=$1 b=$2
    local p=$(( a * b ))
    if (( p < 0 )); then _RET=$(( -((-p) >> SCALE) ))
    else _RET=$(( p >> SCALE )); fi
}

# Corpus stored flat: corpus[idx * DIM + i]
declare -a CORPUS=(
    32767 0 0 0
    0 32767 0 0
    16384 16384 16384 16384
    -32767 0 0 0
)

# dot a_name b_name n → _RET
# (Use unique nameref names per function to avoid bash nameref
# circular-reference warnings when callers pass arrays whose
# names happen to match the formal parameter.)
dot() {
    local -n _dot_A=$1
    local -n _dot_B=$2
    local n=$3 acc=0 i t
    for (( i=0; i<n; i++ )); do
        q_mul "${_dot_A[i]}" "${_dot_B[i]}"
        t=$_RET
        acc=$(( acc + t ))
    done
    _RET=$acc
}

# corpus_sim query_name idx → _RET
corpus_sim() {
    local -n _cs_Q=$1
    local idx=$2 i t acc=0
    local base=$(( idx * DIM ))
    for (( i=0; i<DIM; i++ )); do
        q_mul "${_cs_Q[i]}" "${CORPUS[$(( base + i ))]}"
        t=$_RET
        acc=$(( acc + t ))
    done
    _RET=$acc
}

# nearest query_name → _RET = corpus index
nearest() {
    local query_name=$1
    corpus_sim "$query_name" 0
    local best_idx=0 best_sim=$_RET i s
    for (( i=1; i<N_CORPUS; i++ )); do
        corpus_sim "$query_name" $i
        s=$_RET
        if (( s > best_sim )); then
            best_sim=$s
            best_idx=$i
        fi
    done
    _RET=$best_idx
}

# top_k_neighbors query_name k out_name → _RET = count
top_k_neighbors() {
    local query_name=$1
    local k=$2
    local -n _tk_OUT=$3
    local marks=() j
    for (( j=0; j<N_CORPUS; j++ )); do marks[j]=0; done
    local picked=0 best_idx best_sim first s
    _tk_OUT=()
    while (( picked < k )); do
        best_idx=-1
        best_sim=0
        first=1
        for (( j=0; j<N_CORPUS; j++ )); do
            if (( marks[j] == 0 )); then
                corpus_sim "$query_name" $j
                s=$_RET
                if (( first == 1 )); then
                    best_idx=$j
                    best_sim=$s
                    first=0
                elif (( s > best_sim )); then
                    best_idx=$j
                    best_sim=$s
                fi
            fi
        done
        if (( best_idx < 0 )); then _RET=$picked; return; fi
        marks[best_idx]=1
        _tk_OUT[picked]=$best_idx
        picked=$(( picked + 1 ))
    done
    _RET=$picked
}

pass_count=0
fail_count=0
check() {
    if (( $1 == 1 )); then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }
between() { (( $1 >= $2 && $1 <= $3 )) && _RET=1 || _RET=0; }

# self-similarity: each corpus vector dotted with itself ≈ ONE
for i in 0 1 2 3; do
    declare -a vec=(${CORPUS[@]:$(( i * DIM )):$DIM})
    corpus_sim vec $i
    (( _RET >= 32760 )) && check 1 "v$i self-sim ≈ ONE" || check 0 "v$i self-sim ≈ ONE (got $_RET)"
done

# orthogonal
declare -a v0=(${CORPUS[@]:0:$DIM})
corpus_sim v0 1
eq $_RET 0; check $_RET "v0·v1 = 0"

# opposite
corpus_sim v0 3
between $_RET -$ONE -32760; check $_RET "v0·v3 ≈ -ONE"

# diagonal self-sim
declare -a v2=(${CORPUS[@]:$(( 2 * DIM )):$DIM})
corpus_sim v2 2
eq $_RET $ONE; check $_RET "v2 self-sim = ONE"

# axis-vs-diagonal
corpus_sim v0 2
between $_RET 16380 16384; check $_RET "v0·v2 ≈ 0.5"

# dot symmetric
dot v0 v2 $DIM; ab=$_RET
dot v2 v0 $DIM; ba=$_RET
eq $ab $ba; check $_RET "dot symmetric"

# nearest tests
declare -a q1=(29490 0 0 0)
nearest q1; eq $_RET 0; check $_RET "near-x → v0"
declare -a q2=(0 32767 0 0)
nearest q2; eq $_RET 1; check $_RET "y-axis → v1"
declare -a q3=(16384 16384 16384 16384)
nearest q3; eq $_RET 2; check $_RET "diagonal → v2"
declare -a q4=(-29490 0 0 0)
nearest q4; eq $_RET 3; check $_RET "negative-x → v3"

# top-k
declare -a q5=(32767 0 0 0)
declare -a tk_out=()
top_k_neighbors q5 3 tk_out
eq $_RET 3; check $_RET "top_k returned 3"
[[ ${tk_out[0]} -eq 0 && ${tk_out[1]} -eq 2 && ${tk_out[2]} -eq 1 ]] && check 1 "top-3 ranked v0,v2,v1" || check 0 "top-3 ranked"

# top_k cap at corpus size
declare -a tk_out2=()
top_k_neighbors q5 10 tk_out2
eq $_RET 4; check $_RET "top_k caps at corpus size"

# determinism
declare -a q6=(29490 0 0 0)
nearest q6; idx1=$_RET
nearest q6; idx2=$_RET
eq $idx1 $idx2; check $_RET "deterministic"

echo "=== embeddings ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
