#!/usr/bin/env bash
# Vidya — Compression (LZ77-shaped) in Shell (Bash)
#
# Two-byte token stream matching cyrius.cyr:
#   [0, BYTE]      literal
#   [OFFSET, LEN]  match: copy LEN bytes from out[pos - OFFSET..]
# Bash uses indexed integer arrays for input/output buffers and a
# parallel TOK[] array for the token stream. Greedy O(n^2) match-
# finder, 255-byte window. Decoder enforces an output-cap.
#
# Note: bash subshells (`$(...)`) clobber stateful helpers — see
# field-note bash_subshell_clobbers_stateful_helpers. We use side-
# effect globals for results.

set -euo pipefail

readonly MIN_MATCH=3
readonly MAX_MATCH=255
readonly WIN_SIZE=255

# Encode src array (SRC[], SRC_LEN) into TOK[]; sets TOK_LEN.
# Decode TOK[] (TOK_LEN, OUT_CAP) into OUT[]; sets OUT_LEN, or -1 on bomb.

encode() {
    local -n src=$1
    local src_len=$2
    TOK=()
    TOK_LEN=0
    local pos=0
    while (( pos < src_len )); do
        # best_match: find longest match in last WIN_SIZE bytes
        local win_start=$(( pos > WIN_SIZE ? pos - WIN_SIZE : 0 ))
        local best_off=0 best_len=0
        local i=$win_start
        while (( i < pos )); do
            # match_len_at: count matching bytes from src[i] vs src[pos]
            local n=0
            local max=$(( src_len - pos ))
            (( max > MAX_MATCH )) && max=$MAX_MATCH
            while (( n < max && src[i + n] == src[pos + n] )); do
                n=$(( n + 1 ))
            done
            if (( n > best_len )); then
                best_len=$n
                best_off=$(( pos - i ))
            fi
            i=$(( i + 1 ))
        done
        if (( best_len >= MIN_MATCH )); then
            TOK[TOK_LEN]=$best_off
            TOK[TOK_LEN + 1]=$best_len
            TOK_LEN=$(( TOK_LEN + 2 ))
            pos=$(( pos + best_len ))
        else
            TOK[TOK_LEN]=0
            TOK[TOK_LEN + 1]=${src[pos]}
            TOK_LEN=$(( TOK_LEN + 2 ))
            pos=$(( pos + 1 ))
        fi
    done
}

# Sets OUT[], OUT_LEN. OUT_LEN = -1 on bomb-guard trigger.
decode() {
    local -n tok=$1
    local tok_len=$2
    local out_cap=$3
    OUT=()
    OUT_LEN=0
    local i=0
    while (( i + 1 < tok_len )); do
        local b0=${tok[i]}
        local b1=${tok[i + 1]}
        i=$(( i + 2 ))
        if (( b0 == 0 )); then
            if (( OUT_LEN + 1 > out_cap )); then
                OUT_LEN=-1
                return 0
            fi
            OUT[OUT_LEN]=$b1
            OUT_LEN=$(( OUT_LEN + 1 ))
        else
            if (( OUT_LEN + b1 > out_cap )); then
                OUT_LEN=-1
                return 0
            fi
            local k=0
            while (( k < b1 )); do
                OUT[OUT_LEN + k]=${OUT[OUT_LEN - b0 + k]}
                k=$(( k + 1 ))
            done
            OUT_LEN=$(( OUT_LEN + b1 ))
        fi
    done
}

# Convert ASCII string to indexed byte array.
str_to_bytes() {
    local -n arr=$1
    local s=$2
    arr=()
    local i
    for (( i = 0; i < ${#s}; i++ )); do
        printf -v "byte" "%d" "'${s:i:1}"
        arr[i]=$byte
    done
    BYTES_LEN=${#s}
}

eq_bytes() {
    local -n a=$1
    local -n b=$2
    local n=$3
    local i
    for (( i = 0; i < n; i++ )); do
        [[ ${a[i]} -eq ${b[i]} ]] || return 1
    done
    return 0
}

PASS=0
check() {
    if [[ $1 -eq 1 ]]; then
        PASS=$(( PASS + 1 ))
    else
        echo "FAIL: $2" >&2
        exit 1
    fi
}

main() {
    declare -a S1 T S2 S3 BOMB
    declare -i BYTES_LEN

    # 1. Round-trip with substring match
    str_to_bytes S1 "ABCABCABC"
    n1=$BYTES_LEN
    encode S1 $n1
    [[ $TOK_LEN -gt 0 ]] && PASS=$(( PASS + 1 )) || { echo FAIL t1>0; exit 1; }
    declare -a TOK_SAVE; TOK_SAVE=("${TOK[@]}"); local tok_save_len=$TOK_LEN
    decode TOK_SAVE $tok_save_len 512
    [[ $OUT_LEN -eq $n1 ]] && PASS=$(( PASS + 1 )) || { echo FAIL d1len; exit 1; }
    eq_bytes OUT S1 $n1 && PASS=$(( PASS + 1 )) || { echo FAIL d1eq; exit 1; }

    # 2. Overlapping (RLE)
    str_to_bytes S2 "AAAAAAAA"
    n2=$BYTES_LEN
    encode S2 $n2
    declare -a TOK2; TOK2=("${TOK[@]}"); local tok2_len=$TOK_LEN
    decode TOK2 $tok2_len 512
    eq_bytes OUT S2 $n2 && PASS=$(( PASS + 1 )) || { echo FAIL d2; exit 1; }
    [[ $tok2_len -lt $(( n2 + 4 )) ]] && PASS=$(( PASS + 1 )) || { echo FAIL t2compress; exit 1; }

    # 3. Mostly literals
    str_to_bytes S3 "Hello, World!"
    n3=$BYTES_LEN
    encode S3 $n3
    declare -a TOK3; TOK3=("${TOK[@]}"); local tok3_len=$TOK_LEN
    decode TOK3 $tok3_len 512
    eq_bytes OUT S3 $n3 && PASS=$(( PASS + 1 )) || { echo FAIL d3; exit 1; }

    # 4. Bomb guard
    BOMB=(1 200)
    decode BOMB 2 10
    [[ $OUT_LEN -eq -1 ]] && PASS=$(( PASS + 1 )) || { echo FAIL bomb; exit 1; }

    # 5. Empty input
    declare -a EMPTY; EMPTY=()
    encode EMPTY 0
    [[ $TOK_LEN -eq 0 ]] && PASS=$(( PASS + 1 )) || { echo FAIL emptytok; exit 1; }
    declare -a EMPTYTOK; EMPTYTOK=()
    decode EMPTYTOK 0 512
    [[ $OUT_LEN -eq 0 ]] && PASS=$(( PASS + 1 )) || { echo FAIL emptydec; exit 1; }

    echo "compression: $PASS/11 ok"
}

main
