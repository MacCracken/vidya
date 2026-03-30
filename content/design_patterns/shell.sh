#!/usr/bin/env bash
# Vidya — Design Patterns in Shell (Bash)
#
# Shell patterns: function dispatch tables (strategy), trap for
# cleanup (RAII), associative arrays for state machines, and
# configuration via environment variables (dependency injection).

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Strategy pattern: function dispatch ────────────────────────────────
discount_none() { echo "$1"; }
discount_ten_pct() { echo $(( $1 * 9 / 10 )); }
discount_flat_five() {
    local result=$(( $1 - 5 ))
    (( result < 0 )) && result=0
    echo "$result"
}

apply_discount() {
    local price=$1 strategy=$2
    "$strategy" "$price"
}

assert_eq "$(apply_discount 100 discount_none)" "100" "no discount"
assert_eq "$(apply_discount 100 discount_ten_pct)" "90" "10%"
assert_eq "$(apply_discount 100 discount_flat_five)" "95" "five off"
assert_eq "$(apply_discount 3 discount_flat_five)" "0" "floor 0"

# ── Observer pattern: callback list ────────────────────────────────────
declare -a LISTENERS=()
OBSERVER_LOG=""

observer_register() {
    LISTENERS+=("$1")
}

observer_emit() {
    local event=$1
    for listener in "${LISTENERS[@]}"; do
        "$listener" "$event"
    done
}

listener_a() { OBSERVER_LOG+="A:$1 "; }
listener_b() { OBSERVER_LOG+="B:$1 "; }

observer_register listener_a
observer_register listener_b
observer_emit "click"
observer_emit "hover"
assert_eq "${OBSERVER_LOG% }" "A:click B:click A:hover B:hover" "observer"

# ── State machine via associative array ────────────────────────────────
declare -A TRANSITIONS=(
    ["locked:unlock"]="closed"
    ["closed:open"]="open"
    ["open:close"]="closed"
    ["closed:lock"]="locked"
)

state_transition() {
    local current=$1 action=$2
    local key="${current}:${action}"
    if [[ -z "${TRANSITIONS[$key]+x}" ]]; then
        echo "ERROR"
        return 1
    fi
    echo "${TRANSITIONS[$key]}"
}

state="locked"
state=$(state_transition "$state" "unlock")
assert_eq "$state" "closed" "unlock"
state=$(state_transition "$state" "open")
assert_eq "$state" "open" "open"
state=$(state_transition "$state" "close")
state=$(state_transition "$state" "lock")
assert_eq "$state" "locked" "relock"

if state_transition "locked" "open" >/dev/null 2>&1; then
    echo "FAIL: should reject locked→open" >&2
    exit 1
fi

# ── RAII via trap (cleanup on exit) ────────────────────────────────────
CLEANUP_LOG=""
test_trap_cleanup() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # trap ensures cleanup even on error
    trap "rm -rf '$tmpdir'; CLEANUP_LOG+='cleaned '" RETURN

    echo "data" > "$tmpdir/test.txt"
    [[ -f "$tmpdir/test.txt" ]]
    # tmpdir cleaned on function return
}

test_trap_cleanup
assert_eq "$CLEANUP_LOG" "cleaned " "trap cleanup"

# ── Builder via function chaining ──────────────────────────────────────
# Shell doesn't have objects, but we can use a config file or variables

declare -A SERVER_CONFIG

server_builder_reset() {
    SERVER_CONFIG=()
    SERVER_CONFIG[max_connections]=100
    SERVER_CONFIG[timeout_ms]=5000
}

server_set_host() { SERVER_CONFIG[host]="$1"; }
server_set_port() { SERVER_CONFIG[port]="$1"; }
server_set_timeout() { SERVER_CONFIG[timeout_ms]="$1"; }

server_build() {
    if [[ -z "${SERVER_CONFIG[host]+x}" ]]; then
        echo "ERROR: host required" >&2
        return 1
    fi
    if [[ -z "${SERVER_CONFIG[port]+x}" ]]; then
        echo "ERROR: port required" >&2
        return 1
    fi
    echo "${SERVER_CONFIG[host]}:${SERVER_CONFIG[port]}"
}

server_builder_reset
server_set_host "localhost"
server_set_port 8080
server_set_timeout 3000
result=$(server_build)
assert_eq "$result" "localhost:8080" "builder"
assert_eq "${SERVER_CONFIG[timeout_ms]}" "3000" "timeout set"

# Missing required field
server_builder_reset
server_set_host "localhost"
if server_build 2>/dev/null; then
    echo "FAIL: should require port" >&2
    exit 1
fi

# ── Dependency injection via environment ───────────────────────────────
# Shell's natural DI: configure behavior via environment variables

log_message() {
    local logger=${LOGGER:-stdout}
    local msg=$1
    echo "[$logger] $msg"
}

result=$(LOGGER=stdout log_message "processing order")
assert_eq "$result" "[stdout] processing order" "stdout logger"

result=$(LOGGER=test log_message "processing order")
assert_eq "$result" "[test] processing order" "test logger"

# ── Factory via case dispatch ──────────────────────────────────────────
shape_area() {
    local shape=$1
    shift
    case "$shape" in
        circle)
            # area = π × r² (integer approx: 314 × r² / 100)
            echo $(( 314 * $1 * $1 / 100 ))
            ;;
        rectangle)
            echo $(( $1 * $2 ))
            ;;
        triangle)
            echo $(( $1 * $2 / 2 ))
            ;;
        *)
            echo "ERROR" >&2
            return 1
            ;;
    esac
}

assert_eq "$(shape_area circle 5)" "78" "circle area"
assert_eq "$(shape_area rectangle 3 4)" "12" "rect area"
assert_eq "$(shape_area triangle 6 4)" "12" "triangle area"

if shape_area hexagon 1 2>/dev/null; then
    echo "FAIL: unknown shape" >&2
    exit 1
fi

echo "All design patterns examples passed."
