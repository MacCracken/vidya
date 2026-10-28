#!/usr/bin/env bash
# Vidya — TLS and Encryption in Shell (Bash)
#
# Simulation of TLS 1.3 handshake state machine + cipher negotiation
# + cert chain verification + a toy (NOT authenticated) seal/open.

set -uo pipefail

readonly ST_INIT=0
readonly ST_HELLO_SENT=1
readonly ST_SERVER_HELLO=2
readonly ST_CERT_VERIFIED=3
readonly ST_ESTABLISHED=4
readonly ST_FAILED=5

readonly TLS_AES_128_GCM_SHA256=4865        # 0x1301
readonly TLS_AES_256_GCM_SHA384=4866        # 0x1302
readonly TLS_CHACHA20_POLY1305_SHA256=4867  # 0x1303
readonly TLS_RSA_AES_128_CBC_SHA=47         # 0x002F

is_tls13_cipher() {
    case $1 in
        $TLS_AES_128_GCM_SHA256|$TLS_AES_256_GCM_SHA384|$TLS_CHACHA20_POLY1305_SHA256) return 0;;
    esac
    return 1
}

# pick_cipher SRV_LIST CLI_LIST -> sets PICK
pick_cipher() {
    local srv=$1 cli=$2
    local s c
    for s in $srv; do
        if is_tls13_cipher $s; then
            for c in $cli; do
                if [[ $s -eq $c ]]; then PICK=$s; return; fi
            done
        fi
    done
    PICK=0
}

# Cert encoding: "subject:issuer" string. Chains/trusts are
# space-separated lists of these strings.

cert_subject() { echo "${1%%:*}"; }
cert_issuer()  { echo "${1#*:}"; }

# verify_chain CHAIN TRUST -> sets CHAIN_OK
verify_chain() {
    local chain="$1" trust="$2"
    local arr=($chain)
    local n=${#arr[@]}
    if [[ $n -eq 0 ]]; then CHAIN_OK=0; return; fi
    local i
    for (( i = 0; i < n - 1; i++ )); do
        local issuer=$(cert_issuer "${arr[i]}")
        local next_subj=$(cert_subject "${arr[i+1]}")
        if [[ "$issuer" != "$next_subj" ]]; then CHAIN_OK=0; return; fi
    done
    local last_subj=$(cert_subject "${arr[n-1]}")
    local r
    for r in $trust; do
        if [[ "$(cert_subject "$r")" == "$last_subj" ]]; then CHAIN_OK=1; return; fi
    done
    CHAIN_OK=0
}

cert_matches_hostname() {
    local cert=$1 hostname=$2
    [[ "$(cert_subject "$cert")" == "$hostname" ]]
}

# ---------------------------------------------------------------------------
# WARNING — THIS IS NOT AUTHENTICATED ENCRYPTION. DO NOT USE IT AS SUCH.
#
# demo_seal / demo_open below are a byte-wise XOR plus a "tag" that is nothing
# more than the SUM of the bytes, folded with the key and nonce. A sum does not
# depend on the order of what it adds up, so the tag is permutation-invariant:
# any rearrangement of the same bytes produces exactly the same tag.
#
# Concretely, "transfer 10 usd" and "transfer u0 1sd" differ only by a swap of
# the bytes at index 9 and index 12. Both sum to 1362, so under this file's
# key/nonce (42, 7) both carry tag 1407, and demo_open happily accepts the
# second one as if the sender had written it. That is a forgery. A real AEAD
# (AES-GCM, ChaCha20-Poly1305 — the ciphers negotiated above) uses a keyed,
# position-dependent MAC precisely so this cannot happen.
#
# What this code IS for: showing the STRUCTURAL SHAPE of an AEAD API — seal
# produces ciphertext plus a tag, open recomputes the tag and refuses to
# return plaintext unless it matches. The shape is real; the checksum is not.
# Never roll your own; use a vetted library.
# ---------------------------------------------------------------------------

# Bash works on integer arrays of byte values for the plaintext.

# xor_stream OUT_NAME SRC_NAME LEN KEY
xor_stream() {
    local -n out=$1
    local -n src=$2
    local len=$3 key=$4 i
    for (( i = 0; i < len; i++ )); do out[i]=$(( src[i] ^ key )); done
}

# weak_checksum SRC_NAME LEN KEY NONCE -> sets TAG
# Order-blind by construction: swapping two bytes leaves TAG unchanged.
weak_checksum() {
    local -n src=$1
    local len=$2 key=$3 nonce=$4
    local sum=0 i
    for (( i = 0; i < len; i++ )); do sum=$((sum + src[i])); done
    TAG=$(( (sum ^ key) ^ nonce ))
}

# demo_seal PT_NAME LEN KEY NONCE -> sets CT[] (global) + TAG
declare -a CT
demo_seal() {
    xor_stream CT "$1" "$2" "$3"
    weak_checksum "$1" "$2" "$3" "$4"
}

# demo_open CT_NAME LEN KEY NONCE CLAIMED_TAG -> sets PT_OUT[] + DEMO_OK (1/0)
# DEMO_OK=1 means "the weak checksum matched", NOT "this message is authentic".
declare -a PT_OUT
demo_open() {
    xor_stream PT_OUT "$1" "$2" "$3"
    weak_checksum PT_OUT "$2" "$3" "$4"
    if [[ $TAG -eq $5 ]]; then DEMO_OK=1; else DEMO_OK=0; fi
}

# Handshake driver
HS_STATE=$ST_INIT
HS_NEGOTIATED=0

hs_init() { HS_STATE=$ST_INIT; HS_NEGOTIATED=0; }

# hs_advance SRV CLI CHAIN TRUST HOSTNAME
hs_advance() {
    local srv=$1 cli=$2 chain=$3 trust=$4 hostname=$5
    case $HS_STATE in
        $ST_INIT) HS_STATE=$ST_HELLO_SENT;;
        $ST_HELLO_SENT)
            pick_cipher "$srv" "$cli"
            if [[ $PICK -eq 0 ]]; then HS_STATE=$ST_FAILED; return; fi
            HS_NEGOTIATED=$PICK
            HS_STATE=$ST_SERVER_HELLO;;
        $ST_SERVER_HELLO)
            verify_chain "$chain" "$trust"
            if [[ $CHAIN_OK -eq 0 ]]; then HS_STATE=$ST_FAILED; return; fi
            local arr=($chain)
            if ! cert_matches_hostname "${arr[0]}" "$hostname"; then
                HS_STATE=$ST_FAILED; return
            fi
            HS_STATE=$ST_CERT_VERIFIED;;
        $ST_CERT_VERIFIED) HS_STATE=$ST_ESTABLISHED;;
    esac
}

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

# Cipher negotiation
SRV="$TLS_AES_128_GCM_SHA256 $TLS_AES_256_GCM_SHA384"
CLI="$TLS_AES_128_GCM_SHA256 $TLS_CHACHA20_POLY1305_SHA256"
pick_cipher "$SRV" "$CLI"; check $PICK $TLS_AES_128_GCM_SHA256 "pick"
pick_cipher "$TLS_RSA_AES_128_CBC_SHA" "$CLI"; check $PICK 0 "legacy"

# Cert chain
CHAIN="100:200 200:300 300:300"
TRUST="300:300"
verify_chain "$CHAIN" "$TRUST"; check $CHAIN_OK 1 "chain"
verify_chain "$CHAIN" "999:999"; check $CHAIN_OK 0 "bad trust"
verify_chain "100:100" "$TRUST"; check $CHAIN_OK 0 "ss leaf"

# Demo seal/open (see the warning above — not authenticated encryption)
declare -a PT=(115 101 99 114 101 116 32 109 101 115 115 97 103 101)  # "secret message"
PT_LEN=14
demo_seal PT $PT_LEN 42 7; SAVED_TAG=$TAG
demo_open CT $PT_LEN 42 7 $SAVED_TAG; check $DEMO_OK 1 "roundtrip"
# Tampered ciphertext: a single flipped bit changes the sum, so this one is
# caught. A swap of two bytes would NOT be — that is the whole weakness.
ORIG=${CT[5]}
CT[5]=$(( ORIG ^ 1 ))
demo_open CT $PT_LEN 42 7 $SAVED_TAG; check $DEMO_OK 0 "tampered"
CT[5]=$ORIG
demo_open CT $PT_LEN 42 7 $((SAVED_TAG ^ 1)); check $DEMO_OK 0 "wrong tag"

# Handshake happy path
hs_init
check $HS_STATE $ST_INIT "init"
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100; check $HS_STATE $ST_HELLO_SENT "hello sent"
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100; check $HS_STATE $ST_SERVER_HELLO "server hello"
check $HS_NEGOTIATED $TLS_AES_128_GCM_SHA256 "negotiated"
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100; check $HS_STATE $ST_CERT_VERIFIED "cert verified"
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100; check $HS_STATE $ST_ESTABLISHED "established"

# Hostname mismatch
hs_init
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 100
hs_advance "$SRV" "$CLI" "$CHAIN" "$TRUST" 999
check $HS_STATE $ST_FAILED "hostname mismatch"

# The denominator is a CLAIM about how many checks this file runs, and it
# had drifted to 16 while the file actually runs 15. The gate only
# reads the exit status, so the wrong number shipped green. Assert the
# count so it can never drift silently again.
EXPECTED=15
if [[ $PASS -ne $EXPECTED ]]; then
    echo "FAIL: ran $PASS checks, expected $EXPECTED" >&2
    exit 1
fi
echo "tls_and_encryption: $PASS/$EXPECTED ok"
