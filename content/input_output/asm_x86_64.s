# Vidya — Input/Output in x86_64 Assembly
#
# All I/O at the lowest level is syscalls. Linux x86_64 syscalls:
# read (0), write (1), open (2), close (3). File descriptors are
# integers: 0=stdin, 1=stdout, 2=stderr. Everything is bytes.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All input/output examples passed.\n"
msg_len = . - msg_pass
hello:      .ascii "hello world\n"
hello_len = . - hello
path:       .asciz "/tmp/vidya_asm_io_test"

.section .bss
read_buf:   .skip 64

.section .text

_start:
    # ── sys_write: write to stdout (fd 1) ───────────────────────────
    mov     rax, 1              # sys_write
    mov     rdi, 1              # fd = stdout
    lea     rsi, [hello]
    mov     rdx, hello_len
    syscall
    cmp     rax, hello_len      # should return bytes written
    jne     fail

    # ── sys_open: create a file ─────────────────────────────────────
    # open(path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov     rax, 2              # sys_open
    lea     rdi, [path]
    mov     rsi, 0x241          # O_WRONLY(1) | O_CREAT(0x40) | O_TRUNC(0x200)
    mov     rdx, 0644           # permissions: rw-r--r--
    syscall
    test    rax, rax
    js      fail
    mov     r12, rax            # save fd

    # ── sys_write to file ───────────────────────────────────────────
    mov     rax, 1              # sys_write
    mov     rdi, r12            # fd = our file
    lea     rsi, [hello]
    mov     rdx, hello_len
    syscall
    cmp     rax, hello_len
    jne     fail

    # ── sys_close ───────────────────────────────────────────────────
    mov     rax, 3              # sys_close
    mov     rdi, r12
    syscall
    test    rax, rax
    jnz     fail

    # ── sys_open: read back ─────────────────────────────────────────
    mov     rax, 2              # sys_open
    lea     rdi, [path]
    mov     rsi, 0              # O_RDONLY
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      fail
    mov     r12, rax

    # ── sys_read ────────────────────────────────────────────────────
    mov     rax, 0              # sys_read
    mov     rdi, r12
    lea     rsi, [read_buf]
    mov     rdx, 64
    syscall
    cmp     rax, hello_len      # should read same number of bytes
    jne     fail

    # Verify content matches
    lea     rsi, [hello]
    lea     rdi, [read_buf]
    mov     rcx, hello_len
    call    memcmp
    test    eax, eax
    jnz     fail

    # ── sys_lseek: seek to beginning ────────────────────────────────
    mov     rax, 8              # sys_lseek
    mov     rdi, r12
    xor     rsi, rsi            # offset = 0
    xor     rdx, rdx            # SEEK_SET = 0
    syscall
    test    rax, rax            # should return 0 (new position)
    jnz     fail

    # ── sys_close ───────────────────────────────────────────────────
    mov     rax, 3
    mov     rdi, r12
    syscall

    # ── sys_unlink: delete the file ─────────────────────────────────
    mov     rax, 87             # sys_unlink
    lea     rdi, [path]
    syscall
    test    rax, rax
    jnz     fail

    # ── sys_write to stderr (fd 2) ──────────────────────────────────
    # stderr is always unbuffered
    mov     rax, 1
    mov     rdi, 2              # fd = stderr
    lea     rsi, [hello]
    mov     rdx, 1              # write 1 byte
    syscall
    cmp     rax, 1
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

memcmp:
    push    rsi
    push    rdi
    push    rcx
.mcmp_loop:
    test    rcx, rcx
    jz      .mcmp_eq
    mov     al, [rsi]
    cmp     al, [rdi]
    jne     .mcmp_ne
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     .mcmp_loop
.mcmp_ne:
    mov     eax, 1
    pop     rcx
    pop     rdi
    pop     rsi
    ret
.mcmp_eq:
    xor     eax, eax
    pop     rcx
    pop     rdi
    pop     rsi
    ret
