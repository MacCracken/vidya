// Vidya — Concurrency in AArch64 Assembly
//
// AArch64 uses a weakly-ordered memory model — more barriers needed
// than x86_64. Atomic operations use LDXR/STXR (load/store exclusive)
// pairs, or the LSE (Large System Extensions) atomics: LDADD, SWPAL,
// CAS. DMB/DSB/ISB are the memory barrier instructions.

// TRAP: the LSE atomics below are armv8.1-a, not baseline armv8-a. GNU as
// defaults to the baseline, so LDADD/SWPAL/CAS fail to assemble with
// "selected processor does not support ..." unless you raise the target
// first. `.arch armv8.1-a` is a superset of armv8-a, so the LDXR/STXR and
// barrier code below is unaffected.
.arch armv8.1-a

.global _start

.section .data
.align 8
counter:    .quad 0
lock_var:   .quad 0
flag:       .quad 0

.section .rodata
msg_pass:   .ascii "All concurrency examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Atomic load/store ──────────────────────────────────────────
    // LDAR: load-acquire (all prior loads/stores visible)
    // STLR: store-release (visible to subsequent loads)
    adr     x9, counter

    mov     x0, #42
    stlr    x0, [x9]           // store-release
    ldar    x0, [x9]           // load-acquire
    cmp     x0, #42
    b.ne    fail

    // ── LDXR/STXR: exclusive load/store (CAS building block) ──────
    // Atomic increment: load-exclusive, modify, store-exclusive
    mov     x0, #0
    str     x0, [x9]           // counter = 0

    // Atomic add 10 via LDXR/STXR loop
    mov     x2, #10
.Latomic_add:
    ldxr    x0, [x9]           // load exclusive
    add     x0, x0, x2
    stxr    w1, x0, [x9]       // store exclusive, w1=0 on success
    cbnz    w1, .Latomic_add   // retry if store failed

    ldr     x0, [x9]
    cmp     x0, #10
    b.ne    fail

    // ── LDXR/STXR: compare-and-swap pattern ────────────────────────
    // CAS(ptr, expected, new): if *ptr == expected then *ptr = new
    adr     x9, counter
    mov     x0, #10             // current value
    str     x0, [x9]

    mov     x1, #10             // expected
    mov     x2, #99             // new value
.Lcas_loop:
    ldxr    x0, [x9]
    cmp     x0, x1
    b.ne    .Lcas_fail_expected
    stxr    w3, x2, [x9]
    cbnz    w3, .Lcas_loop      // retry on contention
    b       .Lcas_success

.Lcas_fail_expected:
    clrex                       // clear exclusive monitor
    b       fail

.Lcas_success:
    ldr     x0, [x9]
    cmp     x0, #99
    b.ne    fail

    // ── LDXR/STXR: atomic swap ────────────────────────────────────
    adr     x9, counter
    mov     x0, #100
    str     x0, [x9]

    mov     x2, #200            // new value
.Lswap_loop:
    ldxr    x0, [x9]           // old value in x0
    stxr    w1, x2, [x9]
    cbnz    w1, .Lswap_loop

    cmp     x0, #100            // old value should be 100
    b.ne    fail
    ldr     x0, [x9]
    cmp     x0, #200            // new value should be 200
    b.ne    fail

    // ── LSE atomics (armv8.1-a): LDADD / SWPAL / CAS ───────────────
    // Single instructions that replace whole LDXR/STXR retry loops.
    // They cannot fail spuriously, so there is no `cbnz` retry branch,
    // and on contended many-core systems they are far cheaper because
    // the operation is done at the point of coherency instead of
    // ping-ponging the cache line through an exclusive monitor.
    // Operand order is: LDADD <Xs>, <Xt>, [<Xn>]  —  Xs is the operand,
    // Xt receives the PRE-operation value, [Xn] is the target.
    adr     x9, counter
    mov     x0, #7
    str     x0, [x9]

    // LDADD: atomic fetch-add. *x9 += 3, x1 = old value.
    mov     x0, #3
    ldadd   x0, x1, [x9]
    cmp     x1, #7              // returns the value from BEFORE the add
    b.ne    fail
    ldr     x2, [x9]
    cmp     x2, #10
    b.ne    fail

    // SWPAL: atomic swap with acquire-release ordering.
    // The A/L suffixes are the ordering, not part of the operation:
    // SWP (relaxed), SWPA (acquire), SWPL (release), SWPAL (both).
    mov     x0, #99
    swpal   x0, x3, [x9]
    cmp     x3, #10             // x3 = old value
    b.ne    fail

    // CAS: compare-and-swap in one instruction. If *x9 == x4 then
    // *x9 = x5. Either way x4 is overwritten with the old *x9, so the
    // success test is "did x4 come back as what I expected".
    mov     x4, #99             // expected
    mov     x5, #123            // new
    cas     x4, x5, [x9]
    cmp     x4, #99
    b.ne    fail
    ldr     x2, [x9]
    cmp     x2, #123
    b.ne    fail

    // CAS that must NOT swap: expected value is wrong.
    mov     x4, #55             // expected (wrong — memory holds 123)
    mov     x5, #77             // new
    cas     x4, x5, [x9]
    cmp     x4, #123            // x4 = actual old value, proving the miss
    b.ne    fail
    ldr     x2, [x9]
    cmp     x2, #123            // memory unchanged
    b.ne    fail

    // ── Spinlock via LDXR/STXR ─────────────────────────────────────
    adr     x9, lock_var
    str     xzr, [x9]          // ensure unlocked

    // Acquire
    bl      spinlock_acquire
    ldr     x0, [x9]
    cmp     x0, #1
    b.ne    fail

    // Release
    bl      spinlock_release
    ldr     x0, [x9]
    cbnz    x0, fail

    // ── Memory barriers ────────────────────────────────────────────
    // DMB: data memory barrier (ordering, not completion)
    // DSB: data synchronization barrier (completion)
    // ISB: instruction synchronization barrier

    adr     x9, flag
    mov     x0, #1
    str     x0, [x9]
    dmb     ish                 // inner-shareable domain barrier
    ldr     x0, [x9]
    cmp     x0, #1
    b.ne    fail

    // DSB: stronger — ensures all memory accesses complete
    dsb     ish

    // ── WFE/SEV: wait-for-event / send-event ──────────────────────
    // WFE puts the core in low-power state until an event
    // SEV signals all cores to wake from WFE
    // Used in spinlock contention to save power
    sev                         // send event (harmless if no one waiting)

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// spinlock_acquire: spin until lock_var transitions 0->1
spinlock_acquire:
    adr     x9, lock_var
.Lspin_try:
    ldxr    x0, [x9]
    cbnz    x0, .Lspin_wait    // already locked
    mov     x1, #1
    stxr    w2, x1, [x9]
    cbnz    w2, .Lspin_try     // store failed, retry
    dmb     ish                 // acquire barrier
    ret
.Lspin_wait:
    wfe                         // low-power wait
    b       .Lspin_try

// spinlock_release: store 0 with release semantics
spinlock_release:
    adr     x9, lock_var
    stlr    xzr, [x9]          // store-release zero
    sev                         // wake waiters
    ret
