# Vidya — Game Loop Architecture in x86_64 Assembly
#
# Fixed-timestep accumulator loop with spiral-of-death cap. The driver
# `loop_step` takes an elapsed-microsecond delta in rdi, mutates the
# global accumulator+counter state, and returns the number of fixed-
# step updates fired this frame in rax. A real engine would source
# deltas from RDTSC (or clock_gettime via syscall); tests use
# deterministic deltas so the exit code is reproducible everywhere.

.intel_syntax noprefix
.global _start

.section .data

# GameLoop state: three i64 fields at fixed addresses
g_accum:        .quad 0
g_update_count: .quad 0
g_render_count: .quad 0

.section .rodata

.equ DT_US,     16667
.equ MAX_ACCUM, 83335   # 5 * DT_US

msg_pass:    .ascii "All game_loop_architecture examples passed.\n"
msg_pass_len = . - msg_pass

msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# ── loop_reset: zero all three GameLoop fields ────────────────────────
loop_reset:
    mov     qword ptr [rip + g_accum], 0
    mov     qword ptr [rip + g_update_count], 0
    mov     qword ptr [rip + g_render_count], 0
    ret

# ── loop_step: rdi = elapsed_us, returns rax = updates this frame ─────
loop_step:
    # accum = g_accum + elapsed_us
    mov     rax, [rip + g_accum]
    add     rax, rdi

    # spiral-of-death cap
    mov     rcx, MAX_ACCUM
    cmp     rax, rcx
    jle     .Lcap_ok
    mov     rax, rcx
.Lcap_ok:

    # drain the accumulator in DT_US chunks
    xor     r8, r8                # updates = 0
    mov     rcx, DT_US
.Ldrain:
    cmp     rax, rcx
    jl      .Ldrain_done
    sub     rax, rcx
    inc     r8
    jmp     .Ldrain
.Ldrain_done:

    # store accum, bump counters
    mov     [rip + g_accum], rax
    mov     rdx, [rip + g_update_count]
    add     rdx, r8
    mov     [rip + g_update_count], rdx
    mov     rdx, [rip + g_render_count]
    inc     rdx
    mov     [rip + g_render_count], rdx

    mov     rax, r8
    ret

# ── _start: run all tests ─────────────────────────────────────────────
_start:
    # Test 1: exact dt fires exactly one update; update_count = 1
    call    loop_reset
    mov     rdi, DT_US
    call    loop_step
    cmp     rax, 1
    jne     fail
    mov     rax, [rip + g_update_count]
    cmp     rax, 1
    jne     fail

    # Test 2: under dt fires zero updates
    call    loop_reset
    mov     rdi, DT_US / 2
    call    loop_step
    cmp     rax, 0
    jne     fail

    # Test 3: 50ms catchup fires exactly 2 updates
    call    loop_reset
    mov     rdi, 50000
    call    loop_step
    cmp     rax, 2
    jne     fail

    # Test 4: spiral-of-death cap — 1s hang fires exactly 5 updates
    call    loop_reset
    mov     rdi, 1000000
    call    loop_step
    cmp     rax, 5
    jne     fail

    # Test 5: 3 frames at exact dt → 3 renders, 3 updates
    call    loop_reset
    mov     rdi, DT_US
    call    loop_step
    mov     rdi, DT_US
    call    loop_step
    mov     rdi, DT_US
    call    loop_step
    mov     rax, [rip + g_render_count]
    cmp     rax, 3
    jne     fail
    mov     rax, [rip + g_update_count]
    cmp     rax, 3
    jne     fail

    # Test 6: 1.5*dt → 1 update with positive remainder less than dt
    call    loop_reset
    mov     rdi, DT_US + (DT_US / 2)
    call    loop_step
    mov     rax, [rip + g_accum]
    cmp     rax, DT_US / 4
    jle     fail
    cmp     rax, DT_US
    jge     fail

    # Test 7: 30000 + 5000 + 30000 → 3 updates, 3 renders
    call    loop_reset
    mov     rdi, 30000
    call    loop_step
    mov     rdi, 5000
    call    loop_step
    mov     rdi, 30000
    call    loop_step
    mov     rax, [rip + g_update_count]
    cmp     rax, 3
    jne     fail
    mov     rax, [rip + g_render_count]
    cmp     rax, 3
    jne     fail

    # All passed — print and exit 0
    mov     rax, 1                  # SYS_write
    mov     rdi, 1                  # stdout
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60                 # SYS_exit
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 1
    mov     rdi, 2                  # stderr
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
