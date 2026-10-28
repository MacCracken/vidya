# Vidya — Explicit GPU Synchronization in x86_64 Assembly
#
# Timeline semaphores in .data globals; signal advances iff value
# strictly greater than current; wait returns 0/1 reachability.

.intel_syntax noprefix
.global _start

.section .data
sem_compute:  .quad 0
sem_transfer: .quad 0

.section .rodata
msg_pass:     .ascii "explicit_gpu_synchronization: 19/19 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

sem_reset:
    mov     qword ptr [rip + sem_compute], 0
    mov     qword ptr [rip + sem_transfer], 0
    ret

# signal(rdi=sem, rsi=value) -> rax = 0/1
do_signal:
    test    rdi, rdi
    jnz     .ds_t
    # compute
    mov     rax, [rip + sem_compute]
    cmp     rsi, rax
    jle     .ds_zero
    mov     [rip + sem_compute], rsi
    mov     rax, 1
    ret
.ds_t:
    cmp     rdi, 1
    jne     .ds_zero
    mov     rax, [rip + sem_transfer]
    cmp     rsi, rax
    jle     .ds_zero
    mov     [rip + sem_transfer], rsi
    mov     rax, 1
    ret
.ds_zero:
    xor     rax, rax
    ret

# wait_for(rdi=sem, rsi=target) -> rax
do_wait_for:
    test    rdi, rdi
    jnz     .dw_t
    mov     rax, [rip + sem_compute]
    cmp     rax, rsi
    jge     .dw_one
    jmp     .dw_zero
.dw_t:
    cmp     rdi, 1
    jne     .dw_zero
    mov     rax, [rip + sem_transfer]
    cmp     rax, rsi
    jge     .dw_one
.dw_zero:
    xor     rax, rax
    ret
.dw_one:
    mov     rax, 1
    ret

# wait_all(rdi=c_target, rsi=t_target) -> rax
# Caches targets in callee-saved across the two do_wait_for calls.
do_wait_all:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi              # c_target
    mov     r13, rsi              # t_target
    mov     rdi, 0
    mov     rsi, r12
    call    do_wait_for
    mov     rbx, rax              # cok
    mov     rdi, 1
    mov     rsi, r13
    call    do_wait_for
    test    rbx, rbx
    jz      .da_zero
    test    rax, rax
    jz      .da_zero
    mov     rax, 1
    pop     r13
    pop     r12
    pop     rbx
    ret
.da_zero:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
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
    mov     rdi, [rip + sem_compute]
    mov     rsi, 0
    call    assert_eq
    mov     rdi, [rip + sem_transfer]
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 0
    call    do_wait_for
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 2. signal advances
    mov     rdi, 0
    mov     rsi, 5
    call    do_signal
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, [rip + sem_compute]
    mov     rsi, 5
    call    assert_eq

    # 3. past, current, future
    mov     rdi, 0
    mov     rsi, 3
    call    do_wait_for
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 5
    call    do_wait_for
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 10
    call    do_wait_for
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 4. regression rejected
    mov     rdi, 0
    mov     rsi, 3
    call    do_signal
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, [rip + sem_compute]
    mov     rsi, 5
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 5
    call    do_signal
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 5. multi-sem wait_all
    mov     rdi, 1
    mov     rsi, 3
    call    do_signal
    mov     rdi, [rip + sem_transfer]
    mov     rsi, 3
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 3
    call    do_wait_all
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 5
    mov     rsi, 4
    call    do_wait_all
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 6
    mov     rsi, 3
    call    do_wait_all
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 0
    call    do_wait_all
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 6. monotonic
    call    sem_reset
    mov     rbx, 1                # i
.ml:
    cmp     rbx, 10
    jg      .ml_done
    mov     rdi, 0
    mov     rsi, rbx
    call    do_signal
    inc     rbx
    jmp     .ml
.ml_done:
    mov     rdi, [rip + sem_compute]
    mov     rsi, 10
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 10
    call    do_wait_for
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 11
    call    do_wait_for
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
