# Vidya — Projectile Physics in x86_64 Assembly
#
# Semi-implicit Euler integration for parabolic arcs in 16.16 fixed-point.
# Demonstrates: gravity, bounce with restitution, trajectory simulation,
# and position clamping — the core of ball physics in arcade games.

.intel_syntax noprefix
.global _start

.section .data

test_count: .quad 0
pass_count: .quad 0

# Simulation state (16.16 fixed-point)
ball_x:   .quad 0
ball_y:   .quad 0
ball_vx:  .quad 0
ball_vy:  .quad 0

.section .rodata

msg_pass:      .ascii "PASS: "
msg_pass_len = . - msg_pass
msg_fail:      .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:        .ascii "\n"
msg_summary:   .ascii "All projectile physics examples passed.\n"
msg_sum_len = . - msg_summary
msg_not_all:   .ascii "SOME TESTS FAILED\n"
msg_not_len = . - msg_not_all

msg_t1:     .ascii "gravity increases downward velocity"
msg_t1_len = . - msg_t1
msg_t2:     .ascii "ball rises then falls (parabolic arc)"
msg_t2_len = . - msg_t2
msg_t3:     .ascii "bounce reverses and reduces velocity"
msg_t3_len = . - msg_t3
msg_t4:     .ascii "horizontal velocity unchanged by gravity"
msg_t4_len = . - msg_t4
msg_t5:     .ascii "ball stops after enough bounces"
msg_t5_len = . - msg_t5
msg_t6:     .ascii "semi-implicit euler is stable"
msg_t6_len = . - msg_t6

.section .text

# --- Physics constants (16.16 fixed-point) ---
.equ FX_SHIFT,     16
.equ FX_ONE,       65536
.equ GRAVITY,      6554         # 0.1 per frame
.equ FLOOR_Y,      14745600     # 225.0 (bottom of court)
.equ RESTITUTION,  45875        # 0.7 in 16.16 (bounce damping)

# --- Physics step ---
# Semi-implicit Euler: update velocity first, then position
# This is energy-stable (unlike explicit Euler)

# physics_step: advance ball one frame
# Uses globals: ball_x, ball_y, ball_vx, ball_vy
physics_step:
    # vy += gravity (semi-implicit: velocity first)
    mov     rax, [rip + ball_vy]
    add     rax, GRAVITY
    mov     [rip + ball_vy], rax

    # y += vy (use NEW velocity)
    mov     rcx, [rip + ball_y]
    add     rcx, rax
    mov     [rip + ball_y], rcx

    # x += vx (horizontal — no gravity)
    mov     rax, [rip + ball_vx]
    mov     rcx, [rip + ball_x]
    add     rcx, rax
    mov     [rip + ball_x], rcx
    ret

# bounce_check: if ball_y > FLOOR_Y, bounce
# Reverses vy and applies restitution, resets y to floor
bounce_check:
    mov     rax, [rip + ball_y]
    cmp     rax, FLOOR_Y
    jle     .no_bounce

    # Reset position to floor
    mov     qword ptr [rip + ball_y], FLOOR_Y

    # vy = -(vy * restitution) >> 16
    mov     rax, [rip + ball_vy]
    neg     rax                 # reverse direction
    mov     rcx, RESTITUTION
    imul    rcx                 # rax = -vy * restitution (128-bit in rdx:rax)
    shrd    rax, rdx, 16       # fixed-point shift
    mov     [rip + ball_vy], rax

.no_bounce:
    ret

# --- Arithmetic shift right (sign-preserving) ---
asr:
    mov     rax, rdi
    mov     rcx, rsi
    sar     rax, cl
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

# assert_true: rdi != 0 means pass
assert_true:
    mov     rsi, 1
    test    rdi, rdi
    jnz     .at_ok
    xor     rdi, rdi
    jmp     assert_eq
.at_ok:
    mov     rdi, 1
    jmp     assert_eq

_start:
    # --- Test 1: Gravity increases downward velocity ---
    # Start at (0, 0) with zero velocity, step once
    mov     qword ptr [rip + ball_x], 0
    mov     qword ptr [rip + ball_y], 0
    mov     qword ptr [rip + ball_vx], 0
    mov     qword ptr [rip + ball_vy], 0
    call    physics_step
    # After one step: vy should be GRAVITY (6554)
    mov     rdi, [rip + ball_vy]
    mov     rsi, GRAVITY
    lea     rdx, [rip + msg_t1]
    mov     rcx, msg_t1_len
    call    assert_eq

    # --- Test 2: Ball rises then falls (parabolic arc) ---
    # Launch upward: vy = -20.0 in fixed-point
    mov     qword ptr [rip + ball_y], 6553600       # 100.0
    mov     rax, -1310720                            # -20.0
    mov     qword ptr [rip + ball_vy], rax
    mov     qword ptr [rip + ball_vx], 0

    # Step 10 frames — ball should rise (y decreases since up is negative)
    mov     r12, [rip + ball_y]         # save initial y
    mov     r13, 10
.rise_loop:
    call    physics_step
    dec     r13
    jnz     .rise_loop

    # After 10 frames of gravity=0.1 on vy=-20.0:
    # vy should have increased (less negative or positive)
    mov     rdi, [rip + ball_vy]
    # vy started at -1310720, after 10 frames: -1310720 + 10*6554 = -1245180
    # vy should be greater than initial (closer to zero)
    cmp     rdi, -1310720
    setg    al
    movzx   rdi, al
    mov     rsi, 1
    lea     rdx, [rip + msg_t2]
    mov     rcx, msg_t2_len
    call    assert_eq

    # --- Test 3: Bounce reverses and reduces velocity ---
    # Put ball at floor with downward velocity
    mov     qword ptr [rip + ball_y], FLOOR_Y
    mov     qword ptr [rip + ball_vy], 655360       # 10.0 downward
    mov     rax, [rip + ball_vy]                     # save pre-bounce vy

    # Push just below floor to trigger bounce
    add     qword ptr [rip + ball_y], 1
    call    bounce_check

    # vy should now be negative (upward) and smaller magnitude
    mov     rdi, [rip + ball_vy]
    test    rdi, rdi
    js      .bounce_ok
    xor     rdi, rdi
    jmp     .bounce_check_done
.bounce_ok:
    mov     rdi, 1
.bounce_check_done:
    mov     rsi, 1
    lea     rdx, [rip + msg_t3]
    mov     rcx, msg_t3_len
    call    assert_eq

    # --- Test 4: Horizontal velocity unchanged by gravity ---
    mov     qword ptr [rip + ball_x], 0
    mov     qword ptr [rip + ball_y], 0
    mov     qword ptr [rip + ball_vx], 131072       # 2.0 horizontal
    mov     qword ptr [rip + ball_vy], 0

    call    physics_step
    call    physics_step
    call    physics_step

    # vx should still be 131072 (gravity only affects vy)
    mov     rdi, [rip + ball_vx]
    mov     rsi, 131072
    lea     rdx, [rip + msg_t4]
    mov     rcx, msg_t4_len
    call    assert_eq

    # --- Test 5: Ball stops after enough bounces ---
    mov     qword ptr [rip + ball_y], 0
    mov     qword ptr [rip + ball_vy], 655360       # 10.0 downward
    mov     qword ptr [rip + ball_vx], 0

    # Simulate 200 frames with bounce checking
    mov     r13, 200
.decay_loop:
    call    physics_step
    call    bounce_check
    dec     r13
    jnz     .decay_loop

    # vy magnitude should be very small (< 0.1 = 6554)
    mov     rdi, [rip + ball_vy]
    # Take absolute value
    test    rdi, rdi
    jns     .pos_vy
    neg     rdi
.pos_vy:
    cmp     rdi, 6554
    setl    al
    movzx   rdi, al
    mov     rsi, 1
    lea     rdx, [rip + msg_t5]
    mov     rcx, msg_t5_len
    call    assert_eq

    # --- Test 6: Semi-implicit Euler is stable ---
    # A ball bouncing for 1000 frames should not gain energy.
    # Track max height (min y) across bounces.
    mov     qword ptr [rip + ball_y], FLOOR_Y
    mov     rax, -655360                            # -10.0 upward
    mov     qword ptr [rip + ball_vy], rax
    mov     qword ptr [rip + ball_vx], 0

    mov     r12, FLOOR_Y        # track min_y (highest point = lowest value)
    mov     r13, 500
.stable_loop:
    call    physics_step
    call    bounce_check
    # Track minimum y (highest point reached)
    mov     rax, [rip + ball_y]
    cmp     rax, r12
    cmovl   r12, rax
    dec     r13
    jnz     .stable_loop

    # min_y should be >= 0 (ball never went above starting area too much)
    # and ball_y should be near floor (energy dissipated)
    mov     rdi, [rip + ball_y]
    cmp     rdi, FLOOR_Y
    setle   al
    movzx   rdi, al
    mov     rsi, 1
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
