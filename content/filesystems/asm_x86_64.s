# Vidya — Filesystems in x86_64 Assembly
#
# File operations via Linux syscalls: open, write, read, close, unlink.
# Creates a temporary file, writes data, reads it back, verifies the
# content matches, then removes the file. This is the raw syscall
# interface that libc wraps — no abstraction, just registers and int 0x80
# (or syscall on x86_64).
#
# Build: as --64 asm_x86_64.s -o out.o && ld out.o -o out && ./out

.section .text
.globl _start

# ── Syscall numbers ──────────────────────────────────────────────────
.equ SYS_READ,   0
.equ SYS_WRITE,  1
.equ SYS_OPEN,   2
.equ SYS_CLOSE,  3
.equ SYS_LSEEK,  8
.equ SYS_EXIT,   60
.equ SYS_UNLINK, 87

# ── open() flags ─────────────────────────────────────────────────────
.equ O_RDONLY,    0x0000
.equ O_WRONLY,    0x0001
.equ O_RDWR,     0x0002
.equ O_CREAT,    0x0040
.equ O_TRUNC,    0x0200

# ── File mode ────────────────────────────────────────────────────────
.equ MODE_RW,    0644           # rw-r--r--

# ── lseek whence ─────────────────────────────────────────────────────
.equ SEEK_SET,   0

# ── Data constants ───────────────────────────────────────────────────
.equ WRITE_LEN,  13             # length of write_data

_start:
    # ── Step 1: Create and open file for writing ─────────────────────
    # open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644)
    mov     $SYS_OPEN, %rax
    lea     filepath(%rip), %rdi
    mov     $(O_WRONLY | O_CREAT | O_TRUNC), %rsi
    mov     $MODE_RW, %rdx
    syscall

    # Check open succeeded (fd >= 0)
    test    %rax, %rax
    js      fail
    mov     %rax, %r12             # save fd in callee-saved register

    # ── Step 2: Write data to file ───────────────────────────────────
    # write(fd, buf, len)
    mov     $SYS_WRITE, %rax
    mov     %r12, %rdi
    lea     write_data(%rip), %rsi
    mov     $WRITE_LEN, %rdx
    syscall

    # Verify all bytes were written
    cmp     $WRITE_LEN, %rax
    jne     fail_close

    # ── Step 3: Close the file ───────────────────────────────────────
    mov     $SYS_CLOSE, %rax
    mov     %r12, %rdi
    syscall
    test    %rax, %rax
    jnz     fail

    # ── Step 4: Reopen file for reading ──────────────────────────────
    mov     $SYS_OPEN, %rax
    lea     filepath(%rip), %rdi
    mov     $O_RDONLY, %rsi
    xor     %rdx, %rdx
    syscall

    test    %rax, %rax
    js      fail
    mov     %rax, %r12

    # ── Step 5: Read data back ───────────────────────────────────────
    # read(fd, buf, len)
    mov     $SYS_READ, %rax
    mov     %r12, %rdi
    lea     read_buf(%rip), %rsi
    mov     $WRITE_LEN, %rdx
    syscall

    # Verify correct number of bytes read
    cmp     $WRITE_LEN, %rax
    jne     fail_close

    # ── Step 6: Verify data matches ──────────────────────────────────
    # Compare write_data and read_buf byte by byte
    lea     write_data(%rip), %rsi
    lea     read_buf(%rip), %rdi
    mov     $WRITE_LEN, %rcx
    xor     %r13, %r13             # index = 0

verify_loop:
    cmp     %rcx, %r13
    je      verify_done
    movzbl  (%rsi, %r13), %eax
    movzbl  (%rdi, %r13), %edx
    cmp     %edx, %eax
    jne     fail_close
    inc     %r13
    jmp     verify_loop

verify_done:
    # ── Step 7: Close the file ───────────────────────────────────────
    mov     $SYS_CLOSE, %rax
    mov     %r12, %rdi
    syscall
    test    %rax, %rax
    jnz     fail

    # ── Step 8: Unlink (delete) the file ─────────────────────────────
    mov     $SYS_UNLINK, %rax
    lea     filepath(%rip), %rdi
    syscall
    test    %rax, %rax
    jnz     fail

    # ── Step 9: Verify file is gone (open should fail) ───────────────
    mov     $SYS_OPEN, %rax
    lea     filepath(%rip), %rdi
    mov     $O_RDONLY, %rsi
    xor     %rdx, %rdx
    syscall

    # Should return negative (ENOENT = -2)
    test    %rax, %rax
    jns     fail                   # if non-negative, file still exists

    # ── All passed ───────────────────────────────────────────────────
    mov     $SYS_WRITE, %rax
    mov     $1, %rdi
    lea     msg_pass(%rip), %rsi
    mov     $msg_len, %rdx
    syscall

    mov     $SYS_EXIT, %rax
    xor     %rdi, %rdi
    syscall

fail_close:
    # Close fd before failing
    mov     $SYS_CLOSE, %rax
    mov     %r12, %rdi
    syscall
    # Fall through to unlink attempt then fail
    mov     $SYS_UNLINK, %rax
    lea     filepath(%rip), %rdi
    syscall

fail:
    mov     $SYS_EXIT, %rax
    mov     $1, %rdi
    syscall

# ── Data ─────────────────────────────────────────────────────────────
.section .data
filepath:
    .asciz  "/tmp/vidya_fs_test.tmp"

write_data:
    .ascii  "Hello, vidya!\n"       # 13 bytes (no null needed for write)

read_buf:
    .skip   64                     # buffer for reading back

.section .rodata
msg_pass:
    .ascii "All filesystems examples passed.\n"
    msg_len = . - msg_pass
