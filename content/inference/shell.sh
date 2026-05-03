#!/usr/bin/env bash
# Vidya — LLM Inference (Decoding) — Bash port.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

VOCAB_SIZE=8
TOK_EOS=1

_RET=0

# Bigram table flat: bigram[prev * VOCAB_SIZE + next]
declare -a bigram
init_bigram() {
    local i
    for (( i=0; i<64; i++ )); do bigram[i]=0; done
    bigram[$(( 2 * VOCAB_SIZE + 3 ))]=1000
    bigram[$(( 2 * VOCAB_SIZE + 4 ))]=100
    bigram[$(( 3 * VOCAB_SIZE + 6 ))]=800
    bigram[$(( 3 * VOCAB_SIZE + 5 ))]=200
    bigram[$(( 4 * VOCAB_SIZE + 5 ))]=700
    bigram[$(( 5 * VOCAB_SIZE + 1 ))]=600
    bigram[$(( 6 * VOCAB_SIZE + 7 ))]=900
    bigram[$(( 6 * VOCAB_SIZE + 3 ))]=100
    bigram[$(( 7 * VOCAB_SIZE + 1 ))]=950
}

# argmax_logits arr_name n → _RET = index of max
argmax_logits() {
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

# topk_filter arr_name n k → _RET = number actually picked
topk_filter() {
    local -n arr=$1
    local n=$2 k=$3
    local marks=() i
    for (( i=0; i<n; i++ )); do marks[i]=0; done
    local picked=0 best_idx best_val first j
    while (( picked < k )); do
        best_idx=-1
        best_val=0
        first=1
        for (( j=0; j<n; j++ )); do
            if (( marks[j] == 0 )); then
                if (( first == 1 )); then
                    best_idx=$j
                    best_val=${arr[j]}
                    first=0
                elif (( arr[j] > best_val )); then
                    best_idx=$j
                    best_val=${arr[j]}
                fi
            fi
        done
        if (( best_idx < 0 )); then _RET=$picked; return; fi
        marks[best_idx]=1
        picked=$(( picked + 1 ))
    done
    local m
    for (( m=0; m<n; m++ )); do
        if (( marks[m] == 0 )); then arr[m]=0; fi
    done
    _RET=$picked
}

# bigram_logits prev_token dest_arr_name → fills dest with bigram row
bigram_logits() {
    local prev=$1
    local -n dest=$2
    local i
    for (( i=0; i<VOCAB_SIZE; i++ )); do
        dest[i]=${bigram[$(( prev * VOCAB_SIZE + i ))]}
    done
}

# decode_sequence start max_len out_name → _RET = count
decode_sequence() {
    local start=$1 max_len=$2
    local -n out=$3
    local logits_buf=()
    local current=$start count=0 next_tok i
    out=()
    for (( i=0; i<VOCAB_SIZE; i++ )); do logits_buf[i]=0; done
    while (( count < max_len )); do
        bigram_logits "$current" logits_buf
        argmax_logits logits_buf $VOCAB_SIZE
        next_tok=$_RET
        out[count]=$next_tok
        count=$(( count + 1 ))
        if (( next_tok == TOK_EOS )); then _RET=$count; return; fi
        current=$next_tok
    done
    _RET=$count
}

pass_count=0
fail_count=0
check() {
    if (( $1 == 1 )); then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }

init_bigram

# argmax tests
declare -a am1=(100 500 200 300)
argmax_logits am1 4; eq $_RET 1; check $_RET "argmax picks 1"
declare -a am2=(100 500 500)
argmax_logits am2 3; eq $_RET 1; check $_RET "first-found wins"
declare -a am3=(-100 -50 -200)
argmax_logits am3 3; eq $_RET 1; check $_RET "argmax over negatives"

# topk tests
declare -a tk1=(10 50 30 20 40 5 60 25)
topk_filter tk1 8 3; eq $_RET 3; check $_RET "topk picked 3"
[[ ${tk1[6]} -eq 60 && ${tk1[1]} -eq 50 && ${tk1[4]} -eq 40 ]] && check 1 "top 3 kept" || check 0 "top 3 kept"
for i in 0 2 3 5 7; do
    eq ${tk1[$i]} 0; check $_RET "idx $i zeroed"
done

declare -a tk2=(1 2 3)
topk_filter tk2 3 3; eq $_RET 3; check $_RET "topk(3,3) keeps all"
[[ ${tk2[0]} -eq 1 && ${tk2[1]} -eq 2 && ${tk2[2]} -eq 3 ]] && check 1 "all preserved" || check 0 "all preserved"

# bigram lookup
declare -a bg=(0 0 0 0 0 0 0 0)
bigram_logits 2 bg
argmax_logits bg $VOCAB_SIZE; eq $_RET 3; check $_RET "after hello → world"

# decode tests
declare -a out1=()
decode_sequence 2 10 out1
eq $_RET 4; check $_RET "produced 4 tokens"
[[ ${out1[0]} -eq 3 && ${out1[1]} -eq 6 && ${out1[2]} -eq 7 && ${out1[3]} -eq 1 ]] && check 1 "hello → world,the,end,EOS" || check 0 "hello → ..."

declare -a out2=()
decode_sequence 5 10 out2
eq $_RET 1; check $_RET "produced 1 token (bar)"
eq ${out2[0]} 1; check $_RET "bar → EOS"

declare -a out3=()
decode_sequence 2 2 out3
eq $_RET 2; check $_RET "capped at 2"
[[ ${out3[0]} -eq 3 && ${out3[1]} -eq 6 ]] && check 1 "first 2 of decode" || check 0 "first 2 of decode"

declare -a out4a=() out4b=()
decode_sequence 2 10 out4a
n1=$_RET
decode_sequence 2 10 out4b
n2=$_RET
eq $n1 $n2; check $_RET "same length"
eq=1
for (( i=0; i<n1; i++ )); do
    if [[ ${out4a[$i]} -ne ${out4b[$i]} ]]; then eq=0; fi
done
eq $eq 1; check $_RET "deterministic"

echo "=== inference ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
