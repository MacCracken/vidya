# Vidya — Direct DRM GPU Compute in x86_64 Assembly
#
# In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

.intel_syntax noprefix
.global _start

.equ BO_CAP, 32
.equ VA_CAP, 32

.section .bss
.align 8
bo_size:      .skip 8 * BO_CAP
va_addr:      .skip 8 * VA_CAP
va_bo:        .skip 8 * VA_CAP

.section .data
fd:           .quad 0
next_bo:      .quad 1
va_count:     .quad 0
next_seq:     .quad 1
completed_seq: .quad 0

.section .rodata
msg_pass:     .ascii "direct_drm_gpu_compute: 20/20 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# open_render_node -> rax = fd (always 42)
open_render_node:
    mov     qword ptr [rip + fd], 42
    mov     rax, 42
    ret

# gem_create(rdi=size) -> rax = handle (1..BO_CAP-1) or 0
gem_create:
    mov     rax, [rip + next_bo]
    cmp     rax, BO_CAP
    jge     .gc_full
    inc     qword ptr [rip + next_bo]
    lea     rcx, [rip + bo_size]
    mov     [rcx + rax * 8], rdi
    ret
.gc_full:
    xor     rax, rax
    ret

# gem_destroy(rdi=handle) -> rax = 0/1
gem_destroy:
    test    rdi, rdi
    jz      .gd_zero
    cmp     rdi, BO_CAP
    jge     .gd_zero
    lea     rcx, [rip + bo_size]
    mov     rax, [rcx + rdi * 8]
    test    rax, rax
    jz      .gd_zero
    mov     qword ptr [rcx + rdi * 8], 0
    # Linear scan va_bo[] for matching handle, zero them
    mov     rcx, [rip + va_count]
    xor     rax, rax              # i
.gd_loop:
    cmp     rax, rcx
    jge     .gd_done
    lea     rdx, [rip + va_bo]
    mov     r8, [rdx + rax * 8]
    cmp     r8, rdi
    jne     .gd_next
    mov     qword ptr [rdx + rax * 8], 0
.gd_next:
    inc     rax
    jmp     .gd_loop
.gd_done:
    mov     rax, 1
    ret
.gd_zero:
    xor     rax, rax
    ret

# gem_va_map(rdi=handle, rsi=va) -> rax = 0/1
gem_va_map:
    test    rdi, rdi
    jz      .gv_zero
    cmp     rdi, BO_CAP
    jge     .gv_zero
    lea     rcx, [rip + bo_size]
    mov     rax, [rcx + rdi * 8]
    test    rax, rax
    jz      .gv_zero
    mov     rax, [rip + va_count]
    cmp     rax, VA_CAP
    jge     .gv_zero
    lea     rcx, [rip + va_addr]
    mov     [rcx + rax * 8], rsi
    lea     rcx, [rip + va_bo]
    mov     [rcx + rax * 8], rdi
    inc     qword ptr [rip + va_count]
    mov     rax, 1
    ret
.gv_zero:
    xor     rax, rax
    ret

# va_lookup(rdi=va) -> rax
va_lookup:
    mov     rcx, [rip + va_count]
    xor     rax, rax              # i
.vl_loop:
    cmp     rax, rcx
    jge     .vl_zero
    lea     rdx, [rip + va_addr]
    mov     r8, [rdx + rax * 8]
    cmp     r8, rdi
    jne     .vl_next
    lea     rdx, [rip + va_bo]
    mov     r8, [rdx + rax * 8]
    test    r8, r8
    jz      .vl_next
    mov     rax, r8
    ret
.vl_next:
    inc     rax
    jmp     .vl_loop
.vl_zero:
    xor     rax, rax
    ret

# do_submit(rdi=handle) -> rax = seq (or 0)
do_submit:
    test    rdi, rdi
    jz      .ds_zero
    cmp     rdi, BO_CAP
    jge     .ds_zero
    lea     rcx, [rip + bo_size]
    mov     rax, [rcx + rdi * 8]
    test    rax, rax
    jz      .ds_zero
    mov     rax, [rip + next_seq]
    inc     qword ptr [rip + next_seq]
    mov     [rip + completed_seq], rax
    ret
.ds_zero:
    xor     rax, rax
    ret

# syncobj_wait(rdi=seq) -> rax = 0/1
syncobj_wait:
    mov     rax, [rip + completed_seq]
    cmp     rax, rdi
    jge     .sw_one
    xor     rax, rax
    ret
.sw_one:
    mov     rax, 1
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
    # 1. open_render_node returns non-zero
    call    open_render_node
    test    rax, rax
    jz      fail_exit

    # 2. sequential bo handles
    mov     rdi, 4096
    call    gem_create
    mov     r12, rax
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    mov     rdi, 8192
    call    gem_create
    mov     r13, rax
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    mov     rdi, 16384
    call    gem_create
    mov     r14, rax
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # 3. va_map
    mov     rdi, r12
    mov     rsi, 0x1000
    call    gem_va_map
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    mov     rsi, 0x2000
    call    gem_va_map
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 4. va_lookup
    mov     rdi, 0x1000
    call    va_lookup
    mov     rdi, rax
    mov     rsi, r12
    call    assert_eq
    mov     rdi, 0x2000
    call    va_lookup
    mov     rdi, rax
    mov     rsi, r13
    call    assert_eq
    mov     rdi, 0x9000
    call    va_lookup
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # va_map invalid handles rejected
    mov     rdi, 99
    mov     rsi, 0x3000
    call    gem_va_map
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 0
    mov     rsi, 0x3000
    call    gem_va_map
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 5. submit returns increasing seq
    mov     rdi, r12
    call    do_submit
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    call    do_submit
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq
    mov     rdi, r14
    call    do_submit
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq

    # 6. syncobj_wait
    mov     rdi, 1
    call    syncobj_wait
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 3
    call    syncobj_wait
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 99
    call    syncobj_wait
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 7. destroy invalidates VA
    mov     rdi, r12
    call    gem_destroy
    mov     rdi, 0x1000
    call    va_lookup
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 8. submit on destroyed BO returns 0; next valid picks 4
    mov     rdi, r12
    call    do_submit
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, r13
    call    do_submit
    mov     rdi, rax
    mov     rsi, 4
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
