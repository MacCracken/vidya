#!/bin/bash
# Vidya — Syscalls and ABI in Shell
#
# System calls are the interface between user space and the kernel.
# Shell can observe syscalls through /proc, understand ABI conventions
# through register mappings, and demonstrate syscall number arithmetic.
# This file shows how to inspect the syscall layer from bash without
# requiring strace or other privileged tools.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Syscall number table (x86_64 Linux) ───────────────────────────────
# Syscall numbers are defined in <asm/unistd_64.h>. These are the most
# commonly used ones for systems programming.
declare -A SYSCALL_NAMES=(
    [0]="read"      [1]="write"     [2]="open"      [3]="close"
    [9]="mmap"      [10]="mprotect" [11]="munmap"
    [12]="brk"      [20]="writev"
    [39]="getpid"   [57]="fork"     [59]="execve"
    [60]="exit"     [61]="wait4"    [62]="kill"
    [63]="uname"    [72]="fcntl"
    [158]="arch_prctl"  [186]="gettid"
    [202]="futex"   [231]="exit_group"
    [257]="openat"  [262]="newfstatat"
    [318]="getrandom"
)

# Verify key syscall numbers with arithmetic
assert_eq "${SYSCALL_NAMES[0]}" "read" "syscall 0 = read"
assert_eq "${SYSCALL_NAMES[1]}" "write" "syscall 1 = write"
assert_eq "${SYSCALL_NAMES[59]}" "execve" "syscall 59 = execve"
assert_eq "${SYSCALL_NAMES[60]}" "exit" "syscall 60 = exit"
assert_eq "${SYSCALL_NAMES[39]}" "getpid" "syscall 39 = getpid"

# Syscall number arithmetic: openat replaced open in modern kernels
assert_eq "$(( 257 - 2 ))" "255" "openat is 255 higher than open"

# ── x86_64 System V ABI register conventions ─────────────────────────
# The ABI defines which registers carry function arguments vs syscall
# arguments. The critical difference: syscalls use r10 instead of rcx
# because the kernel uses rcx to save the return address (via SYSCALL).

SYSV_ARG_REGS=("rdi" "rsi" "rdx" "rcx" "r8" "r9")
SYSCALL_ARG_REGS=("rdi" "rsi" "rdx" "r10" "r8" "r9")
SYSCALL_NUM_REG="rax"
SYSCALL_RET_REG="rax"

# SysV ABI: first 6 integer args in registers, rest on stack
assert_eq "${#SYSV_ARG_REGS[@]}" "6" "SysV has 6 arg registers"
assert_eq "${SYSV_ARG_REGS[0]}" "rdi" "SysV arg1 = rdi"
assert_eq "${SYSV_ARG_REGS[3]}" "rcx" "SysV arg4 = rcx"

# Syscall ABI: same as SysV except arg4 uses r10
assert_eq "${SYSCALL_ARG_REGS[3]}" "r10" "syscall arg4 = r10 (NOT rcx)"
assert_eq "$SYSCALL_NUM_REG" "rax" "syscall number in rax"

# Show the difference explicitly
for i in 0 1 2 3 4 5; do
    if [[ "${SYSV_ARG_REGS[$i]}" != "${SYSCALL_ARG_REGS[$i]}" ]]; then
        assert_eq "$i" "3" "only arg4 differs (index 3)"
    fi
done

# ── AArch64 ABI comparison ───────────────────────────────────────────
# AArch64 uses x0-x7 for arguments, x8 for syscall number.
# Simpler than x86_64: no rcx/r10 split.
AARCH64_ARG_REGS=("x0" "x1" "x2" "x3" "x4" "x5" "x6" "x7")
AARCH64_SYSCALL_NUM="x8"

assert_eq "${#AARCH64_ARG_REGS[@]}" "8" "AArch64 has 8 arg registers"
assert_eq "$AARCH64_SYSCALL_NUM" "x8" "AArch64 syscall number in x8"

# ── /proc/self/maps — process memory layout ──────────────────────────
# /proc/self/maps shows every mapped memory region with permissions.
# Format: addr_start-addr_end perms offset dev inode pathname
#
# Permissions: r=read, w=write, x=execute, p=private, s=shared

# Snapshot maps once — /proc/self resolves per-syscall, so redirections
# can see a different process than the shell. cat reads it in one shot.
maps_snapshot=$(</proc/self/maps)
map_count=$(echo "$maps_snapshot" | wc -l)
if (( map_count < 3 )); then
    echo "FAIL: expected at least 3 memory mappings, got $map_count" >&2
    exit 1
fi

# Parse permission fields from the snapshot
declare -A perm_counts=( [r]=0 [w]=0 [x]=0 [p]=0 [s]=0 )

while IFS= read -r line; do
    perms=$(echo "$line" | awk '{print $2}')
    [[ "$perms" == *r* ]] && (( perm_counts[r]++ )) || true
    [[ "$perms" == *w* ]] && (( perm_counts[w]++ )) || true
    [[ "$perms" == *x* ]] && (( perm_counts[x]++ )) || true
    [[ "$perms" == *p* ]] && (( perm_counts[p]++ )) || true
    [[ "$perms" == *s* ]] && (( perm_counts[s]++ )) || true
done <<< "$maps_snapshot"

# Every process must have readable and executable regions (code)
if (( perm_counts[r] == 0 )); then
    echo "FAIL: no readable mappings" >&2
    exit 1
fi
if (( perm_counts[x] == 0 )); then
    echo "FAIL: no executable mappings (no code segment?)" >&2
    exit 1
fi

# ── Identify key memory regions ──────────────────────────────────────
# Look for well-known regions in /proc/self/maps

has_heap=false
has_stack=false
has_vdso=false

while IFS= read -r line; do
    [[ "$line" == *"[heap]"* ]] && has_heap=true
    [[ "$line" == *"[stack]"* ]] && has_stack=true
    [[ "$line" == *"[vdso]"* ]] && has_vdso=true
done <<< "$maps_snapshot"

# Stack is always present; vdso is a kernel-provided shared library
assert_eq "$has_stack" "true" "stack mapping exists"
assert_eq "$has_vdso" "true" "vdso mapping exists"

# ── /proc/self/status — process metadata ─────────────────────────────
# Contains PID, memory stats, signal masks, capabilities, and more.
# Snapshot to avoid subshell PID mismatch when piping to awk.

status_snapshot=$(</proc/self/status)
proc_pid=$(echo "$status_snapshot" | awk '/^Pid:/ {print $2}')
assert_eq "$proc_pid" "$$" "status PID matches \$\$"

# VmSize: total virtual memory (in kB)
vm_size=$(echo "$status_snapshot" | awk '/^VmSize:/ {print $2}')
if (( vm_size < 1000 )); then
    echo "FAIL: VmSize suspiciously small: ${vm_size} kB" >&2
    exit 1
fi

# Threads count — bash is single-threaded
threads=$(echo "$status_snapshot" | awk '/^Threads:/ {print $2}')
assert_eq "$threads" "1" "bash is single-threaded"

# ── Syscall constants and errno values ────────────────────────────────
# Errno values returned (as negative) in rax on syscall failure.

declare -A ERRNO_NAMES=(
    [1]="EPERM"     [2]="ENOENT"    [3]="ESRCH"
    [4]="EINTR"     [5]="EIO"       [9]="EBADF"
    [11]="EAGAIN"   [12]="ENOMEM"   [13]="EACCES"
    [14]="EFAULT"   [17]="EEXIST"   [22]="EINVAL"
    [28]="ENOSPC"   [36]="ENAMETOOLONG"
)

assert_eq "${ERRNO_NAMES[2]}" "ENOENT" "errno 2 = ENOENT"
assert_eq "${ERRNO_NAMES[13]}" "EACCES" "errno 13 = EACCES"
assert_eq "${ERRNO_NAMES[12]}" "ENOMEM" "errno 12 = ENOMEM"

# ── Signal numbers (used with kill syscall) ───────────────────────────
# Signals are how the kernel communicates events to processes.
SIGHUP=1; SIGINT=2; SIGKILL=9; SIGSEGV=11; SIGTERM=15; SIGCHLD=17

assert_eq "$SIGKILL" "9" "SIGKILL = 9"
assert_eq "$SIGSEGV" "11" "SIGSEGV = 11"
assert_eq "$SIGTERM" "15" "SIGTERM = 15"

# Verify kill syscall number + signal number arithmetic
# kill(pid, SIGTERM) => syscall 62, arg1=pid, arg2=15
kill_syscall=62
assert_eq "${SYSCALL_NAMES[$kill_syscall]}" "kill" "syscall 62 = kill"

# ── /proc/self/exe — what binary am I? ────────────────────────────────
# /proc/self/exe is a symlink to the executable running this process.
# readlink forks, so /proc/self resolves to readlink's PID. Use /proc/$$.
exe_path=$(readlink "/proc/$$/exe")
if [[ "$exe_path" != *"bash"* ]]; then
    echo "FAIL: expected bash, got $exe_path" >&2
    exit 1
fi

# ── Strace concepts: syscall tracing ─────────────────────────────────
# strace intercepts syscalls via ptrace(PTRACE_SYSCALL).
# Here we show what strace output looks like and parse it conceptually.
#
# Example strace line:
#   write(1, "hello\n", 6) = 6
#
# Format: syscall_name(args...) = return_value

parse_strace_line() {
    local line="$1"
    local syscall_name="${line%%(*}"
    local retval="${line##*= }"
    echo "$syscall_name $retval"
}

parsed=$(parse_strace_line 'write(1, "hello\n", 6) = 6')
assert_eq "$parsed" "write 6" "parse strace write"

parsed=$(parse_strace_line 'openat(AT_FDCWD, "/etc/hosts", O_RDONLY) = 3')
assert_eq "$parsed" "openat 3" "parse strace openat"

parsed=$(parse_strace_line 'read(3, "127.0.0.1 localhost\n", 4096) = 20')
assert_eq "$parsed" "read 20" "parse strace read"

# ── Calling convention summary ────────────────────────────────────────
# Verify the key ABI rules with array lookups

# Caller-saved (volatile) registers — caller must save before call
CALLER_SAVED=("rax" "rcx" "rdx" "rsi" "rdi" "r8" "r9" "r10" "r11")

# Callee-saved (nonvolatile) registers — function must preserve
CALLEE_SAVED=("rbx" "rbp" "r12" "r13" "r14" "r15")

assert_eq "${#CALLER_SAVED[@]}" "9" "9 caller-saved regs"
assert_eq "${#CALLEE_SAVED[@]}" "6" "6 callee-saved regs"

# Stack must be 16-byte aligned before CALL instruction
STACK_ALIGNMENT=16
assert_eq "$STACK_ALIGNMENT" "16" "stack alignment = 16 bytes"

# Red zone: 128 bytes below rsp that signal handlers won't clobber
RED_ZONE_SIZE=128
assert_eq "$RED_ZONE_SIZE" "128" "red zone = 128 bytes"

echo "All syscalls and ABI examples passed."
