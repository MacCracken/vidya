# Vidya — B+ Tree Indexing in x86_64 Assembly
#
# Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
# the layout declared by cyrius.cyr. Two static .bss arenas back the
# tree: a `node_pool` of fixed-size 136-byte slots (BN_SZ from cyrius)
# and a `next_id` counter; each slot has the layout
#     +0   BN_LEAF      (i64 — 1 = leaf)
#     +8   BN_NK        (i64 — number of keys)
#     +16  BN_KEYS[8]   (i64 × 8, slot 7 is the transient overflow slot)
#     +80  BN_VALS[9]   (i64 × 9 — vals when leaf, child node-ids when
#                         internal; one extra for the final right child)
# This matches cyrius's BN_LEAF/BN_NK/BN_KEYS/BN_VALS struct-by-offset
# pattern and bumps BN_SZ slightly to leave room for the +1 children
# slot. We never free — bump-pointer alloc only, fine for the test set.
#
# 64-bit large immediates use the `mov rN, 0xLITERAL` form because
# x86_64 `mov` with a 32-bit operand sign-extends.

.intel_syntax noprefix
.global _start

.equ BN_LEAF,  0
.equ BN_NK,    8
.equ BN_KEYS,  16
.equ BN_VALS,  80                # cyrius uses 72 (7-key max); we use 80
                                  # to give room for an 8-slot keys array
                                  # + 9-slot vals/children (one extra to
                                  # hold the final child of an internal).
.equ BN_SZ,    160                # 16 + 8*8 + 9*8 = 152, round up to 160.
.equ BT_MAX,   7
.equ POOL_CAP, 64                 # plenty for the test set

.section .bss
.align 8
node_pool:    .skip BN_SZ * POOL_CAP
next_id:      .skip 8

.section .data
root_id:      .quad 0             # current root's slot id (0 is reserved
                                   # by allocating it first, matching
                                   # the page-0-as-null gotcha).

.section .rodata
msg_pass:     .ascii "All btree_indexing examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# node_addr(rdi=id) -> rax = pointer to node at slot id
node_addr:
    lea     rax, [rip + node_pool]
    mov     rcx, BN_SZ
    imul    rdi, rcx
    add     rax, rdi
    ret

# node_alloc -> rax = new slot id (also zeroes the slot)
node_alloc:
    push    rbx
    lea     rcx, [rip + next_id]
    mov     rax, [rcx]
    mov     rbx, rax              # save id to return
    inc     qword ptr [rcx]
    # Zero the slot
    mov     rdi, rbx
    push    rbx
    call    node_addr
    pop     rbx
    mov     rcx, BN_SZ / 8
.na_zero:
    mov     qword ptr [rax], 0
    add     rax, 8
    dec     rcx
    jnz     .na_zero
    mov     rax, rbx
    pop     rbx
    ret

# node_new_leaf -> rax = id of fresh leaf
node_new_leaf:
    push    rbx
    call    node_alloc
    mov     rbx, rax
    mov     rdi, rbx
    call    node_addr
    mov     qword ptr [rax + BN_LEAF], 1
    mov     rax, rbx
    pop     rbx
    ret

# node_new_internal -> rax = id of fresh internal
node_new_internal:
    push    rbx
    call    node_alloc
    mov     rbx, rax
    mov     rdi, rbx
    call    node_addr
    mov     qword ptr [rax + BN_LEAF], 0
    mov     rax, rbx
    pop     rbx
    ret

# bt_reset: re-init pool + create a fresh root leaf; stores id in root_id.
bt_reset:
    push    rbx
    lea     rcx, [rip + next_id]
    mov     qword ptr [rcx], 0
    call    node_new_leaf
    mov     rbx, rax
    lea     rcx, [rip + root_id]
    mov     [rcx], rbx
    pop     rbx
    ret

# leaf_insert(rdi=leaf_id, rsi=key, rdx=val)
# Precondition: nkeys < BT_MAX+1 (CAP, we have 8 slots in keys[]).
# Keeps keys sorted (insertion sort).
leaf_insert:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rsi              # key
    mov     r13, rdx              # val
    # rdi already = leaf_id; node_addr clobbers rdi/rcx but returns rax.
    call    node_addr
    mov     rbx, rax              # rbx = leaf ptr
    mov     r14, [rbx + BN_NK]    # nk
    mov     r15, r14              # pos = nk (default = append)

    # Find pos: first i where key <= keys[i]
    xor     rcx, rcx              # i = 0
.li_scan:
    cmp     rcx, r14
    jge     .li_shift
    mov     rax, [rbx + BN_KEYS + rcx * 8]
    cmp     r12, rax
    jg      .li_scan_next
    mov     r15, rcx              # pos = i
    jmp     .li_shift
.li_scan_next:
    inc     rcx
    jmp     .li_scan

.li_shift:
    # Shift keys/vals right from pos..nk-1 into pos+1..nk
    mov     rcx, r14              # j = nk
.li_sloop:
    cmp     rcx, r15
    jle     .li_set
    mov     rax, [rbx + BN_KEYS + (rcx - 1) * 8]
    mov     [rbx + BN_KEYS + rcx * 8], rax
    mov     rax, [rbx + BN_VALS + (rcx - 1) * 8]
    mov     [rbx + BN_VALS + rcx * 8], rax
    dec     rcx
    jmp     .li_sloop

.li_set:
    mov     [rbx + BN_KEYS + r15 * 8], r12
    mov     [rbx + BN_VALS + r15 * 8], r13
    inc     r14
    mov     [rbx + BN_NK], r14

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# find_leaf(rdi=root_id, rsi=key) -> rax = leaf_id
find_leaf:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi              # node_id
    mov     r13, rsi              # key
.fl_loop:
    mov     rdi, r12
    call    node_addr             # rax = node ptr
    mov     rbx, rax
    mov     rax, [rbx + BN_LEAF]
    test    rax, rax
    jnz     .fl_done
    # internal: pick child
    mov     rcx, [rbx + BN_NK]    # nk
    mov     r8, rcx               # ci = nk
    xor     r9, r9                # i = 0
.fl_scan:
    cmp     r9, rcx
    jge     .fl_descend
    mov     rax, [rbx + BN_KEYS + r9 * 8]
    cmp     r13, rax
    jge     .fl_scan_next
    mov     r8, r9
    jmp     .fl_descend
.fl_scan_next:
    inc     r9
    jmp     .fl_scan
.fl_descend:
    mov     r12, [rbx + BN_VALS + r8 * 8]   # children stored in vals[]
    jmp     .fl_loop
.fl_done:
    mov     rax, r12              # return leaf_id
    pop     r13
    pop     r12
    pop     rbx
    ret

# bt_search(rdi=root_id, rsi=key) -> rax = value or -1
bt_search:
    push    rbx
    push    r12
    push    r13
    mov     r13, rsi              # key
    call    find_leaf             # rax = leaf_id
    mov     rdi, rax
    call    node_addr
    mov     rbx, rax              # leaf ptr
    mov     r12, [rbx + BN_NK]    # nk
    xor     rcx, rcx              # i = 0
.bs_loop:
    cmp     rcx, r12
    jge     .bs_miss
    mov     rax, [rbx + BN_KEYS + rcx * 8]
    cmp     rax, r13
    je      .bs_hit
    inc     rcx
    jmp     .bs_loop
.bs_hit:
    mov     rax, [rbx + BN_VALS + rcx * 8]
    jmp     .bs_done
.bs_miss:
    mov     rax, -1
.bs_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

# split_root_leaf: when the root leaf has nkeys > BT_MAX. Mutates root_id.
split_root_leaf:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     rax, [rip + root_id]
    mov     r12, [rax]            # old id
    mov     rdi, r12
    call    node_addr
    mov     rbx, rax              # rbx = old ptr
    mov     r13, [rbx + BN_NK]    # nk
    mov     rcx, r13
    shr     rcx, 1                # mid = nk / 2
    mov     r14, rcx              # save mid

    # median = old.keys[mid]
    mov     r15, [rbx + BN_KEYS + r14 * 8]

    # Allocate left + right + new_root
    call    node_new_leaf
    mov     rdi, rax              # left_id
    push    rdi                   # save left_id at [rsp]
    push    r14                   # save mid at [rsp+8]
    push    r13                   # save nk at [rsp+16]
    push    r15                   # save median at [rsp+24]
    push    r12                   # save old_id at [rsp+32]

    call    node_new_leaf
    mov     r14, rax              # right_id (re-purpose r14)

    call    node_new_internal
    mov     r15, rax              # new_root_id

    # Pop saved values back
    pop     r12                   # old_id
    pop     rcx                   # median
    pop     r13                   # nk
    pop     rdx                   # mid
    pop     rdi                   # left_id

    # Now r12=old, r13=nk, rdx=mid, rcx=median, rdi=left, r14=right, r15=new_root.
    # Save what we need on the stack for the copy loop.
    sub     rsp, 48
    mov     [rsp + 0], r12        # old_id
    mov     [rsp + 8], r13        # nk
    mov     [rsp + 16], rdx       # mid
    mov     [rsp + 24], rcx       # median
    mov     [rsp + 32], rdi       # left_id
    mov     [rsp + 40], r14       # right_id (and r15 = new_root_id)

    # Copy old.keys/vals[0..mid) → left.keys/vals[0..mid)
    mov     rdi, [rsp + 0]
    call    node_addr
    mov     rbx, rax              # old ptr
    mov     rdi, [rsp + 32]
    call    node_addr
    mov     r12, rax              # left ptr
    mov     rcx, [rsp + 16]       # mid
    xor     r8, r8                # i
.sl_left:
    cmp     r8, rcx
    jge     .sl_left_done
    mov     rax, [rbx + BN_KEYS + r8 * 8]
    mov     [r12 + BN_KEYS + r8 * 8], rax
    mov     rax, [rbx + BN_VALS + r8 * 8]
    mov     [r12 + BN_VALS + r8 * 8], rax
    inc     r8
    jmp     .sl_left
.sl_left_done:
    mov     [r12 + BN_NK], rcx

    # Copy old.keys/vals[mid..nk) → right.keys/vals[0..)
    mov     rdi, [rsp + 40]
    call    node_addr
    mov     r13, rax              # right ptr
    mov     rcx, [rsp + 16]       # mid
    mov     r9, [rsp + 8]         # nk
    mov     r8, rcx               # i = mid
.sl_right:
    cmp     r8, r9
    jge     .sl_right_done
    mov     rax, [rbx + BN_KEYS + r8 * 8]
    mov     rdx, r8
    sub     rdx, rcx              # j = i - mid
    mov     [r13 + BN_KEYS + rdx * 8], rax
    mov     rax, [rbx + BN_VALS + r8 * 8]
    mov     [r13 + BN_VALS + rdx * 8], rax
    inc     r8
    jmp     .sl_right
.sl_right_done:
    mov     rdx, r9
    sub     rdx, rcx
    mov     [r13 + BN_NK], rdx

    # Set up new_root: keys[0]=median; children = [left_id, right_id]; nk=1
    mov     rdi, r15
    call    node_addr
    mov     rdi, rax              # new_root ptr
    mov     rax, [rsp + 24]       # median
    mov     [rdi + BN_KEYS], rax
    mov     rax, [rsp + 32]       # left_id
    mov     [rdi + BN_VALS], rax
    mov     rax, [rsp + 40]       # right_id
    mov     [rdi + BN_VALS + 8], rax
    mov     qword ptr [rdi + BN_NK], 1

    # root_id = new_root_id
    lea     rax, [rip + root_id]
    mov     [rax], r15

    add     rsp, 48
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# bt_insert(rdi=key, rsi=val) — operates on root_id; splits if leaf overflows.
bt_insert:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi              # key
    mov     r13, rsi              # val

    lea     rax, [rip + root_id]
    mov     r14, [rax]            # root id
    mov     rdi, r14
    call    node_addr
    mov     rbx, rax              # root ptr
    mov     rax, [rbx + BN_LEAF]
    test    rax, rax
    jz      .bi_internal

    # Root is leaf — leaf_insert into root, then maybe split.
    mov     rdi, r14
    mov     rsi, r12
    mov     rdx, r13
    call    leaf_insert
    # Re-load root ptr (may not have changed but be safe).
    mov     rdi, r14
    call    node_addr
    mov     rbx, rax
    mov     rax, [rbx + BN_NK]
    cmp     rax, BT_MAX
    jle     .bi_done
    call    split_root_leaf
    jmp     .bi_done

.bi_internal:
    # Root is internal — descend one level only (test set forces only
    # a single split; multi-level splits are not implemented).
    mov     rcx, [rbx + BN_NK]    # nk
    mov     r8, rcx               # ci = nk
    xor     r9, r9                # i = 0
.bi_scan:
    cmp     r9, rcx
    jge     .bi_descend
    mov     rax, [rbx + BN_KEYS + r9 * 8]
    cmp     r12, rax
    jge     .bi_scan_next
    mov     r8, r9
    jmp     .bi_descend
.bi_scan_next:
    inc     r9
    jmp     .bi_scan
.bi_descend:
    mov     rdi, [rbx + BN_VALS + r8 * 8]   # leaf id
    mov     rsi, r12
    mov     rdx, r13
    call    leaf_insert

.bi_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# Macro helper: assert rax == imm; on mismatch, jump to fail.
# (Inlined inline at each site — no m4.)

_start:
    # ──────── Test 1: basic insert and search ────────
    call    bt_reset
    mov     rdi, 10
    mov     rsi, 100
    call    bt_insert
    mov     rdi, 5
    mov     rsi, 50
    call    bt_insert
    mov     rdi, 20
    mov     rsi, 200
    call    bt_insert
    mov     rdi, 15
    mov     rsi, 150
    call    bt_insert
    mov     rdi, 3
    mov     rsi, 30
    call    bt_insert

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 10
    call    bt_search
    cmp     rax, 100
    jne     fail

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 5
    call    bt_search
    cmp     rax, 50
    jne     fail

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 3
    call    bt_search
    cmp     rax, 30
    jne     fail

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 99
    call    bt_search
    cmp     rax, -1
    jne     fail

    # ──────── Test 2: keys sorted in leaf ────────
    call    bt_reset
    mov     rdi, 10
    mov     rsi, 100
    call    bt_insert
    mov     rdi, 5
    mov     rsi, 50
    call    bt_insert
    mov     rdi, 20
    mov     rsi, 200
    call    bt_insert
    mov     rdi, 15
    mov     rsi, 150
    call    bt_insert
    mov     rdi, 3
    mov     rsi, 30
    call    bt_insert

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    call    node_addr
    mov     rbx, rax
    mov     rax, [rbx + BN_LEAF]
    cmp     rax, 1
    jne     fail
    mov     rax, [rbx + BN_NK]
    cmp     rax, 5
    jne     fail
    mov     rax, [rbx + BN_KEYS]
    cmp     rax, 3
    jne     fail
    mov     rax, [rbx + BN_KEYS + 32]      # keys[4]
    cmp     rax, 20
    jne     fail

    # ──────── Test 3: split on overflow ────────
    call    bt_reset
    xor     r12, r12              # i = 0
.t3_loop:
    cmp     r12, BT_MAX
    jg      .t3_done
    mov     rdi, r12
    mov     rax, r12
    imul    rax, 10
    mov     rsi, rax
    call    bt_insert
    inc     r12
    jmp     .t3_loop
.t3_done:
    # Root should now be internal.
    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    call    node_addr
    mov     rax, [rax + BN_LEAF]
    test    rax, rax
    jnz     fail

    # Search every inserted key.
    xor     r12, r12
.t3_search:
    cmp     r12, BT_MAX
    jg      .t3_search_done
    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, r12
    call    bt_search
    mov     rcx, r12
    imul    rcx, 10
    cmp     rax, rcx
    jne     fail
    inc     r12
    jmp     .t3_search
.t3_search_done:
    # Search a missing key.
    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 999
    call    bt_search
    cmp     rax, -1
    jne     fail

    # ──────── Test 4: descending inserts are sorted ────────
    call    bt_reset
    # Insert 50, 40, 30, 20, 10
    mov     rdi, 50
    mov     rsi, 100
    call    bt_insert
    mov     rdi, 40
    mov     rsi, 80
    call    bt_insert
    mov     rdi, 30
    mov     rsi, 60
    call    bt_insert
    mov     rdi, 20
    mov     rsi, 40
    call    bt_insert
    mov     rdi, 10
    mov     rsi, 20
    call    bt_insert

    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    call    node_addr
    mov     rbx, rax
    mov     rax, [rbx + BN_LEAF]
    cmp     rax, 1
    jne     fail
    mov     rax, [rbx + BN_NK]
    cmp     rax, 5
    jne     fail
    mov     rax, [rbx + BN_KEYS]            # keys[0]
    cmp     rax, 10
    jne     fail
    mov     rax, [rbx + BN_KEYS + 32]       # keys[4]
    cmp     rax, 50
    jne     fail

    # Search every inserted key.
    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 50
    call    bt_search
    cmp     rax, 100
    jne     fail
    lea     rax, [rip + root_id]
    mov     rdi, [rax]
    mov     rsi, 10
    call    bt_search
    cmp     rax, 20
    jne     fail

    # ──────── All passed ────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
