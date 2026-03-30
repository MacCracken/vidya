# Vidya — Concurrency in x86_64 Assembly
#
# At the assembly level, concurrency primitives are atomic instructions:
# lock prefix, xchg, cmpxchg, and memory fences. These are the building
# blocks that higher-level mutexes and atomics compile down to.
# This file demonstrates single-threaded atomic operation patterns.
# (Full threading requires clone syscall + shared memory, beyond scope.)

.intel_syntax noprefix
.global _start

.section .data
.align 8
counter:    .quad 0
lock_var:   .quad 0             # 0 = unlocked, 1 = locked
flag:       .quad 0

.section .rodata
msg_pass:   .ascii "All concurrency examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Atomic load and store ───────────────────────────────────────
    # On x86_64, aligned 8-byte loads/stores are naturally atomic
    mov     qword ptr [counter], 42
    mov     rax, [counter]
    cmp     rax, 42
    jne     fail

    # ── LOCK prefix: atomic read-modify-write ───────────────────────
    # lock ensures the operation is atomic across all cores
    mov     qword ptr [counter], 0

    # Atomic increment
    lock inc qword ptr [counter]
    cmp     qword ptr [counter], 1
    jne     fail

    # Atomic add
    lock add qword ptr [counter], 9
    cmp     qword ptr [counter], 10
    jne     fail

    # Atomic decrement
    lock dec qword ptr [counter]
    cmp     qword ptr [counter], 9
    jne     fail

    # ── XCHG: atomic swap (always has implicit lock) ────────────────
    # xchg is always atomic — no lock prefix needed
    mov     qword ptr [counter], 100
    mov     rax, 200
    xchg    [counter], rax      # counter=200, rax=100
    cmp     rax, 100
    jne     fail
    cmp     qword ptr [counter], 200
    jne     fail

    # ── CMPXCHG: compare-and-swap (CAS) ────────────────────────────
    # The foundation of lock-free programming
    # if (*ptr == rax) { *ptr = rcx; ZF=1; } else { rax = *ptr; ZF=0; }
    mov     qword ptr [counter], 42
    mov     rax, 42             # expected value
    mov     rcx, 99             # new value
    lock cmpxchg [counter], rcx
    jnz     fail                # should succeed (ZF=1)
    cmp     qword ptr [counter], 99
    jne     fail

    # Failed CAS: expected != actual
    mov     rax, 0              # wrong expected value
    mov     rcx, 200
    lock cmpxchg [counter], rcx
    jz      fail                # should fail (ZF=0)
    cmp     rax, 99             # rax updated with actual value
    jne     fail
    cmp     qword ptr [counter], 99  # counter unchanged
    jne     fail

    # ── Spinlock implementation ─────────────────────────────────────
    # Acquire: try to swap 0→1 atomically
    mov     qword ptr [lock_var], 0     # ensure unlocked

    # Acquire lock
    call    spinlock_acquire
    cmp     qword ptr [lock_var], 1     # should be locked
    jne     fail

    # Release lock
    call    spinlock_release
    cmp     qword ptr [lock_var], 0     # should be unlocked
    jne     fail

    # ── Memory fences ───────────────────────────────────────────────
    # On x86_64, most ordering is already guaranteed (TSO model).
    # But fences are still needed for some patterns.

    # MFENCE: full barrier (all loads and stores complete)
    mov     qword ptr [counter], 1
    mfence
    mov     rax, [flag]         # guaranteed to see counter=1

    # SFENCE: store fence (all prior stores complete)
    mov     qword ptr [counter], 2
    sfence

    # LFENCE: load fence (all prior loads complete)
    lfence
    mov     rax, [counter]
    cmp     rax, 2
    jne     fail

    # ── PAUSE: hint for spin-wait loops ─────────────────────────────
    # Reduces power consumption and improves performance in spin loops
    # on hyperthreaded cores. Always use in spinlock retry loops.
    pause

    # ── BTS/BTR: atomic bit test and set/reset ──────────────────────
    mov     qword ptr [flag], 0
    lock bts qword ptr [flag], 0    # set bit 0, CF = old value
    jc      fail                     # old bit was 0, CF should be clear
    cmp     qword ptr [flag], 1
    jne     fail

    lock btr qword ptr [flag], 0    # reset bit 0, CF = old value
    jnc     fail                     # old bit was 1, CF should be set
    cmp     qword ptr [flag], 0
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── spinlock_acquire ────────────────────────────────────────────────
# Spin until lock_var transitions from 0 to 1
spinlock_acquire:
.spin_try:
    mov     eax, 1
    xchg    [lock_var], rax     # atomically swap 1 into lock_var
    test    rax, rax            # was it 0 (unlocked)?
    jz      .spin_acquired      # yes — we got the lock
    pause                       # hint: we're spinning
    jmp     .spin_try
.spin_acquired:
    ret

# ── spinlock_release ────────────────────────────────────────────────
# Release by storing 0 (x86 store is release-ordered)
spinlock_release:
    mov     qword ptr [lock_var], 0
    ret
