// Vidya — Networking Fundamentals in AArch64 Assembly
//
// In-memory simulation of TCP socket state machine + lifecycle.

.global _start

.equ ST_CLOSED,      0
.equ ST_LISTEN,      1
.equ ST_ESTABLISHED, 3
.equ ST_FIN_WAIT,    4
.equ SOCK_CAP,       8
.equ BUF_CAP,        256

.bss
.align 8
state:        .skip 8 * SOCK_CAP
port_arr:     .skip 8 * SOCK_CAP
peer_arr:     .skip 8 * SOCK_CAP
rxlen:        .skip 8 * SOCK_CAP
rxbuf:        .skip BUF_CAP * SOCK_CAP
port_to_sock: .skip 8 * 65536

.data
.align 8
next_free:    .quad 1

.section .rodata
msg_pass:     .ascii "networking_fundamentals: 19/19 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

net_init:
    mov     x0, #1
    adrp    x1, next_free
    add     x1, x1, :lo12:next_free
    str     x0, [x1]
    mov     x0, #0
    adrp    x1, state
    add     x1, x1, :lo12:state
    mov     x2, #(4 * SOCK_CAP)       // state+port+peer+rxlen
.ni1:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .ni1
    adrp    x1, port_to_sock
    add     x1, x1, :lo12:port_to_sock
    mov     x2, #65536
.ni2:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .ni2
    ret

// sock_create -> x0
sock_create:
    adrp    x1, next_free
    add     x1, x1, :lo12:next_free
    ldr     x2, [x1]
.sc_loop:
    cmp     x2, #SOCK_CAP
    b.ge    .sc_zero
    adrp    x3, state
    add     x3, x3, :lo12:state
    ldr     x4, [x3, x2, lsl #3]
    cbnz    x4, .sc_next
    adrp    x3, port_arr
    add     x3, x3, :lo12:port_arr
    ldr     x4, [x3, x2, lsl #3]
    cbnz    x4, .sc_next
    add     x4, x2, #1
    str     x4, [x1]
    mov     x0, x2
    ret
.sc_next:
    add     x2, x2, #1
    b       .sc_loop
.sc_zero:
    mov     x0, #0
    ret

// state_get(x0=s) -> x0
state_get:
    cbz     x0, .sg_neg
    cmp     x0, #SOCK_CAP
    b.ge    .sg_neg
    adrp    x1, state
    add     x1, x1, :lo12:state
    ldr     x0, [x1, x0, lsl #3]
    ret
.sg_neg:
    mov     x0, #-1
    ret

// sock_bind(x0=s, x1=port) -> x0
sock_bind:
    cbz     x0, .sb_z
    cmp     x0, #SOCK_CAP
    b.ge    .sb_z
    adrp    x2, port_to_sock
    add     x2, x2, :lo12:port_to_sock
    ldr     x3, [x2, x1, lsl #3]
    cbnz    x3, .sb_z
    adrp    x3, port_arr
    add     x3, x3, :lo12:port_arr
    ldr     x4, [x3, x0, lsl #3]
    cbnz    x4, .sb_z
    str     x1, [x3, x0, lsl #3]
    str     x0, [x2, x1, lsl #3]
    mov     x0, #1
    ret
.sb_z:
    mov     x0, #0
    ret

// sock_listen(x0=s) -> x0
sock_listen:
    cbz     x0, .sl_z
    cmp     x0, #SOCK_CAP
    b.ge    .sl_z
    adrp    x1, state
    add     x1, x1, :lo12:state
    ldr     x2, [x1, x0, lsl #3]
    cmp     x2, #ST_CLOSED
    b.ne    .sl_z
    adrp    x2, port_arr
    add     x2, x2, :lo12:port_arr
    ldr     x3, [x2, x0, lsl #3]
    cbz     x3, .sl_z
    mov     x3, #ST_LISTEN
    str     x3, [x1, x0, lsl #3]
    mov     x0, #1
    ret
.sl_z:
    mov     x0, #0
    ret

// sock_connect(x0=client, x1=port) -> x0
sock_connect:
    cbz     x0, .scn_z
    cmp     x0, #SOCK_CAP
    b.ge    .scn_z
    adrp    x2, port_to_sock
    add     x2, x2, :lo12:port_to_sock
    ldr     x3, [x2, x1, lsl #3]      // server
    cbz     x3, .scn_z
    adrp    x4, state
    add     x4, x4, :lo12:state
    ldr     x5, [x4, x3, lsl #3]
    cmp     x5, #ST_LISTEN
    b.ne    .scn_z
    mov     x5, #ST_ESTABLISHED
    str     x5, [x4, x0, lsl #3]
    str     x5, [x4, x3, lsl #3]
    adrp    x4, peer_arr
    add     x4, x4, :lo12:peer_arr
    str     x3, [x4, x0, lsl #3]
    str     x0, [x4, x3, lsl #3]
    mov     x0, #1
    ret
.scn_z:
    mov     x0, #0
    ret

// sock_send_byte(x0=s, x1=b) -> x0
sock_send_byte:
    cbz     x0, .ss_z
    cmp     x0, #SOCK_CAP
    b.ge    .ss_z
    adrp    x2, state
    add     x2, x2, :lo12:state
    ldr     x3, [x2, x0, lsl #3]
    cmp     x3, #ST_ESTABLISHED
    b.ne    .ss_z
    adrp    x2, peer_arr
    add     x2, x2, :lo12:peer_arr
    ldr     x3, [x2, x0, lsl #3]      // peer
    cbz     x3, .ss_z
    adrp    x2, rxlen
    add     x2, x2, :lo12:rxlen
    ldr     x4, [x2, x3, lsl #3]
    cmp     x4, #BUF_CAP
    b.ge    .ss_z
    // rxbuf[peer * BUF_CAP + rxlen] = b
    mov     x5, #BUF_CAP
    mul     x5, x3, x5
    add     x5, x5, x4
    adrp    x6, rxbuf
    add     x6, x6, :lo12:rxbuf
    strb    w1, [x6, x5]
    add     x4, x4, #1
    str     x4, [x2, x3, lsl #3]
    mov     x0, #1
    ret
.ss_z:
    mov     x0, #0
    ret

// sock_recv_byte(x0=s) -> x0
sock_recv_byte:
    cbz     x0, .sr_neg
    cmp     x0, #SOCK_CAP
    b.ge    .sr_neg
    adrp    x1, state
    add     x1, x1, :lo12:state
    ldr     x2, [x1, x0, lsl #3]
    cmp     x2, #ST_ESTABLISHED
    b.eq    .sr_ok
    cmp     x2, #ST_FIN_WAIT
    b.ne    .sr_neg
.sr_ok:
    adrp    x1, rxlen
    add     x1, x1, :lo12:rxlen
    ldr     x2, [x1, x0, lsl #3]
    cbz     x2, .sr_neg
    mov     x3, #BUF_CAP
    mul     x3, x0, x3                // s * BUF_CAP
    adrp    x4, rxbuf
    add     x4, x4, :lo12:rxbuf
    ldrb    w5, [x4, x3]              // b
    mov     x6, #0                    // i
    sub     x7, x2, #1                // limit
.sr_shift:
    cmp     x6, x7
    b.ge    .sr_shift_done
    add     x8, x3, x6
    add     x8, x8, #1
    ldrb    w9, [x4, x8]
    add     x8, x3, x6
    strb    w9, [x4, x8]
    add     x6, x6, #1
    b       .sr_shift
.sr_shift_done:
    sub     x2, x2, #1
    str     x2, [x1, x0, lsl #3]
    and     x0, x5, #0xff
    ret
.sr_neg:
    mov     x0, #-1
    ret

// sock_close(x0=s) -> x0
sock_close:
    cbz     x0, .scl_z
    cmp     x0, #SOCK_CAP
    b.ge    .scl_z
    adrp    x1, state
    add     x1, x1, :lo12:state
    ldr     x2, [x1, x0, lsl #3]
    cmp     x2, #ST_CLOSED
    b.eq    .scl_z
    adrp    x2, port_arr
    add     x2, x2, :lo12:port_arr
    ldr     x3, [x2, x0, lsl #3]
    cbz     x3, .scl_unmap_done
    adrp    x4, port_to_sock
    add     x4, x4, :lo12:port_to_sock
    mov     x5, #0
    str     x5, [x4, x3, lsl #3]
.scl_unmap_done:
    mov     x3, #ST_CLOSED
    str     x3, [x1, x0, lsl #3]
    mov     x3, #0
    str     x3, [x2, x0, lsl #3]
    adrp    x2, peer_arr
    add     x2, x2, :lo12:peer_arr
    str     x3, [x2, x0, lsl #3]
    mov     x0, #1
    ret
.scl_z:
    mov     x0, #0
    ret

assert_eq:
    cmp     x0, x1
    b.ne    fail_exit
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    bl      net_init

    bl      sock_create
    mov     x19, x0               // srv
    bl      state_get
    mov     x1, #ST_CLOSED
    bl      assert_eq

    mov     x0, x19
    mov     x1, #8080
    bl      sock_bind
    mov     x1, #1
    bl      assert_eq
    mov     x0, x19
    bl      sock_listen
    mov     x1, #1
    bl      assert_eq
    mov     x0, x19
    bl      state_get
    mov     x1, #ST_LISTEN
    bl      assert_eq

    bl      sock_create
    mov     x20, x0               // cli
    mov     x0, x20
    mov     x1, #8080
    bl      sock_connect
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    bl      state_get
    mov     x1, #ST_ESTABLISHED
    bl      assert_eq
    mov     x0, x19
    bl      state_get
    mov     x1, #ST_ESTABLISHED
    bl      assert_eq

    mov     x0, x20
    mov     x1, #65
    bl      sock_send_byte
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    mov     x1, #66
    bl      sock_send_byte
    mov     x1, #1
    bl      assert_eq
    mov     x0, x19
    bl      sock_recv_byte
    mov     x1, #65
    bl      assert_eq
    mov     x0, x19
    bl      sock_recv_byte
    mov     x1, #66
    bl      assert_eq
    mov     x0, x19
    bl      sock_recv_byte
    mov     x1, #-1
    bl      assert_eq
    mov     x0, x19
    mov     x1, #67
    bl      sock_send_byte
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    bl      sock_recv_byte
    mov     x1, #67
    bl      assert_eq

    mov     x0, x20
    bl      sock_close
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    bl      state_get
    mov     x1, #ST_CLOSED
    bl      assert_eq

    bl      sock_create
    mov     x21, x0               // srv2
    mov     x0, x21
    mov     x1, #8080
    bl      sock_bind
    mov     x1, #0
    bl      assert_eq

    mov     x0, x20
    bl      sock_recv_byte
    mov     x1, #-1
    bl      assert_eq

    mov     x0, x19
    bl      sock_close
    mov     x0, x21
    mov     x1, #8080
    bl      sock_bind
    mov     x1, #1
    bl      assert_eq

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
