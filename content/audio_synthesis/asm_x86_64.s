# Vidya — Audio Synthesis — x86_64 Assembly. Q15 fixed-point.
#
# Focused subset: phase advance, sine LUT, square, ADSR full state
# machine. Saw and the multi-waveform Voice dispatch live in
# cyrius.cyr — too verbose for asm.

.intel_syntax noprefix
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

.section .data
.align 8
sine_table:
    .quad 0, 12540, 23170, 30274, 32767, 30274, 23170, 12540
    .quad 0, -12540, -23170, -30274, -32767, -30274, -23170, -12540

.section .bss
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

.section .text

# phase_advance(rdi=cur, rsi=inc) -> rax
phase_advance:
    mov     rax, rdi
    add     rax, rsi
    and     rax, PHASE_MASK
    ret

# osc_sine(rdi=phase) -> rax
osc_sine:
    mov     rax, rdi
    shr     rax, 12
    lea     r8, [rip + sine_table]
    mov     rax, [r8 + rax*8]
    ret

# osc_square(rdi=phase) -> rax
osc_square:
    cmp     rdi, PHASE_HALF
    jge     .sq_neg
    mov     rax, 32767
    ret
.sq_neg:
    mov     rax, -32767
    ret

# env_set_params(rdi=attack, rsi=decay, rdx=sustain, rcx=release)
env_set_params:
    mov     [rip + env_attack_samples], rdi
    mov     [rip + env_decay_samples], rsi
    mov     [rip + env_sustain_level], rdx
    mov     [rip + env_release_samples], rcx
    ret

# env_reset
env_reset:
    mov     qword ptr [rip + env_state], ENV_IDLE
    mov     qword ptr [rip + env_level], 0
    mov     qword ptr [rip + env_stage_samples], 0
    mov     qword ptr [rip + env_release_start], 0
    ret

# env_gate_on
env_gate_on:
    mov     qword ptr [rip + env_state], ENV_ATTACK
    mov     qword ptr [rip + env_stage_samples], 0
    ret

# env_gate_off -> rax = 1 if released, 0 if was idle
env_gate_off:
    mov     rax, [rip + env_state]
    cmp     rax, ENV_IDLE
    jne     .go_release
    xor     rax, rax
    ret
.go_release:
    mov     rax, [rip + env_level]
    mov     [rip + env_release_start], rax
    mov     qword ptr [rip + env_state], ENV_RELEASE
    mov     qword ptr [rip + env_stage_samples], 0
    mov     rax, 1
    ret

# env_step -> rax = new level
env_step:
    mov     rax, [rip + env_state]
    cmp     rax, ENV_IDLE
    jne     .es_not_idle
    mov     qword ptr [rip + env_level], 0
    xor     rax, rax
    ret
.es_not_idle:
    cmp     rax, ENV_ATTACK
    jne     .es_not_attack
    # inc = ONE / attack_samples
    mov     rax, ONE
    cqo
    idiv    qword ptr [rip + env_attack_samples]
    add     [rip + env_level], rax
    inc     qword ptr [rip + env_stage_samples]
    mov     rax, [rip + env_stage_samples]
    cmp     rax, [rip + env_attack_samples]
    jl      .es_attack_ret
    mov     qword ptr [rip + env_level], ONE
    mov     qword ptr [rip + env_state], ENV_DECAY
    mov     qword ptr [rip + env_stage_samples], 0
.es_attack_ret:
    mov     rax, [rip + env_level]
    ret
.es_not_attack:
    cmp     rax, ENV_DECAY
    jne     .es_not_decay
    # dec = (ONE - sustain_level) / decay_samples
    mov     rax, ONE
    sub     rax, [rip + env_sustain_level]
    cqo
    idiv    qword ptr [rip + env_decay_samples]
    sub     [rip + env_level], rax
    inc     qword ptr [rip + env_stage_samples]
    mov     rax, [rip + env_stage_samples]
    cmp     rax, [rip + env_decay_samples]
    jl      .es_decay_ret
    mov     rax, [rip + env_sustain_level]
    mov     [rip + env_level], rax
    mov     qword ptr [rip + env_state], ENV_SUSTAIN
    mov     qword ptr [rip + env_stage_samples], 0
.es_decay_ret:
    mov     rax, [rip + env_level]
    ret
.es_not_decay:
    cmp     rax, ENV_SUSTAIN
    jne     .es_not_sustain
    mov     rax, [rip + env_sustain_level]
    mov     [rip + env_level], rax
    ret
.es_not_sustain:
    cmp     rax, ENV_RELEASE
    jne     .es_done
    # dec = release_start / release_samples
    mov     rax, [rip + env_release_start]
    cqo
    idiv    qword ptr [rip + env_release_samples]
    sub     [rip + env_level], rax
    inc     qword ptr [rip + env_stage_samples]
    mov     rax, [rip + env_stage_samples]
    cmp     rax, [rip + env_release_samples]
    jl      .es_release_ret
    mov     qword ptr [rip + env_level], 0
    mov     qword ptr [rip + env_state], ENV_IDLE
    mov     qword ptr [rip + env_stage_samples], 0
.es_release_ret:
    mov     rax, [rip + env_level]
    ret
.es_done:
    xor     rax, rax
    ret

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
    # phase_advance
    mov     rdi, 60000
    mov     rsi, 10000
    call    phase_advance
    mov     rdi, rax
    mov     rsi, 4464
    call    assert_eq

    # osc_sine
    mov     rdi, 0
    call    osc_sine
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 16384
    call    osc_sine
    mov     rdi, rax
    mov     rsi, 32767
    call    assert_eq
    mov     rdi, 49152
    call    osc_sine
    mov     rdi, rax
    mov     rsi, -32767
    call    assert_eq

    # osc_square
    mov     rdi, 0
    call    osc_square
    mov     rdi, rax
    mov     rsi, 32767
    call    assert_eq
    mov     rdi, PHASE_HALF
    call    osc_square
    mov     rdi, rax
    mov     rsi, -32767
    call    assert_eq

    # env attack
    mov     rdi, 4
    mov     rsi, 4
    mov     rdx, 16384
    mov     rcx, 4
    call    env_set_params
    call    env_reset
    call    env_gate_on
    mov     rcx, 4
.env_at:
    push    rcx
    call    env_step
    pop     rcx
    dec     rcx
    jnz     .env_at
    mov     rdi, [rip + env_state]
    mov     rsi, ENV_DECAY
    call    assert_eq
    mov     rdi, [rip + env_level]
    mov     rsi, ONE
    call    assert_eq

    # env decay → sustain
    mov     rdi, 4
    mov     rsi, 4
    mov     rdx, 16384
    mov     rcx, 4
    call    env_set_params
    call    env_reset
    call    env_gate_on
    mov     rcx, 8
.env_dc:
    push    rcx
    call    env_step
    pop     rcx
    dec     rcx
    jnz     .env_dc
    mov     rdi, [rip + env_state]
    mov     rsi, ENV_SUSTAIN
    call    assert_eq
    mov     rdi, [rip + env_level]
    mov     rsi, 16384
    call    assert_eq

    # env sustain holds across many steps
    mov     rcx, 100
.env_su:
    push    rcx
    call    env_step
    pop     rcx
    dec     rcx
    jnz     .env_su
    mov     rdi, [rip + env_state]
    mov     rsi, ENV_SUSTAIN
    call    assert_eq

    # env release → idle
    call    env_gate_off
    mov     rdi, [rip + env_release_start]
    mov     rsi, 16384
    call    assert_eq
    mov     rcx, 4
.env_rl:
    push    rcx
    call    env_step
    pop     rcx
    dec     rcx
    jnz     .env_rl
    mov     rdi, [rip + env_state]
    mov     rsi, ENV_IDLE
    call    assert_eq
    mov     rdi, [rip + env_level]
    mov     rsi, 0
    call    assert_eq

    # success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
