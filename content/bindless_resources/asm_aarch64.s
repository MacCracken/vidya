// Vidya — Bindless Resources in AArch64 Assembly
//
// In-memory descriptor table — slot 0 reserved as null sentinel,
// LIFO free list for reuse.
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state cached in x19+ across `bl`. 64-bit literals via `ldr =`.

.global _start

.equ TABLE_CAP, 64

.bss
.align 8
slots:        .skip 8 * TABLE_CAP
free_links:   .skip 8 * TABLE_CAP

.data
.align 8
next_id:      .quad 1
free_head:    .quad 0

.section .rodata
msg_pass:     .ascii "bindless_resources: 15/15 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

table_init:
    mov     x0, #1
    adrp    x1, next_id
    add     x1, x1, :lo12:next_id
    str     x0, [x1]
    mov     x0, #0
    adrp    x1, free_head
    add     x1, x1, :lo12:free_head
    str     x0, [x1]
    adrp    x1, slots
    add     x1, x1, :lo12:slots
    mov     x2, #TABLE_CAP
.ti_loop:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .ti_loop
    adrp    x1, free_links
    add     x1, x1, :lo12:free_links
    mov     x2, #TABLE_CAP
.ti_loop2:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .ti_loop2
    ret

// alloc_handle(x0=desc) -> x0 = id
alloc_handle:
    adrp    x1, free_head
    add     x1, x1, :lo12:free_head
    ldr     x2, [x1]
    cbz     x2, .ah_extend
    // Pop free_head
    adrp    x3, free_links
    add     x3, x3, :lo12:free_links
    ldr     x4, [x3, x2, lsl #3]
    str     x4, [x1]
    adrp    x3, slots
    add     x3, x3, :lo12:slots
    str     x0, [x3, x2, lsl #3]
    mov     x0, x2
    ret
.ah_extend:
    adrp    x1, next_id
    add     x1, x1, :lo12:next_id
    ldr     x2, [x1]
    cmp     x2, #TABLE_CAP
    b.ge    .ah_full
    add     x3, x2, #1
    str     x3, [x1]
    adrp    x3, slots
    add     x3, x3, :lo12:slots
    str     x0, [x3, x2, lsl #3]
    mov     x0, x2
    ret
.ah_full:
    mov     x0, #0
    ret

// lookup_handle(x0=id) -> x0
lookup_handle:
    cbz     x0, .lh_zero
    cmp     x0, #TABLE_CAP
    b.ge    .lh_zero
    adrp    x1, slots
    add     x1, x1, :lo12:slots
    ldr     x0, [x1, x0, lsl #3]
    ret
.lh_zero:
    mov     x0, #0
    ret

// update_handle(x0=id, x1=desc) -> x0
update_handle:
    cbz     x0, .uh_zero
    cmp     x0, #TABLE_CAP
    b.ge    .uh_zero
    adrp    x2, slots
    add     x2, x2, :lo12:slots
    str     x1, [x2, x0, lsl #3]
    mov     x0, #1
    ret
.uh_zero:
    mov     x0, #0
    ret

// free_handle(x0=id) -> x0
free_handle:
    cbz     x0, .fh_zero
    cmp     x0, #TABLE_CAP
    b.ge    .fh_zero
    adrp    x1, free_head
    add     x1, x1, :lo12:free_head
    ldr     x2, [x1]
    adrp    x3, free_links
    add     x3, x3, :lo12:free_links
    str     x2, [x3, x0, lsl #3]
    str     x0, [x1]
    adrp    x3, slots
    add     x3, x3, :lo12:slots
    mov     x4, #0
    str     x4, [x3, x0, lsl #3]
    mov     x0, #1
    ret
.fh_zero:
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
    bl      table_init

    // Test 1
    ldr     x0, =0x1111111111111111
    bl      alloc_handle
    mov     x19, x0               // id1
    mov     x1, #1
    bl      assert_eq

    ldr     x0, =0x2222222222222222
    bl      alloc_handle
    mov     x20, x0               // id2
    mov     x1, #2
    bl      assert_eq

    ldr     x0, =0x3333333333333333
    bl      alloc_handle
    mov     x21, x0               // id3
    mov     x1, #3
    bl      assert_eq

    // Test 2: slot 0
    mov     x0, #0
    bl      lookup_handle
    mov     x1, #0
    bl      assert_eq

    // Test 3: lookup
    mov     x0, x19
    bl      lookup_handle
    ldr     x1, =0x1111111111111111
    bl      assert_eq
    mov     x0, x20
    bl      lookup_handle
    ldr     x1, =0x2222222222222222
    bl      assert_eq
    mov     x0, x21
    bl      lookup_handle
    ldr     x1, =0x3333333333333333
    bl      assert_eq

    // Test 4: update id2
    mov     x0, x20
    ldr     x1, =0xAAAAAAAAAAAAAAAA
    bl      update_handle
    mov     x1, #1
    bl      assert_eq
    mov     x0, x20
    bl      lookup_handle
    ldr     x1, =0xAAAAAAAAAAAAAAAA
    bl      assert_eq
    mov     x0, x19
    bl      lookup_handle
    ldr     x1, =0x1111111111111111
    bl      assert_eq
    mov     x0, x21
    bl      lookup_handle
    ldr     x1, =0x3333333333333333
    bl      assert_eq

    // Test 5: free + alloc reuses
    mov     x0, x20
    bl      free_handle
    mov     x0, x20
    bl      lookup_handle
    mov     x1, #0
    bl      assert_eq
    ldr     x0, =0x4444444444444444
    bl      alloc_handle
    mov     x22, x0               // id4
    mov     x1, x20
    bl      assert_eq
    mov     x0, x22
    bl      lookup_handle
    ldr     x1, =0x4444444444444444
    bl      assert_eq

    // Test 6: exhaustion
    bl      table_init
    mov     x23, #1               // i (callee-saved)
.fill_loop:
    cmp     x23, #TABLE_CAP
    b.ge    .fill_done
    mov     x0, x23
    bl      alloc_handle
    add     x23, x23, #1
    b       .fill_loop
.fill_done:
    ldr     x0, =0xDEADBEEF
    bl      alloc_handle
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
