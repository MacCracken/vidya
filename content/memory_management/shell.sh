#!/usr/bin/env bash
# Vidya — Memory Management in Shell (Bash)
#
# Shell doesn't have manual memory management — variables are strings in
# process memory, managed by the shell runtime. But understanding subshell
# scope, variable lifetime, temp files, and process cleanup matters for
# reliable scripts.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Variable scope: local vs global ────────────────────────────────
global_var="global"

my_func() {
    local local_var="local"
    global_var="modified"  # modifies the global
    assert_eq "$local_var" "local" "local inside func"
}

my_func
assert_eq "$global_var" "modified" "global modified by func"
# local_var is not accessible here

# ── Subshell scope isolation ────────────────────────────────────────
# Subshells (parentheses) get a COPY of the environment
parent_var="original"
(
    parent_var="changed in subshell"
)
assert_eq "$parent_var" "original" "subshell isolation"

# Pipes also create subshells — variables set inside are lost!
count=0
echo -e "a\nb\nc" | while read -r line; do
    count=$((count + 1))  # this count lives in the subshell
done
assert_eq "$count" "0" "pipe subshell gotcha"

# GOOD: use process substitution instead
count=0
while read -r line; do
    count=$((count + 1))
done < <(echo -e "a\nb\nc")
assert_eq "$count" "3" "process substitution avoids subshell"

# ── Temp files: create and clean up ────────────────────────────────
tmpfile=$(mktemp)
echo "hello" > "$tmpfile"
content=$(cat "$tmpfile")
rm -f "$tmpfile"
assert_eq "$content" "hello" "temp file"

# Temp directory
tmpdir=$(mktemp -d)
echo "data" > "$tmpdir/file.txt"
assert_eq "$(cat "$tmpdir/file.txt")" "data" "temp dir"
rm -rf "$tmpdir"

# ── trap for cleanup on exit ───────────────────────────────────────
cleanup_file=$(mktemp)
cleanup() {
    rm -f "$cleanup_file"
}
trap cleanup EXIT

echo "will be cleaned up" > "$cleanup_file"
assert_eq "$(cat "$cleanup_file")" "will be cleaned up" "trap file exists"
# cleanup runs automatically when script exits

# ── Heredoc vs herestring: avoiding temp allocations ────────────────
# Herestring: passes string to stdin without a temp file (in most shells)
result=$(cat <<< "hello herestring")
assert_eq "$result" "hello herestring" "herestring"

# ── Array memory: grows dynamically ────────────────────────────────
arr=()
for i in $(seq 1 100); do
    arr+=("$i")
done
assert_eq "${#arr[@]}" "100" "dynamic array growth"

# ── unset: explicitly free variables ────────────────────────────────
big_var="lots of data here that we no longer need"
unset big_var
assert_eq "${big_var:-freed}" "freed" "unset variable"

# Unset array elements
arr=(a b c d e)
unset 'arr[2]'
# Note: this leaves a gap, doesn't reindex!
assert_eq "${arr[3]}" "d" "unset array element"

# ── File descriptors: open and close ────────────────────────────────
tmpfd=$(mktemp)
exec 3>"$tmpfd"         # open fd 3 for writing
echo "via fd" >&3       # write to fd 3
exec 3>&-               # close fd 3
assert_eq "$(cat "$tmpfd")" "via fd" "file descriptor"
rm -f "$tmpfd"

# ── Process cleanup ────────────────────────────────────────────────
# Background processes should be cleaned up
bg_pid=""
start_background() {
    sleep 100 &
    bg_pid=$!
}

start_background
kill "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true

# ── Environment variables: exported scope ───────────────────────────
export VIDYA_TEST="exported"
# Subprocesses inherit exported vars
result=$(bash -c 'echo "$VIDYA_TEST"')
assert_eq "$result" "exported" "exported var"

# Non-exported vars are NOT inherited
local_only="not exported"
result=$(bash -c 'echo "${local_only:-missing}"')
assert_eq "$result" "missing" "non-exported var"
unset VIDYA_TEST

# Reset trap
trap - EXIT
rm -f "$cleanup_file"

echo "All memory management examples passed."
