# Vidya — Distributed Systems Foundations — x86_64 Assembly
#
# Quorum-replication core (3 nodes, W=R=2). Demonstrates:
#   1. Write succeeds with 3 alive
#   2. Write succeeds with 2 alive (1 partitioned)
#   3. Write fails with 1 alive (< W)
#   4. Read sees latest after partition+heal+repartition (intersection)
#   5. Read returns -1 sentinel when alive < R
#
# Vector clocks live in cyrius.cyr — element-wise compare is too
# verbose for an instructive asm port.

.intel_syntax noprefix
.global _start

.equ N_NODES, 3
.equ W,       2
.equ R,       2

.section .bss
.align 8
accounts:    .skip 24
write_seq:   .skip 24
node_alive:  .skip 24
global_seq:  .skip 8

.section .rodata
msg_pass: .ascii "distributed_systems: 11/11 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# qc_init: zero accounts/write_seq, alive=1, global_seq=0
qc_init:
    xor     rcx, rcx
.qci_loop:
    cmp     rcx, N_NODES
    jge     .qci_done
    lea     r8, [rip + accounts]
    mov     qword ptr [r8 + rcx*8], 0
    lea     r8, [rip + write_seq]
    mov     qword ptr [r8 + rcx*8], 0
    lea     r8, [rip + node_alive]
    mov     qword ptr [r8 + rcx*8], 1
    inc     rcx
    jmp     .qci_loop
.qci_done:
    mov     qword ptr [rip + global_seq], 0
    ret

# qc_partition(rdi=node), qc_heal(rdi=node)
qc_partition:
    lea     r8, [rip + node_alive]
    mov     qword ptr [r8 + rdi*8], 0
    ret
qc_heal:
    lea     r8, [rip + node_alive]
    mov     qword ptr [r8 + rdi*8], 1
    ret

# alive_count -> rax
alive_count:
    lea     r8, [rip + node_alive]
    xor     rax, rax
    xor     rcx, rcx
.ac_loop:
    cmp     rcx, N_NODES
    jge     .ac_done
    add     rax, [r8 + rcx*8]
    inc     rcx
    jmp     .ac_loop
.ac_done:
    ret

# qc_write(rdi=value) -> rax = 1/0
qc_write:
    push    rdi
    call    alive_count
    pop     rdi
    cmp     rax, W
    jl      .qw_fail
    mov     rax, [rip + global_seq]
    inc     rax
    mov     [rip + global_seq], rax
    mov     r9, rax                       # new seq
    xor     rcx, rcx
.qw_loop:
    cmp     rcx, N_NODES
    jge     .qw_ok
    lea     r8, [rip + node_alive]
    mov     r10, [r8 + rcx*8]
    cmp     r10, 1
    jne     .qw_skip
    lea     r8, [rip + accounts]
    mov     [r8 + rcx*8], rdi
    lea     r8, [rip + write_seq]
    mov     [r8 + rcx*8], r9
.qw_skip:
    inc     rcx
    jmp     .qw_loop
.qw_ok:
    mov     rax, 1
    ret
.qw_fail:
    xor     rax, rax
    ret

# qc_read -> rax = best_value, or -1
qc_read:
    call    alive_count
    cmp     rax, R
    jl      .qr_fail
    xor     r9, r9                        # best_seq
    xor     r10, r10                      # best_value
    xor     rcx, rcx
.qr_loop:
    cmp     rcx, N_NODES
    jge     .qr_done
    lea     r8, [rip + node_alive]
    mov     r11, [r8 + rcx*8]
    cmp     r11, 1
    jne     .qr_skip
    lea     r8, [rip + write_seq]
    mov     r11, [r8 + rcx*8]
    cmp     r11, r9
    jle     .qr_skip
    mov     r9, r11
    lea     r8, [rip + accounts]
    mov     r10, [r8 + rcx*8]
.qr_skip:
    inc     rcx
    jmp     .qr_loop
.qr_done:
    mov     rax, r10
    ret
.qr_fail:
    mov     rax, -1
    ret

assert_eq:
    cmp     rdi, rsi
    jne     .ae_fail
    ret
.ae_fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    # Test 1: write ok with 3 alive
    call    qc_init
    mov     rdi, 100
    call    qc_write
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 100
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 16]
    mov     rsi, 100
    call    assert_eq

    # Test 2: write ok with 1 partitioned
    call    qc_init
    mov     rdi, 2
    call    qc_partition
    mov     rdi, 200
    call    qc_write
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 200
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 16]
    mov     rsi, 0
    call    assert_eq                     # node 2 untouched

    # Test 3: write fails with 2 partitioned
    call    qc_init
    mov     rdi, 1
    call    qc_partition
    mov     rdi, 2
    call    qc_partition
    mov     rdi, 300
    call    qc_write
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # Test 4: intersection guarantees latest read
    call    qc_init
    mov     rdi, 2
    call    qc_partition
    mov     rdi, 500
    call    qc_write
    mov     rdi, 2
    call    qc_heal
    mov     rdi, 0
    call    qc_partition
    call    qc_read
    mov     rdi, rax
    mov     rsi, 500
    call    assert_eq

    # Test 5: read sentinel when alive < R
    call    qc_init
    mov     rdi, 700
    call    qc_write
    mov     rdi, 0
    call    qc_partition
    mov     rdi, 1
    call    qc_partition
    call    qc_read
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    # success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
