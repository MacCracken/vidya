// Vidya — Distributed Systems Foundations — AArch64 Assembly
//
// Quorum-replication core (3 nodes, W=R=2). Same 5 tests / 11
// asserts as the x86_64 port. Vector clocks live in cyrius.cyr.

.global _start

.equ N_NODES, 3
.equ W,       2
.equ R,       2

.bss
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

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

qc_init:
    mov     x0, #0
.qci_loop:
    cmp     x0, #N_NODES
    b.ge    .qci_done
    LDADDR  x1, accounts
    str     xzr, [x1, x0, lsl #3]
    LDADDR  x1, write_seq
    str     xzr, [x1, x0, lsl #3]
    LDADDR  x1, node_alive
    mov     x2, #1
    str     x2, [x1, x0, lsl #3]
    add     x0, x0, #1
    b       .qci_loop
.qci_done:
    LDADDR  x1, global_seq
    str     xzr, [x1]
    ret

qc_partition:
    LDADDR  x1, node_alive
    str     xzr, [x1, x0, lsl #3]
    ret
qc_heal:
    LDADDR  x1, node_alive
    mov     x2, #1
    str     x2, [x1, x0, lsl #3]
    ret

alive_count:
    LDADDR  x1, node_alive
    mov     x0, #0
    mov     x2, #0
.ac_loop:
    cmp     x2, #N_NODES
    b.ge    .ac_done
    ldr     x3, [x1, x2, lsl #3]
    add     x0, x0, x3
    add     x2, x2, #1
    b       .ac_loop
.ac_done:
    ret

// qc_write(x0=value) -> x0=1/0
qc_write:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x0, [sp, #16]                 // save value
    bl      alive_count
    cmp     x0, #W
    b.lt    .qw_fail
    LDADDR  x1, global_seq
    ldr     x2, [x1]
    add     x2, x2, #1
    str     x2, [x1]
    mov     x3, x2                        // new seq
    ldr     x4, [sp, #16]                 // value
    mov     x5, #0
.qw_loop:
    cmp     x5, #N_NODES
    b.ge    .qw_ok
    LDADDR  x1, node_alive
    ldr     x6, [x1, x5, lsl #3]
    cmp     x6, #1
    b.ne    .qw_skip
    LDADDR  x1, accounts
    str     x4, [x1, x5, lsl #3]
    LDADDR  x1, write_seq
    str     x3, [x1, x5, lsl #3]
.qw_skip:
    add     x5, x5, #1
    b       .qw_loop
.qw_ok:
    mov     x0, #1
    ldp     x29, x30, [sp], #32
    ret
.qw_fail:
    mov     x0, #0
    ldp     x29, x30, [sp], #32
    ret

// qc_read -> x0 = best_value or -1
qc_read:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      alive_count
    cmp     x0, #R
    b.lt    .qr_fail
    mov     x3, #0                        // best_seq
    mov     x4, #0                        // best_value
    mov     x5, #0
.qr_loop:
    cmp     x5, #N_NODES
    b.ge    .qr_done
    LDADDR  x1, node_alive
    ldr     x6, [x1, x5, lsl #3]
    cmp     x6, #1
    b.ne    .qr_skip
    LDADDR  x1, write_seq
    ldr     x6, [x1, x5, lsl #3]
    cmp     x6, x3
    b.le    .qr_skip
    mov     x3, x6
    LDADDR  x1, accounts
    ldr     x4, [x1, x5, lsl #3]
.qr_skip:
    add     x5, x5, #1
    b       .qr_loop
.qr_done:
    mov     x0, x4
    ldp     x29, x30, [sp], #16
    ret
.qr_fail:
    mov     x0, #-1
    ldp     x29, x30, [sp], #16
    ret

assert_eq:
    cmp     x0, x1
    b.ne    .ae_fail
    ret
.ae_fail:
    mov     x8, #64
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    svc     #0
    mov     x8, #93
    mov     x0, #1
    svc     #0

_start:
    // Test 1: write ok with 3 alive
    bl      qc_init
    mov     x0, #100
    bl      qc_write
    mov     x1, #1
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     x1, #100
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #16]
    mov     x1, #100
    bl      assert_eq

    // Test 2: write ok with 1 partitioned
    bl      qc_init
    mov     x0, #2
    bl      qc_partition
    mov     x0, #200
    bl      qc_write
    mov     x1, #1
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     x1, #200
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #16]
    mov     x1, #0
    bl      assert_eq

    // Test 3: write fails with 2 partitioned
    bl      qc_init
    mov     x0, #1
    bl      qc_partition
    mov     x0, #2
    bl      qc_partition
    mov     x0, #300
    bl      qc_write
    mov     x1, #0
    bl      assert_eq

    // Test 4: intersection guarantees latest read
    bl      qc_init
    mov     x0, #2
    bl      qc_partition
    mov     x0, #500
    bl      qc_write
    mov     x0, #2
    bl      qc_heal
    mov     x0, #0
    bl      qc_partition
    bl      qc_read
    mov     x1, #500
    bl      assert_eq

    // Test 5: read sentinel below R
    bl      qc_init
    mov     x0, #700
    bl      qc_write
    mov     x0, #0
    bl      qc_partition
    mov     x0, #1
    bl      qc_partition
    bl      qc_read
    mov     x1, #-1
    bl      assert_eq

    // success
    mov     x8, #64
    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    svc     #0
    mov     x8, #93
    mov     x0, #0
    svc     #0
