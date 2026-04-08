#!/bin/bash
# Vidya — Lexing and Parsing in Shell (Bash)
#
# Demonstrates the front end of a compiler: turning text into tokens,
# then tokens into structure. Shell's read/IFS is a natural tokenizer,
# and shell arithmetic $((...)) is itself a recursive descent parser.
#
# Key concepts:
#   - Lexing: characters → tokens (using parameter expansion and regex)
#   - Tokenization: splitting input on delimiters
#   - Recursive descent parsing: functions calling functions
#   - Operator precedence: multiplication before addition
#   - AST as string representation

set -euo pipefail

PASS=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
    (( ++PASS ))
}

# ── Simple tokenizer using IFS ──────────────────────────────────────
# IFS (Internal Field Separator) is bash's built-in lexer.
# Changing IFS changes what counts as a token boundary.

tokenize_csv() {
    local input="$1"
    local -a tokens
    IFS=',' read -ra tokens <<< "$input"
    echo "${tokens[*]}"
}

result=$(tokenize_csv "hello,world,42")
assert_eq "$result" "hello world 42" "CSV tokenization"

# ── Character-level lexer ────────────────────────────────────────────
# Walk the input character by character, classify each token.
# This is what real lexers do — just with lookup tables instead of case.

lex_arithmetic() {
    local input="$1"
    local -a tokens=()
    local i=0 len=${#input}
    local num=""

    while (( i < len )); do
        local ch="${input:i:1}"
        case "$ch" in
            [0-9])
                num+="$ch"
                ;;
            [+\-*/\(\)])
                # Flush any accumulated number
                if [[ -n "$num" ]]; then
                    tokens+=("NUM:$num")
                    num=""
                fi
                case "$ch" in
                    +) tokens+=("PLUS") ;;
                    -) tokens+=("MINUS") ;;
                    \*) tokens+=("STAR") ;;
                    /) tokens+=("SLASH") ;;
                    \() tokens+=("LPAREN") ;;
                    \)) tokens+=("RPAREN") ;;
                esac
                ;;
            " ") # skip whitespace
                if [[ -n "$num" ]]; then
                    tokens+=("NUM:$num")
                    num=""
                fi
                ;;
            *)
                echo "ERROR: unexpected character '$ch'" >&2
                return 1
                ;;
        esac
        (( i++ ))
    done
    # Flush trailing number
    if [[ -n "$num" ]]; then
        tokens+=("NUM:$num")
    fi
    tokens+=("EOF")
    echo "${tokens[*]}"
}

result=$(lex_arithmetic "3 + 42 * 5")
assert_eq "$result" "NUM:3 PLUS NUM:42 STAR NUM:5 EOF" "lex arithmetic expression"

result=$(lex_arithmetic "(10-2)/4")
assert_eq "$result" "LPAREN NUM:10 MINUS NUM:2 RPAREN SLASH NUM:4 EOF" "lex with parens"

result=$(lex_arithmetic "0")
assert_eq "$result" "NUM:0 EOF" "lex single zero"

# ── Token counting ───────────────────────────────────────────────────
count_tokens() {
    local -a tokens
    IFS=' ' read -ra tokens <<< "$(lex_arithmetic "$1")"
    echo "${#tokens[@]}"
}

assert_eq "$(count_tokens "1+2")" "4" "1+2 = 4 tokens (NUM PLUS NUM EOF)"
assert_eq "$(count_tokens "10 * 20 + 30")" "6" "3 operands + 2 ops + EOF"

# ── Recursive descent parser for arithmetic ──────────────────────────
# Grammar:
#   expr   = term (('+' | '-') term)*
#   term   = factor (('*' | '/') factor)*
#   factor = NUMBER | '(' expr ')'
#
# We store tokens in a global array and use a global position cursor.
# IMPORTANT: All parse functions return via a global RESULT variable
# instead of echo, because $(...) creates a subshell that can't update
# the parent's POS. This is the standard bash pattern for recursive
# descent — globals for shared state, no subshells.

declare -a TOKENS=()
POS=0
RESULT=0

parser_init() {
    IFS=' ' read -ra TOKENS <<< "$(lex_arithmetic "$1")"
    POS=0
    RESULT=0
}

# factor = NUMBER | '(' expr ')'
parse_factor() {
    local tok="${TOKENS[$POS]}"
    if [[ "$tok" =~ ^NUM:(.+) ]]; then
        (( POS++ )) || true
        RESULT=${BASH_REMATCH[1]}
    elif [[ "$tok" == "LPAREN" ]]; then
        (( POS++ )) || true
        parse_expr
        # RESULT is set by parse_expr
        local inner=$RESULT
        if [[ "${TOKENS[$POS]}" != "RPAREN" ]]; then
            echo "Parse error: expected RPAREN, got ${TOKENS[$POS]}" >&2
            return 1
        fi
        (( POS++ )) || true
        RESULT=$inner
    else
        echo "Parse error: unexpected token $tok" >&2
        return 1
    fi
}

# term = factor (('*' | '/') factor)*
parse_term() {
    parse_factor
    local left=$RESULT
    while true; do
        local op="${TOKENS[$POS]}"
        if [[ "$op" == "STAR" ]]; then
            (( POS++ )) || true
            parse_factor
            left=$(( left * RESULT ))
        elif [[ "$op" == "SLASH" ]]; then
            (( POS++ )) || true
            parse_factor
            left=$(( left / RESULT ))
        else
            break
        fi
    done
    RESULT=$left
}

# expr = term (('+' | '-') term)*
parse_expr() {
    parse_term
    local left=$RESULT
    while true; do
        local op="${TOKENS[$POS]}"
        if [[ "$op" == "PLUS" ]]; then
            (( POS++ )) || true
            parse_term
            left=$(( left + RESULT ))
        elif [[ "$op" == "MINUS" ]]; then
            (( POS++ )) || true
            parse_term
            left=$(( left - RESULT ))
        else
            break
        fi
    done
    RESULT=$left
}

evaluate() {
    parser_init "$1"
    parse_expr
    echo "$RESULT"
}

assert_eq "$(evaluate "3 + 4")" "7" "parse 3+4"
assert_eq "$(evaluate "3 + 4 * 5")" "23" "parse 3+4*5 (precedence)"
assert_eq "$(evaluate "(3 + 4) * 5")" "35" "parse (3+4)*5 (parens)"
assert_eq "$(evaluate "100 / 10 - 2")" "8" "parse 100/10-2"
assert_eq "$(evaluate "2 * 3 + 4 * 5")" "26" "parse 2*3+4*5"
assert_eq "$(evaluate "(2 + 3) * (4 + 5)")" "45" "parse (2+3)*(4+5)"

# ── Keyword recognition ─────────────────────────────────────────────
# Real lexers distinguish keywords from identifiers. Pattern matching
# after tokenization is a common approach.

classify_word() {
    case "$1" in
        if|then|else|fi|while|do|done|for|in)
            echo "KEYWORD:$1" ;;
        [a-zA-Z_]*)
            echo "IDENT:$1" ;;
        [0-9]*)
            echo "NUMBER:$1" ;;
        *)
            echo "UNKNOWN:$1" ;;
    esac
}

assert_eq "$(classify_word "if")" "KEYWORD:if" "keyword: if"
assert_eq "$(classify_word "count")" "IDENT:count" "identifier: count"
assert_eq "$(classify_word "42")" "NUMBER:42" "number literal"
assert_eq "$(classify_word "while")" "KEYWORD:while" "keyword: while"
assert_eq "$(classify_word "myVar")" "IDENT:myVar" "identifier: myVar"

# ── Span tracking ────────────────────────────────────────────────────
# Real lexers track where each token starts and ends for error messages.

lex_with_spans() {
    local input="$1"
    local i=0 len=${#input} start
    local num=""

    while (( i < len )); do
        local ch="${input:i:1}"
        case "$ch" in
            [0-9])
                if [[ -z "$num" ]]; then
                    start=$i
                fi
                num+="$ch"
                ;;
            *)
                if [[ -n "$num" ]]; then
                    printf "NUM(%s) @ %d..%d\n" "$num" "$start" "$i"
                    num=""
                fi
                case "$ch" in
                    +) printf "PLUS @ %d\n" "$i" ;;
                    " ") ;; # skip
                esac
                ;;
        esac
        (( i++ ))
    done
    if [[ -n "$num" ]]; then
        printf "NUM(%s) @ %d..%d\n" "$num" "$start" "$i"
    fi
}

spans=$(lex_with_spans "12 + 345")
expected_spans="NUM(12) @ 0..2
PLUS @ 3
NUM(345) @ 5..8"
assert_eq "$spans" "$expected_spans" "token spans"

echo "$PASS tests passed"
exit 0
