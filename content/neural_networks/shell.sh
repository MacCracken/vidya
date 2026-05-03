#!/usr/bin/env bash
# Vidya — Neural Network Forward Pass — Bash port. Q15 fixed-point.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

SCALE=15
ONE=32768
N_IN=2
N_HIDDEN=3
N_OUT=2

_RET=0

q_mul() {
    local a=$1 b=$2
    local p=$(( a * b ))
    if (( p < 0 )); then _RET=$(( -((-p) >> SCALE) ))
    else _RET=$(( p >> SCALE )); fi
}

# Weights as flat arrays.
declare -a W_HIDDEN=(16384 -16384 -16384 16384 16384 16384)
declare -a B_HIDDEN=(0 0 0)
declare -a W_OUTPUT=(16384 0 0 0 16384 0)
declare -a B_OUTPUT=(0 0)

# dense W_name b_name x_name out_name n_in n_out
dense() {
    local -n W=$1
    local -n b=$2
    local -n x=$3
    local -n out=$4
    local n_in=$5 n_out=$6
    local j i acc t
    for (( j=0; j<n_out; j++ )); do
        acc=${b[j]}
        for (( i=0; i<n_in; i++ )); do
            q_mul "${W[$(( j * n_in + i ))]}" "${x[i]}"
            t=$_RET
            acc=$(( acc + t ))
        done
        out[j]=$acc
    done
}

# relu in-place
relu() {
    local -n arr=$1
    local n=$2 i
    for (( i=0; i<n; i++ )); do
        if (( arr[i] < 0 )); then arr[i]=0; fi
    done
}

# argmax — sets _RET to index of max
argmax() {
    local -n arr=$1
    local n=$2
    local best_idx=0 best_val=${arr[0]} i
    for (( i=1; i<n; i++ )); do
        if (( arr[i] > best_val )); then
            best_val=${arr[i]}
            best_idx=$i
        fi
    done
    _RET=$best_idx
}

declare -a last_hidden=(0 0 0)
declare -a last_output=(0 0)

# forward input_name → _RET = predicted class
forward() {
    local -n inp=$1
    last_hidden=(0 0 0)
    last_output=(0 0)
    dense W_HIDDEN B_HIDDEN inp last_hidden $N_IN $N_HIDDEN
    relu last_hidden $N_HIDDEN
    dense W_OUTPUT B_OUTPUT last_hidden last_output $N_HIDDEN $N_OUT
    argmax last_output $N_OUT
}

pass_count=0
fail_count=0
check() {
    if (( $1 == 1 )); then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }
between() { (( $1 >= $2 && $1 <= $3 )) && _RET=1 || _RET=0; }

# q_mul tests
q_mul $ONE 100;       eq $_RET 100;   check $_RET "ONE * 100"
q_mul 16384 16384;    eq $_RET 8192;  check $_RET "0.5 * 0.5"
q_mul -16384 16384;   eq $_RET -8192; check $_RET "-0.5 * 0.5"

# dense layer test
declare -a tw=(16384 16384 8192 24576)
declare -a tb=(0 0)
declare -a tx=(32767 32767)
declare -a ty=(0 0)
dense tw tb tx ty 2 2
between ${ty[0]} 32765 32769; check $_RET "dense y[0] ~= 1.0"
between ${ty[1]} 32765 32769; check $_RET "dense y[1] ~= 1.0"

# bias passes through
declare -a bw=(0 0)
declare -a bb=(12345)
declare -a by=(0)
dense bw bb tx by 2 1
eq ${by[0]} 12345; check $_RET "bias passes through"

# relu test
declare -a rt=(-100 200 -300 400)
relu rt 4
[[ ${rt[0]} -eq 0 && ${rt[1]} -eq 200 && ${rt[2]} -eq 0 && ${rt[3]} -eq 400 ]] && check 1 "relu clips" || check 0 "relu clips"

declare -a rz=(0)
relu rz 1
eq ${rz[0]} 0; check $_RET "relu(0) = 0"

# argmax tests
declare -a am=(100 500 200 300)
argmax am 4; eq $_RET 1; check $_RET "argmax picks 1"
declare -a tie=(100 500 500)
argmax tie 3; eq $_RET 1; check $_RET "first-found wins"

# forward tests
declare -a fx1=(26214 6553)
forward fx1; eq $_RET 0; check $_RET "x=[0.8,0.2] → class 0"
declare -a fx2=(6553 26214)
forward fx2; eq $_RET 1; check $_RET "x=[0.2,0.8] → class 1"
declare -a fx3=(32767 0)
forward fx3; eq $_RET 0; check $_RET "x=[1.0,0.0] → class 0"
declare -a fx4=(0 32767)
forward fx4; eq $_RET 1; check $_RET "x=[0.0,1.0] → class 1"

# relu actually fires
declare -a fx5=(32767 0)
forward fx5
eq ${last_hidden[1]} 0; check $_RET "relu zeroed hidden[1]"
(( last_hidden[0] > 0 )) && check 1 "hidden[0] passed through" || check 0 "hidden[0] passed through"

echo "=== neural_networks ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
