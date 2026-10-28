// Vidya — IPC in AArch64 Assembly
//
// Asm port: shm + pipe + channel state machines, 8 critical asserts.

.global _start

.equ SHM_REGION_CAP, 4
.equ SHM_BYTES,      64
.equ PIPE_CAP,       8
.equ CHAN_CAP,       4
.equ CHAN_QUEUE_CAP, 8

.bss
.align 8
shm:          .skip SHM_REGION_CAP * SHM_BYTES
pipe_buf:     .skip PIPE_CAP
chan_open:    .skip CHAN_CAP * 8
chan_queue:   .skip CHAN_CAP * CHAN_QUEUE_CAP * 8
chan_count:   .skip CHAN_CAP * 8

.data
.align 8
pipe_head:    .quad 0
pipe_count:   .quad 0

.section .rodata
msg_pass:     .ascii "ipc: 8/8 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// shm_write(x0=region, x1=offset, x2=byte) -> x0
shm_write:
    cmp     x0, #0
    b.lt    .sw_zero
    cmp     x0, #SHM_REGION_CAP
    b.ge    .sw_zero
    cmp     x1, #0
    b.lt    .sw_zero
    cmp     x1, #SHM_BYTES
    b.ge    .sw_zero
    mov     x3, #SHM_BYTES
    mul     x3, x0, x3
    add     x3, x3, x1
    adrp    x4, shm
    add     x4, x4, :lo12:shm
    strb    w2, [x4, x3]
    mov     x0, #1
    ret
.sw_zero:
    mov     x0, #0
    ret

// shm_read(x0=region, x1=offset) -> x0
shm_read:
    cmp     x0, #0
    b.lt    .sr_neg
    cmp     x0, #SHM_REGION_CAP
    b.ge    .sr_neg
    cmp     x1, #0
    b.lt    .sr_neg
    cmp     x1, #SHM_BYTES
    b.ge    .sr_neg
    mov     x2, #SHM_BYTES
    mul     x2, x0, x2
    add     x2, x2, x1
    adrp    x3, shm
    add     x3, x3, :lo12:shm
    ldrb    w0, [x3, x2]
    ret
.sr_neg:
    mov     x0, #-1
    ret

// pipe_write(x0=byte) -> x0
pipe_write:
    adrp    x1, pipe_count
    add     x1, x1, :lo12:pipe_count
    ldr     x2, [x1]
    cmp     x2, #PIPE_CAP
    b.ge    .pw_zero
    adrp    x3, pipe_head
    add     x3, x3, :lo12:pipe_head
    ldr     x4, [x3]
    add     x4, x4, x2
    cmp     x4, #PIPE_CAP
    b.lt    .pw_store
    sub     x4, x4, #PIPE_CAP
.pw_store:
    adrp    x5, pipe_buf
    add     x5, x5, :lo12:pipe_buf
    strb    w0, [x5, x4]
    add     x2, x2, #1
    str     x2, [x1]
    mov     x0, #1
    ret
.pw_zero:
    mov     x0, #0
    ret

// pipe_read -> x0
pipe_read:
    adrp    x1, pipe_count
    add     x1, x1, :lo12:pipe_count
    ldr     x2, [x1]
    cbz     x2, .pr_neg
    adrp    x3, pipe_head
    add     x3, x3, :lo12:pipe_head
    ldr     x4, [x3]
    adrp    x5, pipe_buf
    add     x5, x5, :lo12:pipe_buf
    ldrb    w0, [x5, x4]
    add     x4, x4, #1
    cmp     x4, #PIPE_CAP
    b.lt    .pr_set_head
    mov     x4, #0
.pr_set_head:
    str     x4, [x3]
    sub     x2, x2, #1
    str     x2, [x1]
    ret
.pr_neg:
    mov     x0, #-1
    ret

// chan_listen(x0=endpoint) -> x0
chan_listen:
    cmp     x0, #0
    b.lt    .cl_zero
    cmp     x0, #CHAN_CAP
    b.ge    .cl_zero
    adrp    x1, chan_open
    add     x1, x1, :lo12:chan_open
    mov     x2, #1
    str     x2, [x1, x0, lsl #3]
    mov     x0, #1
    ret
.cl_zero:
    mov     x0, #0
    ret

// chan_send(x0=dst, x1=msg) -> x0
chan_send:
    cmp     x0, #0
    b.lt    .cs_zero
    cmp     x0, #CHAN_CAP
    b.ge    .cs_zero
    adrp    x2, chan_open
    add     x2, x2, :lo12:chan_open
    ldr     x3, [x2, x0, lsl #3]
    cmp     x3, #1
    b.ne    .cs_zero
    adrp    x2, chan_count
    add     x2, x2, :lo12:chan_count
    ldr     x3, [x2, x0, lsl #3]
    cmp     x3, #CHAN_QUEUE_CAP
    b.ge    .cs_zero
    mov     x4, #CHAN_QUEUE_CAP
    mul     x4, x0, x4
    add     x4, x4, x3
    adrp    x5, chan_queue
    add     x5, x5, :lo12:chan_queue
    str     x1, [x5, x4, lsl #3]
    add     x3, x3, #1
    str     x3, [x2, x0, lsl #3]
    mov     x0, #1
    ret
.cs_zero:
    mov     x0, #0
    ret

// chan_recv(x0=endpoint) -> x0
chan_recv:
    cmp     x0, #0
    b.lt    .cr_neg
    cmp     x0, #CHAN_CAP
    b.ge    .cr_neg
    adrp    x1, chan_open
    add     x1, x1, :lo12:chan_open
    ldr     x2, [x1, x0, lsl #3]
    cmp     x2, #1
    b.ne    .cr_neg
    adrp    x1, chan_count
    add     x1, x1, :lo12:chan_count
    ldr     x2, [x1, x0, lsl #3]
    cbz     x2, .cr_neg
    mov     x3, #CHAN_QUEUE_CAP
    mul     x3, x0, x3
    adrp    x4, chan_queue
    add     x4, x4, :lo12:chan_queue
    ldr     x5, [x4, x3, lsl #3]      // first msg
    // Shift queue down
    sub     x6, x2, #1
    mov     x7, #0                    // k
.cv_shift:
    cmp     x7, x6
    b.ge    .cv_shift_done
    add     x8, x3, x7
    add     x8, x8, #1
    ldr     x9, [x4, x8, lsl #3]
    add     x8, x3, x7
    str     x9, [x4, x8, lsl #3]
    add     x7, x7, #1
    b       .cv_shift
.cv_shift_done:
    sub     x2, x2, #1
    str     x2, [x1, x0, lsl #3]
    mov     x0, x5
    ret
.cr_neg:
    mov     x0, #-1
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
    // 1. shm write/read
    mov     x0, #1
    mov     x1, #5
    mov     x2, #0xA1
    bl      shm_write
    mov     x1, #1
    bl      assert_eq
    mov     x0, #1
    mov     x1, #5
    bl      shm_read
    mov     x1, #0xA1
    bl      assert_eq

    // 2. shm OOB rejected
    mov     x0, #1
    mov     x1, #99
    mov     x2, #0xFF
    bl      shm_write
    mov     x1, #0
    bl      assert_eq

    // 3. pipe FIFO
    mov     x0, #65
    bl      pipe_write
    mov     x0, #66
    bl      pipe_write
    mov     x0, #67
    bl      pipe_write
    bl      pipe_read
    mov     x1, #65
    bl      assert_eq

    // 4. pipe drain to empty
    bl      pipe_read
    bl      pipe_read
    bl      pipe_read
    mov     x1, #-1
    bl      assert_eq

    // 5. send to closed → 0
    mov     x0, #1
    ldr     x1, =0xCAFE
    bl      chan_send
    mov     x1, #0
    bl      assert_eq

    // 6. listen + send + recv
    mov     x0, #1
    bl      chan_listen
    mov     x0, #1
    ldr     x1, =0xCAFE
    bl      chan_send
    mov     x0, #1
    ldr     x1, =0xBABE
    bl      chan_send
    mov     x0, #1
    bl      chan_recv
    ldr     x1, =0xCAFE
    bl      assert_eq
    mov     x0, #1
    bl      chan_recv
    ldr     x1, =0xBABE
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
