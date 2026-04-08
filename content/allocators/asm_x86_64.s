# Vidya — Allocators in x86_64 Assembly
#
# A bump allocator is the simplest memory allocator: maintain a pointer,
# advance it for each allocation, never free individual allocations.
# This file implements one using the brk syscall (syscall 12).
#
# brk(addr):
#   addr = 0  → returns current program break
#   addr != 0 → sets program break to addr, returns new break
#   On error, returns the current break (unchanged)
#
# The program break is the end of the process data segment. Memory
# between the old and new break is usable heap space.

.intel_syntax noprefix
.global _start

.section .data
.align 8
heap_start:     .quad 0         # base of our heap (initial brk)
heap_current:   .quad 0         # bump pointer (next free byte)
heap_end:       .quad 0         # end of allocated heap (current brk)

.section .rodata
msg_pass:   .ascii "All allocator examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ════════════════════════════════════════════════════════════════
    # Initialize: get current program break
    # ════════════════════════════════════════════════════════════════
    mov     rax, 12             # sys_brk
    xor     rdi, rdi            # addr = 0 → query current break
    syscall
    # rax = current program break address
    test    rax, rax
    jz      fail                # brk should return non-zero address

    mov     [heap_start], rax
    mov     [heap_current], rax
    mov     [heap_end], rax

    # ════════════════════════════════════════════════════════════════
    # Grow the heap by 4096 bytes (one page)
    # ════════════════════════════════════════════════════════════════
    mov     rdi, rax
    add     rdi, 4096           # request: old break + 4096
    mov     rax, 12             # sys_brk
    syscall
    # rax = new program break (should equal old + 4096)
    mov     rcx, [heap_start]
    add     rcx, 4096
    cmp     rax, rcx
    jne     fail                # brk should have moved by 4096

    mov     [heap_end], rax     # update our heap end

    # ════════════════════════════════════════════════════════════════
    # Bump allocator: allocate 8 bytes
    # ════════════════════════════════════════════════════════════════
    mov     rdi, 8              # size = 8 bytes
    call    bump_alloc
    test    rax, rax
    jz      fail                # allocation should succeed
    mov     r12, rax            # save pointer to allocation 1

    # Write to allocated memory
    mov     rax, 0xCAFEBABE
    mov     [r12], rax
    cmp     [r12], rax
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # Allocate another 16 bytes (should be right after first)
    # ════════════════════════════════════════════════════════════════
    mov     rdi, 16
    call    bump_alloc
    test    rax, rax
    jz      fail
    mov     r13, rax            # save pointer to allocation 2

    # Verify allocation 2 is after allocation 1
    mov     rcx, r12
    add     rcx, 8              # alloc1 + size1
    cmp     r13, rcx            # alloc2 should start here
    jne     fail

    # Write to second allocation (should not corrupt first)
    mov     qword ptr [r13], 0x11111111
    mov     qword ptr [r13 + 8], 0x22222222
    mov     rax, 0xCAFEBABE
    cmp     [r12], rax          # first allocation intact
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # Aligned allocation: allocate 32 bytes with 16-byte alignment
    # ════════════════════════════════════════════════════════════════
    mov     rdi, 32             # size
    mov     rsi, 16             # alignment
    call    bump_alloc_aligned
    test    rax, rax
    jz      fail
    mov     r14, rax

    # Verify alignment: address & (align-1) must be 0
    mov     rcx, r14
    and     rcx, 15             # mask with alignment - 1
    test    rcx, rcx
    jnz     fail                # must be 16-byte aligned

    # Write to aligned allocation
    mov     qword ptr [r14], 0xAA
    mov     qword ptr [r14 + 8], 0xBB
    mov     qword ptr [r14 + 16], 0xCC
    mov     qword ptr [r14 + 24], 0xDD
    cmp     qword ptr [r14], 0xAA
    jne     fail
    cmp     qword ptr [r14 + 24], 0xDD
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # Allocate many small chunks to test bump pointer advancement
    # ════════════════════════════════════════════════════════════════
    mov     r15, 0              # counter
.alloc_loop:
    cmp     r15, 100
    jge     .alloc_done
    mov     rdi, 8
    call    bump_alloc
    test    rax, rax
    jz      fail
    mov     qword ptr [rax], r15    # write index to each allocation
    inc     r15
    jmp     .alloc_loop
.alloc_done:

    # Verify total allocated: 8 + 16 + padding + 32 + (100 * 8)
    # The bump pointer should have advanced substantially
    mov     rax, [heap_current]
    mov     rcx, [heap_start]
    sub     rax, rcx            # bytes used
    cmp     rax, 800            # at minimum 8+16+32+800 = 856 bytes
    jl      fail

    # ════════════════════════════════════════════════════════════════
    # Reset allocator (bulk free — the bump allocator's strength)
    # ════════════════════════════════════════════════════════════════
    call    bump_reset
    mov     rax, [heap_current]
    cmp     rax, [heap_start]   # should be back to start
    jne     fail

    # Allocate again after reset — reuses the same memory
    mov     rdi, 64
    call    bump_alloc
    test    rax, rax
    jz      fail
    cmp     rax, [heap_start]   # should be at the very start
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ════════════════════════════════════════════════════════════════════
# bump_alloc(size: u64) -> *mut u8
# Allocates `size` bytes from the bump allocator.
# Returns pointer in rax, or 0 on failure.
# No alignment guarantee beyond natural (8-byte) alignment.
# ════════════════════════════════════════════════════════════════════
bump_alloc:
    push    rbx
    mov     rbx, rdi            # save size

    # Round up size to 8-byte alignment (natural word alignment)
    add     rbx, 7
    and     rbx, -8             # rbx = (size + 7) & ~7

    mov     rax, [heap_current]
    mov     rcx, rax
    add     rcx, rbx            # new_current = current + aligned_size

    # Check if we need to grow the heap
    cmp     rcx, [heap_end]
    jbe     .bump_have_space

    # Grow heap: set brk to at least new_current, rounded up to page
    mov     rdi, rcx
    add     rdi, 4095
    and     rdi, -4096          # round up to page boundary
    push    rax                 # save current pointer
    push    rcx                 # save new_current
    mov     rax, 12             # sys_brk
    syscall
    pop     rcx
    pop     rdx                 # old current pointer
    cmp     rax, rcx            # did we get enough?
    jb      .bump_oom
    mov     [heap_end], rax
    mov     rax, rdx            # restore allocation pointer

.bump_have_space:
    mov     [heap_current], rcx # advance bump pointer
    # rax = pointer to allocated memory (old current)
    pop     rbx
    ret

.bump_oom:
    xor     eax, eax            # return NULL
    pop     rbx
    ret

# ════════════════════════════════════════════════════════════════════
# bump_alloc_aligned(size: u64, align: u64) -> *mut u8
# Allocates with specified alignment (must be power of 2).
# ════════════════════════════════════════════════════════════════════
bump_alloc_aligned:
    push    rbx
    push    r12
    mov     rbx, rdi            # size
    mov     r12, rsi            # alignment

    # Align the current pointer up to the requested alignment
    mov     rax, [heap_current]
    mov     rcx, r12
    dec     rcx                 # align - 1 (mask)
    add     rax, rcx            # current + (align - 1)
    not     rcx                 # ~(align - 1)
    and     rax, rcx            # aligned_current

    # Update heap_current to aligned position
    mov     [heap_current], rax

    # Now do a normal bump allocation
    pop     r12
    pop     rbx
    mov     rdi, rbx
    jmp     bump_alloc          # tail call

# ════════════════════════════════════════════════════════════════════
# bump_reset() — reset allocator to start (bulk free)
# The hallmark of bump allocation: O(1) free of everything.
# ════════════════════════════════════════════════════════════════════
bump_reset:
    mov     rax, [heap_start]
    mov     [heap_current], rax
    ret
