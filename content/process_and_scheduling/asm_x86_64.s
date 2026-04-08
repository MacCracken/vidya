# Vidya — Process and Scheduling in x86_64 Assembly
#
# Context save/restore: the fundamental operation behind process switching.
# A context switch saves all general-purpose registers and RSP for the
# current task, then loads the saved state of the next task. This file
# demonstrates the pattern with two simulated process contexts, switching
# between them and verifying register state is preserved.
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

# ── Process state constants ──────────────────────────────────────────
.equ STATE_READY,    0
.equ STATE_RUNNING,  1
.equ STATE_BLOCKED,  2
.equ STATE_ZOMBIE,   3

# ── Context frame layout (offsets into saved context) ────────────────
# We save 16 GP registers + RFLAGS = 17 quadwords = 136 bytes
.equ CTX_RAX,  0
.equ CTX_RBX,  8
.equ CTX_RCX,  16
.equ CTX_RDX,  24
.equ CTX_RSI,  32
.equ CTX_RDI,  40
.equ CTX_RBP,  48
.equ CTX_R8,   56
.equ CTX_R9,   64
.equ CTX_R10,  72
.equ CTX_R11,  80
.equ CTX_R12,  88
.equ CTX_R13,  96
.equ CTX_R14,  104
.equ CTX_R15,  112
.equ CTX_RFLAGS, 120
.equ CTX_RSP,  128
.equ CTX_SIZE, 136

_start:
    # ── Test 1: Save context to process A's context block ────────────
    # Load known values into all GP registers
    mov     $0x1111, %rax
    mov     $0x2222, %rbx
    mov     $0x3333, %rcx
    mov     $0x4444, %rdx
    mov     $0x5555, %rsi
    # rdi will hold the context pointer
    mov     $0x7777, %rbp
    mov     $0x8888, %r8
    mov     $0x9999, %r9
    mov     $0xAAAA, %r10
    mov     $0xBBBB, %r11
    mov     $0xCCCC, %r12
    mov     $0xDDDD, %r13
    mov     $0xEEEE, %r14
    mov     $0xFFFF, %r15

    # Save context (simulated — a real kernel would do this in the
    # interrupt handler or syscall path)
    lea     ctx_a(%rip), %rdi
    mov     %rax, CTX_RAX(%rdi)
    mov     %rbx, CTX_RBX(%rdi)
    mov     %rcx, CTX_RCX(%rdi)
    mov     %rdx, CTX_RDX(%rdi)
    mov     %rsi, CTX_RSI(%rdi)
    mov     %rbp, CTX_RBP(%rdi)
    mov     %r8,  CTX_R8(%rdi)
    mov     %r9,  CTX_R9(%rdi)
    mov     %r10, CTX_R10(%rdi)
    mov     %r11, CTX_R11(%rdi)
    mov     %r12, CTX_R12(%rdi)
    mov     %r13, CTX_R13(%rdi)
    mov     %r14, CTX_R14(%rdi)
    mov     %r15, CTX_R15(%rdi)
    pushfq
    pop     %rax
    mov     %rax, CTX_RFLAGS(%rdi)
    mov     %rsp, CTX_RSP(%rdi)

    # ── Test 2: Clobber all registers (simulate running process B) ───
    xor     %rax, %rax
    xor     %rbx, %rbx
    xor     %rcx, %rcx
    xor     %rdx, %rdx
    xor     %rsi, %rsi
    xor     %rbp, %rbp
    xor     %r8, %r8
    xor     %r9, %r9
    xor     %r10, %r10
    xor     %r11, %r11
    xor     %r12, %r12
    xor     %r13, %r13
    xor     %r14, %r14
    xor     %r15, %r15

    # ── Test 3: Restore context from process A's context block ───────
    lea     ctx_a(%rip), %rdi
    mov     CTX_RSP(%rdi), %rsp    # restore stack pointer first
    mov     CTX_RFLAGS(%rdi), %rax
    push    %rax
    popfq                          # restore flags
    mov     CTX_RAX(%rdi), %rax
    mov     CTX_RBX(%rdi), %rbx
    mov     CTX_RCX(%rdi), %rcx
    mov     CTX_RDX(%rdi), %rdx
    mov     CTX_RSI(%rdi), %rsi
    mov     CTX_RBP(%rdi), %rbp
    mov     CTX_R8(%rdi),  %r8
    mov     CTX_R9(%rdi),  %r9
    mov     CTX_R10(%rdi), %r10
    mov     CTX_R11(%rdi), %r11
    mov     CTX_R12(%rdi), %r12
    mov     CTX_R13(%rdi), %r13
    mov     CTX_R14(%rdi), %r14
    mov     CTX_R15(%rdi), %r15

    # ── Test 4: Verify all registers were restored correctly ─────────
    cmp     $0x1111, %rax
    jne     fail
    cmp     $0x2222, %rbx
    jne     fail
    cmp     $0x3333, %rcx
    jne     fail
    cmp     $0x4444, %rdx
    jne     fail
    cmp     $0x5555, %rsi
    jne     fail
    cmp     $0x7777, %rbp
    jne     fail
    cmp     $0x8888, %r8
    jne     fail
    cmp     $0x9999, %r9
    jne     fail
    cmp     $0xAAAA, %r10
    jne     fail
    cmp     $0xBBBB, %r11
    jne     fail
    cmp     $0xCCCC, %r12
    jne     fail
    cmp     $0xDDDD, %r13
    jne     fail
    cmp     $0xEEEE, %r14
    jne     fail
    cmp     $0xFFFF, %r15
    jne     fail

    # ── Test 5: Verify process state constants ───────────────────────
    mov     $STATE_READY, %eax
    test    %eax, %eax
    jnz     fail

    mov     $STATE_RUNNING, %eax
    cmp     $1, %eax
    jne     fail

    mov     $STATE_BLOCKED, %eax
    cmp     $2, %eax
    jne     fail

    mov     $STATE_ZOMBIE, %eax
    cmp     $3, %eax
    jne     fail

    # ── Test 6: Context size sanity ──────────────────────────────────
    mov     $CTX_SIZE, %eax
    cmp     $136, %eax
    jne     fail

    # ── All passed ───────────────────────────────────────────────────
    mov     $1, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $60, %rax
    xor     %rdi, %rdi
    syscall

fail:
    mov     $60, %rax
    mov     $1, %rdi
    syscall

# ── Context storage ──────────────────────────────────────────────────
.section .bss
ctx_a:  .skip CTX_SIZE             # Process A context block
ctx_b:  .skip CTX_SIZE             # Process B context block

.section .rodata
msg_pass:
    .ascii "All process and scheduling examples passed.\n"
    msg_len = . - msg_pass
