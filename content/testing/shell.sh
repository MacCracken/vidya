#!/usr/bin/env bash
# Vidya — Testing in Shell (Bash)
#
# Shell testing uses exit codes as assertions, trap for test cleanup,
# and structured output for reporting. While frameworks like bats exist,
# the built-in tools (test, [[, set -e) provide a solid foundation.

set -euo pipefail

# ── Test framework ───────────────────────────────────────���──────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    ((TESTS_RUN++)) || true
    if [[ "$got" == "$expected" ]]; then
        ((TESTS_PASSED++)) || true
    else
        ((TESTS_FAILED++)) || true
        echo "  FAIL: $msg: got '$got', expected '$expected'" >&2
    fi
}

assert_true() {
    local msg="$2"
    ((TESTS_RUN++)) || true
    if eval "$1"; then
        ((TESTS_PASSED++)) || true
    else
        ((TESTS_FAILED++)) || true
        echo "  FAIL: $msg" >&2
    fi
}

assert_fails() {
    local msg="$2"
    ((TESTS_RUN++)) || true
    set +e
    eval "$1" > /dev/null 2>&1
    local exit_code=$?
    set -e
    if [[ "$exit_code" -ne 0 ]]; then
        ((TESTS_PASSED++)) || true
    else
        ((TESTS_FAILED++)) || true
        echo "  FAIL: expected failure: $msg" >&2
    fi
}

# ── Code under test ────────────────────────────────────────────────

parse_kv() {
    local line="$1"
    if [[ "$line" != *=* ]]; then
        echo "error: no '=' found in: $line" >&2
        return 1
    fi
    local key="${line%%=*}"
    local value="${line#*=}"
    key=$(echo "$key" | xargs)  # trim
    value=$(echo "$value" | xargs)  # trim
    if [[ -z "$key" ]]; then
        echo "error: empty key" >&2
        return 1
    fi
    echo "$key=$value"
}

clamp() {
    local value="$1" min="$2" max="$3"
    if ((min > max)); then
        echo "error: min ($min) > max ($max)" >&2
        return 1
    fi
    if ((value < min)); then
        echo "$min"
    elif ((value > max)); then
        echo "$max"
    else
        echo "$value"
    fi
}

# ── Basic assertion tests ──────────────────────────────────────────
result=$(parse_kv "host=localhost")
assert_eq "$result" "host=localhost" "parse valid"

result=$(parse_kv "  port = 3000  ")
assert_eq "$result" "port=3000" "parse trimmed"

result=$(parse_kv "key=")
assert_eq "$result" "key=" "parse empty value"

# ── Error case tests ───────────────────────────────────────────────
assert_fails 'parse_kv "no_equals"' "missing equals"
assert_fails 'parse_kv "=value"' "empty key"

# ── Table-driven tests ─────────────────────────────────────────────
# Shell equivalent: arrays of test cases

clamp_cases=(
    # "value:min:max:expected:name"
    "5:0:10:5:in range"
    "-1:0:10:0:below min"
    "100:0:10:10:above max"
    "0:0:10:0:at min"
    "10:0:10:10:at max"
    "5:5:5:5:min equals max"
)

for tc in "${clamp_cases[@]}"; do
    IFS=: read -r value min max expected name <<< "$tc"
    got=$(clamp "$value" "$min" "$max")
    assert_eq "$got" "$expected" "clamp: $name"
done

# ── Testing error conditions ───────────────────────────────────────
assert_fails 'clamp 5 10 0' "clamp invalid range"

# ── Testing output capture ─────────────────────────────────────────
# Capture stdout and stderr separately
stdout=$(parse_kv "key=value" 2>/dev/null)
assert_eq "$stdout" "key=value" "stdout capture"

stderr=$(parse_kv "invalid" 2>&1 || true)
assert_true '[[ "$stderr" == *"no"*"="* ]]' "stderr capture"

# ── Setup and teardown pattern ──────────────────────────────────────
setup() {
    TEST_DIR=$(mktemp -d)
    echo "test data" > "$TEST_DIR/input.txt"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Test with setup/teardown
setup
assert_eq "$(cat "$TEST_DIR/input.txt")" "test data" "setup file"
assert_true '[[ -d "$TEST_DIR" ]]' "setup dir exists"
teardown
assert_true '[[ ! -d "$TEST_DIR" ]]' "teardown cleaned"

# ── Testing with timeout ───────────────────────────────────────────
assert_completes_in() {
    local seconds="$1" cmd="$2" msg="$3"
    ((TESTS_RUN++)) || true
    if timeout "$seconds" bash -c "$cmd" > /dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
    else
        ((TESTS_FAILED++)) || true
        echo "  FAIL: timeout or error: $msg" >&2
    fi
}

assert_completes_in 2 "echo hello" "quick command"

# ── Test report ─────────────────────────────────────────────────────
if ((TESTS_FAILED > 0)); then
    echo "FAILED: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed" >&2
    exit 1
fi

echo "All testing examples passed."
