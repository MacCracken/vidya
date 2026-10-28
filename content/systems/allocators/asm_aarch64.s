// Vidya — Allocators in AArch64 Assembly
//
// A bump allocator is the simplest memory allocator: maintain a pointer,
// advance it for each allocation, never free individual allocations.
// This file implements one using the brk syscall (syscall 214 on AArch64).
//
// brk(addr):
//   addr = 0  -> returns current program break
//   addr != 0 -> sets program break to addr, returns new break
//   On error, returns the current break (unchanged)
//
// The program break is the end of the process data segment. Memory
// between the old and new break is usable heap space.
//
// AArch64 syscall 214 = brk (vs 12 on x86_64)

.global _start

.section .data
.align 8
heap_start:     .quad 0         // base of our heap (initial brk)
heap_current:   .quad 0         // bump pointer (next free byte)
heap_end:       .quad 0         // end of allocated heap (current brk)

.section .rodata
msg_pass:   .ascii "All allocator examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ════════════════════════════════════════════════════════════════
    // Initialize: get current program break
    // ════════════════════════════════════════════════════════════════
    mov     x8, #214            // sys_brk (AArch64)
    mov     x0, #0              // addr = 0 -> query current break
    svc     #0
    // x0 = current program break address
    cbz     x0, fail            // brk should return non-zero address

    adr     x1, heap_start
    str     x0, [x1]
    adr     x1, heap_current
    str     x0, [x1]
    adr     x1, heap_end
    str     x0, [x1]

    // ════════════════════════════════════════════════════════════════
    // Grow the heap by 4096 bytes (one page)
    // ════════════════════════════════════════════════════════════════
    mov     x1, #4096
    add     x0, x0, x1          // request: old break + 4096
    mov     x8, #214            // sys_brk
    svc     #0
    // x0 = new program break (should equal old + 4096)
    adr     x2, heap_start
    ldr     x1, [x2]
    add     x1, x1, #4096
    cmp     x0, x1
    b.lo    fail                // brk should have moved by 4096

    adr     x2, heap_end
    str     x0, [x2]            // update our heap end

    // ════════════════════════════════════════════════════════════════
    // Bump allocator: allocate 8 bytes
    // ════════════════════════════════════════════════════════════════
    mov     x0, #8              // size = 8 bytes
    bl      bump_alloc
    cbz     x0, fail            // allocation should succeed
    mov     x19, x0             // save pointer to allocation 1

    // Write to allocated memory
    mov     x1, #0xCAFE
    movk    x1, #0xBABE, lsl #16
    str     x1, [x19]
    ldr     x2, [x19]
    cmp     x2, x1
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // Allocate another 16 bytes (should be right after first)
    // ════════════════════════════════════════════════════════════════
    mov     x0, #16
    bl      bump_alloc
    cbz     x0, fail
    mov     x20, x0             // save pointer to allocation 2

    // Verify allocation 2 is after allocation 1
    add     x1, x19, #8         // alloc1 + size1
    cmp     x20, x1             // alloc2 should start here
    b.ne    fail

    // Write to second allocation (should not corrupt first)
    mov     x1, #0x1111
    str     x1, [x20]
    mov     x1, #0x2222
    str     x1, [x20, #8]
    // Verify first allocation is intact
    mov     x1, #0xCAFE
    movk    x1, #0xBABE, lsl #16
    ldr     x2, [x19]
    cmp     x2, x1
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // Aligned allocation: allocate 32 bytes with 16-byte alignment
    // ════════════════════════════════════════════════════════════════
    mov     x0, #32             // size
    mov     x1, #16             // alignment
    bl      bump_alloc_aligned
    cbz     x0, fail
    mov     x21, x0

    // Verify alignment: address & (align-1) must be 0
    tst     x21, #15            // mask with alignment - 1
    b.ne    fail                // must be 16-byte aligned

    // Write to aligned allocation
    mov     x1, #0xAA
    str     x1, [x21]
    mov     x1, #0xDD
    str     x1, [x21, #24]
    ldr     x1, [x21]
    cmp     x1, #0xAA
    b.ne    fail
    ldr     x1, [x21, #24]
    cmp     x1, #0xDD
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // Allocate many small chunks to test bump pointer advancement
    // ════════════════════════════════════════════════════════════════
    mov     x22, #0             // counter
.alloc_loop:
    cmp     x22, #100
    b.ge    .alloc_done
    mov     x0, #8
    bl      bump_alloc
    cbz     x0, fail
    str     x22, [x0]           // write index to each allocation
    add     x22, x22, #1
    b       .alloc_loop
.alloc_done:

    // Verify total allocated: bump pointer should have advanced
    adr     x0, heap_current
    ldr     x0, [x0]
    adr     x1, heap_start
    ldr     x1, [x1]
    sub     x0, x0, x1          // bytes used
    cmp     x0, #800            // at minimum 8+16+32+800 = 856 bytes
    b.lt    fail

    // ════════════════════════════════════════════════════════════════
    // Reset allocator (bulk free — the bump allocator's strength)
    // ════════════════════════════════════════════════════════════════
    bl      bump_reset
    adr     x0, heap_current
    ldr     x0, [x0]
    adr     x1, heap_start
    ldr     x1, [x1]
    cmp     x0, x1              // should be back to start
    b.ne    fail

    // Allocate again after reset — reuses the same memory
    mov     x0, #64
    bl      bump_alloc
    cbz     x0, fail
    adr     x1, heap_start
    ldr     x1, [x1]
    cmp     x0, x1              // should be at the very start
    b.ne    fail

    // ── Print success ─────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ════════════════════════════════════════════════════════════════════
// bump_alloc(size: u64) -> *mut u8
// Allocates `size` bytes from the bump allocator.
// Returns pointer in x0, or 0 on failure.
// Rounds up to 8-byte alignment (natural word alignment).
// ════════════════════════════════════════════════════════════════════
bump_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [x29, #16]

    // Round up size to 8-byte alignment
    add     x0, x0, #7
    and     x0, x0, #-8         // x0 = (size + 7) & ~7
    mov     x19, x0             // save aligned size

    adr     x1, heap_current
    ldr     x0, [x1]            // current pointer
    add     x2, x0, x19         // new_current = current + aligned_size

    // Check if we need to grow the heap
    adr     x3, heap_end
    ldr     x3, [x3]
    cmp     x2, x3
    b.ls    .bump_have_space

    // Grow heap: set brk to at least new_current, rounded up to page
    add     x4, x2, #4095
    and     x4, x4, #-4096      // round up to page boundary
    mov     x5, x0              // save current pointer
    mov     x6, x2              // save new_current
    mov     x0, x4
    mov     x8, #214            // sys_brk
    svc     #0
    cmp     x0, x6              // did we get enough?
    b.lo    .bump_oom
    adr     x3, heap_end
    str     x0, [x3]
    mov     x0, x5              // restore allocation pointer
    mov     x2, x6              // restore new_current

.bump_have_space:
    adr     x1, heap_current
    str     x2, [x1]            // advance bump pointer
    // x0 = pointer to allocated memory (old current)
    ldr     x19, [x29, #16]
    ldp     x29, x30, [sp], #32
    ret

.bump_oom:
    mov     x0, #0              // return NULL
    ldr     x19, [x29, #16]
    ldp     x29, x30, [sp], #32
    ret

// ════════════════════════════════════════════════════════════════════
// bump_alloc_aligned(size: u64, align: u64) -> *mut u8
// Allocates with specified alignment (must be power of 2).
// Args: x0 = size, x1 = alignment
// ════════════════════════════════════════════════════════════════════
bump_alloc_aligned:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [x29, #16]

    mov     x19, x0             // save size

    // Align the current pointer up to the requested alignment
    adr     x2, heap_current
    ldr     x0, [x2]
    sub     x3, x1, #1          // align - 1 (mask)
    add     x0, x0, x3           // current + (align - 1)
    mvn     x3, x3              // ~(align - 1)
    and     x0, x0, x3           // aligned_current
    str     x0, [x2]            // update heap_current

    mov     x0, x19             // pass original size
    ldr     x19, [x29, #16]
    ldp     x29, x30, [sp], #32
    b       bump_alloc          // tail call

// ════════════════════════════════════════════════════════════════════
// bump_reset() — reset allocator to start (bulk free)
// The hallmark of bump allocation: O(1) free of everything.
// ════════════════════════════════════════════════════════════════════
bump_reset:
    adr     x0, heap_start
    ldr     x0, [x0]
    adr     x1, heap_current
    str     x0, [x1]
    ret
