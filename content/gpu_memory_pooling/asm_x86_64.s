# Vidya — GPU Memory Pooling in x86_64 Assembly
#
# Bump allocator over a 1024-byte pool. -1 sentinel for exhaustion;
# alignment via (bump + mask) & ~mask. Pool storage in .bss; bump
# pointer in .data.

.intel_syntax noprefix
.global _start

.equ POOL_SIZE, 1024

.section .bss
.align 8
pool:         .skip POOL_SIZE

.section .data
bump:         .quad 0

.section .rodata
msg_pass:     .ascii "gpu_memory_pooling: 16/16 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

pool_reset:
    mov     qword ptr [rip + bump], 0
    ret

pool_used:
    mov     rax, [rip + bump]
    ret

pool_free:
    mov     rax, POOL_SIZE
    sub     rax, [rip + bump]
    ret

# pool_alloc(rdi=size) -> rax
pool_alloc:
    test    rdi, rdi
    jz      .pa_noop
    mov     rax, [rip + bump]
    add     rax, rdi
    cmp     rax, POOL_SIZE
    jg      .pa_full
    mov     rax, [rip + bump]
    add     qword ptr [rip + bump], rdi
    ret
.pa_noop:
    mov     rax, [rip + bump]
    ret
.pa_full:
    mov     rax, -1
    ret

# pool_alloc_aligned(rdi=size, rsi=align) -> rax
pool_alloc_aligned:
    mov     rax, rsi
    dec     rax                   # mask
    mov     rdx, [rip + bump]
    add     rdx, rax
    not     rax
    and     rdx, rax              # aligned = (bump + mask) & ~mask
    mov     rcx, rdx
    add     rcx, rdi
    cmp     rcx, POOL_SIZE
    jg      .paa_full
    mov     [rip + bump], rcx
    mov     rax, rdx
    ret
.paa_full:
    mov     rax, -1
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
    # 1. init
    call    pool_used
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    call    pool_free
    mov     rdi, rax
    mov     rsi, 1024
    call    assert_eq

    # 2. alloc(100) → 0; used = 100
    mov     rdi, 100
    call    pool_alloc
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    call    pool_used
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq

    # 3. alloc(200) → 100; used = 300
    mov     rdi, 200
    call    pool_alloc
    mov     rdi, rax
    mov     rsi, 100
    call    assert_eq
    call    pool_used
    mov     rdi, rax
    mov     rsi, 300
    call    assert_eq

    # 4. alloc(1000) → -1; used unchanged
    mov     rdi, 1000
    call    pool_alloc
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq
    call    pool_used
    mov     rdi, rax
    mov     rsi, 300
    call    assert_eq

    # 5. reset; alloc(50) → 0
    call    pool_reset
    call    pool_used
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    call    pool_free
    mov     rdi, rax
    mov     rsi, 1024
    call    assert_eq
    mov     rdi, 50
    call    pool_alloc
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 6. alloc_aligned(32, 16) → 64
    mov     rdi, 32
    mov     rsi, 16
    call    pool_alloc_aligned
    mov     rdi, rax
    mov     rsi, 64
    call    assert_eq
    call    pool_used
    mov     rdi, rax
    mov     rsi, 96
    call    assert_eq

    # 7. alloc(0) → 96 (no-op)
    mov     rdi, 0
    call    pool_alloc
    mov     rdi, rax
    mov     rsi, 96
    call    assert_eq
    call    pool_used
    mov     rdi, rax
    mov     rsi, 96
    call    assert_eq

    # 8. 10 × alloc(8) = 80
    call    pool_reset
    mov     rbx, 0                # i; callee-saved
.tens_loop:
    cmp     rbx, 10
    jge     .tens_done
    mov     rdi, 8
    call    pool_alloc
    inc     rbx
    jmp     .tens_loop
.tens_done:
    call    pool_used
    mov     rdi, rax
    mov     rsi, 80
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
