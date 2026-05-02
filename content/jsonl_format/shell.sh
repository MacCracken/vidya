#!/usr/bin/env bash
# Vidya — JSON Lines (JSONL) in Shell (Bash)
#
# In-memory JSONL primitives mirroring cyrius.cyr. Bash uses indexed
# integer arrays as flat byte buffers.

set -uo pipefail

declare -a JSONL
JSONL_LEN=0
declare -a OFFSETS
declare -a LENGTHS
LINE_COUNT=0
declare -a ESC
ESC_LEN=0
declare -a UNESC
UNESC_LEN=0

# Append the bytes of $2 (a string) into JSONL[] + a trailing 0x0A.
append_record() {
    local s=$1
    local i
    for (( i = 0; i < ${#s}; i++ )); do
        printf -v "byte" "%d" "'${s:i:1}"
        JSONL[JSONL_LEN]=$byte
        JSONL_LEN=$((JSONL_LEN + 1))
    done
    JSONL[JSONL_LEN]=10  # \n
    JSONL_LEN=$((JSONL_LEN + 1))
}

build_index() {
    LINE_COUNT=0
    OFFSETS=()
    LENGTHS=()
    local start=0 i
    for (( i = 0; i < JSONL_LEN; i++ )); do
        if [[ ${JSONL[i]} -eq 10 ]]; then
            OFFSETS[LINE_COUNT]=$start
            LENGTHS[LINE_COUNT]=$((i - start))
            LINE_COUNT=$((LINE_COUNT + 1))
            start=$((i + 1))
        fi
    done
    if (( start < JSONL_LEN )); then
        OFFSETS[LINE_COUNT]=$start
        LENGTHS[LINE_COUNT]=$((JSONL_LEN - start))
        LINE_COUNT=$((LINE_COUNT + 1))
    fi
}

# json_escape SRC_NAME SRC_LEN DST_CAP — sets ESC[], ESC_LEN. ESC_LEN=-1 on bounds fail.
json_escape() {
    local -n src=$1
    local src_len=$2
    local dst_cap=$3
    if (( src_len * 2 > dst_cap )); then
        ESC_LEN=-1
        return 0
    fi
    ESC=()
    ESC_LEN=0
    local i c
    for (( i = 0; i < src_len; i++ )); do
        c=${src[i]}
        case $c in
            34)  ESC[ESC_LEN]=92; ESC[ESC_LEN+1]=34; ESC_LEN=$((ESC_LEN + 2));;
            92)  ESC[ESC_LEN]=92; ESC[ESC_LEN+1]=92; ESC_LEN=$((ESC_LEN + 2));;
            10)  ESC[ESC_LEN]=92; ESC[ESC_LEN+1]=110; ESC_LEN=$((ESC_LEN + 2));;
            9)   ESC[ESC_LEN]=92; ESC[ESC_LEN+1]=116; ESC_LEN=$((ESC_LEN + 2));;
            13)  ESC[ESC_LEN]=92; ESC[ESC_LEN+1]=114; ESC_LEN=$((ESC_LEN + 2));;
            *)   ESC[ESC_LEN]=$c; ESC_LEN=$((ESC_LEN + 1));;
        esac
    done
}

json_unescape() {
    local -n src=$1
    local src_len=$2
    UNESC=()
    UNESC_LEN=0
    local i n
    i=0
    while (( i < src_len )); do
        if (( ${src[i]} == 92 && i + 1 < src_len )); then
            n=${src[i+1]}
            case $n in
                34)  UNESC[UNESC_LEN]=34; UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 2));;
                92)  UNESC[UNESC_LEN]=92; UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 2));;
                110) UNESC[UNESC_LEN]=10; UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 2));;
                116) UNESC[UNESC_LEN]=9;  UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 2));;
                114) UNESC[UNESC_LEN]=13; UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 2));;
                *)   UNESC[UNESC_LEN]=${src[i]}; UNESC_LEN=$((UNESC_LEN + 1)); i=$((i + 1));;
            esac
        else
            UNESC[UNESC_LEN]=${src[i]}; UNESC_LEN=$((UNESC_LEN + 1))
            i=$((i + 1))
        fi
    done
}

# Compare slice JSONL[off..off+len] to ASCII string $3.
slice_eq() {
    local off=$1
    local len=$2
    local s=$3
    [[ ${#s} -ne $len ]] && return 1
    local i
    for (( i = 0; i < len; i++ )); do
        printf -v "byte" "%d" "'${s:i:1}"
        [[ ${JSONL[off + i]} -ne $byte ]] && return 1
    done
    return 0
}

bytes_eq() {
    local -n a=$1
    local -n b=$2
    local n=$3
    local i
    for (( i = 0; i < n; i++ )); do
        [[ ${a[i]} -ne ${b[i]} ]] && return 1
    done
    return 0
}

PASS=0
check() { [[ $1 -eq 1 ]] && PASS=$((PASS+1)) || { echo "FAIL: $2" >&2; exit 1; }; }

main() {
    # Test 1
    append_record '{"id":1}'
    append_record '{"id":2}'
    append_record '{"id":3}'
    build_index
    [[ $LINE_COUNT -eq 3 ]] && check 1 "3 records" || check 0 "3 records"
    [[ ${LENGTHS[2]} -eq 8 ]] && check 1 "third length" || check 0 "third length"
    slice_eq ${OFFSETS[2]} ${LENGTHS[2]} '{"id":3}' && check 1 "third bytes" || check 0 "third bytes"

    # Test 2: no trailing newline
    if (( JSONL_LEN > 0 && ${JSONL[JSONL_LEN - 1]} == 10 )); then
        JSONL_LEN=$((JSONL_LEN - 1))
    fi
    build_index
    [[ $LINE_COUNT -eq 3 ]] && check 1 "3 records no trailing" || check 0 "3 records no trailing"

    # Test 3: escape
    declare -a S3=(115 97 121 32 34 104 105 34 9 10 13 92)
    json_escape S3 12 256
    [[ $ESC_LEN -eq 18 ]] && check 1 "escape 18 bytes" || check 0 "escape 18 bytes"

    # Test 4: bounds check
    declare -a S4=(34 34 34 34)
    json_escape S4 4 4
    [[ $ESC_LEN -eq -1 ]] && check 1 "bounds check" || check 0 "bounds check"

    # Test 5: roundtrip — re-escape S3 with cap=256 first
    json_escape S3 12 256
    json_unescape ESC $ESC_LEN
    [[ $UNESC_LEN -eq 12 ]] && check 1 "unescape 12" || check 0 "unescape 12"
    bytes_eq UNESC S3 12 && check 1 "roundtrip bytes" || check 0 "roundtrip bytes"

    echo "jsonl_format: $PASS/8 ok"
}

main
