# Vidya — Compiler Bootstrapping in x86_64 Assembly
#
# This is what a seed compiler PRODUCES: a minimal program
# assembled from a higher-level source into raw machine code.
#
# The bootstrap chain for Cyrius:
#   1. Hand-written assembly seed (this level of code)
#   2. Seed compiles stage 0 (simple language -> ELF)
#   3. Stage 0 compiles stage 1 (richer language -> ELF)
#   4. Stage 1 compiles itself -> self-hosting
#
# Build: as --64 asm_x86_64.s -o boot.o && ld -o boot boot.o

.section .text
.globl _start

# Stage demonstration: compute 10 + 32 = 42, print result, exit
# This is the kind of program a stage 0 compiler would emit.

_start:
    # Load operands (stage 0: mov reg, imm)
    mov $10, %rdi           # first operand
    mov $32, %rsi           # second operand

    # Compute (stage 0: add reg, reg)
    add %rsi, %rdi          # rdi = 42

    # Convert to ASCII digit(s) for display
    # 42 = '4' (0x34) followed by '2' (0x32)
    mov %rdi, %rax
    push $0x0A              # newline

    # Extract digits (simple base-10 conversion)
    xor %rcx, %rcx          # digit count
.digit_loop:
    xor %rdx, %rdx
    mov $10, %rbx
    div %rbx                # rax = quotient, rdx = remainder
    add $0x30, %rdx         # ASCII '0'
    push %rdx
    inc %rcx
    test %rax, %rax
    jnz .digit_loop

    # Print digits from stack
    mov %rcx, %r8           # save digit count
    inc %r8                 # +1 for newline
.print_loop:
    # write(1, rsp, 1)
    mov $1, %rax
    mov $1, %rdi
    mov %rsp, %rsi
    mov $1, %rdx
    syscall
    add $8, %rsp            # pop digit
    dec %r8
    jnz .print_loop

    # exit(0) — success
    mov $60, %rax
    xor %rdi, %rdi
    syscall

# Key insight: this entire program could be emitted by a seed compiler
# that understands just: mov, add, xor, div, push, pop, inc, dec,
# test, jnz, syscall, and labels.
# That's exactly what cyrius-seed does.
