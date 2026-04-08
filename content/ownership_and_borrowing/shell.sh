#!/bin/bash
# Vidya — Ownership and Borrowing in Shell (Bash)
#
# Shell has no ownership system — variables are always copied (value
# semantics). There is no aliasing, no borrow checker, no lifetimes.
# We show how shell's behavior maps to ownership concepts:
#   - Assignment copies (no moves)
#   - Subshells isolate mutations (no shared mutable state)
#   - nameref provides "borrowing" (reference to another variable)
#   - trap provides RAII-like cleanup
#   - Temp file patterns show resource ownership

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

# ── Value semantics: assignment copies ────────────────────────────
# In Rust, `let b = a` moves a. In shell, it copies.
a="hello"
b="$a"
a="changed"

# b is unaffected — it got a copy, not a reference
assert_eq "$b" "hello" "assignment copies"
assert_eq "$a" "changed" "original mutated independently"

# Arrays also copy
arr1=(1 2 3)
arr2=("${arr1[@]}")
arr1[0]=99

assert_eq "${arr2[0]}" "1" "array copy isolation"
assert_eq "${arr1[0]}" "99" "original array mutated"

# ── No aliasing: two variables cannot refer to the same data ──────
x="shared"
y="$x"

# Mutating y never affects x — no aliasing possible with plain variables
y="modified"
assert_eq "$x" "shared" "no aliasing"

# ── Subshell isolation (like Rust's ownership boundary) ───────────
# A subshell gets a COPY of the parent's environment.
# Mutations in the subshell do not escape.

parent_var="original"

(
    # Inside subshell — we have our own copy
    parent_var="subshell_modified"
)

# Parent is unaffected — subshell changes are isolated
assert_eq "$parent_var" "original" "subshell isolation"

# Pipes also create subshells — a classic gotcha
counter=0
echo -e "a\nb\nc" | while read -r line; do
    counter=$((counter + 1))
done
# counter is still 0 — the while loop ran in a subshell (pipe)
assert_eq "$counter" "0" "pipe subshell gotcha"

# Fix: use process substitution to avoid subshell
counter=0
while read -r line; do
    counter=$((counter + 1))
done < <(echo -e "a\nb\nc")
assert_eq "$counter" "3" "process substitution fix"

# ── nameref: borrowing (Bash 4.3+) ───────────────────────────────
# declare -n creates a name reference — like a mutable borrow.
# The nameref aliases another variable by name.

target="before"

modify_via_ref() {
    local -n ref="$1"    # ref "borrows" the named variable
    ref="after"          # mutation through the reference
}

modify_via_ref target
assert_eq "$target" "after" "nameref mutation"

# nameref to array elements
data=(10 20 30)

sum_via_ref() {
    local -n arr_ref="$1"
    local total=0
    for val in "${arr_ref[@]}"; do
        total=$((total + val))
    done
    echo "$total"
}

result=$(sum_via_ref data)
assert_eq "$result" "60" "nameref array borrow"

# ── Read-only variables (immutable binding) ───────────────────────
# declare -r / readonly prevents mutation — like Rust's default immutability

declare -r CONSTANT="immutable"
assert_eq "$CONSTANT" "immutable" "readonly var"

# Attempting to modify a readonly variable would cause an error:
#   CONSTANT="changed"  # -> bash: CONSTANT: readonly variable

# ── trap for cleanup: RAII pattern ────────────────────────────────
# Rust uses Drop for automatic cleanup. Shell uses trap.
# trap EXIT runs cleanup when the scope (script/function) exits.

test_raii_cleanup() {
    local tmpfile
    tmpfile=$(mktemp)

    # Register cleanup — runs on function exit, error, or signal
    trap "rm -f '$tmpfile'" RETURN

    echo "owned resource" > "$tmpfile"
    assert_eq "$(cat "$tmpfile")" "owned resource" "RAII resource"

    # tmpfile will be cleaned up when function returns
}

test_raii_cleanup

# ── Temp file ownership ──────────────────────────────────────────
# Creator owns the resource. Pass the path (not contents) to consumers.
# Clean up in the owner's scope — consumer borrows the path.

owner_creates_resource() {
    local resource
    resource=$(mktemp)
    trap "rm -f '$resource'" RETURN

    echo "payload" > "$resource"

    # Pass path to consumer — consumer "borrows" read access
    consumer_reads "$resource"
}

consumer_reads() {
    local path="$1"
    # Consumer reads but doesn't own — no cleanup responsibility
    local content
    content=$(cat "$path")
    assert_eq "$content" "payload" "borrowed resource read"
}

owner_creates_resource

# ── Export: transferring to child processes ────────────────────────
# export makes a variable available to child processes.
# The child gets a COPY — like passing ownership of a clone.

export GIFT="for-child"

child_result=$(bash -c 'echo "$GIFT"')
assert_eq "$child_result" "for-child" "export to child"

# Child cannot modify parent's copy
bash -c 'GIFT="modified-by-child"'
assert_eq "$GIFT" "for-child" "child cannot affect parent"

# ── local: function-scoped ownership ──────────────────────────────
# local variables are owned by the function. They shadow globals
# and are destroyed when the function returns.

global="outer"

inner_scope() {
    local global="inner"
    assert_eq "$global" "inner" "local shadows global"
}

inner_scope
assert_eq "$global" "outer" "global restored after local"

# ── Ownership summary ────────────────────────────────────────────
# Shell vs Rust ownership concepts:
#
#   Rust concept        Shell equivalent
#   ─────────────       ─────────────────────────
#   Move                Copy (shell always copies)
#   Borrow (&T)         nameref (declare -n)
#   Mut borrow (&mut T) nameref + mutation
#   Drop / RAII         trap EXIT / trap RETURN
#   Scope               Subshell / local variables
#   Clone               Assignment (always a clone)
#   Lifetime            Script/function duration

echo "All ownership and borrowing examples passed ($PASS assertions)."
exit 0
