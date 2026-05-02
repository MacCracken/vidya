// Vidya — GPU Memory Pooling in AArch64 Assembly
//
// Bump allocator over a 1024-byte pool.

.global _start

.equ POOL_SIZE, 1024

.bss
.align 8
pool:         .skip POOL_SIZE

.data
.align 8
bump:         .quad 0

.section .rodata
msg_pass:     .ascii "gpu_memory_pooling: 16/16 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

pool_reset:
    adrp    x0, bump
    add     x0, x0, :lo12:bump
    mov     x1, #0
    str     x1, [x0]
    ret

pool_used:
    adrp    x0, bump
    add     x0, x0, :lo12:bump
    ldr     x0, [x0]
    ret

pool_free:
    adrp    x0, bump
    add     x0, x0, :lo12:bump
    ldr     x1, [x0]
    mov     x0, #POOL_SIZE
    sub     x0, x0, x1
    ret

// pool_alloc(x0=size) -> x0
pool_alloc:
    cbz     x0, .pa_noop
    adrp    x1, bump
    add     x1, x1, :lo12:bump
    ldr     x2, [x1]
    add     x3, x2, x0
    cmp     x3, #POOL_SIZE
    b.gt    .pa_full
    str     x3, [x1]
    mov     x0, x2
    ret
.pa_noop:
    adrp    x1, bump
    add     x1, x1, :lo12:bump
    ldr     x0, [x1]
    ret
.pa_full:
    mov     x0, #-1
    ret

// pool_alloc_aligned(x0=size, x1=align) -> x0
pool_alloc_aligned:
    sub     x2, x1, #1            // mask
    adrp    x3, bump
    add     x3, x3, :lo12:bump
    ldr     x4, [x3]
    add     x4, x4, x2
    bic     x4, x4, x2            // aligned = (bump + mask) & ~mask
    add     x5, x4, x0
    cmp     x5, #POOL_SIZE
    b.gt    .paa_full
    str     x5, [x3]
    mov     x0, x4
    ret
.paa_full:
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
    bl      pool_used
    mov     x1, #0
    bl      assert_eq
    bl      pool_free
    mov     x1, #1024
    bl      assert_eq

    mov     x0, #100
    bl      pool_alloc
    mov     x1, #0
    bl      assert_eq
    bl      pool_used
    mov     x1, #100
    bl      assert_eq

    mov     x0, #200
    bl      pool_alloc
    mov     x1, #100
    bl      assert_eq
    bl      pool_used
    mov     x1, #300
    bl      assert_eq

    mov     x0, #1000
    bl      pool_alloc
    mov     x1, #-1
    bl      assert_eq
    bl      pool_used
    mov     x1, #300
    bl      assert_eq

    bl      pool_reset
    bl      pool_used
    mov     x1, #0
    bl      assert_eq
    bl      pool_free
    mov     x1, #1024
    bl      assert_eq
    mov     x0, #50
    bl      pool_alloc
    mov     x1, #0
    bl      assert_eq

    mov     x0, #32
    mov     x1, #16
    bl      pool_alloc_aligned
    mov     x1, #64
    bl      assert_eq
    bl      pool_used
    mov     x1, #96
    bl      assert_eq

    mov     x0, #0
    bl      pool_alloc
    mov     x1, #96
    bl      assert_eq
    bl      pool_used
    mov     x1, #96
    bl      assert_eq

    bl      pool_reset
    mov     x19, #0               // i (callee-saved)
.tens_loop:
    cmp     x19, #10
    b.ge    .tens_done
    mov     x0, #8
    bl      pool_alloc
    add     x19, x19, #1
    b       .tens_loop
.tens_done:
    bl      pool_used
    mov     x1, #80
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
