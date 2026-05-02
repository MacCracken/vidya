// Vidya — B+ Tree Indexing in AArch64 Assembly
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the layout declared by cyrius.cyr. Static .bss arenas back the tree:
// a `node_pool` of fixed-size 160-byte slots and a `next_id` counter.
// Each slot has the layout
//     +0   BN_LEAF      (i64 — 1 = leaf)
//     +8   BN_NK        (i64 — number of keys)
//     +16  BN_KEYS[8]   (i64 × 8, slot 7 is the transient overflow slot)
//     +80  BN_VALS[9]   (i64 × 9 — vals when leaf, child node-ids when
//                         internal; +1 for the final right child).
// Matches cyrius's BN_LEAF/BN_NK/BN_KEYS/BN_VALS struct-by-offset
// pattern with BN_SZ bumped to 160 for the +1 child slot.
//
// AArch64 conventions used here:
//   - Every function calling `bl` saves x29/x30 in its prologue.
//   - 64-bit literals come in via `ldr xN, =literal` (BN_SZ etc. fit in
//     16 bits, so `mov` is fine — but we still use the safe `=imm` form
//     for clarity in a few places).
//   - x19–x28 are callee-saved and used to cache loop state across
//     `bl` calls (manhattan-style — see cyrius.cyr's gotcha).

.global _start

.equ BN_LEAF,  0
.equ BN_NK,    8
.equ BN_KEYS,  16
.equ BN_VALS,  80
.equ BN_SZ,    160
.equ BT_MAX,   7
.equ POOL_CAP, 64

.section .bss
.align 3
node_pool:    .skip BN_SZ * POOL_CAP
next_id:      .skip 8

.section .data
.align 3
root_id:      .quad 0

.section .rodata
msg_pass:     .ascii "All btree_indexing examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// node_addr(x0=id) -> x0 = ptr
node_addr:
    mov     x9, #BN_SZ
    mul     x10, x0, x9
    adrp    x11, node_pool
    add     x11, x11, :lo12:node_pool
    add     x0, x11, x10
    ret

// node_alloc -> x0 = new id (slot zeroed)
node_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    adrp    x9, next_id
    add     x9, x9, :lo12:next_id
    ldr     x19, [x9]                 // x19 = id to return
    add     x10, x19, #1
    str     x10, [x9]
    // Zero the slot.
    mov     x0, x19
    bl      node_addr                 // x0 = ptr
    mov     x10, #(BN_SZ / 8)
.Lna_zero:
    str     xzr, [x0], #8
    sub     x10, x10, #1
    cbnz    x10, .Lna_zero
    mov     x0, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// node_new_leaf -> x0 = id
node_new_leaf:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    bl      node_alloc
    mov     x19, x0
    bl      node_addr                 // x0 = ptr
    mov     w10, #1
    str     x10, [x0, #BN_LEAF]
    mov     x0, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// node_new_internal -> x0 = id
node_new_internal:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    bl      node_alloc
    mov     x19, x0
    bl      node_addr
    str     xzr, [x0, #BN_LEAF]       // already 0 from zero-init, just be explicit
    mov     x0, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// bt_reset: clear pool, allocate a new leaf as root.
bt_reset:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    adrp    x9, next_id
    add     x9, x9, :lo12:next_id
    str     xzr, [x9]
    bl      node_new_leaf             // x0 = leaf id
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    str     x0, [x9]
    ldp     x29, x30, [sp], #16
    ret

// leaf_insert(x0=leaf_id, x1=key, x2=val) — insertion sort to keep keys sorted.
// Callee-saved usage: x19=leaf ptr, x20=key, x21=val, x22=nk, x23=pos.
leaf_insert:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]

    mov     x20, x1                   // key
    mov     x21, x2                   // val
    bl      node_addr                 // x0 = leaf ptr
    mov     x19, x0
    ldr     x22, [x19, #BN_NK]        // nk
    mov     x23, x22                  // pos = nk

    // Find pos: first i where key <= keys[i]
    mov     x9, #0                    // i
.Lli_scan:
    cmp     x9, x22
    b.ge    .Lli_shift
    add     x10, x19, #BN_KEYS
    ldr     x11, [x10, x9, lsl #3]
    cmp     x20, x11
    b.gt    .Lli_scan_next
    mov     x23, x9
    b       .Lli_shift
.Lli_scan_next:
    add     x9, x9, #1
    b       .Lli_scan

.Lli_shift:
    // Shift right keys/vals from pos..nk-1 into pos+1..nk.
    mov     x9, x22                   // j = nk
.Lli_sloop:
    cmp     x9, x23
    b.le    .Lli_set
    sub     x10, x9, #1
    add     x11, x19, #BN_KEYS
    ldr     x12, [x11, x10, lsl #3]
    str     x12, [x11, x9, lsl #3]
    add     x11, x19, #BN_VALS
    ldr     x12, [x11, x10, lsl #3]
    str     x12, [x11, x9, lsl #3]
    sub     x9, x9, #1
    b       .Lli_sloop

.Lli_set:
    add     x10, x19, #BN_KEYS
    str     x20, [x10, x23, lsl #3]
    add     x10, x19, #BN_VALS
    str     x21, [x10, x23, lsl #3]
    add     x22, x22, #1
    str     x22, [x19, #BN_NK]

    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// find_leaf(x0=root_id, x1=key) -> x0 = leaf_id
// Callee-saved: x19=node_id, x20=key.
find_leaf:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
.Lfl_loop:
    mov     x0, x19
    bl      node_addr                 // x0 = node ptr
    ldr     x9, [x0, #BN_LEAF]
    cbnz    x9, .Lfl_done
    ldr     x9, [x0, #BN_NK]          // nk
    mov     x10, x9                   // ci = nk
    mov     x11, #0                   // i
.Lfl_scan:
    cmp     x11, x9
    b.ge    .Lfl_descend
    add     x12, x0, #BN_KEYS
    ldr     x13, [x12, x11, lsl #3]
    cmp     x20, x13
    b.ge    .Lfl_scan_next
    mov     x10, x11
    b       .Lfl_descend
.Lfl_scan_next:
    add     x11, x11, #1
    b       .Lfl_scan
.Lfl_descend:
    add     x12, x0, #BN_VALS
    ldr     x19, [x12, x10, lsl #3]   // children stored in vals[]
    b       .Lfl_loop
.Lfl_done:
    mov     x0, x19
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// bt_search(x0=root_id, x1=key) -> x0 = value or -1
// Callee-saved: x19=leaf ptr, x20=key, x21=nk.
bt_search:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x20, x1
    bl      find_leaf                 // x0 = leaf id
    bl      node_addr                 // x0 = leaf ptr
    mov     x19, x0
    ldr     x21, [x19, #BN_NK]
    mov     x9, #0                    // i
.Lbs_loop:
    cmp     x9, x21
    b.ge    .Lbs_miss
    add     x10, x19, #BN_KEYS
    ldr     x11, [x10, x9, lsl #3]
    cmp     x11, x20
    b.eq    .Lbs_hit
    add     x9, x9, #1
    b       .Lbs_loop
.Lbs_hit:
    add     x10, x19, #BN_VALS
    ldr     x0, [x10, x9, lsl #3]
    b       .Lbs_done
.Lbs_miss:
    mov     x0, #-1
.Lbs_done:
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// split_root_leaf — root_id refers to a leaf with nkeys > BT_MAX.
// Callee-saved: x19=old_id, x20=mid, x21=nk, x22=median, x23=left_id,
//                x24=right_id, x25=new_root_id, x26=old_ptr, x27=tmp_ptr.
// The pointer caches MUST live in callee-saved regs because node_addr
// is called (via bl from node_new_*) repeatedly and clobbers x9/x10/x11.
split_root_leaf:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    str     x27, [sp, #80]

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x19, [x9]                 // old_id
    mov     x0, x19
    bl      node_addr                 // x0 = old ptr
    mov     x26, x0                   // x26 = old_ptr (callee-saved)
    ldr     x21, [x26, #BN_NK]        // nk
    lsr     x20, x21, #1              // mid = nk / 2
    add     x10, x26, #BN_KEYS
    ldr     x22, [x10, x20, lsl #3]   // median = keys[mid]

    bl      node_new_leaf
    mov     x23, x0                   // left_id
    bl      node_new_leaf
    mov     x24, x0                   // right_id
    bl      node_new_internal
    mov     x25, x0                   // new_root_id

    // Re-fetch old_ptr in case the pool moved (it didn't, but be explicit).
    mov     x0, x19
    bl      node_addr
    mov     x26, x0                   // old ptr (cached in x26)

    mov     x0, x23
    bl      node_addr
    mov     x27, x0                   // left ptr (cached in x27)

    // Copy old.keys/vals[0..mid) → left[0..mid)
    mov     x11, #0
.Lsl_left:
    cmp     x11, x20
    b.ge    .Lsl_left_done
    add     x12, x26, #BN_KEYS
    ldr     x13, [x12, x11, lsl #3]
    add     x14, x27, #BN_KEYS
    str     x13, [x14, x11, lsl #3]
    add     x12, x26, #BN_VALS
    ldr     x13, [x12, x11, lsl #3]
    add     x14, x27, #BN_VALS
    str     x13, [x14, x11, lsl #3]
    add     x11, x11, #1
    b       .Lsl_left
.Lsl_left_done:
    str     x20, [x27, #BN_NK]

    // Copy old.keys/vals[mid..nk) → right[0..)
    mov     x0, x24
    bl      node_addr
    mov     x27, x0                   // right ptr (re-purposed)
    mov     x11, x20                  // i = mid
.Lsl_right:
    cmp     x11, x21
    b.ge    .Lsl_right_done
    add     x12, x26, #BN_KEYS
    ldr     x13, [x12, x11, lsl #3]
    sub     x14, x11, x20             // j = i - mid
    add     x15, x27, #BN_KEYS
    str     x13, [x15, x14, lsl #3]
    add     x12, x26, #BN_VALS
    ldr     x13, [x12, x11, lsl #3]
    add     x15, x27, #BN_VALS
    str     x13, [x15, x14, lsl #3]
    add     x11, x11, #1
    b       .Lsl_right
.Lsl_right_done:
    sub     x14, x21, x20
    str     x14, [x27, #BN_NK]

    // Set up new_root: keys[0]=median; children = [left_id, right_id]; nk=1.
    mov     x0, x25
    bl      node_addr
    mov     x27, x0                   // new_root ptr
    str     x22, [x27, #BN_KEYS]
    add     x12, x27, #BN_VALS
    str     x23, [x12]
    str     x24, [x12, #8]
    mov     x9, #1
    str     x9, [x27, #BN_NK]

    // root_id = new_root_id
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    str     x25, [x9]

    ldr     x27, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #112
    ret

// bt_insert(x0=key, x1=val) — operates on root_id.
// Callee-saved: x19=key, x20=val, x21=root_id, x22=root_ptr.
bt_insert:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0
    mov     x20, x1
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x21, [x9]
    mov     x0, x21
    bl      node_addr
    mov     x22, x0
    ldr     x9, [x22, #BN_LEAF]
    cbz     x9, .Lbi_internal

    // Root is a leaf — insert + maybe split.
    mov     x0, x21
    mov     x1, x19
    mov     x2, x20
    bl      leaf_insert
    mov     x0, x21
    bl      node_addr
    ldr     x9, [x0, #BN_NK]
    cmp     x9, #BT_MAX
    b.le    .Lbi_done
    bl      split_root_leaf
    b       .Lbi_done

.Lbi_internal:
    // Root is internal — descend one level (cyrius test set forces only
    // a single split; multi-level splits are not implemented).
    ldr     x9, [x22, #BN_NK]
    mov     x10, x9                   // ci = nk
    mov     x11, #0
.Lbi_scan:
    cmp     x11, x9
    b.ge    .Lbi_descend
    add     x12, x22, #BN_KEYS
    ldr     x13, [x12, x11, lsl #3]
    cmp     x19, x13
    b.ge    .Lbi_scan_next
    mov     x10, x11
    b       .Lbi_descend
.Lbi_scan_next:
    add     x11, x11, #1
    b       .Lbi_scan
.Lbi_descend:
    add     x12, x22, #BN_VALS
    ldr     x0, [x12, x10, lsl #3]    // child id
    mov     x1, x19
    mov     x2, x20
    bl      leaf_insert

.Lbi_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// _start: run all tests; sp is 16-byte aligned at entry.
// We use x19 as a callee-saved scratch index for loops.
_start:
    // ──────── Test 1: basic insert and search ────────
    bl      bt_reset
    mov     x0, #10
    mov     x1, #100
    bl      bt_insert
    mov     x0, #5
    mov     x1, #50
    bl      bt_insert
    mov     x0, #20
    mov     x1, #200
    bl      bt_insert
    mov     x0, #15
    mov     x1, #150
    bl      bt_insert
    mov     x0, #3
    mov     x1, #30
    bl      bt_insert

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #10
    bl      bt_search
    cmp     x0, #100
    b.ne    fail

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #5
    bl      bt_search
    cmp     x0, #50
    b.ne    fail

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #3
    bl      bt_search
    cmp     x0, #30
    b.ne    fail

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #99
    bl      bt_search
    cmn     x0, #1                    // compare against -1
    b.ne    fail

    // ──────── Test 2: keys sorted in leaf ────────
    bl      bt_reset
    mov     x0, #10
    mov     x1, #100
    bl      bt_insert
    mov     x0, #5
    mov     x1, #50
    bl      bt_insert
    mov     x0, #20
    mov     x1, #200
    bl      bt_insert
    mov     x0, #15
    mov     x1, #150
    bl      bt_insert
    mov     x0, #3
    mov     x1, #30
    bl      bt_insert

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    bl      node_addr
    ldr     x9, [x0, #BN_LEAF]
    cmp     x9, #1
    b.ne    fail
    ldr     x9, [x0, #BN_NK]
    cmp     x9, #5
    b.ne    fail
    ldr     x9, [x0, #BN_KEYS]
    cmp     x9, #3
    b.ne    fail
    ldr     x9, [x0, #BN_KEYS + 32]   // keys[4]
    cmp     x9, #20
    b.ne    fail

    // ──────── Test 3: split on overflow ────────
    bl      bt_reset
    mov     x19, #0                   // i (callee-saved)
.Lt3_loop:
    cmp     x19, #BT_MAX
    b.gt    .Lt3_done
    mov     x0, x19
    mov     x9, #10
    mul     x1, x19, x9
    bl      bt_insert
    add     x19, x19, #1
    b       .Lt3_loop
.Lt3_done:
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    bl      node_addr
    ldr     x9, [x0, #BN_LEAF]
    cbnz    x9, fail                  // expected internal

    mov     x19, #0
.Lt3_search:
    cmp     x19, #BT_MAX
    b.gt    .Lt3_search_done
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, x19
    bl      bt_search
    mov     x9, #10
    mul     x10, x19, x9
    cmp     x0, x10
    b.ne    fail
    add     x19, x19, #1
    b       .Lt3_search
.Lt3_search_done:
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #999
    bl      bt_search
    cmn     x0, #1
    b.ne    fail

    // ──────── Test 4: descending inserts are sorted ────────
    bl      bt_reset
    mov     x0, #50
    mov     x1, #100
    bl      bt_insert
    mov     x0, #40
    mov     x1, #80
    bl      bt_insert
    mov     x0, #30
    mov     x1, #60
    bl      bt_insert
    mov     x0, #20
    mov     x1, #40
    bl      bt_insert
    mov     x0, #10
    mov     x1, #20
    bl      bt_insert

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    bl      node_addr
    ldr     x9, [x0, #BN_LEAF]
    cmp     x9, #1
    b.ne    fail
    ldr     x9, [x0, #BN_NK]
    cmp     x9, #5
    b.ne    fail
    ldr     x9, [x0, #BN_KEYS]
    cmp     x9, #10
    b.ne    fail
    ldr     x9, [x0, #BN_KEYS + 32]
    cmp     x9, #50
    b.ne    fail

    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #50
    bl      bt_search
    cmp     x0, #100
    b.ne    fail
    adrp    x9, root_id
    add     x9, x9, :lo12:root_id
    ldr     x0, [x9]
    mov     x1, #10
    bl      bt_search
    cmp     x0, #20
    b.ne    fail

    // ──────── All passed ────────
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
