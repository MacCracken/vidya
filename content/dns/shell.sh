#!/usr/bin/env bash
# Vidya — DNS in Shell (Bash)
#
# In-memory resolver: zone (parallel arrays), CNAME chains, TTL cache,
# negative cache. Logical clock = NOW global.

set -uo pipefail

readonly RR_A=1
readonly RR_AAAA=2
readonly RR_CNAME=3
readonly RR_MX=4
readonly RR_TXT=5

readonly CNAME_MAX_DEPTH=16
readonly NXDOMAIN=-1
readonly NEGATIVE_TTL=300

declare -a Z_NAME Z_TYPE Z_TTL Z_VALUE
Z_COUNT=0
declare -a C_NAME C_TYPE C_VALUE C_EXPIRES
C_COUNT=0
NOW=0
LAST_STATUS=0

zone_add() {
    Z_NAME[Z_COUNT]=$1
    Z_TYPE[Z_COUNT]=$2
    Z_TTL[Z_COUNT]=$3
    Z_VALUE[Z_COUNT]=$4
    Z_COUNT=$((Z_COUNT + 1))
}

zone_lookup() {
    local name=$1 rtype=$2
    local depth=0 cur=$name i
    while (( depth <= CNAME_MAX_DEPTH )); do
        for (( i = 0; i < Z_COUNT; i++ )); do
            if (( Z_NAME[i] == cur && Z_TYPE[i] == rtype )); then
                ZL_OUT=${Z_VALUE[i]}
                return
            fi
        done
        if (( rtype == RR_A )); then
            local cn=0
            for (( i = 0; i < Z_COUNT; i++ )); do
                if (( Z_NAME[i] == cur && Z_TYPE[i] == RR_CNAME )); then
                    cn=${Z_VALUE[i]}
                    break
                fi
            done
            if (( cn == 0 )); then ZL_OUT=$NXDOMAIN; return; fi
            cur=$cn
            depth=$((depth + 1))
        else
            ZL_OUT=$NXDOMAIN
            return
        fi
    done
    ZL_OUT=$NXDOMAIN
}

cache_init() { C_COUNT=0; NOW=0; C_NAME=(); C_TYPE=(); C_VALUE=(); C_EXPIRES=(); }
advance_time() { NOW=$((NOW + $1)); }

cache_insert() {
    local name=$1 rtype=$2 value=$3 ttl=$4
    local exp=$((NOW + ttl)) i
    for (( i = 0; i < C_COUNT; i++ )); do
        if (( C_NAME[i] == name && C_TYPE[i] == rtype )); then
            C_VALUE[i]=$value
            C_EXPIRES[i]=$exp
            return
        fi
    done
    C_NAME[C_COUNT]=$name
    C_TYPE[C_COUNT]=$rtype
    C_VALUE[C_COUNT]=$value
    C_EXPIRES[C_COUNT]=$exp
    C_COUNT=$((C_COUNT + 1))
}

cache_lookup() {
    local name=$1 rtype=$2 i
    for (( i = 0; i < C_COUNT; i++ )); do
        if (( C_NAME[i] == name && C_TYPE[i] == rtype && C_EXPIRES[i] > NOW )); then
            LAST_STATUS=1
            CL_OUT=${C_VALUE[i]}
            return
        fi
    done
    LAST_STATUS=0
    CL_OUT=$NXDOMAIN
}

resolve() {
    local name=$1 rtype=$2
    cache_lookup $name $rtype
    if (( LAST_STATUS == 1 )); then RESOLVE_OUT=$CL_OUT; return; fi
    zone_lookup $name $rtype
    local v=$ZL_OUT
    if (( v == NXDOMAIN )); then
        cache_insert $name $rtype $NXDOMAIN $NEGATIVE_TTL
        RESOLVE_OUT=$NXDOMAIN
        return
    fi
    local ttl=$NEGATIVE_TTL i
    for (( i = 0; i < Z_COUNT; i++ )); do
        if (( Z_NAME[i] == name && Z_TYPE[i] == rtype )); then ttl=${Z_TTL[i]}; break; fi
    done
    cache_insert $name $rtype $v $ttl
    RESOLVE_OUT=$v
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

zone_add 1 $RR_A 300 2130706433       # 0x7F000001
zone_add 1 $RR_MX 3600 10
zone_add 1 $RR_TXT 60 99
zone_add 2 $RR_CNAME 600 1
zone_add 3 $RR_CNAME 600 4
zone_add 4 $RR_A 60 134744072         # 0x08080808
zone_add 5 $RR_A 3600 167772161       # 0x0A000001
zone_add 10 $RR_CNAME 600 11
zone_add 11 $RR_CNAME 600 10
for k in {20..36}; do zone_add $k $RR_CNAME 600 $((k + 1)); done
zone_add 37 $RR_A 60 305419896        # 0x12345678

zone_lookup 1 $RR_A; check $ZL_OUT 2130706433 "a1"
zone_lookup 2 $RR_A; check $ZL_OUT 2130706433 "cname"
zone_lookup 3 $RR_A; check $ZL_OUT 134744072 "cname2"
zone_lookup 10 $RR_A; check $ZL_OUT $NXDOMAIN "loop"
zone_lookup 20 $RR_A; check $ZL_OUT $NXDOMAIN "deep"

cache_init
resolve 1 $RR_A; first=$RESOLVE_OUT
check $LAST_STATUS 0 "first miss"
resolve 1 $RR_A
check $LAST_STATUS 1 "second hit"
check $RESOLVE_OUT $first "same"

advance_time 301
resolve 1 $RR_A
check $LAST_STATUS 0 "expired"
check $RESOLVE_OUT 2130706433 "requery"

cache_init
resolve 99 $RR_A; check $RESOLVE_OUT $NXDOMAIN "nxdomain"
resolve 99 $RR_A
check $LAST_STATUS 1 "neg cache"

zone_lookup 1 $RR_MX; check $ZL_OUT 10 "mx"
zone_lookup 1 $RR_TXT; check $ZL_OUT 99 "txt"
zone_lookup 1 $RR_AAAA; check $ZL_OUT $NXDOMAIN "aaaa"

echo "dns: $PASS/15 ok"
