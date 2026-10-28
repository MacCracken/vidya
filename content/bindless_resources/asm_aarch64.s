// Vidya — Bindless Resources in AArch64 Assembly
//
// In-memory descriptor table — slot 0 reserved as null sentinel,
// LIFO free list for reuse.
//
// A handle is (generation << 8) | slot. Freeing a slot bumps its
// generation, so a handle kept after free_handle no longer resolves —
// even once the slot is reused — and a double free is rejected instead
// of making the free list point at itself (which would hand the same
// slot to two live allocations). Generation-0 handles are just 1, 2, 3...
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state cached in x19+ across `bl`. 64-bit literals via `ldr =`.

.global _start

.equ TABLE_CAP, 64

.bss
.align 8
slots:        .skip 8 * TABLE_CAP
free_links:   .skip 8 * TABLE_CAP
gens:         .skip 8 * TABLE_CAP     // current generation per slot
live:         .skip 8 * TABLE_CAP     // 1 while the slot is allocated

.data
.align 8
next_id:      .quad 1
free_head:    .quad 0

.section .rodata
msg_pass:     .ascii "bindless_resources: 17/17 ok\n"
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
    mov     x2, #(3 * TABLE_CAP)      // free_links + gens + live
.ti_loop2:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .ti_loop2
    ret

// live_index(x0=handle) -> x0 = slot, or 0 if the handle is invalid,
// freed, or stale (older generation). Clobbers x1-x3.
// The slot bound is unsigned (b.hs): with a signed b.ge a negative value
// would pass and index slots[-1], and free_links[-1] IS slots[63].
live_index:
    and     x1, x0, #0xFF             // slot
    lsr     x2, x0, #8                // generation
    cbz     x1, .li_bad
    cmp     x1, #TABLE_CAP
    b.hs    .li_bad
    adrp    x3, live
    add     x3, x3, :lo12:live
    ldr     x3, [x3, x1, lsl #3]
    cbz     x3, .li_bad               // freed, or never allocated
    adrp    x3, gens
    add     x3, x3, :lo12:gens
    ldr     x3, [x3, x1, lsl #3]
    cmp     x3, x2
    b.ne    .li_bad                   // stale handle from an older generation
    mov     x0, x1
    ret
.li_bad:
    mov     x0, #0
    ret

// alloc_handle(x0=desc) -> x0 = handle ((gen << 8) | slot), 0 if full
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
    b       .ah_take
.ah_extend:
    adrp    x1, next_id
    add     x1, x1, :lo12:next_id
    ldr     x2, [x1]
    cmp     x2, #TABLE_CAP
    b.ge    .ah_full
    add     x3, x2, #1
    str     x3, [x1]
.ah_take:                             // x2 = slot
    adrp    x3, slots
    add     x3, x3, :lo12:slots
    str     x0, [x3, x2, lsl #3]
    adrp    x3, live
    add     x3, x3, :lo12:live
    mov     x4, #1
    str     x4, [x3, x2, lsl #3]
    adrp    x3, gens
    add     x3, x3, :lo12:gens
    ldr     x4, [x3, x2, lsl #3]
    orr     x0, x2, x4, lsl #8        // handle = (gen << 8) | slot
    ret
.ah_full:
    mov     x0, #0
    ret

// lookup_handle(x0=handle) -> x0 = descriptor, 0 if not live
lookup_handle:
    stp     x29, x30, [sp, #-16]!
    bl      live_index
    cbz     x0, .lh_done
    adrp    x1, slots
    add     x1, x1, :lo12:slots
    ldr     x0, [x1, x0, lsl #3]
.lh_done:
    ldp     x29, x30, [sp], #16
    ret

// update_handle(x0=handle, x1=desc) -> x0 = 1 ok / 0 not live
update_handle:
    stp     x29, x30, [sp, #-32]!
    str     x1, [sp, #16]             // desc survives the call
    bl      live_index
    cbz     x0, .uh_done
    ldr     x1, [sp, #16]
    adrp    x2, slots
    add     x2, x2, :lo12:slots
    str     x1, [x2, x0, lsl #3]
    mov     x0, #1
.uh_done:
    ldp     x29, x30, [sp], #32
    ret

// free_handle(x0=handle) -> x0 = 1 freed / 0 rejected (invalid, stale,
// or already freed — a double free must not push the slot twice)
free_handle:
    stp     x29, x30, [sp, #-16]!
    bl      live_index
    cbz     x0, .fh_done
    adrp    x1, live
    add     x1, x1, :lo12:live
    str     xzr, [x1, x0, lsl #3]     // no longer live
    adrp    x1, gens
    add     x1, x1, :lo12:gens
    ldr     x2, [x1, x0, lsl #3]
    add     x2, x2, #1                // bump: every old handle goes stale
    str     x2, [x1, x0, lsl #3]
    adrp    x1, free_head
    add     x1, x1, :lo12:free_head
    ldr     x2, [x1]
    adrp    x3, free_links
    add     x3, x3, :lo12:free_links
    str     x2, [x3, x0, lsl #3]
    str     x0, [x1]
    adrp    x3, slots
    add     x3, x3, :lo12:slots
    str     xzr, [x3, x0, lsl #3]
    mov     x0, #1
.fh_done:
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
    mov     x22, x0               // id4: same slot as id2, next generation
    mov     x1, #((1 << 8) | 2)
    bl      assert_eq
    mov     x0, x22
    bl      lookup_handle
    ldr     x1, =0x4444444444444444
    bl      assert_eq
    // the stale id2 must NOT resolve to id4's descriptor
    mov     x0, x20
    bl      lookup_handle
    mov     x1, #0
    bl      assert_eq
    // and freeing id2 again (a double free) is rejected
    mov     x0, x20
    bl      free_handle
    mov     x1, #0
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
