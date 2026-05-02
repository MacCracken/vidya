# Vidya — Bindless Resources in x86_64 Assembly
#
# In-memory descriptor table — slot 0 reserved as null sentinel,
# LIFO free list for reuse. .bss arenas back the table; helpers in
# .text. Same pattern as page_management's asm port.

.intel_syntax noprefix
.global _start

.equ TABLE_CAP, 64

.section .bss
.align 8
slots:        .skip 8 * TABLE_CAP
free_links:   .skip 8 * TABLE_CAP

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
    mov     rcx, TABLE_CAP
    xor     rax, rax
.ti_loop:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .ti_loop
    lea     rdi, [rip + free_links]
    mov     rcx, TABLE_CAP
.ti_loop2:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .ti_loop2
    ret

# alloc_handle(rdi=desc) -> rax = id
alloc_handle:
    mov     rax, [rip + free_head]
    test    rax, rax
    jz      .ah_extend
    # Pop free_head
    lea     rcx, [rip + free_links]
    mov     rdx, [rcx + rax * 8]
    mov     [rip + free_head], rdx
    lea     rcx, [rip + slots]
    mov     [rcx + rax * 8], rdi
    ret
.ah_extend:
    mov     rax, [rip + next_id]
    cmp     rax, TABLE_CAP
    jl      .ah_ok
    xor     rax, rax
    ret
.ah_ok:
    inc     qword ptr [rip + next_id]
    lea     rcx, [rip + slots]
    mov     [rcx + rax * 8], rdi
    ret

# lookup_handle(rdi=id) -> rax
lookup_handle:
    test    rdi, rdi
    jz      .lh_zero
    cmp     rdi, TABLE_CAP
    jge     .lh_zero
    lea     rax, [rip + slots]
    mov     rax, [rax + rdi * 8]
    ret
.lh_zero:
    xor     rax, rax
    ret

# update_handle(rdi=id, rsi=desc) -> rax = 0/1
update_handle:
    test    rdi, rdi
    jz      .uh_zero
    cmp     rdi, TABLE_CAP
    jge     .uh_zero
    lea     rax, [rip + slots]
    mov     [rax + rdi * 8], rsi
    mov     rax, 1
    ret
.uh_zero:
    xor     rax, rax
    ret

# free_handle(rdi=id) -> rax = 0/1
free_handle:
    test    rdi, rdi
    jz      .fh_zero
    cmp     rdi, TABLE_CAP
    jge     .fh_zero
    lea     rax, [rip + free_links]
    mov     rcx, [rip + free_head]
    mov     [rax + rdi * 8], rcx
    mov     [rip + free_head], rdi
    lea     rax, [rip + slots]
    mov     qword ptr [rax + rdi * 8], 0
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
    mov     rsi, r13
    call    assert_eq
    mov     rdi, r15
    call    lookup_handle
    mov     rdi, rax
    mov     rsi, 0x4444444444444444
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

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
