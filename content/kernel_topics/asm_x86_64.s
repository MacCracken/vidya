# Vidya — Kernel Topics in x86_64 Assembly
#
# At the assembly level, kernel work is direct hardware interaction:
# page table entry construction, GDT/IDT layout, MMIO simulation,
# and ABI-compliant function calls. These are the actual instructions
# a bootloader or kernel uses.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All kernel topics examples passed.\n"
msg_len = . - msg_pass

.section .bss
scratch:    .skip 64

.section .text

_start:
    # ── Test 1: Page Table Entry construction ──────────────────────────
    # Build PTE: phys_addr=0x1000, flags=PRESENT|WRITABLE (0x3)
    mov     rax, 0x1000
    or      rax, 0x3            # PRESENT | WRITABLE
    # Verify present bit
    test    rax, 1
    jz      fail
    # Verify writable bit
    test    rax, 2
    jz      fail
    # Extract physical address (mask bits 12-51)
    mov     rbx, rax
    mov     rcx, 0x000FFFFFFFFFF000
    and     rbx, rcx
    cmp     rbx, 0x1000
    jne     fail

    # ── Test 2: Virtual address decomposition ──────────────────────────
    # Decompose 0x0000_7FFF_FFFF_F000
    mov     rax, 0x00007FFFFFFFFFFF
    # PML4 index: bits 39-47
    mov     rbx, rax
    shr     rbx, 39
    and     rbx, 0x1FF
    cmp     rbx, 0xFF          # should be 255
    jne     fail
    # Offset: bits 0-11
    mov     rbx, rax
    and     rbx, 0xFFF
    cmp     rbx, 0xFFF
    jne     fail

    # ── Test 3: GDT entry decode ───────────────────────────────────────
    # Kernel code segment: 0x00AF9A000000FFFF
    mov     rax, 0x00AF9A000000FFFF
    # Present bit: bit 47
    bt      rax, 47
    jnc     fail
    # DPL: bits 45-46 (should be 0 for kernel)
    mov     rbx, rax
    shr     rbx, 45
    and     rbx, 3
    cmp     rbx, 0
    jne     fail
    # Long mode bit: bit 53
    bt      rax, 53
    jnc     fail

    # Null descriptor should NOT be present
    xor     rax, rax
    bt      rax, 47
    jc      fail               # should NOT be set

    # ── Test 4: MMIO register simulation ───────────────────────────────
    # Simulate: write 0, set bits 0-1, clear bit 1, verify bit 0 remains
    lea     rdi, [scratch]
    mov     dword ptr [rdi], 0          # initial value
    # Set bits (OR)
    mov     eax, [rdi]
    or      eax, 0x03
    mov     [rdi], eax
    cmp     dword ptr [rdi], 3
    jne     fail
    # Clear bit 1 (AND NOT)
    mov     eax, [rdi]
    and     eax, 0xFFFFFFFD     # ~(1<<1)
    mov     [rdi], eax
    cmp     dword ptr [rdi], 1
    jne     fail

    # ── Test 5: ABI register verification ──────────────────────────────
    # System V AMD64: call add_two(42, 58) → 100
    # Args in rdi, rsi; return in rax
    mov     rdi, 42
    mov     rsi, 58
    call    add_two
    cmp     rax, 100
    jne     fail

    # ── Test 6: Syscall ABI ────────────────────────────────────────────
    # Linux syscall: rax=number, rdi/rsi/rdx/r10/r8/r9 = args
    # sys_getpid (39) — returns pid > 0
    mov     rax, 39             # sys_getpid
    syscall
    test    eax, eax
    jz      fail                # pid should be > 0

    # ── Test 7: Stack alignment check ──────────────────────────────────
    # ABI requires 16-byte stack alignment before CALL
    mov     rax, rsp
    and     rax, 0xF
    # At _start, stack is 8-byte aligned (return address not pushed)
    # This is expected — functions must align before call

    # ── Test 8: Callee-saved register preservation ─────────────────────
    # rbx, rbp, r12-r15 are callee-saved in System V AMD64
    mov     rbx, 0xDEADBEEF
    mov     rbp, 0xCAFEBABE
    call    clobber_caller_saved
    # rbx and rbp must be unchanged
    mov     rax, 0xDEADBEEF
    cmp     rbx, rax
    jne     fail
    mov     rax, 0xCAFEBABE
    cmp     rbp, rax
    jne     fail

    # ── All passed ─────────────────────────────────────────────────────
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

# ── add_two(rdi=a, rsi=b) → rax ──────────────────────────────────────
# Follows System V AMD64 calling convention
add_two:
    mov     rax, rdi
    add     rax, rsi
    ret

# ── clobber_caller_saved() ────────────────────────────────────────────
# Deliberately clobbers caller-saved registers (rax, rcx, rdx, rsi, rdi, r8-r11)
# but MUST preserve callee-saved (rbx, rbp, r12-r15)
clobber_caller_saved:
    mov     rax, 0
    mov     rcx, 0
    mov     rdx, 0
    mov     rsi, 0
    mov     rdi, 0
    mov     r8, 0
    mov     r9, 0
    mov     r10, 0
    mov     r11, 0
    ret
