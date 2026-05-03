# Vidya — Transactions and ACID — x86_64 Assembly
#
# Single-tx OCC core. Demonstrates A (atomicity), C (consistency),
# D (durability), and OCC version-snapshot conflict detection.
# (Multi-tx dirty-read isolation is in cyrius.cyr — too verbose here.)
#
# Tests (12 asserts):
#   1. abort discards 3 writes      (A)
#   2. commit installs 3 writes     (A)
#   3. transfer preserves total      (C)
#   4. durability across "crash"     (D)
#   5. raw bump after read aborts commit  (OCC validation)

.intel_syntax noprefix
.global _start

.equ N_ACCOUNTS, 4
.equ TX_CAP,     4
.equ TX_FREE,      0
.equ TX_ACTIVE,    1
.equ TX_COMMITTED, 2
.equ TX_ABORTED,   3

.section .bss
.align 8
accounts:    .skip 32        # 4 × i64
versions:    .skip 32
tx_status:   .skip 8
tx_wcount:   .skip 8
tx_wkeys:    .skip 32        # 4 × i64
tx_wvals:    .skip 32
tx_rcount:   .skip 8
tx_rkeys:    .skip 32
tx_rsnaps:   .skip 32

.section .rodata
msg_pass: .ascii "transactions_and_acid: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# store_init — zero accounts/versions/tx state
store_init:
    lea     rdi, [rip + accounts]
    mov     rcx, 28
.si_loop:
    mov     qword ptr [rdi + rcx*8 - 8], 0
    loop    .si_loop
    mov     qword ptr [rip + accounts], 0
    mov     qword ptr [rip + tx_status], TX_FREE
    mov     qword ptr [rip + tx_wcount], 0
    mov     qword ptr [rip + tx_rcount], 0
    ret

# account_set_raw(rdi=k, rsi=v): bumps version
account_set_raw:
    lea     rax, [rip + accounts]
    mov     [rax + rdi*8], rsi
    lea     rax, [rip + versions]
    mov     rcx, [rax + rdi*8]
    inc     rcx
    mov     [rax + rdi*8], rcx
    ret

# account_total -> rax
account_total:
    lea     rdi, [rip + accounts]
    xor     rax, rax
    mov     rcx, 0
.at_loop:
    cmp     rcx, N_ACCOUNTS
    jge     .at_done
    add     rax, [rdi + rcx*8]
    inc     rcx
    jmp     .at_loop
.at_done:
    ret

# tx_begin -> rax = 0 (only 1 slot)
tx_begin:
    mov     qword ptr [rip + tx_status], TX_ACTIVE
    mov     qword ptr [rip + tx_wcount], 0
    mov     qword ptr [rip + tx_rcount], 0
    xor     rax, rax
    ret

# tx_find_write(rdi=k) -> rax = idx or -1
tx_find_write:
    mov     rcx, [rip + tx_wcount]
    xor     rax, rax
.fw_loop:
    cmp     rax, rcx
    jge     .fw_miss
    lea     r8, [rip + tx_wkeys]
    mov     r9, [r8 + rax*8]
    cmp     r9, rdi
    je      .fw_done
    inc     rax
    jmp     .fw_loop
.fw_miss:
    mov     rax, -1
.fw_done:
    ret

# tx_has_read(rdi=k) -> rax = 1/0
tx_has_read:
    mov     rcx, [rip + tx_rcount]
    xor     r10, r10
.hr_loop:
    cmp     r10, rcx
    jge     .hr_miss
    lea     r8, [rip + tx_rkeys]
    mov     r9, [r8 + r10*8]
    cmp     r9, rdi
    je      .hr_hit
    inc     r10
    jmp     .hr_loop
.hr_hit:
    mov     rax, 1
    ret
.hr_miss:
    xor     rax, rax
    ret

# tx_read(rdi=k) -> rax = value
tx_read:
    push    rdi
    call    tx_find_write
    pop     rdi
    cmp     rax, 0
    jl      .tr_no_w
    lea     r8, [rip + tx_wvals]
    mov     rax, [r8 + rax*8]
    ret
.tr_no_w:
    push    rdi
    call    tx_has_read
    pop     rdi
    test    rax, rax
    jnz     .tr_just_load
    mov     rcx, [rip + tx_rcount]
    cmp     rcx, TX_CAP
    jge     .tr_just_load
    lea     r8, [rip + tx_rkeys]
    mov     [r8 + rcx*8], rdi
    lea     r8, [rip + versions]
    mov     r9, [r8 + rdi*8]
    lea     r8, [rip + tx_rsnaps]
    mov     [r8 + rcx*8], r9
    inc     rcx
    mov     [rip + tx_rcount], rcx
.tr_just_load:
    lea     r8, [rip + accounts]
    mov     rax, [r8 + rdi*8]
    ret

# tx_write(rdi=k, rsi=v) -> rax (always 1 here; assumes cap not exceeded)
tx_write:
    push    rsi
    push    rdi
    call    tx_find_write
    pop     rdi
    pop     rsi
    cmp     rax, 0
    jl      .tw_new
    lea     r8, [rip + tx_wvals]
    mov     [r8 + rax*8], rsi
    mov     rax, 1
    ret
.tw_new:
    mov     rcx, [rip + tx_wcount]
    lea     r8, [rip + tx_wkeys]
    mov     [r8 + rcx*8], rdi
    lea     r8, [rip + tx_wvals]
    mov     [r8 + rcx*8], rsi
    inc     rcx
    mov     [rip + tx_wcount], rcx
    mov     rax, 1
    ret

# tx_validate -> rax = 1/0
tx_validate:
    mov     rcx, [rip + tx_rcount]
    xor     r10, r10
.tv_loop:
    cmp     r10, rcx
    jge     .tv_pass
    lea     r8, [rip + tx_rkeys]
    mov     rdi, [r8 + r10*8]
    lea     r8, [rip + tx_rsnaps]
    mov     r9, [r8 + r10*8]
    lea     r8, [rip + versions]
    mov     r11, [r8 + rdi*8]
    cmp     r9, r11
    jne     .tv_fail
    inc     r10
    jmp     .tv_loop
.tv_pass:
    mov     rax, 1
    ret
.tv_fail:
    xor     rax, rax
    ret

# tx_commit -> rax = 1/0
tx_commit:
    call    tx_validate
    test    rax, rax
    jz      .tc_abort
    mov     rcx, [rip + tx_wcount]
    xor     r10, r10
.tc_install:
    cmp     r10, rcx
    jge     .tc_done
    lea     r8, [rip + tx_wkeys]
    mov     rdi, [r8 + r10*8]
    lea     r8, [rip + tx_wvals]
    mov     rsi, [r8 + r10*8]
    lea     r8, [rip + accounts]
    mov     [r8 + rdi*8], rsi
    lea     r8, [rip + versions]
    mov     r9, [r8 + rdi*8]
    inc     r9
    mov     [r8 + rdi*8], r9
    inc     r10
    jmp     .tc_install
.tc_done:
    mov     qword ptr [rip + tx_status], TX_COMMITTED
    mov     rax, 1
    ret
.tc_abort:
    mov     qword ptr [rip + tx_status], TX_ABORTED
    xor     rax, rax
    ret

# tx_abort
tx_abort:
    mov     qword ptr [rip + tx_status], TX_ABORTED
    ret

# crash_recovery: clear tx scratch
crash_recovery:
    mov     qword ptr [rip + tx_status], TX_FREE
    mov     qword ptr [rip + tx_wcount], 0
    mov     qword ptr [rip + tx_rcount], 0
    ret

# seed: store_init + accounts[0]=1000, [1]=500, [2]=200
seed:
    call    store_init
    mov     rdi, 0
    mov     rsi, 1000
    call    account_set_raw
    mov     rdi, 1
    mov     rsi, 500
    call    account_set_raw
    mov     rdi, 2
    mov     rsi, 200
    call    account_set_raw
    ret

# assert_eq(rdi=actual, rsi=expected): tail-calls fail on mismatch
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
    # Test 1: abort discards
    call    seed
    call    tx_begin
    mov     rdi, 0
    mov     rsi, 9999
    call    tx_write
    mov     rdi, 1
    mov     rsi, 8888
    call    tx_write
    mov     rdi, 2
    mov     rsi, 7777
    call    tx_write
    call    tx_abort
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 1000
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 8]
    mov     rsi, 500
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 16]
    mov     rsi, 200
    call    assert_eq

    # Test 2: commit installs all
    call    seed
    call    tx_begin
    mov     rdi, 0
    mov     rsi, 100
    call    tx_write
    mov     rdi, 1
    mov     rsi, 200
    call    tx_write
    mov     rdi, 2
    mov     rsi, 300
    call    tx_write
    call    tx_commit
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 100
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 8]
    mov     rsi, 200
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 16]
    mov     rsi, 300
    call    assert_eq

    # Test 3: transfer preserves total
    call    seed
    call    account_total
    mov     r12, rax              # initial total
    call    tx_begin
    mov     rdi, 0
    call    tx_read
    mov     r13, rax
    mov     rdi, 1
    call    tx_read
    mov     r14, rax
    mov     rdi, 0
    mov     rsi, r13
    sub     rsi, 100
    call    tx_write
    mov     rdi, 1
    mov     rsi, r14
    add     rsi, 100
    call    tx_write
    call    tx_commit
    call    account_total
    mov     rdi, rax
    mov     rsi, r12
    call    assert_eq

    # Test 4: durability across crash
    call    seed
    call    tx_begin
    mov     rdi, 0
    mov     rsi, 12345
    call    tx_write
    call    tx_commit
    call    crash_recovery
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 12345
    call    assert_eq

    # Test 5: OCC validation — raw-bump after read aborts commit
    call    seed
    call    tx_begin
    mov     rdi, 0
    call    tx_read               # snapshots versions[0]
    # External "concurrent" change bumps version[0]
    mov     rdi, 0
    mov     rsi, 5555
    call    account_set_raw       # versions[0] += 1
    mov     rdi, 0
    mov     rsi, 9999
    call    tx_write
    call    tx_commit
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq             # commit must return 0 (conflict)
    mov     rdi, [rip + tx_status]
    mov     rsi, TX_ABORTED
    call    assert_eq
    lea     r8, [rip + accounts]
    mov     rdi, [r8 + 0]
    mov     rsi, 5555             # raw value preserved; tx_write discarded
    call    assert_eq

    # All asserts passed → write success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
