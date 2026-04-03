; Binary Formats — x86_64 Assembly Implementation
;
; The simplest possible ELF program, written in NASM.
; Prints "ELF!" and exits. No libc, no linker tricks.
;
; Build: nasm -f elf64 asm_x86_64.s -o elf.o && ld -o elf elf.o
; Or: nasm -f bin asm_x86_64.s -o elf (flat binary, self-contained ELF)
;
; This is what the Cyrius seed generates: pure syscall programs
; with no external dependencies.

section .text
global _start

_start:
    ; write(1, msg, 5)
    mov rax, 1          ; syscall number: write
    mov rdi, 1          ; fd: stdout
    lea rsi, [rel msg]  ; buf: address of message
    mov rdx, 5          ; len: 5 bytes
    syscall

    ; exit(0)
    mov rax, 60         ; syscall number: exit
    xor rdi, rdi        ; status: 0
    syscall

section .rodata
msg:
    db "ELF!", 0x0A     ; "ELF!\n"

; Linux x86_64 syscall ABI:
;   Number in RAX
;   Arguments: RDI, RSI, RDX, R10, R8, R9
;   Return value in RAX
;   Clobbers: RCX, R11
;
; Key syscalls for bootstrap tools:
;   0  = read(fd, buf, count)
;   1  = write(fd, buf, count)
;   2  = open(path, flags, mode)
;   3  = close(fd)
;   60 = exit(status)
