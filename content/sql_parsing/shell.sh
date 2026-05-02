#!/bin/bash
# Vidya — SQL Parsing in Shell (Bash)
#
# Idiomatic shape: walk the input string one character at a time using
# parameter expansion (${input:i:1}), classify with [[ ]] character-class
# tests, and accumulate token kind+text into parallel global arrays.
# Bash subshells $(...) cannot mutate parent globals, so we use side-
# effect functions and parallel arrays (TOK_KIND, TOK_TEXT) for output.
# Mirrors the cyrius.cyr reference: SELECT/FROM/WHERE keywords plus
# IDENT, INT, single-char operators, EOF.

set -euo pipefail

PASS=0

assert() {
    if ! eval "$1"; then
        echo "FAIL: $2" >&2
        exit 1
    fi
    (( ++PASS ))
}

# ── Token tables — parallel arrays (set as side-effect of tokenize) ───
declare -a TOK_KIND
declare -a TOK_TEXT
TOK_N=0

upper() {
    # Uppercase via bash's built-in pattern operator
    echo "${1^^}"
}

classify_word() {
    local up
    up=$(upper "$1")
    case "$up" in
        SELECT) echo "SELECT" ;;
        FROM)   echo "FROM" ;;
        WHERE)  echo "WHERE" ;;
        *)      echo "IDENT" ;;
    esac
}

# tokenize <sql> — populates TOK_KIND, TOK_TEXT, TOK_N as globals.
# Returns 0 on success. Cannot use $(tokenize ...) to capture results
# because subshells discard global mutations.
tokenize() {
    local sql="$1"
    local len=${#sql}
    local i=0 ch start text
    TOK_KIND=()
    TOK_TEXT=()
    TOK_N=0

    # NOTE: post-increment `(( i++ ))` returns the OLD value of i — when
    # i was 0, that's a 0, which `set -e` treats as failure. We use
    # i=$((i+1)) consistently to dodge this trap.
    while (( i < len )); do
        ch="${sql:i:1}"
        case "$ch" in
            " "|$'\t'|$'\n'|$'\r')
                i=$((i + 1))
                ;;
            [A-Za-z_])
                start=$i
                while (( i < len )); do
                    ch="${sql:i:1}"
                    [[ "$ch" =~ [A-Za-z0-9_] ]] || break
                    i=$((i + 1))
                done
                text="${sql:start:i-start}"
                TOK_KIND+=("$(classify_word "$text")")
                TOK_TEXT+=("$text")
                TOK_N=$((TOK_N + 1))
                ;;
            [0-9])
                start=$i
                while (( i < len )); do
                    ch="${sql:i:1}"
                    [[ "$ch" =~ [0-9] ]] || break
                    i=$((i + 1))
                done
                text="${sql:start:i-start}"
                TOK_KIND+=("INT")
                TOK_TEXT+=("$text")
                TOK_N=$((TOK_N + 1))
                ;;
            "*")
                TOK_KIND+=("STAR"); TOK_TEXT+=("*"); TOK_N=$((TOK_N + 1)); i=$((i + 1))
                ;;
            "=")
                TOK_KIND+=("EQ"); TOK_TEXT+=("="); TOK_N=$((TOK_N + 1)); i=$((i + 1))
                ;;
            "(")
                TOK_KIND+=("LPAREN"); TOK_TEXT+=("("); TOK_N=$((TOK_N + 1)); i=$((i + 1))
                ;;
            ")")
                TOK_KIND+=("RPAREN"); TOK_TEXT+=(")"); TOK_N=$((TOK_N + 1)); i=$((i + 1))
                ;;
            ",")
                TOK_KIND+=("COMMA"); TOK_TEXT+=(","); TOK_N=$((TOK_N + 1)); i=$((i + 1))
                ;;
            *)
                # Unknown char — skip
                i=$((i + 1))
                ;;
        esac
    done
    TOK_KIND+=("EOF")
    TOK_TEXT+=("")
    TOK_N=$((TOK_N + 1))
}

# is_valid_select: examine TOK_KIND globals after a tokenize call.
# Echoes "1" (valid) or "0" (invalid).
is_valid_select() {
    if (( TOK_N == 0 )) || [[ "${TOK_KIND[0]}" != "SELECT" ]]; then
        echo 0
        return
    fi
    local from_idx=-1 i=0
    while (( i < TOK_N )); do
        if [[ "${TOK_KIND[i]}" == "FROM" ]]; then
            from_idx=$i
            break
        fi
        i=$(( i + 1 ))
    done
    if (( from_idx < 0 )) || (( from_idx == 1 )); then
        echo 0
        return
    fi
    if (( from_idx + 1 >= TOK_N )) || [[ "${TOK_KIND[from_idx + 1]}" != "IDENT" ]]; then
        echo 0
        return
    fi
    echo 1
}

# kinds_match <expected_csv> — returns 0 if TOK_KIND matches expected
kinds_match() {
    local expected="$1"
    local actual
    actual=$(IFS=,; echo "${TOK_KIND[*]}")
    [[ "$actual" == "$expected" ]]
}

# ── Test 1: canonical SELECT (mirrors cyrius reference) ──────────────
tokenize "SELECT * FROM users WHERE id = 1"
assert 'kinds_match "SELECT,STAR,FROM,IDENT,WHERE,IDENT,EQ,INT,EOF"' "canonical kinds"
assert '[[ "${TOK_TEXT[3]}" == "users" ]]' "users text"
assert '[[ "${TOK_TEXT[5]}" == "id" ]]'    "id text"
assert '[[ "${TOK_TEXT[7]}" == "1" ]]'     "1 text"

# ── Test 2: case insensitive ─────────────────────────────────────────
tokenize "select * from T"
assert 'kinds_match "SELECT,STAR,FROM,IDENT,EOF"' "lowercase kinds"
tokenize "Select * From T"
assert 'kinds_match "SELECT,STAR,FROM,IDENT,EOF"' "mixed-case kinds"

# ── Test 3: 'selected' is an identifier, not SELECT ──────────────────
tokenize "selected"
assert '[[ "${TOK_KIND[0]}" == "IDENT" ]]' "'selected' is IDENT"
assert '[[ "${TOK_TEXT[0]}" == "selected" ]]' "'selected' text"

# ── Test 4: parens + commas ──────────────────────────────────────────
tokenize "SELECT (a, b) FROM t"
assert 'kinds_match "SELECT,LPAREN,IDENT,COMMA,IDENT,RPAREN,FROM,IDENT,EOF"' "parens kinds"

# ── Test 5: integer literal ──────────────────────────────────────────
tokenize "12345"
assert '[[ "${TOK_KIND[0]}" == "INT" ]]'   "INT kind"
assert '[[ "${TOK_TEXT[0]}" == "12345" ]]' "12345 text"

# ── Test 6: validator ────────────────────────────────────────────────
tokenize "SELECT * FROM t"
assert '[[ "$(is_valid_select)" == "1" ]]' "valid simple"
tokenize "SELECT a FROM t WHERE id = 1"
assert '[[ "$(is_valid_select)" == "1" ]]' "valid with WHERE"
tokenize "FROM t"
assert '[[ "$(is_valid_select)" == "0" ]]' "leading FROM rejected"
tokenize "SELECT FROM t"
assert '[[ "$(is_valid_select)" == "0" ]]' "empty cols rejected"
tokenize "SELECT * FROM"
assert '[[ "$(is_valid_select)" == "0" ]]' "missing table rejected"

# ── Test 7: whitespace tolerance ─────────────────────────────────────
tokenize "  SELECT	*
FROM	t  "
assert 'kinds_match "SELECT,STAR,FROM,IDENT,EOF"' "whitespace kinds"

echo "All sql_parsing examples passed."
exit 0
