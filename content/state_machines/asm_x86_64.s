# Vidya — State Machines in x86_64 Assembly
#
# Finite state machines using jump tables and enum dispatch.
# Demonstrates: player state transitions, committed states with timers,
# game state hierarchy, and transition validation.

.intel_syntax noprefix
.global _start

.section .data

test_count: .quad 0
pass_count: .quad 0

# Player state machine
player_state:       .quad 0     # current state (enum)
player_prev_state:  .quad 0     # previous state (for transition detection)
player_timer:       .quad 0     # frames remaining in committed state

# Game state machine
game_state:         .quad 0

.section .rodata

# --- State enum values ---
.equ PS_IDLE,    0
.equ PS_RUN,     1
.equ PS_SHOOT,   2
.equ PS_DUNK,    3
.equ PS_PASS,    4
.equ PS_STEAL,   5
.equ PS_BLOCK,   6
.equ PS_FALL,    7
.equ PS_REBOUND, 8
.equ PS_COUNT,   9

.equ GS_MENU,      0
.equ GS_SELECT,    1
.equ GS_TIPOFF,    2
.equ GS_PLAYING,   3
.equ GS_HALFTIME,  4
.equ GS_OVERTIME,  5
.equ GS_GAMEOVER,  6
.equ GS_ATTRACT,   7

# Committed state durations (frames at 60fps)
.equ SHOOT_FRAMES, 30      # 0.5s shooting animation
.equ DUNK_FRAMES,  45      # 0.75s dunk animation
.equ FALL_FRAMES,  20      # 0.33s fall recovery

# Inputs
.equ INPUT_NONE,   0
.equ INPUT_MOVE,   1
.equ INPUT_SHOOT,  2
.equ INPUT_PASS,   3
.equ INPUT_STEAL,  4

msg_pass:      .ascii "PASS: "
msg_pass_len = . - msg_pass
msg_fail:      .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:        .ascii "\n"
msg_summary:   .ascii "All state machine examples passed.\n"
msg_sum_len = . - msg_summary
msg_not_all:   .ascii "SOME TESTS FAILED\n"
msg_not_len = . - msg_not_all

msg_t1:     .ascii "idle -> run on move input"
msg_t1_len = . - msg_t1
msg_t2:     .ascii "shoot is committed (rejects input)"
msg_t2_len = . - msg_t2
msg_t3:     .ascii "shoot timer expires -> idle"
msg_t3_len = . - msg_t3
msg_t4:     .ascii "dunk is committed for 45 frames"
msg_t4_len = . - msg_t4
msg_t5:     .ascii "transition detection (prev != current)"
msg_t5_len = . - msg_t5
msg_t6:     .ascii "game state: menu -> select -> playing"
msg_t6_len = . - msg_t6

.section .text

# --- State machine functions ---

# is_committed: returns 1 if current state is committed (cannot be interrupted)
is_committed:
    mov     rax, [rip + player_state]
    cmp     rax, PS_SHOOT
    je      .committed
    cmp     rax, PS_DUNK
    je      .committed
    cmp     rax, PS_FALL
    je      .committed
    xor     rax, rax
    ret
.committed:
    mov     rax, 1
    ret

# player_transition: attempt state change
# rdi = input
# Returns new state. Rejects input during committed states with active timer.
player_transition:
    # Check if currently in a committed state with time remaining
    call    is_committed
    test    rax, rax
    jz      .can_transition

    # In committed state — check if timer expired
    mov     rax, [rip + player_timer]
    test    rax, rax
    jg      .reject_input    # timer still active, reject

.can_transition:
    # Save previous state for transition detection
    mov     rax, [rip + player_state]
    mov     [rip + player_prev_state], rax

    # Dispatch on input
    cmp     rdi, INPUT_MOVE
    je      .to_run
    cmp     rdi, INPUT_SHOOT
    je      .to_shoot
    cmp     rdi, INPUT_PASS
    je      .to_pass
    cmp     rdi, INPUT_STEAL
    je      .to_steal

    # No valid input → return to idle if not committed
    mov     qword ptr [rip + player_state], PS_IDLE
    mov     rax, PS_IDLE
    ret

.to_run:
    mov     qword ptr [rip + player_state], PS_RUN
    mov     rax, PS_RUN
    ret

.to_shoot:
    mov     qword ptr [rip + player_state], PS_SHOOT
    mov     qword ptr [rip + player_timer], SHOOT_FRAMES
    mov     rax, PS_SHOOT
    ret

.to_pass:
    mov     qword ptr [rip + player_state], PS_PASS
    mov     rax, PS_PASS
    ret

.to_steal:
    mov     qword ptr [rip + player_state], PS_STEAL
    mov     rax, PS_STEAL
    ret

.reject_input:
    # Return current state unchanged
    mov     rax, [rip + player_state]
    ret

# player_tick: advance timer, auto-transition when committed state expires
player_tick:
    mov     rax, [rip + player_timer]
    test    rax, rax
    jle     .no_timer
    dec     rax
    mov     [rip + player_timer], rax
    test    rax, rax
    jnz     .no_timer

    # Timer expired — save prev state, transition to idle
    mov     rax, [rip + player_state]
    mov     [rip + player_prev_state], rax
    mov     qword ptr [rip + player_state], PS_IDLE
    mov     qword ptr [rip + player_timer], 0

.no_timer:
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

# reset player to idle
reset_player:
    mov     qword ptr [rip + player_state], PS_IDLE
    mov     qword ptr [rip + player_prev_state], PS_IDLE
    mov     qword ptr [rip + player_timer], 0
    ret

_start:
    # --- Test 1: IDLE -> RUN on move input ---
    call    reset_player
    mov     rdi, INPUT_MOVE
    call    player_transition
    mov     rdi, [rip + player_state]
    mov     rsi, PS_RUN
    lea     rdx, [rip + msg_t1]
    mov     rcx, msg_t1_len
    call    assert_eq

    # --- Test 2: SHOOT is committed (rejects further input) ---
    call    reset_player
    mov     rdi, INPUT_SHOOT
    call    player_transition

    # Now try to move — should be rejected (timer is active)
    mov     rdi, INPUT_MOVE
    call    player_transition
    mov     rdi, [rip + player_state]
    mov     rsi, PS_SHOOT       # should still be SHOOT
    lea     rdx, [rip + msg_t2]
    mov     rcx, msg_t2_len
    call    assert_eq

    # --- Test 3: SHOOT timer expires -> IDLE ---
    call    reset_player
    mov     rdi, INPUT_SHOOT
    call    player_transition

    # Tick through all frames
    mov     r12, SHOOT_FRAMES
.tick_shoot:
    call    player_tick
    dec     r12
    jnz     .tick_shoot

    # Should have auto-transitioned to IDLE
    mov     rdi, [rip + player_state]
    mov     rsi, PS_IDLE
    lea     rdx, [rip + msg_t3]
    mov     rcx, msg_t3_len
    call    assert_eq

    # --- Test 4: DUNK is committed for 45 frames ---
    call    reset_player
    # Manually set to dunk state
    mov     qword ptr [rip + player_state], PS_DUNK
    mov     qword ptr [rip + player_timer], DUNK_FRAMES

    # Try input during dunk — should be rejected
    mov     rdi, INPUT_MOVE
    call    player_transition
    mov     rdi, [rip + player_state]
    mov     rsi, PS_DUNK
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq

    # --- Test 5: Transition detection ---
    call    reset_player
    mov     rdi, INPUT_SHOOT
    call    player_transition
    # prev_state should be IDLE, current should be SHOOT
    mov     rdi, [rip + player_prev_state]
    mov     rsi, PS_IDLE
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq

    # --- Test 6: Game state progression ---
    mov     qword ptr [rip + game_state], GS_MENU
    # menu -> select
    mov     qword ptr [rip + game_state], GS_SELECT
    # select -> playing
    mov     qword ptr [rip + game_state], GS_PLAYING
    mov     rdi, [rip + game_state]
    mov     rsi, GS_PLAYING
    lea     rdx, [rip + msg_t6]
    mov     rcx, msg_t6_len
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
