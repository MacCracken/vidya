# Vidya — Memory Management in x86_64 Assembly
#
# At the assembly level, you see exactly where data lives: registers,
# stack, .data/.bss sections, or heap (via mmap/brk syscall). There
# is no allocator — you manage every byte. Stack grows down, heap grows
# up, and alignment matters for performance and correctness.

.intel_syntax noprefix
.global _start

.section .data
static_val: .quad 42            # initialized data in .data section

.section .rodata
msg_pass:   .ascii "All memory management examples passed.\n"
msg_len = . - msg_pass

.section .bss
bss_buf:    .skip 4096          # uninitialized data, zeroed by OS

.section .text

_start:
    # ── Register storage (fastest) ──────────────────────────────────
    mov     rax, 42
    mov     rbx, rax            # register-to-register: 0 latency
    cmp     rbx, 42
    jne     fail

    # ── Stack allocation (push/sub rsp) ─────────────────────────────
    # Allocate 32 bytes on stack
    sub     rsp, 32
    mov     qword ptr [rsp], 100        # local variable at [rsp]
    mov     qword ptr [rsp + 8], 200    # local variable at [rsp+8]
    cmp     qword ptr [rsp], 100
    jne     fail
    cmp     qword ptr [rsp + 8], 200
    jne     fail
    add     rsp, 32             # deallocate (restore stack pointer)

    # ── Stack frame with push/pop ───────────────────────────────────
    push    rbx                 # save callee-saved register
    mov     rbx, 99
    cmp     rbx, 99
    jne     fail
    pop     rbx                 # restore

    # ── Static data (.data section) ─────────────────────────────────
    cmp     qword ptr [static_val], 42
    jne     fail
    mov     qword ptr [static_val], 100 # writable
    cmp     qword ptr [static_val], 100
    jne     fail
    mov     qword ptr [static_val], 42  # restore

    # ── BSS: zero-initialized uninitialized data ────────────────────
    cmp     qword ptr [bss_buf], 0      # guaranteed zero
    jne     fail
    mov     qword ptr [bss_buf], 0xDEAD # write to it
    cmp     qword ptr [bss_buf], 0xDEAD
    jne     fail

    # ── Heap allocation via mmap ────────────────────────────────────
    # mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov     rax, 9              # sys_mmap
    xor     rdi, rdi            # addr = NULL (kernel chooses)
    mov     rsi, 4096           # length = 4096 bytes (one page)
    mov     rdx, 3              # prot = PROT_READ | PROT_WRITE
    mov     r10, 0x22           # flags = MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1              # fd = -1 (anonymous)
    xor     r9, r9              # offset = 0
    syscall

    # Check mmap succeeded (returns address, not negative)
    test    rax, rax
    js      fail
    mov     r12, rax            # save heap pointer in callee-saved reg

    # Write to heap memory
    mov     qword ptr [r12], 0xCAFE
    cmp     qword ptr [r12], 0xCAFE
    jne     fail

    # Write at end of page
    mov     qword ptr [r12 + 4088], 0xBEEF
    cmp     qword ptr [r12 + 4088], 0xBEEF
    jne     fail

    # Free heap memory with munmap
    mov     rax, 11             # sys_munmap
    mov     rdi, r12            # addr
    mov     rsi, 4096           # length
    syscall
    test    rax, rax
    jnz     fail                # munmap returns 0 on success

    # ── Stack alignment ─────────────────────────────────────────────
    # x86_64 ABI requires 16-byte stack alignment before call
    # The call instruction pushes 8 bytes (return address),
    # so stack must be 16-byte aligned BEFORE the call.
    mov     rax, rsp
    and     rax, 0xF            # check alignment
    # rsp should be 8-byte aligned here (after _start entry)

    # ── Memory ordering with mfence ─────────────────────────────────
    # Ensure all prior stores are visible before subsequent loads
    mov     qword ptr [bss_buf], 42
    mfence                      # full memory barrier
    cmp     qword ptr [bss_buf], 42
    jne     fail

    # ── LEA: address computation without memory access ──────────────
    # lea doesn't access memory — it computes the address
    lea     rax, [static_val]   # rax = address of static_val
    cmp     qword ptr [rax], 42
    jne     fail

    # LEA for arithmetic: rax = rbx*4 + 8 without using mul
    mov     rbx, 10
    lea     rax, [rbx * 4 + 8]
    cmp     rax, 48             # 10*4 + 8 = 48
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
