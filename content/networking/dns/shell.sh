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
# Three negative outcomes, three answers. NXDOMAIN tells an RFC 8020
# resolver that nothing exists at or below the name, so answering it for a
# name that exists but lacks the type (AAAA for name 1 below) would deny
# that name's other records too; that case is NODATA. A CNAME loop or an
# over-deep chain is a failure to resolve (RFC 1034 §3.6.2): SERVFAIL.
readonly NXDOMAIN=-1   # the name does not exist at all (RCODE 3)
readonly NODATA=-2     # the name exists, but has no record of this type (RFC 2308 §2.2)
readonly SERVFAIL=-3   # CNAME loop or chain too deep
readonly NEGATIVE_TTL=300

declare -a Z_NAME Z_TYPE Z_TTL Z_VALUE
Z_COUNT=0
declare -a C_NAME C_TYPE C_VALUE C_EXPIRES
C_COUNT=0
NOW=0
LAST_STATUS=0
# TTL of the last successful zone_lookup: the MINIMUM over every record on
# the CNAME chain. Each link expires on its own TTL, so the collapsed
# answer may be cached no longer than its shortest-lived link.
ZL_TTL=0

zone_add() {
    Z_NAME[Z_COUNT]=$1
    Z_TYPE[Z_COUNT]=$2
    Z_TTL[Z_COUNT]=$3
    Z_VALUE[Z_COUNT]=$4
    Z_COUNT=$((Z_COUNT + 1))
}

zone_lookup() {
    local name=$1 rtype=$2
    local depth=0 cur=$name i min_ttl=-1 miss
    while (( depth <= CNAME_MAX_DEPTH )); do
        miss=$NXDOMAIN
        for (( i = 0; i < Z_COUNT; i++ )); do
            if (( Z_NAME[i] == cur )); then miss=$NODATA; fi
            if (( Z_NAME[i] == cur && Z_TYPE[i] == rtype )); then
                ZL_OUT=${Z_VALUE[i]}
                ZL_TTL=${Z_TTL[i]}
                if (( min_ttl >= 0 && min_ttl < ZL_TTL )); then ZL_TTL=$min_ttl; fi
                return
            fi
        done
        if (( rtype == RR_A )); then
            local cn=0
            for (( i = 0; i < Z_COUNT; i++ )); do
                if (( Z_NAME[i] == cur && Z_TYPE[i] == RR_CNAME )); then
                    cn=${Z_VALUE[i]}
                    if (( min_ttl < 0 || Z_TTL[i] < min_ttl )); then min_ttl=${Z_TTL[i]}; fi
                    break
                fi
            done
            if (( cn == 0 )); then ZL_OUT=$miss; return; fi
            cur=$cn
            depth=$((depth + 1))
        else
            ZL_OUT=$miss
            return
        fi
    done
    ZL_OUT=$SERVFAIL
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
    if (( v < 0 )); then   # NXDOMAIN, NODATA and SERVFAIL are all cached briefly
        cache_insert $name $rtype $v $NEGATIVE_TTL
        RESOLVE_OUT=$v
        return
    fi
    # Not "the TTL of a (name, rtype) record": for 3 -> CNAME -> 4 no such
    # record exists, and that fallback cached 4's 60 s A for 300 s.
    cache_insert $name $rtype $v $ZL_TTL
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
zone_lookup 10 $RR_A; check $ZL_OUT $SERVFAIL "loop"   # 10 -> 11 -> 10
zone_lookup 20 $RR_A; check $ZL_OUT $SERVFAIL "deep"   # 17 hops > CNAME_MAX_DEPTH

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

# CNAME chain 3 -> 4 (A ttl 60): the cached answer expires with the A
cache_init
resolve 3 $RR_A; check $RESOLVE_OUT 134744072 "cname answer"
advance_time 61
resolve 3 $RR_A
check $LAST_STATUS 0 "cname answer expires with the 60 s A, not 300 s"

cache_init
resolve 99 $RR_A; check $RESOLVE_OUT $NXDOMAIN "nxdomain"
resolve 99 $RR_A
check $LAST_STATUS 1 "neg cache"

zone_lookup 1 $RR_MX; check $ZL_OUT 10 "mx"
zone_lookup 1 $RR_TXT; check $ZL_OUT 99 "txt"
zone_lookup 1 $RR_AAAA; check $ZL_OUT $NODATA "aaaa on an existing name is NODATA"
zone_lookup 99 $RR_AAAA; check $ZL_OUT $NXDOMAIN "aaaa on a missing name is NXDOMAIN"

echo "dns: $PASS/18 ok"
