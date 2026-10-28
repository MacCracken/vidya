# Vidya — Concurrent File Access (flock) in x86_64 Assembly
#
# Single-process exercise via two opens of the same file. flock is
# per-OPEN; each fd has independent lock state. Direct syscalls:
#   SYS_OPEN   = 2
#   SYS_CLOSE  = 3
#   SYS_WRITE  = 1
#   SYS_READ   = 0
#   SYS_LSEEK  = 8
#   SYS_FLOCK  = 73
#   SYS_UNLINK = 87
# Lock op constants: LOCK_SH=1, LOCK_EX=2, LOCK_UN=8, LOCK_NB=4.
# Returns: 0 on success, negative errno on failure.

.intel_syntax noprefix
.global _start

.section .data
path:         .asciz "/tmp/vidya_cfa_x86.bin"
write_data:   .quad 0xDEADBEEF12345678
.equ data_len, 8

.section .bss
.align 8
read_buf:     .skip 8
fd1:          .skip 8
fd2:          .skip 8

.section .rodata
msg_pass:     .ascii "concurrent_file_access: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# open_rw(rdi=path) -> rax = fd
open_rw:
    mov     rsi, 66                # O_RDWR | O_CREAT
    mov     rdx, 420               # 0644
    mov     rax, 2                 # SYS_OPEN
    syscall
    ret

# do_flock(rdi=fd, rsi=op) -> rax = 0 or -errno
do_flock:
    mov     rax, 73                # SYS_FLOCK
    syscall
    ret

# do_write(rdi=fd, rsi=buf, rdx=count) -> rax = bytes
do_write:
    mov     rax, 1                 # SYS_WRITE
    syscall
    ret

# do_read(rdi=fd, rsi=buf, rdx=count) -> rax = bytes
do_read:
    mov     rax, 0                 # SYS_READ
    syscall
    ret

# do_lseek(rdi=fd, rsi=offset, rdx=whence) -> rax
do_lseek:
    mov     rax, 8                 # SYS_LSEEK
    syscall
    ret

fail_exit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    # Unlink any stale file
    lea     rdi, [rip + path]
    mov     rax, 87                # SYS_UNLINK
    syscall

    # --- Test 1: open + LOCK_EX + write + LOCK_UN ---
    lea     rdi, [rip + path]
    call    open_rw
    test    rax, rax
    js      fail_exit
    mov     [rip + fd1], rax

    mov     rdi, [rip + fd1]
    mov     rsi, 2                 # LOCK_EX
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    mov     rdi, [rip + fd1]
    xor     rsi, rsi
    xor     rdx, rdx               # SEEK_SET
    call    do_lseek

    mov     rdi, [rip + fd1]
    lea     rsi, [rip + write_data]
    mov     rdx, data_len
    call    do_write
    cmp     rax, data_len
    jne     fail_exit

    mov     rdi, [rip + fd1]
    mov     rsi, 8                 # LOCK_UN
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    # --- Test 2: LOCK_SH + read + verify roundtrip + LOCK_UN ---
    mov     rdi, [rip + fd1]
    mov     rsi, 1                 # LOCK_SH
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    mov     rdi, [rip + fd1]
    xor     rsi, rsi
    xor     rdx, rdx
    call    do_lseek

    mov     rdi, [rip + fd1]
    lea     rsi, [rip + read_buf]
    mov     rdx, data_len
    call    do_read
    cmp     rax, data_len
    jne     fail_exit

    mov     rax, [rip + read_buf]
    mov     rcx, [rip + write_data]
    cmp     rax, rcx
    jne     fail_exit

    mov     rdi, [rip + fd1]
    mov     rsi, 8                 # LOCK_UN
    call    do_flock

    # --- Test 3: open fd2, fd1 LOCK_EX, fd2 LOCK_EX|LOCK_NB fails ---
    lea     rdi, [rip + path]
    call    open_rw
    test    rax, rax
    js      fail_exit
    mov     [rip + fd2], rax

    mov     rdi, [rip + fd1]
    mov     rsi, 2                 # LOCK_EX
    call    do_flock

    mov     rdi, [rip + fd2]
    mov     rsi, 6                 # LOCK_EX | LOCK_NB
    call    do_flock
    test    rax, rax
    jns     fail_exit              # must be < 0 (jns: jump if NOT signed = >= 0)

    # --- Test 4: release fd1, fd2 acquires ---
    mov     rdi, [rip + fd1]
    mov     rsi, 8                 # LOCK_UN
    call    do_flock

    mov     rdi, [rip + fd2]
    mov     rsi, 6                 # LOCK_EX | LOCK_NB
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    mov     rdi, [rip + fd2]
    mov     rsi, 8                 # LOCK_UN
    call    do_flock

    # --- Test 5: shared locks coexist ---
    mov     rdi, [rip + fd1]
    mov     rsi, 5                 # LOCK_SH | LOCK_NB
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    mov     rdi, [rip + fd2]
    mov     rsi, 5                 # LOCK_SH | LOCK_NB
    call    do_flock
    test    rax, rax
    jnz     fail_exit

    mov     rdi, [rip + fd1]
    mov     rsi, 8
    call    do_flock
    mov     rdi, [rip + fd2]
    mov     rsi, 8
    call    do_flock

    # Close + unlink
    mov     rdi, [rip + fd1]
    mov     rax, 3                 # SYS_CLOSE
    syscall
    mov     rdi, [rip + fd2]
    mov     rax, 3
    syscall

    lea     rdi, [rip + path]
    mov     rax, 87
    syscall

    # Success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
