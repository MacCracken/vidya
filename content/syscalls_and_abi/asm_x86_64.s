# Vidya — Syscalls and ABI in x86_64 Assembly
#
# The System V AMD64 ABI defines how functions pass arguments, preserve
# registers, align the stack, and return values. Linux syscalls use a
# similar but distinct convention: syscall number in rax, arguments in
# rdi, rsi, rdx, r10, r8, r9 (note r10 replaces rcx, which is clobbered
# by the syscall instruction). This file demonstrates both conventions
# with real syscalls and a function call.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All syscalls and ABI examples passed.\n"
msg_len = . - msg_pass
msg_pid:    .ascii "getpid succeeded.\n"
pid_len = . - msg_pid

.section .data
.align 8
result_buf: .quad 0

.section .text

_start:
    # ── Syscall calling convention ──────────────────────────────────
    # Linux x86_64 syscall ABI:
    #   rax = syscall number
    #   rdi = arg1, rsi = arg2, rdx = arg3
    #   r10 = arg4, r8  = arg5, r9  = arg6
    #   Return value in rax (-errno on error)
    #   Clobbered: rcx (set to rip), r11 (set to rflags)
    #   Preserved: rbx, rbp, r12-r15, rsp

    # ── sys_getpid (syscall 39) — simplest syscall, no args ────────
    mov     rax, 39             # sys_getpid
    syscall
    # rax now contains our PID (always > 0)
    test    rax, rax
    jle     fail                # PID must be positive

    # Save PID for later verification
    mov     r12, rax

    # Call getpid again — must return same value
    mov     rax, 39
    syscall
    cmp     rax, r12
    jne     fail                # PID should be stable

    # ── sys_write (syscall 1) — demonstrates 3 argument syscall ────
    # write(fd=1, buf=msg_pid, count=pid_len)
    mov     rax, 1              # sys_write
    mov     rdi, 1              # fd = stdout
    lea     rsi, [msg_pid]      # buf = message pointer
    mov     rdx, pid_len        # count = message length
    syscall
    # Returns bytes written in rax
    cmp     rax, pid_len
    jne     fail                # should write all bytes

    # ── sys_getuid (syscall 102) — another no-arg syscall ──────────
    mov     rax, 102            # sys_getuid
    syscall
    # rax = uid (>= 0, usually 1000+ for regular users)
    # Just verify it didn't fail (no error return for getuid)
    mov     r13, rax            # save uid

    # ── sys_getgid (syscall 104) ───────────────────────────────────
    mov     rax, 104            # sys_getgid
    syscall
    mov     r14, rax            # save gid

    # ── Function calling convention (System V AMD64 ABI) ────────────
    # Integer arguments: rdi, rsi, rdx, rcx, r8, r9
    # Return value: rax (and rdx for 128-bit)
    # Caller-saved (volatile):  rax, rcx, rdx, rsi, rdi, r8-r11
    # Callee-saved (preserved): rbx, rbp, r12-r15, rsp
    # Stack must be 16-byte aligned BEFORE the call instruction
    #   (call pushes 8 bytes, so callee sees rsp % 16 == 8)

    # Demonstrate function call with arguments
    mov     rdi, 10             # arg1
    mov     rsi, 32             # arg2
    call    add_two_numbers
    cmp     rax, 42
    jne     fail

    # Demonstrate that callee-saved registers are preserved
    mov     rbx, 0xAAAA
    mov     rbp, 0xBBBB
    mov     r12, 0xCCCC
    mov     rdi, 100
    mov     rsi, 200
    call    add_with_callee_saves
    cmp     rax, 300
    jne     fail
    cmp     rbx, 0xAAAA         # must be preserved
    jne     fail
    cmp     rbp, 0xBBBB         # must be preserved
    jne     fail
    cmp     r12, 0xCCCC         # must be preserved
    jne     fail

    # ── Demonstrate r10 vs rcx in syscalls ──────────────────────────
    # Syscalls use r10 for arg4 because syscall clobbers rcx.
    # Function calls use rcx for arg4.
    # Example: sys_pread64(fd, buf, count, offset) uses r10 for offset
    # We'll just demonstrate the register difference conceptually:
    mov     rcx, 0xDEAD         # set rcx to known value
    mov     rax, 39             # sys_getpid (doesn't use rcx)
    syscall
    # After syscall, rcx is CLOBBERED (set to return rip)
    # This is why syscalls use r10 instead of rcx for arg4
    cmp     rcx, 0xDEAD
    je      fail                # rcx MUST have been clobbered

    # ── Demonstrate stack alignment for function calls ──────────────
    # At _start, the stack is 8-byte aligned (no return address).
    # Before calling a function, we need 16-byte alignment.
    # The call instruction pushes 8 bytes, so if rsp is 16-aligned
    # before call, the callee sees rsp % 16 == 8 — which is correct.
    #
    # If we need to call from a state where rsp isn't aligned:
    push    rax                 # align stack (now 16-byte aligned)
    mov     rdi, 5
    mov     rsi, 7
    call    add_two_numbers
    pop     rcx                 # restore stack
    cmp     rax, 12
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60             # sys_exit
    xor     rdi, rdi            # status = 0
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── add_two_numbers ─────────────────────────────────────────────────
# Args: rdi = a, rsi = b
# Returns: rax = a + b
# Leaf function — no frame needed, no callee-saved regs used
add_two_numbers:
    lea     rax, [rdi + rsi]
    ret

# ── add_with_callee_saves ───────────────────────────────────────────
# Args: rdi = a, rsi = b
# Returns: rax = a + b
# Demonstrates proper callee-saved register preservation
add_with_callee_saves:
    push    rbx                 # save callee-saved register
    push    r12                 # save another callee-saved register
    mov     rbx, rdi            # use callee-saved for local work
    mov     r12, rsi
    lea     rax, [rbx + r12]    # compute result
    pop     r12                 # restore in reverse order
    pop     rbx
    ret
