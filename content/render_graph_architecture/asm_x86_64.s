# Vidya — Render Graph Architecture in x86_64 Assembly
#
# Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

.intel_syntax noprefix
.global _start

.equ PASS_CAP, 16

.section .bss
.align 8
pass_id:      .skip 8 * PASS_CAP
reads_arr:    .skip 8 * PASS_CAP
writes_arr:   .skip 8 * PASS_CAP
topo_order:   .skip 8 * PASS_CAP
in_degree:    .skip 8 * PASS_CAP

.section .data
pass_count:   .quad 0
topo_len:     .quad 0

.section .rodata
msg_pass:     .ascii "render_graph_architecture: 14/14 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

graph_init:
    lea     rdi, [rip + pass_id]
    mov     rcx, PASS_CAP
    xor     rax, rax
.gi_loop1:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .gi_loop1
    lea     rdi, [rip + reads_arr]
    mov     rcx, PASS_CAP
.gi_loop2:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .gi_loop2
    lea     rdi, [rip + writes_arr]
    mov     rcx, PASS_CAP
.gi_loop3:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .gi_loop3
    mov     qword ptr [rip + pass_count], 0
    mov     qword ptr [rip + topo_len], 0
    ret

# add_pass(rdi=id, rsi=r, rdx=w) -> rax = idx or -1
add_pass:
    mov     rax, [rip + pass_count]
    cmp     rax, PASS_CAP
    jge     .ap_full
    inc     qword ptr [rip + pass_count]
    lea     rcx, [rip + pass_id]
    mov     [rcx + rax * 8], rdi
    lea     rcx, [rip + reads_arr]
    mov     [rcx + rax * 8], rsi
    lea     rcx, [rip + writes_arr]
    mov     [rcx + rax * 8], rdx
    ret
.ap_full:
    mov     rax, -1
    ret

# has_edge(rdi=p, rsi=c) -> rax = 0/1
has_edge:
    lea     rax, [rip + writes_arr]
    mov     rax, [rax + rdi * 8]
    lea     rcx, [rip + reads_arr]
    mov     rcx, [rcx + rsi * 8]
    and     rax, rcx
    test    rax, rax
    jz      .he_zero
    mov     rax, 1
    ret
.he_zero:
    xor     rax, rax
    ret

# topo_sort -> rax = topo_len
# Uses callee-saved across has_edge calls.
topo_sort:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    # Zero in_degree
    lea     rdi, [rip + in_degree]
    mov     rcx, PASS_CAP
    xor     rax, rax
.ts_zero:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .ts_zero

    # Compute in_degrees: for each pair (j, i), if has_edge(j, i): in_degree[i]++
    mov     r12, [rip + pass_count]   # count (callee-saved)
    xor     r13, r13                  # i
.ts_in_i:
    cmp     r13, r12
    jge     .ts_kahn_init
    xor     r14, r14                  # j
.ts_in_j:
    cmp     r14, r12
    jge     .ts_in_i_next
    cmp     r13, r14
    je      .ts_in_j_next
    mov     rdi, r14
    mov     rsi, r13
    call    has_edge
    test    rax, rax
    jz      .ts_in_j_next
    lea     rcx, [rip + in_degree]
    mov     rax, [rcx + r13 * 8]
    inc     rax
    mov     [rcx + r13 * 8], rax
.ts_in_j_next:
    inc     r14
    jmp     .ts_in_j
.ts_in_i_next:
    inc     r13
    jmp     .ts_in_i

.ts_kahn_init:
    mov     qword ptr [rip + topo_len], 0
    xor     r15, r15                  # emitted
.ts_kahn_loop:
    cmp     r15, r12
    jge     .ts_done
    # Pick next pass with in_degree == 0
    mov     rbx, -1
    xor     r13, r13
.ts_pick:
    cmp     r13, r12
    jge     .ts_pick_done
    lea     rcx, [rip + in_degree]
    mov     rax, [rcx + r13 * 8]
    test    rax, rax
    jnz     .ts_pick_next
    mov     rbx, r13
    jmp     .ts_pick_done
.ts_pick_next:
    inc     r13
    jmp     .ts_pick
.ts_pick_done:
    cmp     rbx, 0
    jl      .ts_done
    # Emit picked
    mov     rcx, [rip + topo_len]
    lea     rax, [rip + topo_order]
    mov     [rax + rcx * 8], rbx
    inc     qword ptr [rip + topo_len]
    # Mark emitted
    lea     rcx, [rip + in_degree]
    mov     qword ptr [rcx + rbx * 8], -1
    # Decrement consumers' in_degrees
    xor     r13, r13                  # c
.ts_dec:
    cmp     r13, r12
    jge     .ts_dec_done
    cmp     r13, rbx
    je      .ts_dec_next
    mov     rdi, rbx
    mov     rsi, r13
    call    has_edge
    test    rax, rax
    jz      .ts_dec_next
    lea     rcx, [rip + in_degree]
    mov     rax, [rcx + r13 * 8]
    test    rax, rax
    jle     .ts_dec_next
    dec     rax
    mov     [rcx + r13 * 8], rax
.ts_dec_next:
    inc     r13
    jmp     .ts_dec
.ts_dec_done:
    inc     r15
    jmp     .ts_kahn_loop
.ts_done:
    mov     rax, [rip + topo_len]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# barrier_count -> rax
barrier_count:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, [rip + topo_len]
    xor     rbx, rbx                  # count
    xor     r13, r13                  # i
.bc_i:
    cmp     r13, r12
    jge     .bc_done
    mov     r14, r13
    inc     r14                       # j
.bc_j:
    cmp     r14, r12
    jge     .bc_i_next
    lea     rcx, [rip + topo_order]
    mov     rdi, [rcx + r13 * 8]
    mov     rsi, [rcx + r14 * 8]
    call    has_edge
    test    rax, rax
    jz      .bc_j_next
    inc     rbx
.bc_j_next:
    inc     r14
    jmp     .bc_j
.bc_i_next:
    inc     r13
    jmp     .bc_i
.bc_done:
    mov     rax, rbx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# cull_dead -> rax = culled count
cull_dead:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, [rip + pass_count]
    xor     rbx, rbx                  # culled
    xor     r13, r13                  # i
.cd_i:
    cmp     r13, r12
    jge     .cd_done
    lea     rcx, [rip + writes_arr]
    mov     r14, [rcx + r13 * 8]      # w
    test    r14, r14
    jz      .cd_i_next
    # any_reader?
    push    r15
    xor     r15, r15                  # any
    push    rax
    push    rcx
    xor     rax, rax                  # j
.cd_j:
    cmp     rax, r12
    jge     .cd_j_done
    cmp     rax, r13
    je      .cd_j_next
    lea     rcx, [rip + reads_arr]
    mov     rdi, [rcx + rax * 8]
    and     rdi, r14
    test    rdi, rdi
    jz      .cd_j_next
    mov     r15, 1
    jmp     .cd_j_done
.cd_j_next:
    inc     rax
    jmp     .cd_j
.cd_j_done:
    pop     rcx
    pop     rax
    test    r15, r15
    jnz     .cd_pop_next
    # No reader → cull
    lea     rcx, [rip + writes_arr]
    mov     qword ptr [rcx + r13 * 8], 0
    lea     rcx, [rip + reads_arr]
    mov     qword ptr [rcx + r13 * 8], 0
    inc     rbx
.cd_pop_next:
    pop     r15
.cd_i_next:
    inc     r13
    jmp     .cd_i
.cd_done:
    mov     rax, rbx
    pop     r14
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
    call    graph_init

    mov     rdi, 100
    mov     rsi, 0
    mov     rdx, 1
    call    add_pass
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    mov     rdi, 101
    mov     rsi, 1
    mov     rdx, 2
    call    add_pass
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    mov     rdi, 102
    mov     rsi, 2
    mov     rdx, 0
    call    add_pass
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    call    topo_sort
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq
    lea     rcx, [rip + topo_order]
    mov     rdi, [rcx]
    mov     rsi, 0
    call    assert_eq
    lea     rcx, [rip + topo_order]
    mov     rdi, [rcx + 8]
    mov     rsi, 1
    call    assert_eq
    lea     rcx, [rip + topo_order]
    mov     rdi, [rcx + 16]
    mov     rsi, 2
    call    assert_eq

    call    barrier_count
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    mov     rdi, 103
    mov     rsi, 0
    mov     rdx, 4
    call    add_pass
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq
    call    cull_dead
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     rcx, [rip + writes_arr]
    mov     rdi, [rcx + 24]
    mov     rsi, 0
    call    assert_eq

    call    topo_sort
    mov     rdi, rax
    mov     rsi, 4
    call    assert_eq
    call    barrier_count
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    # Cycle test
    call    graph_init
    mov     rdi, 200
    mov     rsi, 1
    mov     rdx, 2
    call    add_pass
    mov     rdi, 201
    mov     rsi, 2
    mov     rdx, 1
    call    add_pass
    call    topo_sort
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
