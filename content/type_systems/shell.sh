#!/usr/bin/env bash
# Vidya — Type Systems in Shell (Bash)
#
# Bash is dynamically and weakly typed — everything is a string by default.
# declare/typeset can add constraints: -i for integers, -a for arrays,
# -A for associative arrays, -r for readonly. This is as close to a
# "type system" as shell gets.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Everything is a string ─────────────────────────────────────────
num="42"
str="42"
assert_eq "$num" "$str" "string comparison of numbers"

# Arithmetic context treats strings as numbers
result=$((num + 8))
assert_eq "$result" "50" "arithmetic on string"

# ── declare -i: integer type ───────────────────────────────────────
declare -i counter=0
counter+=5           # arithmetic addition, not string concat!
assert_eq "$counter" "5" "integer add"

counter="0+0"        # expressions are evaluated; non-numeric causes error with -u
assert_eq "$counter" "0" "integer expression"

# ── declare -r: readonly (immutable) ───────────────────────────────
declare -r constant="immutable"
assert_eq "$constant" "immutable" "readonly value"
# constant="changed"  # ← would error: readonly variable

# ── declare -a: indexed array ──────────────────────────────────────
declare -a fruits=("apple" "banana" "cherry")
assert_eq "${fruits[0]}" "apple" "array index"
assert_eq "${#fruits[@]}" "3" "array length"

fruits+=("date")
assert_eq "${#fruits[@]}" "4" "array append"

# ── declare -A: associative array (map) ────────────────────────────
declare -A config
config[host]="localhost"
config[port]="3000"
config[debug]="true"

assert_eq "${config[host]}" "localhost" "assoc array access"
assert_eq "${#config[@]}" "3" "assoc array size"

# Check key existence
if [[ -v config[host] ]]; then
    result="exists"
else
    result="missing"
fi
assert_eq "$result" "exists" "key exists"

if [[ -v config[missing] ]]; then
    result="exists"
else
    result="missing"
fi
assert_eq "$result" "missing" "key missing"

# ── declare -l / -u: case enforcement (Bash 4+) ───────────────────
declare -l lowercase_var
lowercase_var="HELLO"
assert_eq "$lowercase_var" "hello" "lowercase enforcement"

declare -u uppercase_var
uppercase_var="hello"
assert_eq "$uppercase_var" "HELLO" "uppercase enforcement"

# ── nameref: variable references (Bash 4.3+) ───────────────────────
target="original"
declare -n ref=target
assert_eq "$ref" "original" "nameref read"
ref="modified"
assert_eq "$target" "modified" "nameref write"
unset -n ref  # unset the nameref, not the target

# ── Type checking via patterns ──────────────────────────────────────
is_integer() { [[ "$1" =~ ^-?[0-9]+$ ]]; }
is_float() { [[ "$1" =~ ^-?[0-9]*\.[0-9]+$ ]]; }
is_boolean() { [[ "$1" =~ ^(true|false)$ ]]; }
is_empty() { [[ -z "$1" ]]; }

assert_eq "$(is_integer "42" && echo yes || echo no)" "yes" "is integer"
assert_eq "$(is_integer "abc" && echo yes || echo no)" "no" "not integer"
assert_eq "$(is_float "3.14" && echo yes || echo no)" "yes" "is float"
assert_eq "$(is_boolean "true" && echo yes || echo no)" "yes" "is boolean"
assert_eq "$(is_empty "" && echo yes || echo no)" "yes" "is empty"

# ── Function "interfaces": convention-based polymorphism ────────────
# Shell doesn't have interfaces, but you can use function naming conventions

greet_english() { echo "hello, $1"; }
greet_spanish() { echo "hola, $1"; }
greet_french() { echo "bonjour, $1"; }

# Dynamic dispatch via variable function names
lang="english"
result=$("greet_${lang}" "world")
assert_eq "$result" "hello, world" "dynamic dispatch"

lang="spanish"
result=$("greet_${lang}" "mundo")
assert_eq "$result" "hola, mundo" "spanish dispatch"

# ── Structs via associative arrays ──────────────────────────────────
new_point() {
    local -n point=$1
    point[x]=$2
    point[y]=$3
}

point_distance() {
    local -n p=$1
    # Integer-only math; use bc for floating point
    echo $(( p[x] * p[x] + p[y] * p[y] ))
}

declare -A pt
new_point pt 3 4
assert_eq "${pt[x]}" "3" "point x"
assert_eq "$(point_distance pt)" "25" "point distance squared"

# ── Export: type information across process boundary ────────────────
# Only strings cross process boundaries via environment
export MY_VAR="42"
result=$(bash -c 'echo "$MY_VAR"')
assert_eq "$result" "42" "exported across process"
unset MY_VAR
# Arrays and associative arrays CANNOT be exported

echo "All type system examples passed."
