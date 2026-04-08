#!/bin/bash
# Vidya — Process and Scheduling in Shell
#
# Processes are the fundamental unit of execution. Shell is uniquely
# positioned to demonstrate process management — PIDs, forking,
# background jobs, signals, and scheduling. This file uses /proc,
# bash builtins, and arithmetic to explore how the Linux kernel
# manages processes and decides which one runs next.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── PID basics ────────────────────────────────────────────────────────
# $$ is the PID of the current shell. $PPID is the parent.
# $BASHPID gives the PID within subshells (differs from $$).

my_pid=$$
my_ppid=$PPID

# PID must be positive
if (( my_pid <= 0 )); then
    echo "FAIL: PID must be positive, got $my_pid" >&2
    exit 1
fi

# PPID must also be positive (we have a parent)
if (( my_ppid <= 0 )); then
    echo "FAIL: PPID must be positive, got $my_ppid" >&2
    exit 1
fi

# PID and PPID must differ (we're not init)
if (( my_pid == my_ppid )); then
    echo "FAIL: PID should differ from PPID" >&2
    exit 1
fi

# $$ stays the same in subshells; $BASHPID changes
subshell_dollar=$(bash -c 'echo $$')
# The subshell gets its own PID
if [[ "$subshell_dollar" == "$$" ]]; then
    echo "FAIL: subshell should have different PID" >&2
    exit 1
fi

# ── /proc/self/status — detailed process info ────────────────────────
# /proc/self/status contains human-readable process metadata.
# Snapshot it to avoid subshell PID mismatch when piping to awk.

status_snapshot=$(</proc/self/status)
proc_name=$(echo "$status_snapshot" | awk '/^Name:/ {print $2}')
proc_pid=$(echo "$status_snapshot" | awk '/^Pid:/ {print $2}')
proc_ppid=$(echo "$status_snapshot" | awk '/^PPid:/ {print $2}')
proc_threads=$(echo "$status_snapshot" | awk '/^Threads:/ {print $2}')
proc_state=$(echo "$status_snapshot" | awk '/^State:/ {print $2}')

assert_eq "$proc_pid" "$my_pid" "/proc PID matches \$\$"
assert_eq "$proc_ppid" "$my_ppid" "/proc PPID matches \$PPID"
assert_eq "$proc_threads" "1" "bash is single-threaded"

# State should be R (running) since we're actively executing
assert_eq "$proc_state" "R" "process state = Running"

# ── Process states ────────────────────────────────────────────────────
# Linux process states visible in /proc/*/status:
#   R — Running or runnable (on run queue)
#   S — Sleeping (interruptible, waiting for event)
#   D — Disk sleep (uninterruptible, usually I/O)
#   T — Stopped (by signal or debugger)
#   Z — Zombie (terminated, waiting for parent to reap)
#   X — Dead (should never be visible)

declare -A PROC_STATES=(
    [R]="Running"
    [S]="Sleeping (interruptible)"
    [D]="Disk sleep (uninterruptible)"
    [T]="Stopped"
    [Z]="Zombie"
    [X]="Dead"
)

assert_eq "${PROC_STATES[R]}" "Running" "R = Running"
assert_eq "${PROC_STATES[Z]}" "Zombie" "Z = Zombie"
assert_eq "${#PROC_STATES[@]}" "6" "6 process states"

# ── /proc/self/stat — raw scheduler data ──────────────────────────────
# Fields are space-separated but field 2 (comm) is in parentheses and
# may contain spaces, so we parse carefully.

# Snapshot /proc/self/stat — bash builtin read avoids forking
stat_line=$(</proc/self/stat)
# Remove the (comm) field to get clean field parsing
# comm is between first ( and last )
stat_after_comm="${stat_line##*) }"

# Field 1 after comm = state (field 3 of stat)
sched_state=$(echo "$stat_after_comm" | awk '{print $1}')
assert_eq "$sched_state" "R" "scheduler sees us as Running"

# Field 17 after comm = nice value (field 19 of raw stat)
# Field 16 = priority (20 for default), field 17 = nice (0 for default)
nice_val=$(echo "$stat_after_comm" | awk '{print $17}')
# Default nice is 0
assert_eq "$nice_val" "0" "default nice = 0"

# Field 20 after comm = num_threads (field 22 of stat, but offset by our parsing)
# This is more reliably read from /proc/self/status

# ── Nice values and priority ─────────────────────────────────────────
# Nice values range from -20 (highest priority) to 19 (lowest).
# Only root can set negative nice values.

NICE_MIN=-20
NICE_MAX=19
NICE_DEFAULT=0
NICE_RANGE=$(( NICE_MAX - NICE_MIN + 1 ))

assert_eq "$NICE_RANGE" "40" "40 nice levels"

# Linux maps nice to priority: priority = nice + 20
# So nice -20 = priority 0 (highest), nice 19 = priority 39 (lowest)
nice_to_priority() {
    echo $(( $1 + 20 ))
}

assert_eq "$(nice_to_priority -20)" "0" "nice -20 = priority 0"
assert_eq "$(nice_to_priority 0)" "20" "nice 0 = priority 20"
assert_eq "$(nice_to_priority 19)" "39" "nice 19 = priority 39"

# Real-time priorities are separate: 1-99 (above all nice values)
RT_PRIO_MIN=1
RT_PRIO_MAX=99
assert_eq "$(( RT_PRIO_MAX - RT_PRIO_MIN + 1 ))" "99" "99 RT priority levels"

# ── Background jobs and wait ──────────────────────────────────────────
# Shell demonstrates fork+exec naturally through & and wait.

# Launch a background job
sleep 0.01 &
bg_pid=$!

# $! gives the PID of the last background job
if (( bg_pid <= 0 )); then
    echo "FAIL: background PID should be positive" >&2
    exit 1
fi

# The background process should be visible in /proc
if [[ ! -d "/proc/$bg_pid" ]]; then
    echo "FAIL: /proc/$bg_pid should exist for background job" >&2
    exit 1
fi

# wait reaps the child process (equivalent to waitpid syscall)
wait "$bg_pid"
exit_status=$?
assert_eq "$exit_status" "0" "background job exited cleanly"

# After wait, /proc entry should eventually disappear
# (may take a moment for kernel cleanup)

# ── Multiple background jobs ─────────────────────────────────────────
declare -a job_pids=()

for i in 0 1 2 3; do
    sleep 0.01 &
    job_pids+=($!)
done

assert_eq "${#job_pids[@]}" "4" "launched 4 background jobs"

# Wait for all jobs
for pid in "${job_pids[@]}"; do
    wait "$pid"
done

# All should have completed successfully
# (wait would have set $? to the exit status)

# ── Exit status conventions ──────────────────────────────────────────
# Shell exit codes encode process termination status.
#   0:       success
#   1-125:   general errors
#   126:     command not executable
#   127:     command not found
#   128+N:   killed by signal N (e.g., 137 = 128+9 = SIGKILL)

signal_from_exit() {
    local code=$1
    if (( code > 128 )); then
        echo $(( code - 128 ))
    else
        echo "0"
    fi
}

assert_eq "$(signal_from_exit 137)" "9" "exit 137 = SIGKILL"
assert_eq "$(signal_from_exit 139)" "11" "exit 139 = SIGSEGV"
assert_eq "$(signal_from_exit 143)" "15" "exit 143 = SIGTERM"
assert_eq "$(signal_from_exit 0)" "0" "exit 0 = no signal"

# ── Scheduler time slice concepts ─────────────────────────────────────
# CFS (Completely Fair Scheduler) doesn't use fixed time slices.
# Instead, it tracks virtual runtime and gives CPU time proportionally.
# These constants illustrate the concepts.

# Default scheduler latency (target for one full cycle through all tasks)
SCHED_LATENCY_NS=6000000       # 6ms in nanoseconds
SCHED_MIN_GRANULARITY_NS=750000  # 0.75ms minimum slice

assert_eq "$SCHED_LATENCY_NS" "6000000" "sched latency = 6ms"
assert_eq "$SCHED_MIN_GRANULARITY_NS" "750000" "min granularity = 0.75ms"

# Maximum tasks before latency stretches
max_tasks_default=$(( SCHED_LATENCY_NS / SCHED_MIN_GRANULARITY_NS ))
assert_eq "$max_tasks_default" "8" "8 tasks fit in default latency"

# Weight for nice 0 (default priority) — used in CFS fair share calculation
NICE_0_WEIGHT=1024
# Each nice level changes weight by ~1.25x
# nice -1 weight ≈ 1277, nice +1 weight ≈ 820
NICE_NEG1_WEIGHT=1277
NICE_POS1_WEIGHT=820

# A nice -1 process gets ~1.56x more CPU than nice +1
ratio=$(( (NICE_NEG1_WEIGHT * 100) / NICE_POS1_WEIGHT ))
if (( ratio < 150 || ratio > 160 )); then
    echo "FAIL: nice weight ratio should be ~1.56x, got ${ratio}%" >&2
    exit 1
fi

# ── /proc/self/sched — scheduler statistics ──────────────────────────
# Contains detailed CFS scheduler data for the current process.

if [[ -f /proc/self/sched ]]; then
    # nr_switches: total context switches (voluntary + involuntary)
    sched_snapshot=$(</proc/self/sched)
    nr_switches=$(echo "$sched_snapshot" | awk '/nr_switches/ {print $NF}' | head -1)
    if [[ "$nr_switches" =~ ^[0-9.]+$ ]]; then
        # Process has had at least some scheduler interaction
        # (could be 0 if very fast, which is fine in a test)
        true
    fi
fi

# ── /proc/self/limits — resource limits ──────────────────────────────
# The kernel enforces per-process resource limits (setrlimit/getrlimit).

if [[ -f /proc/self/limits ]]; then
    limits_snapshot=$(</proc/self/limits)

    # Max open files
    max_files=$(echo "$limits_snapshot" | awk '/Max open files/ {print $4}')
    if [[ "$max_files" =~ ^[0-9]+$ ]] && (( max_files < 64 )); then
        echo "FAIL: max open files suspiciously low: $max_files" >&2
        exit 1
    fi

    # Max processes
    max_procs=$(echo "$limits_snapshot" | awk '/Max processes/ {print $3}')
    if [[ "$max_procs" =~ ^[0-9]+$ ]] && (( max_procs < 64 )); then
        echo "FAIL: max processes suspiciously low: $max_procs" >&2
        exit 1
    fi
fi

# ── CPU affinity ──────────────────────────────────────────────────────
# Processes can be pinned to specific CPUs. The kernel tracks this
# as a bitmask. We can read the allowed CPUs from /proc.

allowed_cpus=$(echo "$status_snapshot" | awk '/^Cpus_allowed:/ {print $2}' | head -1)
if [[ -z "$allowed_cpus" ]]; then
    echo "FAIL: could not read Cpus_allowed" >&2
    exit 1
fi

# Count online CPUs
online_cpus=$(nproc)
if (( online_cpus < 1 )); then
    echo "FAIL: must have at least 1 CPU" >&2
    exit 1
fi

# CPU affinity mask: for N CPUs, at least N bits should be set
# Example: 4 CPUs → mask = 0xf (binary 1111)
expected_min_mask=$(( (1 << online_cpus) - 1 ))
actual_mask=$(( 16#$allowed_cpus ))
# The actual mask should have at least as many bits as online CPUs
if (( (actual_mask & expected_min_mask) != expected_min_mask )); then
    # Some systems have offline CPUs, so the mask might not match exactly.
    # Just verify the mask is nonzero.
    if (( actual_mask == 0 )); then
        echo "FAIL: CPU affinity mask is zero" >&2
        exit 1
    fi
fi

echo "All process and scheduling examples passed."
