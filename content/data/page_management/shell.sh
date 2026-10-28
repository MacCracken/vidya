#!/usr/bin/env bash
# Vidya — Page Management in Shell (Bash)
#
# Bash has no random-access file I/O primitives, so we simulate the
# 4KB-page database in memory using indexed integer arrays. PAGES[]
# stores one i64 per page slot (the value at byte offset 0 of the
# page); FREE_NEXT[] stores the next-page pointer for freed pages.
# Header lives in HDR_PAGECOUNT and HDR_FREEHEAD scalars. The test
# surface is exactly the cyrius reference's six assertions.

set -euo pipefail

readonly PAGE_SZ=4096
readonly MAGIC=1346458194  # 0x50415452

declare -a PAGES
declare -a FREE_NEXT
HDR_MAGIC=0
HDR_PAGECOUNT=0
HDR_FREEHEAD=0

hdr_init() {
    HDR_MAGIC=$MAGIC
    HDR_PAGECOUNT=1
    HDR_FREEHEAD=0
}

hdr_verify() { [[ $HDR_MAGIC -eq $MAGIC ]]; }

# page_alloc — return new page number via PAGE_OUT global
page_alloc() {
    if [[ $HDR_FREEHEAD -ne 0 ]]; then
        local fh=$HDR_FREEHEAD
        HDR_FREEHEAD=${FREE_NEXT[fh]:-0}
        FREE_NEXT[fh]=0
        PAGE_OUT=$fh
        return 0
    fi
    local num=$HDR_PAGECOUNT
    HDR_PAGECOUNT=$((HDR_PAGECOUNT + 1))
    PAGES[num]=0
    PAGE_OUT=$num
}

page_free() {
    local num=$1
    FREE_NEXT[num]=$HDR_FREEHEAD
    HDR_FREEHEAD=$num
}

page_write() {
    local num=$1
    local val=$2
    PAGES[num]=$val
}

page_read() {
    local num=$1
    PAGE_OUT=${PAGES[num]:-0}
}

PASS=0
check_eq() {
    local got=$1 want=$2 label=$3
    if [[ $got -eq $want ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL $label: got $got want $want" >&2
        exit 1
    fi
}

main() {
    hdr_init
    if hdr_verify; then PASS=$((PASS + 1)); else echo "FAIL magic ok" >&2; exit 1; fi
    check_eq "$HDR_PAGECOUNT" 1 "pgcount starts at 1"

    page_alloc; p1=$PAGE_OUT
    check_eq "$p1" 1 "first alloc = 1"
    page_alloc; p2=$PAGE_OUT
    check_eq "$p2" 2 "second alloc = 2"

    page_write "$p1" 42
    page_read "$p1"; got=$PAGE_OUT
    check_eq "$got" 42 "read back 42"

    page_free "$p2"
    page_alloc; p3=$PAGE_OUT
    check_eq "$p3" 2 "reused freed page"

    echo "page_management: $PASS/6 ok"
}

main
