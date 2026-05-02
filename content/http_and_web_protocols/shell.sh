#!/usr/bin/env bash
# Vidya — HTTP and Web Protocols in Shell (Bash)
#
# HTTP/1.1 request parser. Bash uses arrays for parsed fields; raw
# bytes flow through as strings (CRLF preserved with $'...').

set -uo pipefail

REQ_METHOD=""
REQ_PATH=""
REQ_VERSION=""
declare -a HDR_NAMES HDR_VALUES
HDR_COUNT=0
REQ_BODY=""
PARSE_OK=0

# parse_request RAW_TEXT — sets the globals. Returns 1 on success.
parse_request() {
    local raw=$1
    REQ_METHOD=""; REQ_PATH=""; REQ_VERSION=""
    HDR_NAMES=(); HDR_VALUES=(); HDR_COUNT=0
    REQ_BODY=""
    PARSE_OK=0

    # Split on \r\n\r\n into headers section and body
    local sep=$'\r\n\r\n'
    local idx=${raw%%"$sep"*}
    if [[ "$idx" == "$raw" ]]; then return; fi   # no \r\n\r\n
    local headers_part=$idx
    REQ_BODY=${raw#*"$sep"}

    # Split headers_part on \r\n
    local IFS=$'\n'
    local lines=()
    local line
    while IFS= read -r line; do lines+=("${line%$'\r'}"); done <<< "${headers_part//$'\r\n'/$'\n'}"

    # First line is the request line
    local rl=${lines[0]}
    REQ_METHOD=${rl%% *}
    local rest=${rl#* }
    REQ_PATH=${rest%% *}
    REQ_VERSION=${rest#* }

    # Remaining lines are headers
    local i
    for (( i = 1; i < ${#lines[@]}; i++ )); do
        local hl=${lines[i]}
        [[ -z "$hl" ]] && continue
        local name=${hl%%:*}
        local value=${hl#*: }
        # Lowercase name
        name=${name,,}
        HDR_NAMES[HDR_COUNT]=$name
        HDR_VALUES[HDR_COUNT]=$value
        HDR_COUNT=$((HDR_COUNT + 1))
    done
    PARSE_OK=1
}

# header_lookup NAME → sets HDR_OUT (or empty + HDR_FOUND=0)
header_lookup() {
    local query=${1,,}
    local i
    HDR_FOUND=0
    HDR_OUT=""
    for (( i = 0; i < HDR_COUNT; i++ )); do
        if [[ ${HDR_NAMES[i]} == "$query" ]]; then
            HDR_OUT=${HDR_VALUES[i]}
            HDR_FOUND=1
            return
        fi
    done
}

PASS=0
check() { [[ "$1" == "$2" ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got '$1' want '$2')" >&2; exit 1; }; }
check_n() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

# 1. Simple GET
req1=$'GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n'
parse_request "$req1"
check_n $PARSE_OK 1 "req1 ok"
check "$REQ_METHOD" "GET" "method"
check "$REQ_PATH" "/index.html" "path"
check "$REQ_VERSION" "HTTP/1.1" "version"
check_n $HDR_COUNT 1 "hdr count"

# 2. Case-insensitive lookup
header_lookup "host"; check "$HDR_OUT" "example.com" "host (lower)"
header_lookup "HOST"; check "$HDR_OUT" "example.com" "HOST (upper)"
header_lookup "Host"; check "$HDR_OUT" "example.com" "Host (mixed)"

# 3. Multiple headers
req3=$'GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n'
parse_request "$req3"
check_n $HDR_COUNT 3 "3 headers"
header_lookup "user-agent"
check "$HDR_OUT" "test/1.0" "user-agent value"

# 4. POST with body
req4=$'POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world'
parse_request "$req4"
check "$REQ_METHOD" "POST" "POST method"
check "$REQ_BODY" "hello world" "POST body"

# 5. Body with CRLF preserved
req5=$'POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!'
parse_request "$req5"
check_n ${#REQ_BODY} 13 "body5 len"
check "$REQ_BODY" $'line1\r\nline2!' "body5 bytes"

# 6. Malformed (no \r\n\r\n)
req6=$'GET / HTTP/1.1\r\nHost: x\r\n'
parse_request "$req6"
check_n $PARSE_OK 0 "malformed rejected"

# 7. Absent header
parse_request "$req1"
header_lookup "authorization"
check_n $HDR_FOUND 0 "absent header"

echo "http_and_web_protocols: $PASS/24 ok"
