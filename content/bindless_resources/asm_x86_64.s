# Vidya — Bindless Resources in x86_64 Assembly
#
# In-memory descriptor table — slot 0 reserved as null sentinel,
# LIFO free list for reuse. .bss arenas back the table; helpers in
# .text. Same pattern as page_management's asm port.
#
# A handle is (generation << 8) | slot. Freeing a slot bumps its
# generation, so a handle kept after free_handle no longer matches and is
# refused — instead of silently resolving to whatever reuses the slot. The
# same check turns a double free into an error rather than a free-list
# cycle that hands one slot to two owners.

.intel_syntax noprefix
.global _start

.equ TABLE_CAP, 64

.section .bss
.align 8
slots:        .skip 8 * TABLE_CAP
free_links:   .skip 8 * TABLE_CAP
gens:         .skip 8 * TABLE_CAP     # current generation of each slot
live:         .skip 8 * TABLE_CAP     # 1 while the slot is allocated

.section .data
next_id:      .quad 1
free_head:    .quad 0

.section .rodata
msg_pass:     .ascii "bindless_resources: 15/15 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

table_init:
    mov     qword ptr [rip + next_id], 1
    mov     qword ptr [rip + free_head], 0
    lea     rdi, [rip + slots]
    mov     rcx, TABLE_CAP * 4        # slots, free_links, gens, live
    xor     rax, rax
.ti_loop:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .ti_loop
    ret

# live_index(rdi=handle) -> rax = slot, or -1 if the handle is not live
# (slot 0 / out of range / freed / stale generation). Clobbers rcx, rdx.
live_index:
    mov     rax, rdi
    and     rax, 0xFF                 # slot
    jz      .li_bad
    cmp     rax, TABLE_CAP
    jae     .li_bad                   # unsigned
    lea     rcx, [rip + live]
    cmp     qword ptr [rcx + rax * 8], 0
    je      .li_bad
    mov     rdx, rdi
    shr     rdx, 8                    # generation in the handle
    lea     rcx, [rip + gens]
    cmp     rdx, [rcx + rax * 8]
    jne     .li_bad                   # stale: the slot was freed since
    ret
.li_bad:
    mov     rax, -1
    ret

# alloc_handle(rdi=desc) -> rax = handle (0 if the table is full)
alloc_handle:
    mov     rax, [rip + free_head]
    test    rax, rax
    jz      .ah_extend
    # Pop free_head
    lea     rcx, [rip + free_links]
    mov     rdx, [rcx + rax * 8]
    mov     [rip + free_head], rdx
    jmp     .ah_take
.ah_extend:
    mov     rax, [rip + next_id]
    cmp     rax, TABLE_CAP
    jl      .ah_ok
    xor     rax, rax
    ret
.ah_ok:
    inc     qword ptr [rip + next_id]
.ah_take:
    lea     rcx, [rip + slots]
    mov     [rcx + rax * 8], rdi
    lea     rcx, [rip + live]
    mov     qword ptr [rcx + rax * 8], 1
    lea     rcx, [rip + gens]
    mov     rdx, [rcx + rax * 8]
    shl     rdx, 8
    or      rax, rdx                  # handle = gen << 8 | slot
    ret

# lookup_handle(rdi=handle) -> rax (0 if not live)
lookup_handle:
    call    live_index
    cmp     rax, -1
    je      .lh_zero
    lea     rcx, [rip + slots]
    mov     rax, [rcx + rax * 8]
    ret
.lh_zero:
    xor     rax, rax
    ret

# update_handle(rdi=handle, rsi=desc) -> rax = 0/1
update_handle:
    call    live_index
    cmp     rax, -1
    je      .uh_zero
    lea     rcx, [rip + slots]
    mov     [rcx + rax * 8], rsi
    mov     rax, 1
    ret
.uh_zero:
    xor     rax, rax
    ret

# free_handle(rdi=handle) -> rax = 0/1 (0: not live — stale or double free)
free_handle:
    call    live_index
    cmp     rax, -1
    je      .fh_zero
    lea     rcx, [rip + live]
    mov     qword ptr [rcx + rax * 8], 0
    lea     rcx, [rip + gens]
    inc     qword ptr [rcx + rax * 8] # old handles to this slot go stale
    lea     rcx, [rip + slots]
    mov     qword ptr [rcx + rax * 8], 0
    lea     rcx, [rip + free_links]
    mov     rdx, [rip + free_head]
    mov     [rcx + rax * 8], rdx
    mov     [rip + free_head], rax
    mov     rax, 1
    ret
.fh_zero:
    xor     rax, rax
    ret

assert_eq:
    cmp     rdi, rsi
    jne     fail_exit
    ret

fail_exit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    call    table_init

    # Test 1: sequential alloc returns 1, 2, 3
    mov     rdi, 0x1111111111111111
    call    alloc_handle
    mov     r12, rax              # id1
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    mov     rdi, 0x2222222222222222
    call    alloc_handle
    mov     r13, rax              # id2
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    mov     rdi, 0x3333333333333333
    call    alloc_handle
    mov     r14, rax              # id3
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # Test 2: slot 0 reserved
    mov     rdi, 0
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # Test 3: lookup returns descriptor
    mov     rdi, r12
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x1111111111111111
    call    assert_eq
    mov     rdi, r13
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x2222222222222222
    call    assert_eq
    mov     rdi, r14
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x3333333333333333
    call    assert_eq

    # Test 4: update id2
    mov     rdi, r13
    mov     rsi, 0xAAAAAAAAAAAAAAAA
    call    update_handle
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0xAAAAAAAAAAAAAAAA
    call    assert_eq
    mov     rdi, r12
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x1111111111111111
    call    assert_eq
    mov     rdi, r14
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x3333333333333333
    call    assert_eq

    # Test 5: free + alloc reuses slot
    mov     rdi, r13
    call    free_handle
    mov     rdi, r13
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 0x4444444444444444
    call    alloc_handle
    mov     r15, rax              # id4
    mov     rdi, rax
    and     rdi, 0xFF             # same slot as id2...
    mov     rsi, r13
    call    assert_eq
    mov     rdi, r15
    mov     rsi, r13
    add     rsi, 0x100            # ...one generation later
    call    assert_eq
    mov     rdi, r15
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x4444444444444444
    call    assert_eq
    mov     rdi, r13              # the stale id2 must NOT see id4's data
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, r13              # and freeing it again is refused
    call    free_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # Test 6: exhaustion
    call    table_init
    mov     rbx, 1                # i = 1; callee-saved
.fill_loop:
    cmp     rbx, TABLE_CAP
    jge     .fill_done
    mov     rdi, rbx
    call    alloc_handle
    inc     rbx
    jmp     .fill_loop
.fill_done:
    mov     rdi, 0xDEADBEEF
    call    alloc_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # Test 7: negative handles are rejected (unsigned bounds check)
    mov     rdi, -1
    call    free_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, -1
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
