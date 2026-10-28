#!/usr/bin/env bash
# Vidya — Strings in Shell (Bash)
#
# Bash strings are untyped — everything is text. Quoting rules matter:
# double quotes expand variables, single quotes are literal. String
# manipulation uses parameter expansion, not method calls.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# ── Creation and quoting ────────────────────────────────────────────
literal='hello world'         # single quotes: literal, no expansion
name="world"
interpolated="hello $name"    # double quotes: variable expansion
assert_eq "$interpolated" "hello world" "interpolation"

# Command substitution
date_str=$(echo "2024-01-01")
assert_eq "$date_str" "2024-01-01" "command substitution"

# ── String length ───────────────────────────────────────────────────
str="hello"
assert_eq "${#str}" "5" "string length"

# ── Substring extraction ───────────────────────────────────────────
text="hello world"
assert_eq "${text:0:5}" "hello" "substring"
assert_eq "${text:6}" "world" "substring from offset"

# ── String replacement ─────────────────────────────────────────────
path="/home/user/docs/file.txt"
assert_eq "${path/user/admin}" "/home/admin/docs/file.txt" "replace first"
assert_eq "${path//\//|}" "|home|user|docs|file.txt" "replace all"

# ── Prefix and suffix removal ──────────────────────────────────────
filename="archive.tar.gz"
assert_eq "${filename%.gz}" "archive.tar" "remove shortest suffix"
assert_eq "${filename%%.*}" "archive" "remove longest suffix"
assert_eq "${filename#*.}" "tar.gz" "remove shortest prefix"
assert_eq "${filename##*.}" "gz" "remove longest prefix (extension)"

# ── Case conversion (Bash 4+) ──────────────────────────────────────
word="Hello"
assert_eq "${word,,}" "hello" "lowercase"
assert_eq "${word^^}" "HELLO" "uppercase"

# ── Default values ──────────────────────────────────────────────────
unset_var=""
assert_eq "${unset_var:-default}" "default" "default for empty"

set_var="actual"
assert_eq "${set_var:-default}" "actual" "no default needed"

# ── String comparison ───────────────────────────────────────────────
[[ "hello" == "hello" ]] || fail "equality"
[[ "abc" < "def" ]] || fail "less than"
[[ "hello" == h* ]] || fail "glob pattern"
[[ "hello123" =~ ^[a-z]+[0-9]+$ ]] || fail "regex match"

# ── Concatenation ──────────────────────────────────────────────────
a="hello"
b="world"
c="$a $b"
assert_eq "$c" "hello world" "concatenation"

# Concatenation in a loop — use array + join pattern
words=("hello" "world" "from" "shell")
joined=$(IFS=' '; echo "${words[*]}")
assert_eq "$joined" "hello world from shell" "array join"

# ── Here strings and here documents ────────────────────────────────
result=$(cat <<< "hello here-string")
assert_eq "$result" "hello here-string" "here string"

result=$(cat <<EOF
line one
line two
EOF
)
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert_eq "$line_count" "2" "heredoc lines"

# ── Splitting strings ──────────────────────────────────────────────
csv="a,b,c,d"
IFS=',' read -ra parts <<< "$csv"
assert_eq "${#parts[@]}" "4" "split count"
assert_eq "${parts[1]}" "b" "split element"

# ── Trimming whitespace ────────────────────────────────────────────
# Parameter expansion, no subprocess: strip the longest leading run of
# whitespace, then the longest trailing run. (`echo "$s" | xargs` is a
# common "trim" that is wrong: xargs parses quotes and backslashes — "it's"
# fails with "unmatched single quote", C:\path loses its \ — and it
# squeezes internal runs of spaces.)
trim() {
    local s=$1
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}
padded="  hello  "
assert_eq "$(trim "$padded")" "hello" "trim whitespace"
assert_eq "$(trim "  it's  a  test  ")" "it's  a  test" "trim keeps quotes and inner spaces"

echo "All string examples passed."
