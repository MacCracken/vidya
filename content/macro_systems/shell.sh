#!/bin/bash
# Vidya — Macro Systems in Shell (Bash)
#
# Shell has no macro system in the Rust/C sense, but it has powerful
# text-expansion mechanisms that serve similar purposes:
#   - Parameter expansion (${var:-default}, ${var//pat/rep})
#   - Arithmetic expansion $(( ))
#   - Command substitution $()
#   - Aliases (textual replacement before parsing)
#   - eval (runtime code generation — dangerous)
#   - source (file inclusion, like C's #include)
#   - Here-docs and here-strings for templates

set -euo pipefail

PASS=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
    PASS=$((PASS + 1))
}

# ── Parameter expansion: shell's most powerful "macro" ────────────

# Default values — like Rust's unwrap_or
unset maybe_val
assert_eq "${maybe_val:-fallback}" "fallback" "default value"

maybe_val="present"
assert_eq "${maybe_val:-fallback}" "present" "value present"

# Assign default if unset — ${var:=default} sets the variable
unset auto_set
: "${auto_set:=initialized}"
assert_eq "$auto_set" "initialized" "assign default"

# Error if unset — ${var:?message} aborts with message
# safe_var="${required_var:?must be set}"  # would abort

# ── String manipulation expansions ────────────────────────────────

text="Hello, World!"

# Substring: ${var:offset:length}
assert_eq "${text:0:5}" "Hello" "substring"
assert_eq "${text:7}" "World!" "substring from offset"

# Length: ${#var}
assert_eq "${#text}" "13" "string length"

# Pattern substitution: ${var/pattern/replacement}
assert_eq "${text/World/Shell}" "Hello, Shell!" "single replace"

# Global substitution: ${var//pattern/replacement}
csv="a,b,c,d"
assert_eq "${csv//,/ }" "a b c d" "global replace"

# Remove prefix: ${var#pattern} (shortest) ${var##pattern} (longest)
filepath="/home/user/docs/file.tar.gz"
assert_eq "${filepath##*/}" "file.tar.gz" "basename via ##"
assert_eq "${filepath#*/}" "home/user/docs/file.tar.gz" "remove leading /"

# Remove suffix: ${var%pattern} (shortest) ${var%%pattern} (longest)
assert_eq "${filepath%.gz}" "/home/user/docs/file.tar" "remove .gz"
assert_eq "${filepath%%.*}" "/home/user/docs/file" "remove all extensions"

# Case conversion (Bash 4+)
word="hello"
assert_eq "${word^}" "Hello" "capitalize first"
assert_eq "${word^^}" "HELLO" "uppercase all"
upper="WORLD"
assert_eq "${upper,,}" "world" "lowercase all"

# ── Arithmetic expansion ─────────────────────────────────────────
# $(( )) evaluates arithmetic — like a numeric macro

assert_eq "$((2 + 3))" "5" "arithmetic add"
assert_eq "$((10 % 3))" "1" "arithmetic mod"
assert_eq "$((1 << 8))" "256" "arithmetic shift"
assert_eq "$((0xFF))" "255" "hex literal"

# Ternary operator
x=5
assert_eq "$(( x > 3 ? 1 : 0 ))" "1" "arithmetic ternary"

# Compound expressions
assert_eq "$(( (3 + 4) * 2 ))" "14" "arithmetic compound"

# ── Command substitution: computed values ─────────────────────────
# $() captures stdout — the most general expansion

now=$(date +%Y)
assert_eq "$((now >= 2024))" "1" "command substitution"

# Nested substitution
inner=$(echo "$(echo "nested")")
assert_eq "$inner" "nested" "nested substitution"

# ── Brace expansion: compile-time enumeration ────────────────────
# Brace expansion happens before variable expansion — truly "macro-like"

expanded=$(echo {a,b,c}_{1,2})
assert_eq "$expanded" "a_1 a_2 b_1 b_2 c_1 c_2" "brace expansion"

# Sequence
seq_result=$(echo {1..5})
assert_eq "$seq_result" "1 2 3 4 5" "sequence expansion"

# With step
step_result=$(echo {0..10..3})
assert_eq "$step_result" "0 3 6 9" "step expansion"

# ── Here-doc templates ────────────────────────────────────────────
# Here-docs with variable expansion act as simple template engines

name="vidya"
version="1.0"

config=$(cat <<EOF
app_name=$name
app_version=$version
debug=false
EOF
)

# Variables were expanded in the template
first_line=$(echo "$config" | head -1)
assert_eq "$first_line" "app_name=vidya" "heredoc template"

# Quoted delimiter prevents expansion (raw template)
raw=$(cat <<'EOF'
value=$name
EOF
)
assert_eq "$raw" 'value=$name' "heredoc no expand"

# ── eval: runtime code generation ────────────────────────────────
# eval parses and executes a string as code.
# DANGER: never eval untrusted input — injection risk.

# Generate variable assignments dynamically
for i in 1 2 3; do
    eval "gen_var_$i=$((i * 10))"
done

assert_eq "$gen_var_1" "10" "eval generated var 1"
assert_eq "$gen_var_2" "20" "eval generated var 2"
assert_eq "$gen_var_3" "30" "eval generated var 3"

# Safer alternative: use declare
for i in 4 5; do
    declare "gen_var_$i=$((i * 10))"
done
assert_eq "$gen_var_4" "40" "declare generated var"
assert_eq "$gen_var_5" "50" "declare generated var 2"

# ── source: file inclusion ───────────────────────────────────────
# source (or .) reads and executes another file in the current shell.
# Like C's #include — the sourced code runs in our scope.

tmplib=$(mktemp)
trap "rm -f '$tmplib'" EXIT

cat > "$tmplib" <<'LIBEOF'
sourced_greet() {
    echo "hello from sourced lib"
}
SOURCED_CONST="sourced_value"
LIBEOF

# shellcheck disable=SC1090
source "$tmplib"

assert_eq "$(sourced_greet)" "hello from sourced lib" "source function"
assert_eq "$SOURCED_CONST" "sourced_value" "source variable"

# ── "Code generation" with functions ──────────────────────────────
# Generate repetitive functions programmatically

make_converter() {
    local from="$1" to="$2" factor="$3"
    eval "${from}_to_${to}() { echo \$(( \$1 * ${factor} )); }"
}

make_converter km miles 62    # approximate: * 0.62, using integers * 100
make_converter meters cm 100

assert_eq "$(meters_to_cm 5)" "500" "generated converter"
assert_eq "$(km_to_miles 10)" "620" "generated converter 2"

# ── Indirect expansion: ${!var} ───────────────────────────────────
# Access a variable whose name is stored in another variable
# Like a one-level macro expansion

color_red="FF0000"
color_blue="0000FF"

lookup="color_red"
assert_eq "${!lookup}" "FF0000" "indirect expansion"

lookup="color_blue"
assert_eq "${!lookup}" "0000FF" "indirect expansion 2"

# List variables matching a prefix: ${!prefix@}
pfx_count=0
for var in "${!color_@}"; do
    pfx_count=$((pfx_count + 1))
done
assert_eq "$pfx_count" "2" "prefix listing"

# ── Summary ───────────────────────────────────────────────────────
# Shell "macro" mechanisms mapped to traditional macro concepts:
#
#   Macro concept           Shell equivalent
#   ─────────────────       ─────────────────────────────────
#   Text substitution       Parameter expansion ${var...}
#   Conditional compilation ${var:-default}, ${var:+alt}
#   Numeric macros          Arithmetic expansion $(( ))
#   Include                 source / .
#   Template instantiation  Here-docs with expansion
#   Code generation         eval, declare (prefer declare)
#   Compile-time iteration  Brace expansion {a,b,c}
#   Token pasting           String concatenation "${a}_${b}"

echo "All macro system examples passed ($PASS assertions)."
exit 0
