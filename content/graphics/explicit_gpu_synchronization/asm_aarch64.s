// Vidya — Explicit GPU Synchronization in AArch64 Assembly
//
// Timeline semaphores in .data globals.

.global _start

.data
.align 8
sem_compute:  .quad 0
sem_transfer: .quad 0

.section .rodata
msg_pass:     .ascii "explicit_gpu_synchronization: 19/19 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

sem_reset:
    mov     x0, #0
    adrp    x1, sem_compute
    add     x1, x1, :lo12:sem_compute
    str     x0, [x1]
    adrp    x1, sem_transfer
    add     x1, x1, :lo12:sem_transfer
    str     x0, [x1]
    ret

// do_signal(x0=sem, x1=value) -> x0
do_signal:
    cbnz    x0, .ds_t
    adrp    x2, sem_compute
    add     x2, x2, :lo12:sem_compute
    ldr     x3, [x2]
    cmp     x1, x3
    b.le    .ds_zero
    str     x1, [x2]
    mov     x0, #1
    ret
.ds_t:
    cmp     x0, #1
    b.ne    .ds_zero
    adrp    x2, sem_transfer
    add     x2, x2, :lo12:sem_transfer
    ldr     x3, [x2]
    cmp     x1, x3
    b.le    .ds_zero
    str     x1, [x2]
    mov     x0, #1
    ret
.ds_zero:
    mov     x0, #0
    ret

// do_wait_for(x0=sem, x1=target) -> x0
do_wait_for:
    cbnz    x0, .dw_t
    adrp    x2, sem_compute
    add     x2, x2, :lo12:sem_compute
    ldr     x3, [x2]
    cmp     x3, x1
    b.ge    .dw_one
    b       .dw_zero
.dw_t:
    cmp     x0, #1
    b.ne    .dw_zero
    adrp    x2, sem_transfer
    add     x2, x2, :lo12:sem_transfer
    ldr     x3, [x2]
    cmp     x3, x1
    b.ge    .dw_one
.dw_zero:
    mov     x0, #0
    ret
.dw_one:
    mov     x0, #1
    ret

// do_wait_all(x0=c, x1=t) -> x0
// Cache targets + cok in callee-saved across the two do_wait_for calls.
do_wait_all:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    mov     x19, x0               // c_target
    mov     x20, x1               // t_target
    mov     x0, #0
    mov     x1, x19
    bl      do_wait_for
    mov     x21, x0               // cok
    mov     x0, #1
    mov     x1, x20
    bl      do_wait_for
    cbz     x21, .da_zero
    cbz     x0, .da_zero
    mov     x0, #1
    b       .da_done
.da_zero:
    mov     x0, #0
.da_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
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
    // 1. init
    adrp    x0, sem_compute
    add     x0, x0, :lo12:sem_compute
    ldr     x0, [x0]
    mov     x1, #0
    bl      assert_eq
    adrp    x0, sem_transfer
    add     x0, x0, :lo12:sem_transfer
    ldr     x0, [x0]
    mov     x1, #0
    bl      assert_eq
    mov     x0, #0
    mov     x1, #0
    bl      do_wait_for
    mov     x1, #1
    bl      assert_eq

    // 2. signal advances
    mov     x0, #0
    mov     x1, #5
    bl      do_signal
    mov     x1, #1
    bl      assert_eq
    adrp    x0, sem_compute
    add     x0, x0, :lo12:sem_compute
    ldr     x0, [x0]
    mov     x1, #5
    bl      assert_eq

    // 3. past, current, future
    mov     x0, #0
    mov     x1, #3
    bl      do_wait_for
    mov     x1, #1
    bl      assert_eq
    mov     x0, #0
    mov     x1, #5
    bl      do_wait_for
    mov     x1, #1
    bl      assert_eq
    mov     x0, #0
    mov     x1, #10
    bl      do_wait_for
    mov     x1, #0
    bl      assert_eq

    // 4. regression rejected
    mov     x0, #0
    mov     x1, #3
    bl      do_signal
    mov     x1, #0
    bl      assert_eq
    adrp    x0, sem_compute
    add     x0, x0, :lo12:sem_compute
    ldr     x0, [x0]
    mov     x1, #5
    bl      assert_eq
    mov     x0, #0
    mov     x1, #5
    bl      do_signal
    mov     x1, #0
    bl      assert_eq

    // 5. multi-sem
    mov     x0, #1
    mov     x1, #3
    bl      do_signal
    adrp    x0, sem_transfer
    add     x0, x0, :lo12:sem_transfer
    ldr     x0, [x0]
    mov     x1, #3
    bl      assert_eq
    mov     x0, #5
    mov     x1, #3
    bl      do_wait_all
    mov     x1, #1
    bl      assert_eq
    mov     x0, #5
    mov     x1, #4
    bl      do_wait_all
    mov     x1, #0
    bl      assert_eq
    mov     x0, #6
    mov     x1, #3
    bl      do_wait_all
    mov     x1, #0
    bl      assert_eq
    mov     x0, #0
    mov     x1, #0
    bl      do_wait_all
    mov     x1, #1
    bl      assert_eq

    // 6. monotonic
    bl      sem_reset
    mov     x19, #1
.ml:
    cmp     x19, #10
    b.gt    .ml_done
    mov     x0, #0
    mov     x1, x19
    bl      do_signal
    add     x19, x19, #1
    b       .ml
.ml_done:
    adrp    x0, sem_compute
    add     x0, x0, :lo12:sem_compute
    ldr     x0, [x0]
    mov     x1, #10
    bl      assert_eq
    mov     x0, #0
    mov     x1, #10
    bl      do_wait_for
    mov     x1, #1
    bl      assert_eq
    mov     x0, #0
    mov     x1, #11
    bl      do_wait_for
    mov     x1, #0
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
