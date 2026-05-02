// Vidya — Direct DRM GPU Compute in AArch64 Assembly
//
// In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

.global _start

.equ BO_CAP, 32
.equ VA_CAP, 32

.bss
.align 8
bo_size:      .skip 8 * BO_CAP
va_addr:      .skip 8 * VA_CAP
va_bo:        .skip 8 * VA_CAP

.data
.align 8
fd:            .quad 0
next_bo:       .quad 1
va_count:      .quad 0
next_seq:      .quad 1
completed_seq: .quad 0

.section .rodata
msg_pass:     .ascii "direct_drm_gpu_compute: 20/20 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// open_render_node -> x0 = 42
open_render_node:
    adrp    x0, fd
    add     x0, x0, :lo12:fd
    mov     x1, #42
    str     x1, [x0]
    mov     x0, #42
    ret

// gem_create(x0=size) -> x0
gem_create:
    adrp    x1, next_bo
    add     x1, x1, :lo12:next_bo
    ldr     x2, [x1]
    cmp     x2, #BO_CAP
    b.ge    .gc_zero
    add     x3, x2, #1
    str     x3, [x1]
    adrp    x3, bo_size
    add     x3, x3, :lo12:bo_size
    str     x0, [x3, x2, lsl #3]
    mov     x0, x2
    ret
.gc_zero:
    mov     x0, #0
    ret

// gem_destroy(x0=handle) -> x0
gem_destroy:
    cbz     x0, .gd_zero
    cmp     x0, #BO_CAP
    b.ge    .gd_zero
    adrp    x1, bo_size
    add     x1, x1, :lo12:bo_size
    ldr     x2, [x1, x0, lsl #3]
    cbz     x2, .gd_zero
    mov     x3, #0
    str     x3, [x1, x0, lsl #3]
    // Scan va_bo[] for matching handle
    adrp    x4, va_count
    add     x4, x4, :lo12:va_count
    ldr     x4, [x4]
    adrp    x5, va_bo
    add     x5, x5, :lo12:va_bo
    mov     x6, #0                // i
.gd_loop:
    cmp     x6, x4
    b.ge    .gd_done
    ldr     x7, [x5, x6, lsl #3]
    cmp     x7, x0
    b.ne    .gd_next
    str     x3, [x5, x6, lsl #3]  // x3 = 0
.gd_next:
    add     x6, x6, #1
    b       .gd_loop
.gd_done:
    mov     x0, #1
    ret
.gd_zero:
    mov     x0, #0
    ret

// gem_va_map(x0=handle, x1=va) -> x0
gem_va_map:
    cbz     x0, .gv_zero
    cmp     x0, #BO_CAP
    b.ge    .gv_zero
    adrp    x2, bo_size
    add     x2, x2, :lo12:bo_size
    ldr     x3, [x2, x0, lsl #3]
    cbz     x3, .gv_zero
    adrp    x2, va_count
    add     x2, x2, :lo12:va_count
    ldr     x3, [x2]
    cmp     x3, #VA_CAP
    b.ge    .gv_zero
    adrp    x4, va_addr
    add     x4, x4, :lo12:va_addr
    str     x1, [x4, x3, lsl #3]
    adrp    x4, va_bo
    add     x4, x4, :lo12:va_bo
    str     x0, [x4, x3, lsl #3]
    add     x3, x3, #1
    str     x3, [x2]
    mov     x0, #1
    ret
.gv_zero:
    mov     x0, #0
    ret

// va_lookup(x0=va) -> x0
va_lookup:
    adrp    x1, va_count
    add     x1, x1, :lo12:va_count
    ldr     x1, [x1]
    adrp    x2, va_addr
    add     x2, x2, :lo12:va_addr
    adrp    x3, va_bo
    add     x3, x3, :lo12:va_bo
    mov     x4, #0
.vl_loop:
    cmp     x4, x1
    b.ge    .vl_zero
    ldr     x5, [x2, x4, lsl #3]
    cmp     x5, x0
    b.ne    .vl_next
    ldr     x5, [x3, x4, lsl #3]
    cbz     x5, .vl_next
    mov     x0, x5
    ret
.vl_next:
    add     x4, x4, #1
    b       .vl_loop
.vl_zero:
    mov     x0, #0
    ret

// do_submit(x0=handle) -> x0
do_submit:
    cbz     x0, .ds_zero
    cmp     x0, #BO_CAP
    b.ge    .ds_zero
    adrp    x1, bo_size
    add     x1, x1, :lo12:bo_size
    ldr     x2, [x1, x0, lsl #3]
    cbz     x2, .ds_zero
    adrp    x1, next_seq
    add     x1, x1, :lo12:next_seq
    ldr     x0, [x1]
    add     x2, x0, #1
    str     x2, [x1]
    adrp    x1, completed_seq
    add     x1, x1, :lo12:completed_seq
    str     x0, [x1]
    ret
.ds_zero:
    mov     x0, #0
    ret

// syncobj_wait(x0=seq) -> x0
syncobj_wait:
    adrp    x1, completed_seq
    add     x1, x1, :lo12:completed_seq
    ldr     x1, [x1]
    cmp     x1, x0
    b.ge    .sw_one
    mov     x0, #0
    ret
.sw_one:
    mov     x0, #1
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
    bl      open_render_node
    cbz     x0, fail_exit

    mov     x0, #4096
    bl      gem_create
    mov     x19, x0
    mov     x1, #1
    bl      assert_eq

    mov     x0, #8192
    bl      gem_create
    mov     x20, x0
    mov     x1, #2
    bl      assert_eq

    mov     x0, #16384
    bl      gem_create
    mov     x21, x0
    mov     x1, #3
    bl      assert_eq

    mov     x0, x19
    mov     x1, #0x1000
    bl      gem_va_map
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    mov     x1, #0x2000
    bl      gem_va_map
    mov     x1, #1
    bl      assert_eq

    mov     x0, #0x1000
    bl      va_lookup
    mov     x1, x19
    bl      assert_eq
    mov     x0, #0x2000
    bl      va_lookup
    mov     x1, x20
    bl      assert_eq
    mov     x0, #0x9000
    bl      va_lookup
    mov     x1, #0
    bl      assert_eq

    mov     x0, #99
    mov     x1, #0x3000
    bl      gem_va_map
    mov     x1, #0
    bl      assert_eq
    mov     x0, #0
    mov     x1, #0x3000
    bl      gem_va_map
    mov     x1, #0
    bl      assert_eq

    mov     x0, x19
    bl      do_submit
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    bl      do_submit
    mov     x1, #2
    bl      assert_eq
    mov     x0, x21
    bl      do_submit
    mov     x1, #3
    bl      assert_eq

    mov     x0, #1
    bl      syncobj_wait
    mov     x1, #1
    bl      assert_eq
    mov     x0, #3
    bl      syncobj_wait
    mov     x1, #1
    bl      assert_eq
    mov     x0, #99
    bl      syncobj_wait
    mov     x1, #0
    bl      assert_eq

    mov     x0, x19
    bl      gem_destroy
    mov     x0, #0x1000
    bl      va_lookup
    mov     x1, #0
    bl      assert_eq

    mov     x0, x19
    bl      do_submit
    mov     x1, #0
    bl      assert_eq
    mov     x0, x20
    bl      do_submit
    mov     x1, #4
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
