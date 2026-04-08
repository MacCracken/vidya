#!/bin/bash
# Vidya — Tracing in Shell (Bash)
#
# Shell has built-in tracing via set -x, PS4 customization, trap DEBUG,
# and introspection variables (BASH_SOURCE, LINENO, FUNCNAME).
# These provide printf-style debugging, structured trace output,
# and function-level instrumentation without external tools.

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

# ── Setup: capture output to files ────────────────────────────────
TRACE_DIR=$(mktemp -d)
trap "rm -rf '$TRACE_DIR'" EXIT

# ── set -x: basic execution tracing ──────────────────────────────
# set -x prints each command before execution to stderr.
# set +x disables it. Trace output goes to stderr (fd 2).

trace_log="$TRACE_DIR/xtrace.log"

# Capture trace output by redirecting stderr
{
    set -x
    result=$((2 + 3))
    greeting="hello"
    set +x
} 2> "$trace_log"

# Trace log should contain the commands that ran
trace_content=$(cat "$trace_log")
assert_eq "$(($(echo "$trace_content" | wc -l) > 0))" "1" "set -x produces output"

# Verify traced commands appear (arithmetic is evaluated before trace)
if echo "$trace_content" | grep -q "result=5"; then
    found_arith="yes"
else
    found_arith="no"
fi
assert_eq "$found_arith" "yes" "trace shows assignment"

# ── PS4: customize trace prefix ───────────────────────────────────
# PS4 controls the prefix for set -x output.
# Default is "+ ". Can include file, line, function info.

ps4_log="$TRACE_DIR/ps4.log"

{
    # Show script name, line number, and function name in traces
    PS4='+ ${BASH_SOURCE[0]##*/}:${LINENO} (${FUNCNAME[0]:-main}): '
    set -x
    traced_value="traced"
    set +x
} 2> "$ps4_log"

ps4_content=$(cat "$ps4_log")
# PS4 prefix should include line number
if echo "$ps4_content" | grep -qE ':[0-9]+ '; then
    has_line="yes"
else
    has_line="no"
fi
assert_eq "$has_line" "yes" "PS4 shows line numbers"

# Reset PS4
PS4='+ '

# ── Redirect trace to a file with exec ───────────────────────────
# exec 2>file redirects ALL stderr (including traces) to a file.
# Useful for logging an entire script's trace without cluttering terminal.

exec_log="$TRACE_DIR/exec_trace.log"

# Save original stderr, redirect to file, trace, then restore
exec 3>&2           # save stderr to fd 3
exec 2>"$exec_log"  # redirect stderr to file

set -x
exec_traced="captured"
set +x

exec 2>&3           # restore stderr
exec 3>&-           # close saved fd

exec_content=$(cat "$exec_log")
assert_eq "$(($(echo "$exec_content" | wc -l) > 0))" "1" "exec redirect captures trace"

# ── BASH_SOURCE, LINENO, FUNCNAME: location introspection ────────
# These arrays provide call stack information at any point.

get_location() {
    # FUNCNAME[0] = current function
    # BASH_SOURCE[0] = current file
    # LINENO = current line
    echo "${FUNCNAME[0]}:${LINENO}"
}

loc=$(get_location)
# Should contain function name and a line number
if [[ "$loc" =~ ^get_location:[0-9]+$ ]]; then
    loc_valid="yes"
else
    loc_valid="no"
fi
assert_eq "$loc_valid" "yes" "location introspection"

# Call stack depth
outer_func() {
    inner_func
}

inner_func() {
    # FUNCNAME array is the call stack
    echo "${#FUNCNAME[@]}"
}

depth=$(outer_func)
# Stack: inner_func -> outer_func -> main -> subshell
assert_eq "$((depth >= 3))" "1" "call stack depth"

# ── Structured trace function ─────────────────────────────────────
# Build a reusable trace function with timestamp and location

trace() {
    local level="$1" msg="$2"
    local func="${FUNCNAME[1]:-main}"
    local line="${BASH_LINENO[0]}"
    local ts
    ts=$(date +%H:%M:%S)
    echo "[$ts] $level $func:$line $msg"
}

trace_output=$(trace "INFO" "starting operation")
if [[ "$trace_output" =~ ^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]\ INFO\ main:[0-9]+\ starting\ operation$ ]]; then
    trace_valid="yes"
else
    trace_valid="no"
fi
assert_eq "$trace_valid" "yes" "structured trace format"

# ── trap DEBUG: instrument every command ──────────────────────────
# trap '...' DEBUG runs before each simple command.
# Powerful for profiling and tracing function entry/exit.

debug_log="$TRACE_DIR/debug.log"
: > "$debug_log"
debug_count=0

# Install DEBUG trap
trap 'debug_count=$((debug_count + 1))' DEBUG

# These commands each trigger the DEBUG trap
_d1="a"
_d2="b"
_d3="c"

# Remove trap before assertion (otherwise assert triggers it too)
saved_count=$debug_count
trap - DEBUG

# At least our 3 assignments were traced (plus the saved_count assignment)
assert_eq "$((saved_count >= 3))" "1" "DEBUG trap fires per command"

# ── Function entry/exit tracing with DEBUG ────────────────────────

call_log="$TRACE_DIR/calls.log"
: > "$call_log"

traced_function_a() {
    echo "in a" > /dev/null
}

traced_function_b() {
    traced_function_a
}

# extdebug lets the DEBUG trap see FUNCNAME inside called functions
shopt -s extdebug

# Install a DEBUG trap that logs function transitions
_prev_func=""
trap '
    _cur="${FUNCNAME[0]:-main}"
    if [[ "$_cur" != "$_prev_func" ]]; then
        echo "enter $_cur" >> "'"$call_log"'"
        _prev_func="$_cur"
    fi
' DEBUG

traced_function_b

trap - DEBUG
shopt -u extdebug

call_content=$(cat "$call_log")
if echo "$call_content" | grep -q "enter traced_function_b"; then
    saw_b="yes"
else
    saw_b="no"
fi
assert_eq "$saw_b" "yes" "DEBUG trap function entry"

if echo "$call_content" | grep -q "enter traced_function_a"; then
    saw_a="yes"
else
    saw_a="no"
fi
assert_eq "$saw_a" "yes" "DEBUG trap nested entry"

# ── logger: syslog integration ───────────────────────────────────
# logger sends messages to the system log (syslog/journald).
# Useful for production scripts that integrate with log aggregation.
#
# Usage (not executed — would write to system log):
#   logger -t myapp -p user.info "operation completed"
#   logger -t myapp -p user.error "disk full"
#
# Tags (-t) identify the source, priority (-p) sets severity.

# Verify logger is available
if command -v logger > /dev/null 2>&1; then
    logger_available="yes"
else
    logger_available="no"
fi
assert_eq "$logger_available" "yes" "logger command available"

# ── Timing with SECONDS and date ─────────────────────────────────
# SECONDS is a built-in that counts seconds since shell start.
# Useful for coarse-grained performance tracing.

SECONDS=0
for (( i = 0; i < 1000; i++ )); do :; done
elapsed=$SECONDS
assert_eq "$((elapsed >= 0))" "1" "SECONDS timer"

# ── BASH_XTRACEFD: trace to a specific file descriptor ───────────
# Redirect trace output to a file descriptor other than stderr.
# This separates trace output from error output.

xtrace_log="$TRACE_DIR/xtracefd.log"
exec 4>"$xtrace_log"
BASH_XTRACEFD=4

set -x
_xfd_var="traced to fd4"
set +x

exec 4>&-
unset BASH_XTRACEFD

xfd_content=$(cat "$xtrace_log")
if echo "$xfd_content" | grep -q "xfd_var"; then
    xfd_ok="yes"
else
    xfd_ok="no"
fi
assert_eq "$xfd_ok" "yes" "BASH_XTRACEFD redirect"

# ── Conditional tracing ──────────────────────────────────────────
# Enable tracing only when a flag is set — production vs debug mode

TRACE_ENABLED=0

trace_if() {
    if (( TRACE_ENABLED )); then
        local func="${FUNCNAME[1]:-main}"
        echo "[TRACE] $func: $*" >&2
    fi
}

# Silent in production mode
output=$(trace_if "test message" 2>&1)
assert_eq "$output" "" "trace disabled"

TRACE_ENABLED=1
output=$(trace_if "test message" 2>&1)
assert_eq "$output" "[TRACE] main: test message" "trace enabled"
TRACE_ENABLED=0

# ── Summary ───────────────────────────────────────────────────────
# Shell tracing mechanisms:
#
#   Mechanism               Purpose
#   ─────────────────       ─────────────────────────────────────
#   set -x / set +x         Toggle command tracing
#   PS4                     Customize trace prefix (file:line:func)
#   BASH_XTRACEFD           Redirect traces to specific fd
#   exec 2>file             Redirect all stderr (incl traces)
#   trap DEBUG              Hook before every command
#   FUNCNAME/BASH_SOURCE    Call stack introspection
#   LINENO/BASH_LINENO      Line number at call sites
#   SECONDS                 Elapsed time (coarse profiling)
#   logger                  Syslog integration

echo "All tracing examples passed ($PASS assertions)."
exit 0
