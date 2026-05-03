// Vidya — Transactions and ACID — AArch64 Assembly
//
// Single-tx OCC core. Demonstrates A (atomicity), C (consistency),
// D (durability), and OCC version-snapshot conflict detection.
// (Multi-tx dirty-read isolation is in cyrius.cyr — too verbose here.)

.global _start

.equ N_ACCOUNTS, 4
.equ TX_CAP,     4
.equ TX_FREE,      0
.equ TX_ACTIVE,    1
.equ TX_COMMITTED, 2
.equ TX_ABORTED,   3

.bss
.align 8
accounts:    .skip 32
versions:    .skip 32
tx_status:   .skip 8
tx_wcount:   .skip 8
tx_wkeys:    .skip 32
tx_wvals:    .skip 32
tx_rcount:   .skip 8
tx_rkeys:    .skip 32
tx_rsnaps:   .skip 32

.section .rodata
msg_pass: .ascii "transactions_and_acid: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// --- helpers ---

// load address of label `sym` into reg
.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// store_init: zero accounts + versions + tx state
store_init:
    LDADDR  x0, accounts
    mov     x1, #0
.si_loop:
    cmp     x1, #28
    b.ge    .si_done_a
    str     xzr, [x0, x1, lsl #0]
    add     x1, x1, #8
    b       .si_loop
.si_done_a:
    LDADDR  x0, tx_status
    str     xzr, [x0]
    LDADDR  x0, tx_wcount
    str     xzr, [x0]
    LDADDR  x0, tx_rcount
    str     xzr, [x0]
    ret

// account_set_raw(x0=k, x1=v): bumps version
account_set_raw:
    LDADDR  x2, accounts
    str     x1, [x2, x0, lsl #3]
    LDADDR  x2, versions
    ldr     x3, [x2, x0, lsl #3]
    add     x3, x3, #1
    str     x3, [x2, x0, lsl #3]
    ret

// account_total -> x0
account_total:
    LDADDR  x1, accounts
    mov     x0, #0
    mov     x2, #0
.at_loop:
    cmp     x2, #N_ACCOUNTS
    b.ge    .at_done
    ldr     x3, [x1, x2, lsl #3]
    add     x0, x0, x3
    add     x2, x2, #1
    b       .at_loop
.at_done:
    ret

// tx_begin -> x0=0
tx_begin:
    mov     x1, #TX_ACTIVE
    LDADDR  x0, tx_status
    str     x1, [x0]
    LDADDR  x0, tx_wcount
    str     xzr, [x0]
    LDADDR  x0, tx_rcount
    str     xzr, [x0]
    mov     x0, #0
    ret

// tx_find_write(x0=k) -> x0 = idx or -1
tx_find_write:
    LDADDR  x1, tx_wcount
    ldr     x1, [x1]
    mov     x2, #0
.fw_loop:
    cmp     x2, x1
    b.ge    .fw_miss
    LDADDR  x3, tx_wkeys
    ldr     x4, [x3, x2, lsl #3]
    cmp     x4, x0
    b.eq    .fw_done
    add     x2, x2, #1
    b       .fw_loop
.fw_miss:
    mov     x0, #-1
    ret
.fw_done:
    mov     x0, x2
    ret

// tx_has_read(x0=k) -> x0 = 1/0
tx_has_read:
    LDADDR  x1, tx_rcount
    ldr     x1, [x1]
    mov     x2, #0
.hr_loop:
    cmp     x2, x1
    b.ge    .hr_miss
    LDADDR  x3, tx_rkeys
    ldr     x4, [x3, x2, lsl #3]
    cmp     x4, x0
    b.eq    .hr_hit
    add     x2, x2, #1
    b       .hr_loop
.hr_hit:
    mov     x0, #1
    ret
.hr_miss:
    mov     x0, #0
    ret

// tx_read(x0=k) -> x0 = value
tx_read:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    sub     sp, sp, #16
    str     x0, [sp]                // save k
    bl      tx_find_write
    ldr     x1, [sp]                // x1 = k (restored)
    cmp     x0, #0
    b.lt    .tr_no_w
    LDADDR  x2, tx_wvals
    ldr     x0, [x2, x0, lsl #3]
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret
.tr_no_w:
    mov     x0, x1                  // k
    bl      tx_has_read
    ldr     x1, [sp]                // restore k
    cbnz    x0, .tr_just_load
    LDADDR  x2, tx_rcount
    ldr     x3, [x2]
    cmp     x3, #TX_CAP
    b.ge    .tr_just_load
    LDADDR  x4, tx_rkeys
    str     x1, [x4, x3, lsl #3]
    LDADDR  x4, versions
    ldr     x5, [x4, x1, lsl #3]
    LDADDR  x4, tx_rsnaps
    str     x5, [x4, x3, lsl #3]
    add     x3, x3, #1
    str     x3, [x2]
.tr_just_load:
    LDADDR  x4, accounts
    ldr     x0, [x4, x1, lsl #3]
    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

// tx_write(x0=k, x1=v) -> x0=1
tx_write:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x0, x1, [sp, #-16]!     // save k, v
    bl      tx_find_write
    ldp     x1, x2, [sp]            // x1=k, x2=v
    cmp     x0, #0
    b.lt    .tw_new
    LDADDR  x3, tx_wvals
    str     x2, [x3, x0, lsl #3]
    add     sp, sp, #16
    mov     x0, #1
    ldp     x29, x30, [sp], #16
    ret
.tw_new:
    LDADDR  x3, tx_wcount
    ldr     x4, [x3]
    LDADDR  x5, tx_wkeys
    str     x1, [x5, x4, lsl #3]
    LDADDR  x5, tx_wvals
    str     x2, [x5, x4, lsl #3]
    add     x4, x4, #1
    str     x4, [x3]
    add     sp, sp, #16
    mov     x0, #1
    ldp     x29, x30, [sp], #16
    ret

// tx_validate -> x0=1/0
tx_validate:
    LDADDR  x1, tx_rcount
    ldr     x1, [x1]
    mov     x2, #0
.tv_loop:
    cmp     x2, x1
    b.ge    .tv_pass
    LDADDR  x3, tx_rkeys
    ldr     x4, [x3, x2, lsl #3]    // x4 = key
    LDADDR  x3, tx_rsnaps
    ldr     x5, [x3, x2, lsl #3]    // x5 = snap
    LDADDR  x3, versions
    ldr     x6, [x3, x4, lsl #3]    // x6 = current version
    cmp     x5, x6
    b.ne    .tv_fail
    add     x2, x2, #1
    b       .tv_loop
.tv_pass:
    mov     x0, #1
    ret
.tv_fail:
    mov     x0, #0
    ret

// tx_commit -> x0=1/0
tx_commit:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      tx_validate
    cbz     x0, .tc_abort
    LDADDR  x1, tx_wcount
    ldr     x1, [x1]
    mov     x2, #0
.tc_install:
    cmp     x2, x1
    b.ge    .tc_done
    LDADDR  x3, tx_wkeys
    ldr     x4, [x3, x2, lsl #3]    // key
    LDADDR  x3, tx_wvals
    ldr     x5, [x3, x2, lsl #3]    // val
    LDADDR  x3, accounts
    str     x5, [x3, x4, lsl #3]
    LDADDR  x3, versions
    ldr     x6, [x3, x4, lsl #3]
    add     x6, x6, #1
    str     x6, [x3, x4, lsl #3]
    add     x2, x2, #1
    b       .tc_install
.tc_done:
    mov     x1, #TX_COMMITTED
    LDADDR  x0, tx_status
    str     x1, [x0]
    mov     x0, #1
    ldp     x29, x30, [sp], #16
    ret
.tc_abort:
    mov     x1, #TX_ABORTED
    LDADDR  x0, tx_status
    str     x1, [x0]
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

// tx_abort
tx_abort:
    mov     x1, #TX_ABORTED
    LDADDR  x0, tx_status
    str     x1, [x0]
    ret

// crash_recovery
crash_recovery:
    LDADDR  x0, tx_status
    str     xzr, [x0]
    LDADDR  x0, tx_wcount
    str     xzr, [x0]
    LDADDR  x0, tx_rcount
    str     xzr, [x0]
    ret

// seed
seed:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      store_init
    mov     x0, #0
    mov     x1, #1000
    bl      account_set_raw
    mov     x0, #1
    mov     x1, #500
    bl      account_set_raw
    mov     x0, #2
    mov     x1, #200
    bl      account_set_raw
    ldp     x29, x30, [sp], #16
    ret

// assert_eq(x0=actual, x1=expected): exit on mismatch
assert_eq:
    cmp     x0, x1
    b.ne    .ae_fail
    ret
.ae_fail:
    mov     x8, #64                 // sys_write
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    svc     #0
    mov     x8, #93                 // sys_exit
    mov     x0, #1
    svc     #0

_start:
    // Test 1: abort discards
    bl      seed
    bl      tx_begin
    mov     x0, #0
    mov     x1, #9999
    bl      tx_write
    mov     x0, #1
    mov     x1, #8888
    bl      tx_write
    mov     x0, #2
    mov     x1, #7777
    bl      tx_write
    bl      tx_abort
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     x1, #1000
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #8]
    mov     x1, #500
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #16]
    mov     x1, #200
    bl      assert_eq

    // Test 2: commit installs all
    bl      seed
    bl      tx_begin
    mov     x0, #0
    mov     x1, #100
    bl      tx_write
    mov     x0, #1
    mov     x1, #200
    bl      tx_write
    mov     x0, #2
    mov     x1, #300
    bl      tx_write
    bl      tx_commit
    mov     x1, #1
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     x1, #100
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #8]
    mov     x1, #200
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #16]
    mov     x1, #300
    bl      assert_eq

    // Test 3: transfer preserves total
    bl      seed
    bl      account_total
    mov     x19, x0                 // x19 = initial
    bl      tx_begin
    mov     x0, #0
    bl      tx_read
    mov     x20, x0                 // src
    mov     x0, #1
    bl      tx_read
    mov     x21, x0                 // dst
    mov     x0, #0
    sub     x1, x20, #100
    bl      tx_write
    mov     x0, #1
    add     x1, x21, #100
    bl      tx_write
    bl      tx_commit
    bl      account_total
    mov     x1, x19
    bl      assert_eq

    // Test 4: durability across crash
    bl      seed
    bl      tx_begin
    mov     x0, #0
    mov     w1, #12345              // 12345 fits in 16 bits but use w1 for clarity
    bl      tx_write
    bl      tx_commit
    bl      crash_recovery
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     w1, #12345
    bl      assert_eq

    // Test 5: OCC validation — raw bump after read aborts commit
    bl      seed
    bl      tx_begin
    mov     x0, #0
    bl      tx_read
    mov     x0, #0
    mov     x1, #5555
    bl      account_set_raw
    mov     x0, #0
    mov     x1, #9999
    bl      tx_write
    bl      tx_commit
    mov     x1, #0
    bl      assert_eq
    LDADDR  x2, tx_status
    ldr     x0, [x2]
    mov     x1, #TX_ABORTED
    bl      assert_eq
    LDADDR  x2, accounts
    ldr     x0, [x2, #0]
    mov     x1, #5555
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
