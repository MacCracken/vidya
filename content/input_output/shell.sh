#!/usr/bin/env bash
# Vidya — Input/Output in Shell (Bash)
#
# Shell I/O revolves around file descriptors, redirection operators
# (>, >>, <, |), and the three standard streams (stdin=0, stdout=1,
# stderr=2). Pipes connect stdout to stdin for composable pipelines.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

# ── Writing to files ────────────────────────────────────────────────
echo "line 1" > "$tmpdir/out.txt"      # overwrite
echo "line 2" >> "$tmpdir/out.txt"     # append
echo "line 3" >> "$tmpdir/out.txt"

# ── Reading files ───────────────────────────────────────────────────
content=$(< "$tmpdir/out.txt")         # bash builtin, no cat needed
assert_eq "$(echo "$content" | wc -l | tr -d ' ')" "3" "line count"

# ── Line-by-line reading ───────────────────────────────────────────
count=0
while IFS= read -r line; do
    count=$((count + 1))
done < "$tmpdir/out.txt"
assert_eq "$count" "3" "while-read lines"

# ── Pipes: compose commands ─────────────────────────────────────────
result=$(echo -e "banana\napple\ncherry" | sort | head -1)
assert_eq "$result" "apple" "pipe sort"

# ── Redirect stderr separately ──────────────────────────────────────
echo "error msg" > "$tmpdir/stderr.txt" 2>&1
assert_eq "$(cat "$tmpdir/stderr.txt")" "error msg" "stderr redirect"

# ── Discard output ──────────────────────────────────────────────────
echo "discarded" > /dev/null 2>&1

# ── Here document ──────────────────────────────────────────────────
cat > "$tmpdir/heredoc.txt" <<EOF
first
second
third
EOF
assert_eq "$(wc -l < "$tmpdir/heredoc.txt" | tr -d ' ')" "3" "heredoc"

# ── Here string ─────────────────────────────────────────────────────
result=$(cat <<< "hello here-string")
assert_eq "$result" "hello here-string" "herestring"

# ── File descriptors: open, write, close ────────────────────────────
exec 3> "$tmpdir/fd.txt"   # open fd 3 for writing
echo "via fd 3" >&3
exec 3>&-                   # close fd 3
assert_eq "$(cat "$tmpdir/fd.txt")" "via fd 3" "fd write"

# ── Process substitution ───────────────────────────────────────────
diff_out=$(diff <(echo "hello") <(echo "hello"))
assert_eq "$diff_out" "" "process substitution diff"

# ── tee: write to file and stdout ───────────────────────────────────
result=$(echo "teed" | tee "$tmpdir/tee.txt")
assert_eq "$result" "teed" "tee stdout"
assert_eq "$(cat "$tmpdir/tee.txt")" "teed" "tee file"

# ── Reading specific bytes ──────────────────────────────────────────
echo -n "hello world" > "$tmpdir/bytes.txt"
first5=$(dd if="$tmpdir/bytes.txt" bs=1 count=5 2>/dev/null)
assert_eq "$first5" "hello" "dd bytes"

# ── Checking file properties ───────────────────────────────────────
assert_eq "$([[ -f "$tmpdir/out.txt" ]] && echo yes || echo no)" "yes" "file exists"
assert_eq "$([[ -s "$tmpdir/out.txt" ]] && echo yes || echo no)" "yes" "file non-empty"
assert_eq "$([[ -d "$tmpdir" ]] && echo yes || echo no)" "yes" "dir exists"

# ── Reading from command output ─────────────────────────────────────
mapfile -t words <<< "$(echo -e "one\ntwo\nthree")"
assert_eq "${#words[@]}" "3" "mapfile from command"
assert_eq "${words[1]}" "two" "mapfile element"

echo "All input/output examples passed."
