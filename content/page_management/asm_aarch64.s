// Vidya — Page Management in AArch64 Assembly
//
// In-memory simulation matching the cyrius reference's six-assertion
// test surface. .bss arenas back the page store: PAGES is one i64 per
// slot, FREE_NEXT is the next-page pointer for freed pages. HDR
// globals match the cyrius layout (H_PGCOUNT, H_FREEHEAD offsets).
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// - x0–x18 caller-saved across `bl`; cache loop state in x19–x28.
// - 64-bit immediates (MAGIC = 0x50415452) load via `ldr xN, =literal`.
// - `cmp xN, #imm` is 12-bit unsigned; small numbers (1, 2, 42) inline.

.global _start

.equ POOL_CAP, 64

.bss
.align 8
PAGES:        .skip 8 * POOL_CAP
FREE_NEXT:    .skip 8 * POOL_CAP

.data
.align 8
HDR_MAGIC:     .quad 0
HDR_PAGECOUNT: .quad 0
HDR_FREEHEAD:  .quad 0

.section .rodata
msg_pass:     .ascii "page_management: 6/6 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// hdr_init — zero header, set MAGIC + page_count=1
hdr_init:
    ldr     x0, =0x50415452
    adrp    x1, HDR_MAGIC
    add     x1, x1, :lo12:HDR_MAGIC
    str     x0, [x1]
    mov     x0, #1
    adrp    x1, HDR_PAGECOUNT
    add     x1, x1, :lo12:HDR_PAGECOUNT
    str     x0, [x1]
    mov     x0, #0
    adrp    x1, HDR_FREEHEAD
    add     x1, x1, :lo12:HDR_FREEHEAD
    str     x0, [x1]
    ret

// page_alloc -> x0 = newly-allocated page id
page_alloc:
    adrp    x1, HDR_FREEHEAD
    add     x1, x1, :lo12:HDR_FREEHEAD
    ldr     x0, [x1]
    cbz     x0, .pa_extend
    // x0 = old freehead; pop FREE_NEXT[x0] into freehead slot
    adrp    x2, FREE_NEXT
    add     x2, x2, :lo12:FREE_NEXT
    ldr     x3, [x2, x0, lsl #3]
    str     x3, [x1]
    ret
.pa_extend:
    adrp    x1, HDR_PAGECOUNT
    add     x1, x1, :lo12:HDR_PAGECOUNT
    ldr     x0, [x1]
    add     x2, x0, #1
    str     x2, [x1]
    // Zero the slot
    adrp    x3, PAGES
    add     x3, x3, :lo12:PAGES
    mov     x4, #0
    str     x4, [x3, x0, lsl #3]
    ret

// page_free(x0=num)
page_free:
    adrp    x1, HDR_FREEHEAD
    add     x1, x1, :lo12:HDR_FREEHEAD
    ldr     x2, [x1]
    adrp    x3, FREE_NEXT
    add     x3, x3, :lo12:FREE_NEXT
    str     x2, [x3, x0, lsl #3]
    str     x0, [x1]
    ret

// page_write(x0=num, x1=val)
page_write:
    adrp    x2, PAGES
    add     x2, x2, :lo12:PAGES
    str     x1, [x2, x0, lsl #3]
    ret

// page_read(x0=num) -> x0
page_read:
    adrp    x1, PAGES
    add     x1, x1, :lo12:PAGES
    ldr     x0, [x1, x0, lsl #3]
    ret

// fail_exit — write FAIL\n + exit(1)
fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64                // SYS_write
    svc     #0
    mov     x0, #1
    mov     x8, #93                // SYS_exit
    svc     #0

_start:
    bl      hdr_init

    // 1. magic ok — clobber-tolerant: reload from .data
    adrp    x19, HDR_MAGIC
    add     x19, x19, :lo12:HDR_MAGIC
    ldr     x0, [x19]
    ldr     x1, =0x50415452
    cmp     x0, x1
    b.ne    fail_exit

    // 2. pgcount starts at 1
    adrp    x19, HDR_PAGECOUNT
    add     x19, x19, :lo12:HDR_PAGECOUNT
    ldr     x0, [x19]
    cmp     x0, #1
    b.ne    fail_exit

    // 3. first alloc = 1
    bl      page_alloc
    mov     x19, x0               // callee-saved cache for p1
    cmp     x0, #1
    b.ne    fail_exit

    // 4. second alloc = 2
    bl      page_alloc
    mov     x20, x0               // callee-saved cache for p2
    cmp     x0, #2
    b.ne    fail_exit

    // 5. write 42 to p1, read back, verify == 42
    mov     x0, x19
    mov     x1, #42
    bl      page_write
    mov     x0, x19
    bl      page_read
    cmp     x0, #42
    b.ne    fail_exit

    // 6. free p2, alloc returns 2 (free list reuse)
    mov     x0, x20
    bl      page_free
    bl      page_alloc
    cmp     x0, #2
    b.ne    fail_exit

    // success
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
