# Vidya — Networking Fundamentals in x86_64 Assembly
#
# In-memory simulation of TCP socket state machine + lifecycle.

.intel_syntax noprefix
.global _start

.equ ST_CLOSED,      0
.equ ST_LISTEN,      1
.equ ST_ESTABLISHED, 3
.equ ST_FIN_WAIT,    4
.equ SOCK_CAP,       8
.equ BUF_CAP,        256

.section .bss
.align 8
state:        .skip 8 * SOCK_CAP
port_arr:     .skip 8 * SOCK_CAP
peer_arr:     .skip 8 * SOCK_CAP
rxlen:        .skip 8 * SOCK_CAP
rxbuf:        .skip BUF_CAP * SOCK_CAP
port_to_sock: .skip 8 * 65536

.section .data
next_free:    .quad 1

.section .rodata
msg_pass:     .ascii "networking_fundamentals: 19/19 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

net_init:
    mov     qword ptr [rip + next_free], 1
    lea     rdi, [rip + state]
    mov     rcx, SOCK_CAP * 4 + 65536        # state+port+peer+rxlen+port_to_sock
    xor     rax, rax
    # Just zero what we need: state, port_arr, peer_arr, rxlen each 64 bytes
    # plus port_to_sock 524288 bytes — too much to inline, use rep stosq.
    lea     rdi, [rip + state]
    mov     rcx, 4 * SOCK_CAP
    rep stosq
    lea     rdi, [rip + port_to_sock]
    mov     rcx, 65536
    rep stosq
    ret

# sock_create -> rax = id (or 0)
sock_create:
    mov     rcx, [rip + next_free]
.sc_loop:
    cmp     rcx, SOCK_CAP
    jge     .sc_zero
    lea     rdx, [rip + state]
    mov     rax, [rdx + rcx * 8]
    test    rax, rax
    jnz     .sc_next
    lea     rdx, [rip + port_arr]
    mov     rax, [rdx + rcx * 8]
    test    rax, rax
    jnz     .sc_next
    inc     rcx
    mov     [rip + next_free], rcx
    dec     rcx
    mov     rax, rcx
    ret
.sc_next:
    inc     rcx
    jmp     .sc_loop
.sc_zero:
    xor     rax, rax
    ret

# state_get(rdi=s) -> rax
state_get:
    test    rdi, rdi
    jz      .sg_neg
    cmp     rdi, SOCK_CAP
    jge     .sg_neg
    lea     rax, [rip + state]
    mov     rax, [rax + rdi * 8]
    ret
.sg_neg:
    mov     rax, -1
    ret

# sock_bind(rdi=s, rsi=port) -> rax 0/1
sock_bind:
    test    rdi, rdi
    jz      .sb_zero
    cmp     rdi, SOCK_CAP
    jge     .sb_zero
    lea     rax, [rip + port_to_sock]
    mov     rdx, [rax + rsi * 8]
    test    rdx, rdx
    jnz     .sb_zero
    lea     rax, [rip + port_arr]
    mov     rdx, [rax + rdi * 8]
    test    rdx, rdx
    jnz     .sb_zero
    mov     [rax + rdi * 8], rsi
    lea     rax, [rip + port_to_sock]
    mov     [rax + rsi * 8], rdi
    mov     rax, 1
    ret
.sb_zero:
    xor     rax, rax
    ret

# sock_listen(rdi=s) -> rax
sock_listen:
    test    rdi, rdi
    jz      .sl_zero
    cmp     rdi, SOCK_CAP
    jge     .sl_zero
    lea     rax, [rip + state]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, ST_CLOSED
    jne     .sl_zero
    lea     rdx, [rip + port_arr]
    mov     rcx, [rdx + rdi * 8]
    test    rcx, rcx
    jz      .sl_zero
    mov     qword ptr [rax + rdi * 8], ST_LISTEN
    mov     rax, 1
    ret
.sl_zero:
    xor     rax, rax
    ret

# sock_connect(rdi=client, rsi=port) -> rax
sock_connect:
    test    rdi, rdi
    jz      .sc_z
    cmp     rdi, SOCK_CAP
    jge     .sc_z
    lea     rax, [rip + port_to_sock]
    mov     rdx, [rax + rsi * 8]            # server
    test    rdx, rdx
    jz      .sc_z
    lea     rax, [rip + state]
    mov     rcx, [rax + rdx * 8]
    cmp     rcx, ST_LISTEN
    jne     .sc_z
    mov     qword ptr [rax + rdi * 8], ST_ESTABLISHED
    mov     qword ptr [rax + rdx * 8], ST_ESTABLISHED
    lea     rax, [rip + peer_arr]
    mov     [rax + rdi * 8], rdx
    mov     [rax + rdx * 8], rdi
    mov     rax, 1
    ret
.sc_z:
    xor     rax, rax
    ret

# sock_send_byte(rdi=s, rsi=b) -> rax
sock_send_byte:
    test    rdi, rdi
    jz      .ss_z
    cmp     rdi, SOCK_CAP
    jge     .ss_z
    lea     rax, [rip + state]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, ST_ESTABLISHED
    jne     .ss_z
    lea     rax, [rip + peer_arr]
    mov     rdx, [rax + rdi * 8]            # peer
    test    rdx, rdx
    jz      .ss_z
    lea     rax, [rip + rxlen]
    mov     rcx, [rax + rdx * 8]
    cmp     rcx, BUF_CAP
    jge     .ss_z
    # rxbuf[peer * BUF_CAP + rxlen] = b
    mov     r8, rdx
    imul    r8, BUF_CAP
    add     r8, rcx
    lea     r9, [rip + rxbuf]
    mov     [r9 + r8], sil                  # store low byte of rsi
    inc     rcx
    mov     [rax + rdx * 8], rcx
    mov     rax, 1
    ret
.ss_z:
    xor     rax, rax
    ret

# sock_recv_byte(rdi=s) -> rax
sock_recv_byte:
    test    rdi, rdi
    jz      .sr_neg
    cmp     rdi, SOCK_CAP
    jge     .sr_neg
    lea     rax, [rip + state]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, ST_ESTABLISHED
    je      .sr_ok
    cmp     rdx, ST_FIN_WAIT
    jne     .sr_neg
.sr_ok:
    lea     rax, [rip + rxlen]
    mov     rcx, [rax + rdi * 8]
    test    rcx, rcx
    jz      .sr_neg
    # b = rxbuf[s * BUF_CAP]
    mov     r8, rdi
    imul    r8, BUF_CAP
    lea     r9, [rip + rxbuf]
    movzx   r10, byte ptr [r9 + r8]
    # Shift rxbuf[s][1..rxlen] left by one
    xor     r11, r11                        # i
.sr_shift:
    mov     rdx, rcx
    dec     rdx
    cmp     r11, rdx
    jge     .sr_shift_done
    mov     rdx, r8
    add     rdx, r11
    mov     dl, [r9 + rdx + 1]
    mov     rax, r8
    add     rax, r11
    mov     [r9 + rax], dl
    inc     r11
    jmp     .sr_shift
.sr_shift_done:
    dec     rcx
    lea     rax, [rip + rxlen]
    mov     [rax + rdi * 8], rcx
    mov     rax, r10
    ret
.sr_neg:
    mov     rax, -1
    ret

# sock_close(rdi=s) -> rax
sock_close:
    test    rdi, rdi
    jz      .scl_z
    cmp     rdi, SOCK_CAP
    jge     .scl_z
    lea     rax, [rip + state]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, ST_CLOSED
    je      .scl_z
    lea     rdx, [rip + port_arr]
    mov     rcx, [rdx + rdi * 8]
    test    rcx, rcx
    jz      .scl_unmap_done
    lea     r8, [rip + port_to_sock]
    mov     qword ptr [r8 + rcx * 8], 0
.scl_unmap_done:
    mov     qword ptr [rax + rdi * 8], ST_CLOSED
    mov     qword ptr [rdx + rdi * 8], 0
    lea     rax, [rip + peer_arr]
    mov     qword ptr [rax + rdi * 8], 0
    mov     rax, 1
    ret
.scl_z:
    xor     rax, rax
    ret

assert_eq:
    cmp     rdi, rsi
    jne     fail_exit
    ret

fail_exit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    call    net_init

    call    sock_create
    mov     r12, rax              # srv
    mov     rdi, rax
    call    state_get
    mov     rdi, rax
    mov     rsi, ST_CLOSED
    call    assert_eq

    mov     rdi, r12
    mov     rsi, 8080
    call    sock_bind
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r12
    call    sock_listen
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r12
    call    state_get
    mov     rdi, rax
    mov     rsi, ST_LISTEN
    call    assert_eq

    call    sock_create
    mov     r13, rax              # cli
    mov     rdi, r13
    mov     rsi, 8080
    call    sock_connect
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    call    state_get
    mov     rdi, rax
    mov     rsi, ST_ESTABLISHED
    call    assert_eq
    mov     rdi, r12
    call    state_get
    mov     rdi, rax
    mov     rsi, ST_ESTABLISHED
    call    assert_eq

    mov     rdi, r13
    mov     rsi, 65
    call    sock_send_byte
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    mov     rsi, 66
    call    sock_send_byte
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r12
    call    sock_recv_byte
    mov     rdi, rax
    mov     rsi, 65
    call    assert_eq
    mov     rdi, r12
    call    sock_recv_byte
    mov     rdi, rax
    mov     rsi, 66
    call    assert_eq
    mov     rdi, r12
    call    sock_recv_byte
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq
    mov     rdi, r12
    mov     rsi, 67
    call    sock_send_byte
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    call    sock_recv_byte
    mov     rdi, rax
    mov     rsi, 67
    call    assert_eq

    mov     rdi, r13
    call    sock_close
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, r13
    call    state_get
    mov     rdi, rax
    mov     rsi, ST_CLOSED
    call    assert_eq

    call    sock_create
    mov     r14, rax              # srv2
    mov     rdi, r14
    mov     rsi, 8080
    call    sock_bind
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    mov     rdi, r13
    call    sock_recv_byte
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    mov     rdi, r12
    call    sock_close
    mov     rdi, r14
    mov     rsi, 8080
    call    sock_bind
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
