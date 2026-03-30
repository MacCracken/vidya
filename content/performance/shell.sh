#!/usr/bin/env bash
# Vidya — Performance in Shell (Bash)
#
# Shell scripts are inherently slower than compiled languages — each
# external command spawns a process. The key to performance: minimize
# subprocesses, use built-in operations, batch I/O, and reach for
# awk/sed for heavy text processing instead of bash loops.

set -euo pipefail

# ── Helper functions ───────────────────────────────────���────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Use built-ins over external commands ────────────────────────────
# GOOD: bash built-in string operations (no subprocess)
str="hello world"
assert_eq "${str%% *}" "hello" "builtin prefix"
assert_eq "${#str}" "11" "builtin length"

# BAD: external commands for simple string ops
# result=$(echo "$str" | cut -d' ' -f1)  # spawns subshell + cut
# result=$(echo "$str" | wc -c)          # spawns subshell + wc

# ── Avoid subshells in loops ───────────────────────────────────────
# GOOD: use parameter expansion
count=0
for f in "a.txt" "b.rs" "c.py" "d.rs"; do
    if [[ "$f" == *.rs ]]; then
        ((count++)) || true
    fi
done
assert_eq "$count" "2" "builtin glob match"

# BAD: calling grep/external commands per iteration
# for f in *.rs; do echo "$f" | grep -q '\.rs$' && ((count++)); done

# ── Batch operations with awk ───────────────────────────────────────
# One awk invocation replaces hundreds of bash iterations
data=$(printf '%s\n' "alice:30" "bob:25" "charlie:35" "diana:28")
sum=$(echo "$data" | awk -F: '{sum += $2} END {print sum}')
assert_eq "$sum" "118" "awk batch sum"

# ── Here-string over echo-pipe ──────────────────────────────────────
# GOOD: herestring (no subshell for echo)
result=$(tr '[:lower:]' '[:upper:]' <<< "hello")
assert_eq "$result" "HELLO" "herestring"

# BAD: echo | pipe spawns an extra process
# result=$(echo "hello" | tr '[:lower:]' '[:upper:]')

# ── Printf over echo ───────────────────────────────────────────────
# printf is a builtin and more portable than echo
result=$(printf '%s %s\n' "hello" "world")
assert_eq "$result" "hello world" "printf builtin"

# ── Read entire file at once ────────────────────────────────────────
# GOOD: read whole file with < redirection
tmpfile=$(mktemp)
trap "rm -f $tmpfile" EXIT
printf 'line1\nline2\nline3\n' > "$tmpfile"

content=$(< "$tmpfile")  # bash built-in, no cat subprocess
assert_eq "$(echo "$content" | wc -l | tr -d ' ')" "3" "read whole file"

# BAD: cat spawns a process
# content=$(cat "$tmpfile")

# ── Arrays over repeated parsing ────────────────────────────────────
# Parse once into an array, access many times
IFS=: read -ra path_parts <<< "/usr/local/bin:/usr/bin:/bin"
assert_eq "${#path_parts[@]}" "3" "parse once"
assert_eq "${path_parts[0]}" "/usr/local/bin" "array access"

# ── Arithmetic: (( )) over expr/let ────────────────────────────────
# GOOD: (( )) is a bash builtin
result=0
for i in $(seq 1 100); do
    ((result += i))
done
assert_eq "$result" "5050" "builtin arithmetic"

# BAD: expr spawns a process per operation
# result=$(expr $result + $i)

# ── Minimize disk I/O ──────────────────────────────────────────────
# GOOD: collect output, write once
output=""
for i in $(seq 1 10); do
    output+="line $i"$'\n'
done
echo -n "$output" > "$tmpfile"
line_count=$(wc -l < "$tmpfile" | tr -d ' ')
assert_eq "$line_count" "10" "batch write"

# BAD: write per iteration
# for i in $(seq 1 10); do echo "line $i" >> "$tmpfile"; done

# ── Use [[ over [ ───────────────────────────────────────────────────
# [[ is a bash builtin keyword (faster, more features)
# [ is an external command on some systems
if [[ "hello" == h* ]]; then
    result="matched"
fi
assert_eq "$result" "matched" "builtin [["

# ── Mapfile for bulk line reading ───────────────────────────────────
# GOOD: one call reads all lines into array
mapfile -t lines < "$tmpfile"
assert_eq "${#lines[@]}" "10" "mapfile bulk"

# BAD: while-read loop (slower for large files)
# while IFS= read -r line; do ...; done < "$tmpfile"

# ── Process substitution avoids temp files ──────────────────────────
# GOOD: no temp file needed
common=$(comm -12 <(echo -e "a\nb\nc" | sort) <(echo -e "b\nc\nd" | sort))
assert_eq "$(echo "$common" | wc -l | tr -d ' ')" "2" "process sub no temp"

# ── Cleanup
trap - EXIT
rm -f "$tmpfile"

echo "All performance examples passed."
