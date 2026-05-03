// Vidya — Audio Synthesis — AArch64 Assembly. Q15 fixed-point.
//
// Focused subset (matches x86_64 port): phase advance, sine LUT,
// square, ADSR full state machine. Saw + Voice dispatch in cyrius.cyr.

.global _start

.equ SCALE,      15
.equ ONE,        32768
.equ PHASE_MASK, 65535
.equ PHASE_HALF, 32768

.equ ENV_IDLE,    0
.equ ENV_ATTACK,  1
.equ ENV_DECAY,   2
.equ ENV_SUSTAIN, 3
.equ ENV_RELEASE, 4

.data
.align 8
sine_table:
    .quad 0, 12540, 23170, 30274, 32767, 30274, 23170, 12540
    .quad 0, -12540, -23170, -30274, -32767, -30274, -23170, -12540

.bss
.align 8
env_state:           .skip 8
env_level:           .skip 8
env_stage_samples:   .skip 8
env_release_start:   .skip 8
env_attack_samples:  .skip 8
env_decay_samples:   .skip 8
env_sustain_level:   .skip 8
env_release_samples: .skip 8

.section .rodata
msg_pass: .ascii "audio_synthesis: 13/13 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// phase_advance(x0=cur, x1=inc) -> x0
phase_advance:
    add     x0, x0, x1
    and     x0, x0, #PHASE_MASK
    ret

// osc_sine(x0=phase) -> x0
osc_sine:
    lsr     x0, x0, #12
    LDADDR  x1, sine_table
    ldr     x0, [x1, x0, lsl #3]
    ret

// osc_square(x0=phase) -> x0
osc_square:
    mov     x1, #PHASE_HALF
    cmp     x0, x1
    b.ge    .sq_neg
    mov     x0, #32767
    ret
.sq_neg:
    mov     x0, #-32767
    ret

// env_set_params(x0=attack, x1=decay, x2=sustain, x3=release)
env_set_params:
    LDADDR  x4, env_attack_samples
    str     x0, [x4]
    LDADDR  x4, env_decay_samples
    str     x1, [x4]
    LDADDR  x4, env_sustain_level
    str     x2, [x4]
    LDADDR  x4, env_release_samples
    str     x3, [x4]
    ret

env_reset:
    LDADDR  x0, env_state
    str     xzr, [x0]
    LDADDR  x0, env_level
    str     xzr, [x0]
    LDADDR  x0, env_stage_samples
    str     xzr, [x0]
    LDADDR  x0, env_release_start
    str     xzr, [x0]
    ret

env_gate_on:
    mov     x0, #ENV_ATTACK
    LDADDR  x1, env_state
    str     x0, [x1]
    LDADDR  x1, env_stage_samples
    str     xzr, [x1]
    ret

// env_gate_off -> x0 = 1 if released, 0 if was idle
env_gate_off:
    LDADDR  x1, env_state
    ldr     x0, [x1]
    cmp     x0, #ENV_IDLE
    b.ne    .go_release
    mov     x0, #0
    ret
.go_release:
    LDADDR  x2, env_level
    ldr     x0, [x2]
    LDADDR  x2, env_release_start
    str     x0, [x2]
    mov     x0, #ENV_RELEASE
    LDADDR  x1, env_state
    str     x0, [x1]
    LDADDR  x1, env_stage_samples
    str     xzr, [x1]
    mov     x0, #1
    ret

// env_step -> x0 = new level
env_step:
    LDADDR  x1, env_state
    ldr     x0, [x1]
    cmp     x0, #ENV_IDLE
    b.ne    .es_not_idle
    LDADDR  x1, env_level
    str     xzr, [x1]
    mov     x0, #0
    ret
.es_not_idle:
    cmp     x0, #ENV_ATTACK
    b.ne    .es_not_attack
    // inc = ONE / attack_samples
    mov     w2, #ONE
    LDADDR  x3, env_attack_samples
    ldr     x4, [x3]
    sdiv    x5, x2, x4
    LDADDR  x6, env_level
    ldr     x7, [x6]
    add     x7, x7, x5
    str     x7, [x6]
    LDADDR  x8, env_stage_samples
    ldr     x9, [x8]
    add     x9, x9, #1
    str     x9, [x8]
    cmp     x9, x4
    b.lt    .es_attack_ret
    mov     w10, #ONE
    str     x10, [x6]
    mov     x10, #ENV_DECAY
    LDADDR  x1, env_state
    str     x10, [x1]
    str     xzr, [x8]
.es_attack_ret:
    LDADDR  x1, env_level
    ldr     x0, [x1]
    ret
.es_not_attack:
    cmp     x0, #ENV_DECAY
    b.ne    .es_not_decay
    // dec = (ONE - sustain_level) / decay_samples
    mov     w2, #ONE
    LDADDR  x3, env_sustain_level
    ldr     x4, [x3]
    sub     x2, x2, x4
    LDADDR  x3, env_decay_samples
    ldr     x4, [x3]
    sdiv    x5, x2, x4
    LDADDR  x6, env_level
    ldr     x7, [x6]
    sub     x7, x7, x5
    str     x7, [x6]
    LDADDR  x8, env_stage_samples
    ldr     x9, [x8]
    add     x9, x9, #1
    str     x9, [x8]
    cmp     x9, x4
    b.lt    .es_decay_ret
    LDADDR  x3, env_sustain_level
    ldr     x10, [x3]
    str     x10, [x6]
    mov     x10, #ENV_SUSTAIN
    LDADDR  x1, env_state
    str     x10, [x1]
    str     xzr, [x8]
.es_decay_ret:
    LDADDR  x1, env_level
    ldr     x0, [x1]
    ret
.es_not_decay:
    cmp     x0, #ENV_SUSTAIN
    b.ne    .es_not_sustain
    LDADDR  x3, env_sustain_level
    ldr     x10, [x3]
    LDADDR  x6, env_level
    str     x10, [x6]
    mov     x0, x10
    ret
.es_not_sustain:
    cmp     x0, #ENV_RELEASE
    b.ne    .es_done
    // dec = release_start / release_samples
    LDADDR  x3, env_release_start
    ldr     x2, [x3]
    LDADDR  x3, env_release_samples
    ldr     x4, [x3]
    sdiv    x5, x2, x4
    LDADDR  x6, env_level
    ldr     x7, [x6]
    sub     x7, x7, x5
    str     x7, [x6]
    LDADDR  x8, env_stage_samples
    ldr     x9, [x8]
    add     x9, x9, #1
    str     x9, [x8]
    cmp     x9, x4
    b.lt    .es_release_ret
    str     xzr, [x6]
    mov     x10, #ENV_IDLE
    LDADDR  x1, env_state
    str     x10, [x1]
    str     xzr, [x8]
.es_release_ret:
    LDADDR  x1, env_level
    ldr     x0, [x1]
    ret
.es_done:
    mov     x0, #0
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
    // phase_advance
    mov     x0, #60000
    mov     x1, #10000
    bl      phase_advance
    mov     x1, #4464
    bl      assert_eq

    // osc_sine
    mov     x0, #0
    bl      osc_sine
    mov     x1, #0
    bl      assert_eq
    mov     x0, #16384
    bl      osc_sine
    mov     x1, #32767
    bl      assert_eq
    mov     x0, #49152
    bl      osc_sine
    mov     x1, #-32767
    bl      assert_eq

    // osc_square
    mov     x0, #0
    bl      osc_square
    mov     x1, #32767
    bl      assert_eq
    mov     x0, #PHASE_HALF
    bl      osc_square
    mov     x1, #-32767
    bl      assert_eq

    // env attack
    mov     x0, #4
    mov     x1, #4
    mov     w2, #16384
    mov     x3, #4
    bl      env_set_params
    bl      env_reset
    bl      env_gate_on
    mov     x19, #4
.env_at:
    bl      env_step
    sub     x19, x19, #1
    cbnz    x19, .env_at
    LDADDR  x2, env_state
    ldr     x0, [x2]
    mov     x1, #ENV_DECAY
    bl      assert_eq
    LDADDR  x2, env_level
    ldr     x0, [x2]
    mov     w1, #ONE
    bl      assert_eq

    // env decay → sustain
    mov     x0, #4
    mov     x1, #4
    mov     w2, #16384
    mov     x3, #4
    bl      env_set_params
    bl      env_reset
    bl      env_gate_on
    mov     x19, #8
.env_dc:
    bl      env_step
    sub     x19, x19, #1
    cbnz    x19, .env_dc
    LDADDR  x2, env_state
    ldr     x0, [x2]
    mov     x1, #ENV_SUSTAIN
    bl      assert_eq
    LDADDR  x2, env_level
    ldr     x0, [x2]
    mov     w1, #16384
    bl      assert_eq

    // env sustain holds
    mov     x19, #100
.env_su:
    bl      env_step
    sub     x19, x19, #1
    cbnz    x19, .env_su
    LDADDR  x2, env_state
    ldr     x0, [x2]
    mov     x1, #ENV_SUSTAIN
    bl      assert_eq

    // env release → idle
    bl      env_gate_off
    LDADDR  x2, env_release_start
    ldr     x0, [x2]
    mov     w1, #16384
    bl      assert_eq
    mov     x19, #4
.env_rl:
    bl      env_step
    sub     x19, x19, #1
    cbnz    x19, .env_rl
    LDADDR  x2, env_state
    ldr     x0, [x2]
    mov     x1, #ENV_IDLE
    bl      assert_eq
    LDADDR  x2, env_level
    ldr     x0, [x2]
    mov     x1, #0
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
