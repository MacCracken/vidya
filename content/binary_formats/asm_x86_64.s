# Vidya — Binary Formats in x86_64 Assembly
#
# The simplest possible ELF program in GNU as syntax.
# Prints "ELF!" and exits. No libc, no linker tricks.
#
# Build: as --64 asm_x86_64.s -o elf.o && ld -o elf elf.o
#
# This is what the Cyrius seed generates: pure syscall programs
# with no external dependencies.

.section .text
.globl _start

_start:
    # write(1, msg, 5)
    mov $1, %rax            # syscall number: write
    mov $1, %rdi            # fd: stdout
    lea msg(%rip), %rsi     # buf: address of message (RIP-relative)
    mov $5, %rdx            # len: 5 bytes
    syscall

    # exit(0)
    mov $60, %rax           # syscall number: exit
    xor %rdi, %rdi          # status: 0
    syscall

.section .rodata
msg:
    .ascii "ELF!\n"         # "ELF!\n"

# Linux x86_64 syscall ABI:
#   Number in RAX
#   Arguments: RDI, RSI, RDX, R10, R8, R9
#   Return value in RAX
#   Clobbers: RCX, R11
#
# Key syscalls for bootstrap tools:
#   0  = read(fd, buf, count)
#   1  = write(fd, buf, count)
#   2  = open(path, flags, mode)
#   3  = close(fd)
#   60 = exit(status)
