#!/usr/bin/env bash
# Vidya — Iterators in Shell (Bash)
#
# Shell iteration uses for loops, while-read for line processing, and
# pipes for composable data transformation. Arrays and process
# substitution provide the building blocks.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── For loop over words ────────────────────────────────────────────
count=0
for word in hello world from shell; do
    ((count++)) || true
done
assert_eq "$count" "4" "for word count"

# ── For loop over array ────────────────────────────────────────────
numbers=(1 2 3 4 5 6 7 8 9 10)
sum=0
for n in "${numbers[@]}"; do
    sum=$((sum + n))
done
assert_eq "$sum" "55" "array sum"

# ── C-style for loop ───────────────────────────────────────────────
sum=0
for ((i = 1; i <= 10; i++)); do
    sum=$((sum + i))
done
assert_eq "$sum" "55" "c-style loop"

# ── While-read: line-by-line processing ─────────────────────────────
line_count=0
while IFS= read -r line; do
    ((line_count++)) || true
done <<EOF
line one
line two
line three
EOF
assert_eq "$line_count" "3" "while-read lines"

# ── Pipe processing (the shell's iterator chain) ───────────────────
# seq | grep (filter) | awk (map) | paste (collect)
result=$(seq 1 10 | grep -E '^[0-9]*[02468]$' | awk '{print $1 * $1}' | paste -sd, -)
assert_eq "$result" "4,16,36,64,100" "pipe chain"

# ── Process substitution ───────────────────────────────────────────
# Compare two streams without temp files
diff_count=$(diff <(echo -e "a\nb\nc") <(echo -e "a\nx\nc") | grep -c '^[<>]' || true)
assert_eq "$diff_count" "2" "process substitution diff"

# ── Iterating with index ───────────────────────────────────────────
fruits=("apple" "banana" "cherry")
indices=""
for i in "${!fruits[@]}"; do
    indices+="$i "
done
assert_eq "${indices% }" "0 1 2" "array indices"

# ── Glob iteration (file patterns) ─────────────────────────────────
# for f in *.sh; do ... done
# for f in /etc/*.conf; do ... done

# ── while-read with delimiter ──────────────────────────────────────
csv="alice:30:dev bob:25:ops charlie:35:mgr"
names=""
for entry in $csv; do
    name=$(echo "$entry" | cut -d: -f1)
    names+="$name "
done
assert_eq "${names% }" "alice bob charlie" "csv parsing"

# ── Sequence generation ────────────────────────────────────────────
range_result=$(seq -s, 1 5)
assert_eq "$range_result" "1,2,3,4,5" "seq generation"

# Brace expansion
brace_result=$(echo {1..5} | tr ' ' ',')
assert_eq "$brace_result" "1,2,3,4,5" "brace expansion"

# ── xargs: parallel iteration ──────────────────────────────────────
result=$(echo "1 2 3 4 5" | xargs -n1 | sort -r | head -3 | paste -sd, -)
assert_eq "$result" "5,4,3" "xargs + sort"

# ── Mapfile/readarray: read into array ──────────────────────────────
mapfile -t lines <<EOF
first
second
third
EOF
assert_eq "${#lines[@]}" "3" "mapfile count"
assert_eq "${lines[1]}" "second" "mapfile element"

# ── Associative array iteration ─────────────────────────────────────
declare -A ages
ages[alice]=30
ages[bob]=25
key_count=0
for key in "${!ages[@]}"; do
    ((key_count++)) || true
done
assert_eq "$key_count" "2" "assoc array iteration"

# ── Filtering arrays ───────────────────────────────────────────────
numbers=(1 2 3 4 5 6 7 8 9 10)
evens=()
for n in "${numbers[@]}"; do
    if ((n % 2 == 0)); then
        evens+=("$n")
    fi
done
assert_eq "${#evens[@]}" "5" "filtered array"
assert_eq "${evens[0]}" "2" "first even"

# ── Accumulating results ───────────────────────────────────────────
result=""
for n in "${numbers[@]}"; do
    if ((n > 5)); then
        result+="${n},"
    fi
done
result="${result%,}"  # remove trailing comma
assert_eq "$result" "6,7,8,9,10" "accumulate filtered"

echo "All iterator examples passed."
