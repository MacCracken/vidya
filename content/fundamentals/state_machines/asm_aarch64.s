// Vidya — State Machines in AArch64 Assembly
//
// Three globals model a single Player: state, prev_state, timer.
// Constants are .equ-defined; transition + tick are CBZ/CBNZ-driven
// branches with no implicit conversions. Same FSM as cyrius.cyr.

.global _start

.equ PS_IDLE,    0
.equ PS_RUN,     1
.equ PS_SHOOT,   2
.equ PS_DUNK,    3
.equ PS_PASS,    4
.equ PS_STEAL,   5
.equ PS_FALL,    7

.equ IN_NONE,    0
.equ IN_MOVE,    1
.equ IN_SHOOT,   2
.equ IN_PASS,    3
.equ IN_STEAL,   4

.equ SHOOT_FRAMES, 30
.equ DUNK_FRAMES,  45

.section .data
.align 3
p_state:      .quad 0
p_prev:       .quad 0
p_timer:      .quad 0

.section .rodata
msg_pass:    .ascii "All state_machines examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// reset: zero out all three player slots
player_reset:
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    str     xzr, [x9]
    str     xzr, [x9, #8]
    str     xzr, [x9, #16]
    ret

// is_committed: x0 = state ; returns 1 in x0 if committed else 0
is_committed:
    cmp     x0, #PS_SHOOT
    b.eq    .Lcomm_yes
    cmp     x0, #PS_DUNK
    b.eq    .Lcomm_yes
    cmp     x0, #PS_FALL
    b.eq    .Lcomm_yes
    mov     x0, #0
    ret
.Lcomm_yes:
    mov     x0, #1
    ret

// transition: x0 = input
// Calls is_committed via `bl`, so we must save FP (x29) + LR (x30) in
// the prologue or the inner `bl` clobbers our return address.
transition:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]       // x19 callee-saved scratch (input)
    mov     x19, x0              // input

    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x10, [x9]            // state
    ldr     x11, [x9, #16]       // timer

    // committed-with-timer guard: skip apply if both true
    mov     x0, x10
    bl      is_committed
    cbz     x0, .Ltrans_apply
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x11, [x9, #16]
    cbz     x11, .Ltrans_apply
    b       .Ltrans_done

.Ltrans_apply:
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x10, [x9]
    str     x10, [x9, #8]        // prev_state = state
    cmp     x19, #IN_MOVE
    b.eq    .Lt_move
    cmp     x19, #IN_SHOOT
    b.eq    .Lt_shoot
    cmp     x19, #IN_PASS
    b.eq    .Lt_pass
    cmp     x19, #IN_STEAL
    b.eq    .Lt_steal
    mov     x10, #PS_IDLE
    str     x10, [x9]
    b       .Ltrans_done
.Lt_move:
    mov     x10, #PS_RUN
    str     x10, [x9]
    b       .Ltrans_done
.Lt_shoot:
    mov     x10, #PS_SHOOT
    str     x10, [x9]
    mov     x10, #SHOOT_FRAMES
    str     x10, [x9, #16]
    b       .Ltrans_done
.Lt_pass:
    mov     x10, #PS_PASS
    str     x10, [x9]
    b       .Ltrans_done
.Lt_steal:
    mov     x10, #PS_STEAL
    str     x10, [x9]
.Ltrans_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// tick: decrement timer; on hit-zero, save prev and idle
tick:
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x10, [x9, #16]
    cbz     x10, .Ltick_done
    sub     x10, x10, #1
    str     x10, [x9, #16]
    cbnz    x10, .Ltick_done
    ldr     x11, [x9]
    str     x11, [x9, #8]
    mov     x11, #PS_IDLE
    str     x11, [x9]
.Ltick_done:
    ret

// _start: run all tests; SP is 16-byte aligned at entry; bl uses LR
_start:
    // -------- Test 1: idle -> run on move --------
    bl      player_reset
    mov     x0, #IN_MOVE
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_RUN
    b.ne    fail

    // -------- Test 2: shoot rejects move/pass while timer > 0 --------
    bl      player_reset
    mov     x0, #IN_SHOOT
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_SHOOT
    b.ne    fail

    mov     x0, #IN_MOVE
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_SHOOT
    b.ne    fail

    mov     x0, #IN_PASS
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_SHOOT
    b.ne    fail

    // -------- Test 3: timer expiry returns to idle --------
    bl      player_reset
    mov     x0, #IN_SHOOT
    bl      transition
    mov     x19, #SHOOT_FRAMES
.Lspin_shoot:
    bl      tick
    sub     x19, x19, #1
    cbnz    x19, .Lspin_shoot
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_IDLE
    b.ne    fail
    ldr     x0, [x9, #16]
    cbnz    x0, fail

    // -------- Test 4: dunk rejects then expires --------
    bl      player_reset
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    mov     x10, #PS_DUNK
    str     x10, [x9]
    mov     x10, #DUNK_FRAMES
    str     x10, [x9, #16]

    mov     x0, #IN_MOVE
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_DUNK
    b.ne    fail

    mov     x19, #DUNK_FRAMES
.Lspin_dunk:
    bl      tick
    sub     x19, x19, #1
    cbnz    x19, .Lspin_dunk
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_IDLE
    b.ne    fail

    // -------- Test 5: committed-then-free --------
    bl      player_reset
    mov     x0, #IN_SHOOT
    bl      transition
    mov     x19, #SHOOT_FRAMES
.Lspin_free:
    bl      tick
    sub     x19, x19, #1
    cbnz    x19, .Lspin_free
    mov     x0, #IN_MOVE
    bl      transition
    adrp    x9, p_state
    add     x9, x9, :lo12:p_state
    ldr     x0, [x9]
    cmp     x0, #PS_RUN
    b.ne    fail

    // -------- Done — exit 0 --------
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
