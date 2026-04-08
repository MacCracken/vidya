#!/bin/bash
# Vidya — Module Systems in Shell (Bash)
#
# Shell has no formal module system. Code organization relies on:
#   - source (.) for file inclusion
#   - Function name prefixes for namespacing
#   - PATH for executable discovery
#   - Subshells for isolation
#   - export for environment propagation
#   - local for function-scoped encapsulation

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

# ── Setup: temp directory for module files ─────────────────────────
MOD_DIR=$(mktemp -d)
trap "rm -rf '$MOD_DIR'" EXIT

# ── source: the basic inclusion mechanism ─────────────────────────
# source (or .) reads a file and executes it in the current shell.
# All functions and variables from the sourced file are available.

cat > "$MOD_DIR/math_lib.sh" <<'EOF'
# math_lib.sh — a "module" of math functions

math_add() { echo $(( $1 + $2 )); }
math_mul() { echo $(( $1 * $2 )); }
math_pow2() { echo $(( $1 * $1 )); }

MATH_PI_APPROX=314  # pi * 100 for integer math
EOF

# shellcheck disable=SC1091
source "$MOD_DIR/math_lib.sh"

assert_eq "$(math_add 3 4)" "7" "sourced function add"
assert_eq "$(math_mul 5 6)" "30" "sourced function mul"
assert_eq "$(math_pow2 8)" "64" "sourced function pow2"
assert_eq "$MATH_PI_APPROX" "314" "sourced constant"

# ── Function namespacing with prefixes ────────────────────────────
# Convention: prefix all functions with module name + underscore.
# This prevents name collisions — shell's substitute for namespaces.

# Module: string utilities
str_upper() { echo "${1^^}"; }
str_lower() { echo "${1,,}"; }
str_len() { echo "${#1}"; }
str_repeat() {
    local s="" i
    for (( i = 0; i < $2; i++ )); do s+="$1"; done
    echo "$s"
}

# Module: array utilities
arr_len() {
    local -n _arr="$1"
    echo "${#_arr[@]}"
}

arr_sum() {
    local -n _arr="$1"
    local total=0
    for v in "${_arr[@]}"; do total=$((total + v)); done
    echo "$total"
}

assert_eq "$(str_upper "hello")" "HELLO" "str module upper"
assert_eq "$(str_len "abcde")" "5" "str module len"
assert_eq "$(str_repeat "ab" 3)" "ababab" "str module repeat"

nums=(10 20 30)
assert_eq "$(arr_len nums)" "3" "arr module len"
assert_eq "$(arr_sum nums)" "60" "arr module sum"

# ── Multiple module files with dependency ─────────────────────────

cat > "$MOD_DIR/log_lib.sh" <<'EOF'
# log_lib.sh — logging "module"
LOG_LEVEL="info"

log_set_level() { LOG_LEVEL="$1"; }

log_msg() {
    local level="$1" msg="$2"
    echo "[$level] $msg"
}

log_info() { log_msg "INFO" "$1"; }
log_warn() { log_msg "WARN" "$1"; }
log_error() { log_msg "ERROR" "$1"; }
EOF

cat > "$MOD_DIR/app.sh" <<'APPEOF'
# app.sh — depends on math_lib and log_lib

app_calculate() {
    local a="$1" b="$2"
    local result
    result=$(math_add "$a" "$b")
    log_info "calculated $a + $b = $result" > /dev/null
    echo "$result"
}
APPEOF

# shellcheck disable=SC1091
source "$MOD_DIR/log_lib.sh"
# shellcheck disable=SC1091
source "$MOD_DIR/app.sh"

assert_eq "$(app_calculate 10 20)" "30" "multi-module dependency"
assert_eq "$(log_info "test")" "[INFO] test" "log module"
assert_eq "$(log_warn "caution")" "[WARN] caution" "log warn"

# ── Include guards (source-once pattern) ──────────────────────────
# Shell has no #pragma once. Use a guard variable.

cat > "$MOD_DIR/guarded.sh" <<'EOF'
# Include guard — only define once
if [[ -n "${_GUARDED_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_GUARDED_SH_LOADED=1

GUARDED_COUNTER=0
guarded_increment() {
    GUARDED_COUNTER=$((GUARDED_COUNTER + 1))
}
EOF

# Source twice — second time should be a no-op
# shellcheck disable=SC1091
source "$MOD_DIR/guarded.sh"
# shellcheck disable=SC1091
source "$MOD_DIR/guarded.sh"

guarded_increment
assert_eq "$GUARDED_COUNTER" "1" "include guard"

# ── PATH: executable module discovery ─────────────────────────────
# PATH is shell's module search path. Adding a directory to PATH
# makes all executables in it available by name.

mkdir -p "$MOD_DIR/bin"

cat > "$MOD_DIR/bin/greet-tool" <<'EOF'
#!/bin/bash
echo "hello from tool"
EOF
chmod +x "$MOD_DIR/bin/greet-tool"

# Add to PATH
export PATH="$MOD_DIR/bin:$PATH"

assert_eq "$(greet-tool)" "hello from tool" "PATH discovery"

# which/command -v finds the resolved path
tool_path=$(command -v greet-tool)
assert_eq "$tool_path" "$MOD_DIR/bin/greet-tool" "command -v resolution"

# ── Subshell isolation: private scope ─────────────────────────────
# A subshell inherits everything but mutations stay local.
# This simulates private module scope.

outer_state="visible"

result=$(
    # This runs in a subshell — a private scope
    private_var="hidden"
    outer_state="modified_inside"
    echo "$private_var"
)

assert_eq "$result" "hidden" "subshell private var"
assert_eq "$outer_state" "visible" "subshell isolation"

# ── export: environment propagation ───────────────────────────────
# export makes a variable available to child processes.
# Non-exported variables are local to the current shell.

MODULE_VERSION="2.0"
export MODULE_EXPORTED="yes"

child_sees_exported=$(bash -c 'echo "${MODULE_EXPORTED:-missing}"')
child_sees_local=$(bash -c 'echo "${MODULE_VERSION:-missing}"')

assert_eq "$child_sees_exported" "yes" "exported var in child"
assert_eq "$child_sees_local" "missing" "non-exported invisible"

# ── Function export ───────────────────────────────────────────────
# export -f makes a function available to child bash processes

exported_fn() { echo "I travel"; }
export -f exported_fn

child_result=$(bash -c 'exported_fn')
assert_eq "$child_result" "I travel" "exported function"

# ── Listing module contents ───────────────────────────────────────
# Introspect what a "module" (prefix group) provides

math_functions=()
while IFS= read -r fn; do
    math_functions+=("$fn")
done < <(declare -F | awk '{print $3}' | grep '^math_')

assert_eq "$((${#math_functions[@]} >= 3))" "1" "list module functions"

# ── Summary ───────────────────────────────────────────────────────
# Module concepts mapped to shell mechanisms:
#
#   Module concept          Shell mechanism
#   ─────────────────       ─────────────────────────────────
#   Import                  source / .
#   Namespace               Function name prefix (mod_func)
#   Public API              Exported functions (export -f)
#   Private scope           Subshell ( ... )
#   Module search path      PATH
#   Include guard           Guard variable + early return
#   Dependency              source order
#   Encapsulation           local variables in functions

echo "All module system examples passed ($PASS assertions)."
exit 0
