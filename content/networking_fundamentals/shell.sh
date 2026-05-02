#!/usr/bin/env bash
# Vidya — Networking Fundamentals in Shell (Bash)
#
# In-memory simulation of TCP socket state machine + lifecycle.

set -uo pipefail

readonly ST_CLOSED=0
readonly ST_LISTEN=1
readonly ST_ESTABLISHED=3
readonly ST_FIN_WAIT=4
readonly SOCK_CAP=8
readonly BUF_CAP=256

declare -a STATE PORT PEER RXLEN
declare -A PORT_TO_SOCK
NEXT_FREE=1

# RX bufs: encode as flat 8*256 byte array (RXBUF[s*256+i])
declare -a RXBUF

net_init() {
    local i
    for (( i = 0; i < SOCK_CAP; i++ )); do
        STATE[i]=$ST_CLOSED; PORT[i]=0; PEER[i]=0; RXLEN[i]=0
    done
    PORT_TO_SOCK=()
    NEXT_FREE=1
    RXBUF=()
}

sock_create() {
    local i
    for (( i = NEXT_FREE; i < SOCK_CAP; i++ )); do
        if (( STATE[i] == ST_CLOSED && PORT[i] == 0 )); then
            NEXT_FREE=$((i + 1))
            OUT=$i
            return
        fi
    done
    OUT=0
}

state_get() {
    local s=$1
    if (( s == 0 || s >= SOCK_CAP )); then OUT=-1; return; fi
    OUT=${STATE[s]}
}

sock_bind() {
    local s=$1 port=$2
    if (( s == 0 || s >= SOCK_CAP )); then OUT=0; return; fi
    if [[ -n ${PORT_TO_SOCK[$port]+x} ]]; then OUT=0; return; fi
    if (( PORT[s] != 0 )); then OUT=0; return; fi
    PORT[s]=$port
    PORT_TO_SOCK[$port]=$s
    OUT=1
}

sock_listen() {
    local s=$1
    if (( s == 0 || s >= SOCK_CAP )); then OUT=0; return; fi
    if (( STATE[s] != ST_CLOSED || PORT[s] == 0 )); then OUT=0; return; fi
    STATE[s]=$ST_LISTEN
    OUT=1
}

sock_connect() {
    local client=$1 port=$2
    if (( client == 0 || client >= SOCK_CAP )); then OUT=0; return; fi
    local server=${PORT_TO_SOCK[$port]:-0}
    if (( server == 0 || STATE[server] != ST_LISTEN )); then OUT=0; return; fi
    STATE[client]=$ST_ESTABLISHED
    STATE[server]=$ST_ESTABLISHED
    PEER[client]=$server
    PEER[server]=$client
    OUT=1
}

sock_send_byte() {
    local s=$1 b=$2
    if (( s == 0 || s >= SOCK_CAP || STATE[s] != ST_ESTABLISHED )); then OUT=0; return; fi
    local peer=${PEER[s]}
    if (( peer == 0 || RXLEN[peer] >= BUF_CAP )); then OUT=0; return; fi
    RXBUF[peer * BUF_CAP + RXLEN[peer]]=$b
    RXLEN[peer]=$((RXLEN[peer] + 1))
    OUT=1
}

sock_recv_byte() {
    local s=$1
    if (( s == 0 || s >= SOCK_CAP )); then OUT=-1; return; fi
    local st=${STATE[s]}
    if (( st != ST_ESTABLISHED && st != ST_FIN_WAIT )); then OUT=-1; return; fi
    if (( RXLEN[s] == 0 )); then OUT=-1; return; fi
    local b=${RXBUF[s * BUF_CAP]}
    local i
    for (( i = 0; i < RXLEN[s] - 1; i++ )); do
        RXBUF[s * BUF_CAP + i]=${RXBUF[s * BUF_CAP + i + 1]}
    done
    RXLEN[s]=$((RXLEN[s] - 1))
    OUT=$b
}

sock_close() {
    local s=$1
    if (( s == 0 || s >= SOCK_CAP || STATE[s] == ST_CLOSED )); then OUT=0; return; fi
    local p=${PORT[s]}
    # Capture the port to a scalar first — `unset 'arr[ARR[s]]'` doesn't
    # expand the inner array reference in bash.
    if (( p != 0 )); then unset "PORT_TO_SOCK[$p]"; fi
    STATE[s]=$ST_CLOSED
    PORT[s]=0
    PEER[s]=0
    OUT=1
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

net_init
sock_create; srv=$OUT
state_get $srv; check $OUT $ST_CLOSED "init closed"

sock_bind $srv 8080; check $OUT 1 "bind"
sock_listen $srv; check $OUT 1 "listen"
state_get $srv; check $OUT $ST_LISTEN "listen state"

sock_create; cli=$OUT
sock_connect $cli 8080; check $OUT 1 "connect"
state_get $cli; check $OUT $ST_ESTABLISHED "cli est"
state_get $srv; check $OUT $ST_ESTABLISHED "srv est"

sock_send_byte $cli 65; check $OUT 1 "send A"
sock_send_byte $cli 66; check $OUT 1 "send B"
sock_recv_byte $srv; check $OUT 65 "recv A"
sock_recv_byte $srv; check $OUT 66 "recv B"
sock_recv_byte $srv; check $OUT -1 "empty"
sock_send_byte $srv 67; check $OUT 1 "echo"
sock_recv_byte $cli; check $OUT 67 "cli recv"

sock_close $cli; check $OUT 1 "close"
state_get $cli; check $OUT $ST_CLOSED "closed"

sock_create; srv2=$OUT
sock_bind $srv2 8080; check $OUT 0 "port reuse rejected"

sock_recv_byte $cli; check $OUT -1 "recv closed -1"

sock_close $srv
sock_bind $srv2 8080; check $OUT 1 "rebind after close"

echo "networking_fundamentals: $PASS/19 ok"
