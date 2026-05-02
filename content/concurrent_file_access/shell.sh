#!/usr/bin/env bash
# Vidya — Concurrent File Access (flock) in Shell (Bash)
#
# Real flock(1) wraps the syscall. Pattern: open the file via exec
# redirection, hold the fd, call flock on it. Two distinct fds (200
# and 201) on the same file simulate two opens — flock is per-OPEN,
# so they have independent lock state.
#
# Bash gotcha (see field-note bash_subshell_clobbers_stateful_helpers):
# `flock -n -x 200 || rc=1` would put rc in a subshell. We invoke
# flock directly and check $? in the parent shell.

set -uo pipefail

PATH_TMP="/tmp/vidya_cfa_shell.bin"
rm -f "$PATH_TMP"
touch "$PATH_TMP"

PASS=0
check() { [[ $1 -eq $2 ]] && PASS=$((PASS+1)) || { echo "FAIL: $3 (got $1 want $2)" >&2; exit 1; }; }

# Test 1: exclusive write
exec 200<>"$PATH_TMP"
flock -x 200; check $? 0 "fd1 LOCK_EX"
printf 'DEADBEEF' >&200; check $? 0 "wrote 8 bytes"
flock -u 200; check $? 0 "fd1 LOCK_UN"

# Test 2: shared read with roundtrip
flock -s 200; check $? 0 "fd1 LOCK_SH"
exec 200<&-
exec 200<>"$PATH_TMP"
read -r -n 8 GOT <&200
check ${#GOT} 8 "read 8 bytes"
[[ "$GOT" == "DEADBEEF" ]] && PASS=$((PASS+1)) || { echo "FAIL roundtrip: got '$GOT'" >&2; exit 1; }
flock -u 200; check $? 0 "fd1 LOCK_UN after read"

# Test 3: exclusive contention
exec 201<>"$PATH_TMP"
flock -x 200; check $? 0 "fd1 re-acquires LOCK_EX"
flock -n -x 201
RC=$?
[[ $RC -ne 0 ]] && PASS=$((PASS+1)) || { echo "FAIL fd2 LOCK_NB should have failed (got $RC)" >&2; exit 1; }

# Test 4: release fd1, fd2 acquires
flock -u 200; check $? 0 "fd1 LOCK_UN"
flock -n -x 201; check $? 0 "fd2 acquires after fd1 releases"
flock -u 201; check $? 0 "fd2 LOCK_UN"

# Test 5: shared locks coexist
flock -n -s 200; check $? 0 "fd1 LOCK_SH non-blocking"
flock -n -s 201; check $? 0 "fd2 LOCK_SH non-blocking coexists"
flock -u 200
flock -u 201

exec 200<&-
exec 201<&-
rm -f "$PATH_TMP"

echo "concurrent_file_access: $PASS/12 ok"
