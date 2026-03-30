#!/usr/bin/env bash
# Vidya — Concurrency in Shell (Bash)
#
# Shell concurrency uses background processes (&), wait, pipes,
# xargs -P for parallelism, and named pipes (FIFOs) for IPC.
# There are no threads — each concurrent unit is an OS process.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Background processes with & ─────────────────────────────────────
tmpfile=$(mktemp)
trap "rm -f $tmpfile" EXIT

echo "start" > "$tmpfile"

# Run in background
(echo "done" > "$tmpfile") &
bg_pid=$!
wait "$bg_pid"

assert_eq "$(cat "$tmpfile")" "done" "background process"

# ── wait: synchronize on completion ─────────────────────────────────
pids=()
for i in 1 2 3; do
    (sleep 0.01) &
    pids+=($!)
done

# Wait for all background jobs
for pid in "${pids[@]}"; do
    wait "$pid"
done
# All three completed

# ── Pipes: streaming concurrency ───────────────────────────────────
# Each pipe segment runs in its own process, concurrently
result=$(seq 1 5 | awk '{print $1 * $1}' | paste -sd, -)
assert_eq "$result" "1,4,9,16,25" "pipe concurrency"

# ── xargs -P: parallel execution ───────────────────────────────────
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir $tmpfile" EXIT

# Process 4 items in parallel with 2 workers
seq 1 4 | xargs -P2 -I{} bash -c "echo {} > $tmpdir/{}.txt"

file_count=$(ls "$tmpdir" | wc -l | tr -d ' ')
assert_eq "$file_count" "4" "xargs parallel"

# ── Named pipes (FIFOs): inter-process communication ────────────────
fifo=$(mktemp -u)
mkfifo "$fifo"

# Writer in background
(echo "message via fifo" > "$fifo") &
writer_pid=$!

# Reader
result=$(cat "$fifo")
wait "$writer_pid"
rm -f "$fifo"

assert_eq "$result" "message via fifo" "named pipe"

# ── Process substitution for concurrent streams ─────────────────────
# <(...) runs a command and provides its output as a file descriptor
result=$(paste -d: <(echo -e "a\nb\nc") <(echo -e "1\n2\n3") | head -1)
assert_eq "$result" "a:1" "process substitution"

# ── Lock files: mutual exclusion ───────────────────────────────────
lockfile=$(mktemp)
rm -f "$lockfile"

acquire_lock() {
    local lock="$1"
    # Atomic: create file only if it doesn't exist
    if (set -o noclobber; echo $$ > "$lock") 2>/dev/null; then
        return 0
    fi
    return 1
}

release_lock() {
    rm -f "$1"
}

# Acquire lock
acquire_lock "$lockfile"
assert_eq "$?" "0" "lock acquired"

# Second acquire should fail
set +e
acquire_lock "$lockfile"
got_lock=$?
set -e
assert_eq "$got_lock" "1" "lock contention"

release_lock "$lockfile"

# ── Job control ─────────────────────────────────────────────────────
# jobs -l: list background jobs
# fg %1: bring job 1 to foreground
# bg %1: resume job 1 in background
# kill %1: kill job 1

# ── Coproc: bidirectional communication (Bash 4+) ──────────────────
coproc WORKER { while IFS= read -r line; do echo "processed: $line"; done; }

echo "hello" >&"${WORKER[1]}"
read -r response <&"${WORKER[0]}"
assert_eq "$response" "processed: hello" "coproc"

# Close the coproc
exec {WORKER[1]}>&-
wait "$WORKER_PID" 2>/dev/null || true

# ── Parallel loops with job limiting ────────────────────────────────
max_jobs=3
results_dir=$(mktemp -d)

for i in $(seq 1 6); do
    (
        echo "$((i * i))" > "$results_dir/$i.txt"
    ) &

    # Limit concurrent jobs
    if (( $(jobs -r | wc -l) >= max_jobs )); then
        wait -n  # wait for any one job to finish
    fi
done
wait  # wait for remaining jobs

total=0
for f in "$results_dir"/*.txt; do
    total=$((total + $(cat "$f")))
done
assert_eq "$total" "91" "parallel job results"  # 1+4+9+16+25+36

rm -rf "$results_dir"

# Reset trap
trap - EXIT
rm -f "$tmpfile"
rm -rf "$tmpdir"

echo "All concurrency examples passed."
