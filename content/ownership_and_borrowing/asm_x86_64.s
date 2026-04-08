# Vidya — Ownership and Borrowing in x86_64 Assembly
#
# Assembly has NO ownership model. Any register or memory location can
# be read or written by any instruction at any time. There is no borrow
# checker, no lifetime, no move semantics. Aliasing is the default —
# two pointers to the same data is just two registers holding the same
# address. Resource management (allocate/deallocate) is entirely manual:
# the programmer must pair every acquire with a release.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All ownership and borrowing examples passed.\n"
msg_len = . - msg_pass

.section .bss
# Simulated "heap" — a static buffer we manage manually
heap_block: .skip 64

.section .data
# Resource counter: tracks acquire/release for leak detection
resource_count: .long 0

.section .text

_start:
    # ── No ownership: any register can alias anything ──────────────
    # Load the same address into two different registers.
    # Both can read and write — no compiler prevents this.
    lea     rax, [heap_block]
    mov     rcx, rax            # rcx aliases rax — same pointer

    # Write through one "pointer"
    mov     dword ptr [rax], 42

    # Read through the other — sees the same value
    cmp     dword ptr [rcx], 42
    jne     fail

    # Write through the alias
    mov     dword ptr [rcx], 99

    # Original "pointer" sees the mutation — no ownership prevents this
    cmp     dword ptr [rax], 99
    jne     fail

    # ── Mutable aliasing: the thing Rust forbids ───────────────────
    # Two "mutable references" to overlapping memory — perfectly legal
    # in assembly, undefined behavior in safe Rust.
    lea     rsi, [heap_block]       # points to byte 0
    lea     rdi, [heap_block + 2]   # points to byte 2 (overlapping!)

    # Write a 4-byte value through rsi
    mov     dword ptr [rsi], 0x44332211

    # Read 4 bytes through rdi — overlaps bytes 2-5
    # Bytes at heap_block: 11 22 33 44
    # rdi reads from offset 2: 33 44 00 00
    mov     eax, dword ptr [rdi]
    cmp     ax, 0x4433              # low 2 bytes are 0x33, 0x44
    jne     fail

    # ── Manual resource management pattern ─────────────────────────
    # There is no RAII in assembly. You must manually pair acquire/release.
    # Forgetting to release = leak. Double release = corruption.

    # Acquire resource 1
    call    resource_acquire
    cmp     eax, 1              # count should be 1
    jne     fail

    # Acquire resource 2
    call    resource_acquire
    cmp     eax, 2              # count should be 2
    jne     fail

    # Release resource 2
    call    resource_release
    cmp     eax, 1              # count should be 1
    jne     fail

    # Release resource 1
    call    resource_release
    cmp     eax, 0              # count should be 0 — no leak
    jne     fail

    # ── Simulated allocate/use/deallocate cycle ────────────────────
    # This is the manual pattern that ownership automates.
    call    fake_alloc          # "allocate" — returns pointer in rax
    mov     rbx, rax            # save the "owned" pointer

    # Use the allocation
    mov     dword ptr [rbx], 0xDEADBEEF
    cmp     dword ptr [rbx], 0xDEADBEEF
    jne     fail

    # "Deallocate" — zero the memory (simulate cleanup)
    mov     rdi, rbx
    call    fake_dealloc

    # After dealloc, memory is zeroed — use-after-free reads zero
    # In real code this is a bug. Assembly won't stop you.
    cmp     dword ptr [rbx], 0
    jne     fail

    # ── Stack "ownership": push/pop discipline ─────────────────────
    # The stack is the closest thing assembly has to scoped ownership.
    # push = acquire stack space, pop = release it. LIFO ordering is
    # enforced by convention, not hardware.
    mov     rax, 111
    push    rax                 # "acquire" stack slot
    mov     rax, 222
    push    rax                 # "acquire" another

    pop     rcx                 # "release" in reverse order
    cmp     rcx, 222
    jne     fail

    pop     rcx                 # "release" first slot
    cmp     rcx, 111
    jne     fail

    # ── Move semantics: just a copy in assembly ────────────────────
    # In Rust, move invalidates the source. In assembly, mov just copies.
    # The "source" is still accessible — nothing prevents use-after-move.
    lea     rax, [heap_block]
    mov     dword ptr [rax], 77
    mov     rcx, rax            # "move" — but rax is still valid!
    cmp     dword ptr [rax], 77 # "use after move" — works fine in asm
    jne     fail
    cmp     dword ptr [rcx], 77
    jne     fail

    # ── Print success ──────────────────────────────────────────────
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

# ── resource_acquire() → eax: incremented count ───────────────────
resource_acquire:
    lea     rax, [resource_count]
    inc     dword ptr [rax]
    mov     eax, dword ptr [rax]
    ret

# ── resource_release() → eax: decremented count ───────────────────
resource_release:
    lea     rax, [resource_count]
    dec     dword ptr [rax]
    mov     eax, dword ptr [rax]
    ret

# ── fake_alloc() → rax: pointer to heap_block ─────────────────────
# In real code this would be brk/mmap. Here we return a static buffer.
fake_alloc:
    lea     rax, [heap_block]
    ret

# ── fake_dealloc(rdi=ptr) — zero 8 bytes at ptr ───────────────────
# Simulates cleanup. Real dealloc would return memory to the OS.
fake_dealloc:
    mov     qword ptr [rdi], 0
    ret
