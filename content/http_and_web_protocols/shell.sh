#!/usr/bin/env bash
# Vidya — HTTP and Web Protocols in Shell (Bash)
#
# HTTP/1.1 request parser. Bash uses arrays for parsed fields; raw
# bytes flow through as strings (CRLF preserved with $'...').
#
# The body is framed by Content-Length (RFC 9112 §6.3), never "whatever
# follows the headers": on a keep-alive connection the rest of the buffer
# is the next pipelined request, and treating it as body is the root of
# request smuggling. Chunked Transfer-Encoding is out of scope.

set -uo pipefail

REQ_METHOD=""
REQ_PATH=""
REQ_VERSION=""
declare -a HDR_NAMES HDR_VALUES
HDR_COUNT=0
REQ_BODY=""
PARSE_OK=0
BODY_CAP=$(( 1 << 20 ))   # 413 Content Too Large above this

# parse_request RAW_TEXT — sets the globals; PARSE_OK=1 on success, 0 on
# malformed input. (The exit status is not the result: it is 0 either way.)
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
        # A header line without ':' is malformed — reject, like cyrius.cyr.
        [[ $hl == *:* ]] || return
        local name=${hl%%:*}
        # Value = after the first ':', minus optional leading whitespace
        # (RFC 9112 OWS). `${hl#*: }` would demand exactly one space and
        # return the whole line for "Host:x".
        local value=${hl#*:}
        value=${value#"${value%%[![:blank:]]*}"}
        # Lowercase name
        name=${name,,}
        HDR_NAMES[HDR_COUNT]=$name
        HDR_VALUES[HDR_COUNT]=$value
        HDR_COUNT=$((HDR_COUNT + 1))
    done

    # Content-Length counts BYTES; in a UTF-8 locale ${#s} and ${s:0:n}
    # count characters. The C locale makes both byte-wise (restored on
    # return, since it is local).
    local LC_ALL=C
    local body_len=0                              # no Content-Length, no body
    header_lookup "content-length"
    if (( HDR_FOUND )); then
        [[ $HDR_OUT =~ ^[0-9]+$ ]] || return      # 400 Bad Request
        # Strip leading zeros: "010" would otherwise be read as octal,
        # and a 20-digit value would wrap bash's 64-bit arithmetic.
        local v=${HDR_OUT#"${HDR_OUT%%[!0]*}"}
        (( ${#v} <= 7 && 10#${v:-0} <= BODY_CAP )) || return   # 413
        body_len=$(( 10#${v:-0} ))
    fi
    (( body_len <= ${#REQ_BODY} )) || return     # body not fully received
    REQ_BODY=${REQ_BODY:0:body_len}
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
check "$REQ_BODY" "" "no Content-Length, no body"

# 8. Content-Length frames the body: trailing bytes are the next request
parse_request $'POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n\r\n'
check_n $PARSE_OK 1 "pipelined req ok"
check "$REQ_BODY" "hello" "body stops at Content-Length"

# 9. A short body is incomplete, not accepted
parse_request $'POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort'
check_n $PARSE_OK 0 "short body rejected"

# 10. Non-numeric and oversize Content-Length are rejected
parse_request $'POST /x HTTP/1.1\r\nContent-Length: 5x\r\n\r\nhello'
check_n $PARSE_OK 0 "non-numeric Content-Length rejected"
parse_request $'POST /x HTTP/1.1\r\nContent-Length: 18446744073709551621\r\n\r\nhello'
check_n $PARSE_OK 0 "Content-Length past 64 bits rejected (no wrap to 5)"

# 11. Content-Length is bytes: "é" is 2 bytes (1 character in UTF-8)
parse_request $'POST /x HTTP/1.1\r\nContent-Length: 2\r\n\r\n\xc3\xa9'
check_n $PARSE_OK 1 "2-byte body accepted under CL 2"

# The denominator is a CLAIM about how many checks this file runs, and it
# had drifted to 24 while the file actually runs 16. The gate only
# reads the exit status, so the wrong number shipped green. Assert the
# count so it can never drift silently again.
EXPECTED=23
if [[ $PASS -ne $EXPECTED ]]; then
    echo "FAIL: ran $PASS checks, expected $EXPECTED" >&2
    exit 1
fi
echo "http_and_web_protocols: $PASS/$EXPECTED ok"
