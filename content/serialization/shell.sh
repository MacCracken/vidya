#!/usr/bin/env bash
# Vidya — Serialization in Shell (Bash)
#
# Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

set -uo pipefail

readonly MAX_VARINT_BYTES=10
readonly MAX_MSG_SIZE=1024

# encode_varint VALUE — sets ENC[] (byte array) + ENC_LEN
declare -a ENC
encode_varint() {
    local value=$1
    ENC=()
    ENC_LEN=0
    while (( value >= 128 )); do
        ENC[ENC_LEN]=$(( (value & 0x7F) | 0x80 ))
        value=$((value >> 7))
        ENC_LEN=$((ENC_LEN + 1))
    done
    ENC[ENC_LEN]=$((value & 0x7F))
    ENC_LEN=$((ENC_LEN + 1))
}

# decode_varint BUF_NAME BUF_LEN — sets DEC_VAL + DEC_BYTES; DEC_BYTES=-1 on failure
decode_varint() {
    local -n _buf=$1
    local buf_len=$2
    DEC_VAL=0
    local shift=0 i
    for (( i = 0; i < MAX_VARINT_BYTES; i++ )); do
        if (( i >= buf_len )); then DEC_BYTES=-1; return; fi
        local b=${_buf[i]}
        local low7=$(( b & 0x7F ))
        DEC_VAL=$(( DEC_VAL + (low7 << shift) ))
        if (( (b & 0x80) == 0 )); then
            DEC_BYTES=$((i + 1))
            return
        fi
        shift=$((shift + 7))
    done
    DEC_BYTES=-1
}

# encode_frame PAYLOAD_NAME PAYLOAD_LEN OUT_NAME — sets FRAME_LEN
encode_frame() {
    local -n payload=$1
    local pl_len=$2
    local -n out=$3
    encode_varint $pl_len
    out=()
    local i
    for (( i = 0; i < ENC_LEN; i++ )); do out[i]=${ENC[i]}; done
    for (( i = 0; i < pl_len; i++ )); do out[ENC_LEN + i]=${payload[i]}; done
    FRAME_LEN=$((ENC_LEN + pl_len))
}

# decode_frame BUF_NAME BUF_LEN PAYLOAD_OUT_NAME MAX_MSG — sets FRAME_CONSUMED (-1 on fail)
decode_frame() {
    local buf_arg=$1
    local -n _buf=$1
    local buf_len=$2
    local -n pl_out=$3
    local max_msg=$4
    # Pass the caller's array name through so decode_varint's nameref
    # doesn't create a self-cycle on the same local name.
    decode_varint $buf_arg $buf_len
    if (( DEC_BYTES < 0 )); then FRAME_CONSUMED=-1; return; fi
    if (( DEC_VAL > max_msg )); then FRAME_CONSUMED=-1; return; fi
    local hdr=$DEC_BYTES
    local total=$((hdr + DEC_VAL))
    if (( total > buf_len )); then FRAME_CONSUMED=-1; return; fi
    pl_out=()
    local i
    for (( i = 0; i < DEC_VAL; i++ )); do pl_out[i]=${_buf[hdr + i]}; done
    FRAME_CONSUMED=$total
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

# Varint sizes
encode_varint 0; check $ENC_LEN 1 "v0 size"; check ${ENC[0]} 0 "v0 byte"
encode_varint 127; check $ENC_LEN 1 "v127 size"; check ${ENC[0]} 127 "v127 byte"
encode_varint 128; check $ENC_LEN 2 "v128 size"
check ${ENC[0]} 128 "v128 b0"; check ${ENC[1]} 1 "v128 b1"
encode_varint 16383; check $ENC_LEN 2 "v16383"
encode_varint 16384; check $ENC_LEN 3 "v16384"

# Round-trip
encode_varint 1234567890
declare -a SAMPLE_BUF; SAMPLE_BUF=("${ENC[@]}"); SAMPLE_LEN=$ENC_LEN
decode_varint SAMPLE_BUF $SAMPLE_LEN
check $DEC_VAL 1234567890 "roundtrip val"
check $DEC_BYTES $SAMPLE_LEN "roundtrip bytes"

# Overflow guard
declare -a BOMB
for (( i = 0; i < 11; i++ )); do BOMB[i]=255; done
decode_varint BOMB 11
check $DEC_BYTES -1 "overflow guard"

# Frame round-trip — payload "hello, world"
declare -a HELLO=(104 101 108 108 111 44 32 119 111 114 108 100)
declare -a FRAME PAYLOAD_OUT
encode_frame HELLO 12 FRAME
check $FRAME_LEN 13 "frame len"
check ${FRAME[0]} 12 "frame hdr byte"
decode_frame FRAME $FRAME_LEN PAYLOAD_OUT $MAX_MSG_SIZE
check $FRAME_CONSUMED 13 "frame consumed"

# Stream of 3 frames
declare -a A3=(65 65 65) B4=(66 66 66 66) C5=(67 67 67 67 67)
declare -a STREAM=() FA FB FC
encode_frame A3 3 FA; for (( i = 0; i < FRAME_LEN; i++ )); do STREAM[i]=${FA[i]}; done
S_OFF=$FRAME_LEN
encode_frame B4 4 FB; for (( i = 0; i < FRAME_LEN; i++ )); do STREAM[S_OFF + i]=${FB[i]}; done
S_OFF=$((S_OFF + FRAME_LEN))
encode_frame C5 5 FC; for (( i = 0; i < FRAME_LEN; i++ )); do STREAM[S_OFF + i]=${FC[i]}; done
S_OFF=$((S_OFF + FRAME_LEN))

POS=0; MSGS=0
while (( POS < S_OFF )); do
    declare -a SUB
    for (( i = 0; i < S_OFF - POS; i++ )); do SUB[i]=${STREAM[POS + i]}; done
    decode_frame SUB $((S_OFF - POS)) PAYLOAD_OUT $MAX_MSG_SIZE
    if (( FRAME_CONSUMED < 0 )); then break; fi
    MSGS=$((MSGS + 1))
    POS=$((POS + FRAME_CONSUMED))
done
check $MSGS 3 "stream count"

# Truncated frame
declare -a TRUNC=(100 66 67 68 69 70)
decode_frame TRUNC 6 PAYLOAD_OUT $MAX_MSG_SIZE
check $FRAME_CONSUMED -1 "truncated"

# Oversize length rejected
encode_varint 9999
declare -a OVER; OVER=("${ENC[@]}"); OVER_LEN=$ENC_LEN
decode_frame OVER $OVER_LEN PAYLOAD_OUT $MAX_MSG_SIZE
check $FRAME_CONSUMED -1 "oversize"

echo "serialization: $PASS/19 ok"
