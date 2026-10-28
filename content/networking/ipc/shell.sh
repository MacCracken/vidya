#!/usr/bin/env bash
# Vidya — IPC in Shell (Bash)
#
# In-memory simulation: shared memory, pipe, named channel.

set -uo pipefail

readonly SHM_REGION_CAP=4
readonly SHM_BYTES=64
readonly PIPE_CAP=8
readonly CHAN_CAP=4
readonly CHAN_QUEUE_CAP=8

declare -a SHM           # flat: SHM[region * SHM_BYTES + offset]
declare -a PIPE_BUF
PIPE_HEAD=0
PIPE_COUNT=0
declare -a CHAN_OPEN
declare -a CHAN_QUEUE    # flat: endpoint * CHAN_QUEUE_CAP + slot
declare -a CHAN_COUNT

ipc_init() {
    local i
    for (( i = 0; i < SHM_REGION_CAP * SHM_BYTES; i++ )); do SHM[i]=0; done
    for (( i = 0; i < PIPE_CAP; i++ )); do PIPE_BUF[i]=0; done
    PIPE_HEAD=0; PIPE_COUNT=0
    for (( i = 0; i < CHAN_CAP; i++ )); do CHAN_OPEN[i]=0; CHAN_COUNT[i]=0; done
    for (( i = 0; i < CHAN_CAP * CHAN_QUEUE_CAP; i++ )); do CHAN_QUEUE[i]=0; done
}

shm_write() {
    local region=$1 offset=$2 byte=$3
    if (( region < 0 || region >= SHM_REGION_CAP )); then OUT=0; return; fi
    if (( offset < 0 || offset >= SHM_BYTES )); then OUT=0; return; fi
    SHM[region * SHM_BYTES + offset]=$byte
    OUT=1
}

shm_read() {
    local region=$1 offset=$2
    if (( region < 0 || region >= SHM_REGION_CAP )); then OUT=-1; return; fi
    if (( offset < 0 || offset >= SHM_BYTES )); then OUT=-1; return; fi
    OUT=${SHM[region * SHM_BYTES + offset]}
}

pipe_write() {
    if (( PIPE_COUNT >= PIPE_CAP )); then OUT=0; return; fi
    local tail=$(( (PIPE_HEAD + PIPE_COUNT) % PIPE_CAP ))
    PIPE_BUF[tail]=$1
    PIPE_COUNT=$((PIPE_COUNT + 1))
    OUT=1
}

pipe_read() {
    if (( PIPE_COUNT == 0 )); then OUT=-1; return; fi
    OUT=${PIPE_BUF[PIPE_HEAD]}
    PIPE_HEAD=$(( (PIPE_HEAD + 1) % PIPE_CAP ))
    PIPE_COUNT=$((PIPE_COUNT - 1))
}

chan_listen() {
    local endpoint=$1
    if (( endpoint < 0 || endpoint >= CHAN_CAP )); then OUT=0; return; fi
    CHAN_OPEN[endpoint]=1
    OUT=1
}

chan_send() {
    local dst=$1 msg=$2
    if (( dst < 0 || dst >= CHAN_CAP )); then OUT=0; return; fi
    if (( CHAN_OPEN[dst] != 1 )); then OUT=0; return; fi
    if (( CHAN_COUNT[dst] >= CHAN_QUEUE_CAP )); then OUT=0; return; fi
    CHAN_QUEUE[dst * CHAN_QUEUE_CAP + CHAN_COUNT[dst]]=$msg
    CHAN_COUNT[dst]=$((CHAN_COUNT[dst] + 1))
    OUT=1
}

chan_recv() {
    local endpoint=$1
    if (( endpoint < 0 || endpoint >= CHAN_CAP )); then OUT=-1; return; fi
    if (( CHAN_OPEN[endpoint] != 1 )); then OUT=-1; return; fi
    if (( CHAN_COUNT[endpoint] == 0 )); then OUT=-1; return; fi
    OUT=${CHAN_QUEUE[endpoint * CHAN_QUEUE_CAP]}
    local k
    for (( k = 0; k < CHAN_COUNT[endpoint] - 1; k++ )); do
        CHAN_QUEUE[endpoint * CHAN_QUEUE_CAP + k]=${CHAN_QUEUE[endpoint * CHAN_QUEUE_CAP + k + 1]}
    done
    CHAN_COUNT[endpoint]=$((CHAN_COUNT[endpoint] - 1))
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

ipc_init

shm_write 1 5 161; check $OUT 1 "shm write"
shm_read 1 5; check $OUT 161 "shm read"
shm_read 2 5; check $OUT 0 "other region"
shm_write 1 99 255; check $OUT 0 "oob write"
shm_read 1 99; check $OUT -1 "oob read"

pipe_write 65; pipe_write 66; pipe_write 67
pipe_read; check $OUT 65 "pipe1"
pipe_read; check $OUT 66 "pipe2"
pipe_read; check $OUT 67 "pipe3"
pipe_read; check $OUT -1 "pipe empty"

# Pipe full
ipc_init
for (( k = 0; k < PIPE_CAP; k++ )); do pipe_write $((k + 100)); done
pipe_write 99; check $OUT 0 "pipe full"
pipe_read
pipe_write 99; check $OUT 1 "post-drain"

# Channel
ipc_init
chan_send 1 16777216; check $OUT 0 "send to closed"
chan_listen 1
chan_send 1 51966; check $OUT 1 "send 1"   # 0xCAFE
chan_send 1 47806; check $OUT 1 "send 2"   # 0xBABE
chan_recv 1; check $OUT 51966 "recv 1"
chan_recv 1; check $OUT 47806 "recv 2"
chan_recv 1; check $OUT -1 "recv empty"
chan_recv 2; check $OUT -1 "recv unopened"

echo "ipc: $PASS/18 ok"
