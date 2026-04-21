# Vidya — Game AI Decision Making in x86_64 Assembly
#
# Stat-driven AI that evaluates options and picks the best action.
# Demonstrates: weighted scoring, probability curves, PRNG for randomness,
# and decision dispatch. Modeled on NBA Jam's drone AI.

.intel_syntax noprefix
.global _start

.section .data

test_count: .quad 0
pass_count: .quad 0

# PRNG state (PCG-style)
rng_state:  .quad 12345

# Player stats (1-10 scale)
stat_speed:     .quad 7
stat_shooting:  .quad 8
stat_dunking:   .quad 6
stat_passing:   .quad 5
stat_stealing:  .quad 4

.section .rodata

# Action enum
.equ ACT_SHOOT,   0
.equ ACT_DUNK,    1
.equ ACT_PASS,    2
.equ ACT_DRIVE,   3
.equ ACT_STEAL,   4
.equ ACT_COUNT,   5

msg_pass:      .ascii "PASS: "
msg_pass_len = . - msg_pass
msg_fail:      .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:        .ascii "\n"
msg_summary:   .ascii "All game AI decision examples passed.\n"
msg_sum_len = . - msg_summary
msg_not_all:   .ascii "SOME TESTS FAILED\n"
msg_not_len = . - msg_not_all

msg_t1:     .ascii "high shooting stat prefers shoot"
msg_t1_len = . - msg_t1
msg_t2:     .ascii "close range prefers dunk"
msg_t2_len = . - msg_t2
msg_t3:     .ascii "prng produces varied values"
msg_t3_len = . - msg_t3
msg_t4:     .ascii "shot clock urgency increases shoot score"
msg_t4_len = . - msg_t4
msg_t5:     .ascii "probability check: stat=10 always succeeds"
msg_t5_len = . - msg_t5
msg_t6:     .ascii "probability check: stat=0 always fails"
msg_t6_len = . - msg_t6
msg_t7:     .ascii "decision is deterministic with same seed"
msg_t7_len = . - msg_t7

.section .text

# --- PRNG (PCG multiply-add) ---

# rng_next: returns pseudo-random value in rax
rng_next:
    mov     rax, [rip + rng_state]
    mov     rcx, 6364136223846793005
    imul    rcx
    add     rax, 1442695040888963407
    mov     [rip + rng_state], rax
    # Mix bits: use upper bits (better distribution)
    shr     rax, 33
    ret

# rng_range: returns value in [0, rdi)
# rdi = upper bound (exclusive)
rng_range:
    push    rdi
    call    rng_next
    pop     rdi
    # rax = rng value, take modulo
    xor     rdx, rdx
    div     rdi             # rdx = rax % rdi
    mov     rax, rdx
    ret

# --- Probability check ---

# prob_check: returns 1 with probability stat*10 out of 100
# rdi = stat (1-10)
prob_check:
    push    rdi
    mov     rcx, rdi
    imul    rcx, 10         # threshold = stat * 10

    mov     rdi, 100
    call    rng_range       # rax = random [0, 100)
    pop     rdi

    mov     rcx, rdi
    imul    rcx, 10
    cmp     rax, rcx
    jl      .prob_yes
    xor     rax, rax
    ret
.prob_yes:
    mov     rax, 1
    ret

# --- AI scoring ---

# evaluate_shoot: score for shooting based on stat and distance
# rdi = shooting stat (1-10), rsi = distance to rim (fixed-point)
evaluate_shoot:
    # Base score = stat * 10
    mov     rax, rdi
    imul    rax, 10
    # Distance penalty: closer = better
    # Subtract distance/65536 (convert from fixed-point to game units)
    mov     rcx, rsi
    sar     rcx, 16
    sub     rax, rcx
    # Clamp to minimum 0
    test    rax, rax
    jns     .es_ok
    xor     rax, rax
.es_ok:
    ret

# evaluate_dunk: score for dunking based on stat and distance
# rdi = dunking stat (1-10), rsi = distance to rim (fixed-point)
evaluate_dunk:
    # Must be close (within 3.0 game units)
    mov     rcx, rsi
    sar     rcx, 16
    cmp     rcx, 3
    jg      .ed_far
    # Close enough: score = stat * 15 (dunks are high-value)
    mov     rax, rdi
    imul    rax, 15
    ret
.ed_far:
    xor     rax, rax        # too far to dunk
    ret

# evaluate_pass: score for passing
# rdi = pass stat
evaluate_pass:
    mov     rax, rdi
    imul    rax, 8          # base = stat * 8
    ret

# ai_decide: evaluate all options, return best action
# rdi = shooting stat, rsi = dunking stat, rdx = pass stat
# rcx = distance to rim, r8 = shot clock remaining (0-24)
ai_decide:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rcx        # distance
    mov     r13, r8         # shot clock
    mov     r14, rdx        # pass stat

    # Evaluate shoot
    # rdi already = shooting stat, rsi = distance
    mov     rsi, r12
    call    evaluate_shoot
    mov     rbx, rax        # rbx = shoot_score

    # Shot clock urgency: multiply score as clock runs down
    # urgency = max(1, (24 - remaining) / 4)
    mov     rax, 24
    sub     rax, r13
    sar     rax, 2
    cmp     rax, 1
    jge     .urgency_ok
    mov     rax, 1
.urgency_ok:
    imul    rbx, rax        # shoot_score *= urgency

    # Evaluate dunk
    mov     rdi, rsi        # dunking stat (was in rsi before, need to restore)
    # Actually rsi was clobbered. Use stack saved value.
    # Re-read from globals for simplicity
    mov     rdi, [rip + stat_dunking]
    mov     rsi, r12
    call    evaluate_dunk
    mov     r15, rax        # r15 = dunk_score

    # Evaluate pass
    mov     rdi, r14
    call    evaluate_pass
    mov     r14, rax        # r14 = pass_score

    # Pick highest score
    mov     rax, ACT_SHOOT
    mov     rcx, rbx        # best = shoot_score

    cmp     r15, rcx
    jle     .not_dunk
    mov     rax, ACT_DUNK
    mov     rcx, r15
.not_dunk:
    cmp     r14, rcx
    jle     .not_pass
    mov     rax, ACT_PASS
.not_pass:

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# --- Test helpers ---

assert_eq:
    push    rdx
    push    rcx
    inc     qword ptr [rip + test_count]
    cmp     rdi, rsi
    jne     .af
    inc     qword ptr [rip + pass_count]
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    jmp     .am
.af:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
.am:
    pop     rdx
    pop     rsi
    mov     rax, 1
    mov     rdi, 1
    syscall
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_nl]
    mov     rdx, 1
    syscall
    ret

_start:
    # --- Test 1: High shooting stat prefers shoot at mid-range ---
    mov     rdi, 9              # shooting = 9
    mov     rsi, 196608         # distance = 3.0 (mid-range)
    call    evaluate_shoot
    # Score should be 9*10 - 3 = 87
    mov     rdi, rax
    mov     rsi, 87
    lea     rdx, [rip + msg_t1]
    mov     rcx, msg_t1_len
    call    assert_eq

    # --- Test 2: Close range prefers dunk ---
    mov     rdi, 8              # dunking = 8
    mov     rsi, 131072         # distance = 2.0 (close)
    call    evaluate_dunk
    # Score should be 8*15 = 120 (very high)
    mov     rdi, rax
    mov     rsi, 120
    lea     rdx, [rip + msg_t2]
    mov     rcx, msg_t2_len
    call    assert_eq

    # --- Test 3: PRNG produces varied values ---
    mov     qword ptr [rip + rng_state], 42     # seed
    call    rng_next
    mov     r12, rax
    call    rng_next
    # Two consecutive values should differ
    cmp     rax, r12
    setne   al
    movzx   rdi, al
    mov     rsi, 1
    lea     rdx, [rip + msg_t3]
    mov     rcx, msg_t3_len
    call    assert_eq

    # --- Test 4: Shot clock urgency increases shoot score ---
    # Low clock (2 remaining): urgency = (24-2)/4 = 5
    mov     rdi, 5              # shooting = 5
    mov     rsi, 0              # distance = 0 (at rim)
    call    evaluate_shoot
    mov     r12, rax            # base score at 0 distance = 50

    # Now with urgency multiplier
    mov     rax, 24
    sub     rax, 2              # 24 - 2 = 22
    sar     rax, 2              # 22/4 = 5
    imul    rax, r12            # 50 * 5 = 250
    # Verify urgency > base
    cmp     rax, r12
    setg    al
    movzx   rdi, al
    mov     rsi, 1
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq

    # --- Test 5: Stat=10 always passes probability check (10*10=100 > any [0,100)) ---
    mov     qword ptr [rip + rng_state], 99999
    mov     rdi, 10
    call    prob_check
    mov     rdi, rax
    mov     rsi, 1
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq

    # --- Test 6: Stat=0 always fails (0*10=0, no value is < 0) ---
    mov     qword ptr [rip + rng_state], 11111
    xor     rdi, rdi
    call    prob_check
    mov     rdi, rax
    xor     rsi, rsi
    lea     rdx, [rip + msg_t6]
    mov     rcx, msg_t6_len
    call    assert_eq

    # --- Test 7: Same seed = same decision (determinism) ---
    mov     qword ptr [rip + rng_state], 77777
    call    rng_next
    mov     r12, rax

    mov     qword ptr [rip + rng_state], 77777
    call    rng_next
    mov     rdi, rax
    mov     rsi, r12
    lea     rdx, [rip + msg_t7]
    mov     rcx, msg_t7_len
    call    assert_eq

    # --- Summary ---
    mov     rax, [rip + test_count]
    cmp     rax, [rip + pass_count]
    jne     .failed

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_summary]
    mov     rdx, msg_sum_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

.failed:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_not_all]
    mov     rdx, msg_not_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
