#!/bin/bash
# Vidya — Allocators in Shell (Bash)
#
# Shell has no memory allocator — everything is strings and processes.
# We simulate allocator concepts with arrays and arithmetic to show
# how bump, free-list (slab), and bitmap allocators work internally.
# Each "allocation" is a slot index; "memory" is a flat array.
#
# Note: functions that modify global state use a REPLY variable instead
# of echo + $(), because $() runs a subshell that cannot update the parent.

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

# ── Bump allocator ─────────────────────────────────────────────────
# Simplest allocator: advance a pointer, never free individually.
# Fast allocation, bulk reset only.

BUMP_SIZE=16
declare -a bump_heap=()
bump_ptr=0

# Sets REPLY to the allocated slot index, or -1 on OOM.
bump_alloc() {
    local size="$1"
    if (( bump_ptr + size > BUMP_SIZE )); then
        REPLY=-1
        return
    fi
    REPLY=$bump_ptr
    # Fill the allocated slots with a tag
    for (( i = bump_ptr; i < bump_ptr + size; i++ )); do
        bump_heap[$i]="used"
    done
    bump_ptr=$((bump_ptr + size))
}

bump_reset() {
    bump_ptr=0
    bump_heap=()
}

# Allocate 4 slots — pointer advances from 0 to 4
bump_alloc 4
assert_eq "$REPLY" "0" "bump alloc first"
assert_eq "$bump_ptr" "4" "bump pointer after first"

# Allocate 6 more — pointer advances from 4 to 10
bump_alloc 6
assert_eq "$REPLY" "4" "bump alloc second"
assert_eq "$bump_ptr" "10" "bump pointer after second"

# Allocate too much — fails
bump_alloc 10
assert_eq "$REPLY" "-1" "bump alloc OOM"

# Reset frees everything at once
bump_reset
assert_eq "$bump_ptr" "0" "bump reset"

# Can allocate again after reset
bump_alloc 2
assert_eq "$REPLY" "0" "bump alloc after reset"

# ── Free-list (slab-style) allocator ───────────────────────────────
# Fixed-size slots. Free list tracks available slots as an array.
# Allocate = pop from free list. Free = push back to free list.

SLAB_SLOTS=8
declare -a slab_mem=()
declare -a slab_free_list=()

slab_init() {
    slab_mem=()
    slab_free_list=()
    # All slots start free — push onto free list in reverse
    for (( i = SLAB_SLOTS - 1; i >= 0; i-- )); do
        slab_free_list+=("$i")
        slab_mem[$i]="free"
    done
}

# Sets REPLY to slot index, or -1 if empty.
slab_alloc() {
    local count=${#slab_free_list[@]}
    if (( count == 0 )); then
        REPLY=-1
        return
    fi
    # Pop last element (stack top)
    REPLY=${slab_free_list[$((count - 1))]}
    unset 'slab_free_list[-1]'
    slab_mem[$REPLY]="alloc"
}

slab_free() {
    local idx="$1"
    slab_mem[$idx]="free"
    slab_free_list+=("$idx")
}

slab_init

# Allocate three slots — taken from free list
slab_alloc; a=$REPLY
slab_alloc; b=$REPLY
slab_alloc; c=$REPLY
assert_eq "$a" "0" "slab first alloc"
assert_eq "$b" "1" "slab second alloc"
assert_eq "$c" "2" "slab third alloc"
assert_eq "${#slab_free_list[@]}" "5" "slab free count"

# Free slot 1 — it goes back to the free list
slab_free 1
assert_eq "${#slab_free_list[@]}" "6" "slab free after return"
assert_eq "${slab_mem[1]}" "free" "slab slot freed"

# Re-allocate — gets slot 1 back (LIFO)
slab_alloc; d=$REPLY
assert_eq "$d" "1" "slab reuse freed slot"

# ── Bitmap allocator ──────────────────────────────────────────────
# Track allocation with a bitmask. Each bit = one slot.
# 1 = allocated, 0 = free. Use arithmetic bit ops.

BITMAP_SLOTS=8
bitmap=0  # 8 bits, all free

# Sets REPLY to slot index, or -1 if full.
bitmap_alloc() {
    for (( i = 0; i < BITMAP_SLOTS; i++ )); do
        if (( (bitmap & (1 << i)) == 0 )); then
            bitmap=$((bitmap | (1 << i)))
            REPLY=$i
            return
        fi
    done
    REPLY=-1
}

bitmap_free() {
    local idx="$1"
    bitmap=$((bitmap & ~(1 << idx)))
}

bitmap_is_allocated() {
    local idx="$1"
    if (( (bitmap & (1 << idx)) != 0 )); then
        echo "1"
    else
        echo "0"
    fi
}

bitmap_count_used() {
    local count=0
    local b=$bitmap
    while (( b > 0 )); do
        (( count += b & 1 ))
        b=$((b >> 1))
    done
    echo "$count"
}

# Start empty
assert_eq "$(bitmap_count_used)" "0" "bitmap empty"

# Allocate three slots
bitmap_alloc; s1=$REPLY
bitmap_alloc; s2=$REPLY
bitmap_alloc; s3=$REPLY
assert_eq "$s1" "0" "bitmap alloc 0"
assert_eq "$s2" "1" "bitmap alloc 1"
assert_eq "$s3" "2" "bitmap alloc 2"
assert_eq "$(bitmap_count_used)" "3" "bitmap 3 used"

# Verify specific bit
assert_eq "$(bitmap_is_allocated 1)" "1" "bitmap bit 1 set"
assert_eq "$(bitmap_is_allocated 5)" "0" "bitmap bit 5 clear"

# Free slot 1
bitmap_free 1
assert_eq "$(bitmap_is_allocated 1)" "0" "bitmap bit 1 after free"
assert_eq "$(bitmap_count_used)" "2" "bitmap 2 used after free"

# Re-allocate — gets slot 1 (first-fit)
bitmap_alloc; s4=$REPLY
assert_eq "$s4" "1" "bitmap reuse slot 1"

# Fill all slots
bitmap=0
for (( i = 0; i < BITMAP_SLOTS; i++ )); do
    bitmap_alloc
done
assert_eq "$(bitmap_count_used)" "8" "bitmap full"

# OOM when full
bitmap_alloc
assert_eq "$REPLY" "-1" "bitmap OOM"

# ── Allocator comparison ──────────────────────────────────────────
# Bump:   O(1) alloc, no individual free, bulk reset only
# Slab:   O(1) alloc/free via free list, fixed-size slots
# Bitmap: O(n) alloc (scan bits), O(1) free, compact metadata

echo "All allocator examples passed ($PASS assertions)."
exit 0
