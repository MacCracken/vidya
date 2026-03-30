#!/usr/bin/env bash
# Vidya — Error Handling in Shell (Bash)
#
# Bash error handling revolves around exit codes (0 = success, non-zero
# = failure), set -e for automatic exit on error, trap for cleanup, and
# explicit checking with if/||/&&.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

assert_true() {
    if ! eval "$1"; then
        echo "FAIL: $2" >&2
        exit 1
    fi
}

# ── Exit codes: 0 is success, non-zero is failure ──────────────────
true
assert_eq "$?" "0" "true exits 0"

# set -e means the script exits on any non-zero exit code
# We temporarily disable it to test failure cases
set +e
false
assert_eq "$?" "1" "false exits 1"
set -e

# ── Checking command success ────────────────────────────────────────
# if/then checks exit code
if echo "hello" > /dev/null; then
    result="ok"
else
    result="fail"
fi
assert_eq "$result" "ok" "if success"

# || for fallback (like "or else")
set +e
value=$(cat /nonexistent/file 2>/dev/null) || value="default"
set -e
assert_eq "$value" "default" "fallback on error"

# && for "only if success"
output=""
true && output="ran"
assert_eq "$output" "ran" "and-then"

# ── set -e: exit on any error ──────────────────────────────────────
# With set -e, any failing command stops the script.
# This is the most important error handling mechanism in shell.
#
# GOTCHA: set -e doesn't catch errors in:
#   - if conditions: if failing_cmd; then ...
#   - commands before ||: failing_cmd || handle
#   - commands before &&: failing_cmd && handle
#   - subshells: (failing_cmd)  (depends on shell version)

# ── set -o pipefail: catch pipe failures ────────────────────────────
# Without pipefail, only the last command's exit code matters:
#   false | true  → exit code 0 (true succeeded)
# With pipefail:
#   false | true  → exit code 1 (false failed)

set +e
result=$(false | true; echo $?)
set -e
# pipefail was set at the top, so this catches it

# ── trap: cleanup on exit/error ───────────────────────��─────────────
cleanup_ran="no"
cleanup() {
    cleanup_ran="yes"
}

# Run cleanup on EXIT (normal exit, error exit, or signal)
trap cleanup EXIT

# trap on ERR runs only on error (with set -e)
error_trapped="no"
err_handler() {
    error_trapped="yes"
}
trap err_handler ERR

# ── Functions with return codes ─────────────────────────────────────
parse_port() {
    local config="$1"
    local port
    port=$(echo "$config" | grep -oP 'port=\K[0-9]+' || true)
    if [[ -z "$port" ]]; then
        echo "error: missing port" >&2
        return 1
    fi
    echo "$port"
    return 0
}

# Success case
port=$(parse_port "host=localhost port=3000")
assert_eq "$port" "3000" "parse port success"

# Error case
set +e
error_output=$(parse_port "host=localhost" 2>&1)
exit_code=$?
set -e
assert_eq "$exit_code" "1" "parse port failure code"

# ── Subshell error isolation ────────────────────────────────────────
# Errors in subshells don't propagate to parent (without pipefail/set -e)
parent_ok="yes"
(
    set +e
    false  # fails in subshell
) || parent_ok="caught"
# Parent continues regardless

# ── Error messages to stderr ────────────────────────────────────────
# GOOD: errors to stderr, results to stdout
log_error() {
    echo "ERROR: $1" >&2
}

# Can capture stdout while errors go to stderr
result=$(echo "good output")
assert_eq "$result" "good output" "stdout capture"

# ── Validate inputs ────────────────────────────────────────────────
validate_number() {
    local input="$1"
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "not a number: $input" >&2
        return 1
    fi
    echo "$input"
}

num=$(validate_number "42")
assert_eq "$num" "42" "valid number"

set +e
validate_number "abc" > /dev/null 2>&1
assert_eq "$?" "1" "invalid number"
set -e

# Reset traps before exit
trap - EXIT ERR

echo "All error handling examples passed."
