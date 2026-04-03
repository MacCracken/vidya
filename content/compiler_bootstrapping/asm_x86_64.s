; Compiler Bootstrapping — x86_64 Assembly
;
; This is what a seed compiler PRODUCES: a minimal program
; assembled from a higher-level source into raw machine code.
;
; The bootstrap chain for Cyrius:
;   1. Hand-written assembly seed (this level of code)
;   2. Seed compiles stage 0 (simple language → ELF)
;   3. Stage 0 compiles stage 1 (richer language → ELF)
;   4. Stage 1 compiles itself → self-hosting
;
; Build: nasm -f elf64 asm_x86_64.s -o boot.o && ld -o boot boot.o

section .text
global _start

; ── Stage demonstration: compute 10 + 32 = 42, print result, exit ──
; This is the kind of program a stage 0 compiler would emit.

_start:
    ; Load operands (stage 0: mov reg, imm)
    mov rdi, 10         ; first operand
    mov rsi, 32         ; second operand

    ; Compute (stage 0: add reg, reg)
    add rdi, rsi        ; rdi = 42

    ; Convert to ASCII digit(s) for display
    ; 42 = '4' (0x34) followed by '2' (0x32)
    mov rax, rdi
    push 0x0A           ; newline

    ; Extract digits (simple base-10 conversion)
    xor rcx, rcx        ; digit count
.digit_loop:
    xor rdx, rdx
    mov rbx, 10
    div rbx             ; rax = quotient, rdx = remainder
    add rdx, 0x30       ; ASCII '0'
    push rdx
    inc rcx
    test rax, rax
    jnz .digit_loop

    ; Print digits from stack
    mov r8, rcx          ; save digit count
    inc r8               ; +1 for newline
.print_loop:
    ; write(1, rsp, 1)
    mov rax, 1
    mov rdi, 1
    mov rsi, rsp
    mov rdx, 1
    syscall
    add rsp, 8           ; pop digit
    dec r8
    jnz .print_loop

    ; exit(42) — the computed value as exit code
    mov rax, 60
    mov rdi, 42
    syscall

; Key insight: this entire program could be emitted by a seed compiler
; that understands just: mov, add, xor, div, push, pop, inc, dec,
; test, jnz, syscall, and labels.
; That's exactly what cyrius-seed does.
