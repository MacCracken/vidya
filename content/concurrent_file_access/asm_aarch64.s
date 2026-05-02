// Vidya — Concurrent File Access (flock) in AArch64 Assembly
//
// Single-process exercise via two opens of the same file. flock is
// per-OPEN; each fd has independent lock state.
//
// AArch64 syscall numbers (generic table):
//   SYS_OPENAT    = 56     (open via AT_FDCWD; SYS_OPEN deprecated)
//   SYS_CLOSE     = 57
//   SYS_WRITE     = 64
//   SYS_READ      = 63
//   SYS_LSEEK     = 62
//   SYS_FLOCK     = 32
//   SYS_UNLINKAT  = 35
// Op constants: LOCK_SH=1, LOCK_EX=2, LOCK_UN=8, LOCK_NB=4.
// AT_FDCWD = -100 (signed).
//
// AArch64 ABI: cache fds in callee-saved x19/x20 across `bl`.

.global _start

.section .data
.align 8
path:         .asciz "/tmp/vidya_cfa_a64.bin"
write_data:   .quad 0xDEADBEEF12345678
.equ data_len, 8

.bss
.align 8
read_buf:     .skip 8

.section .rodata
msg_pass:     .ascii "concurrent_file_access: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// open_rw -> x0 = fd (AT_FDCWD path, O_RDWR|O_CREAT, mode 0644)
open_rw:
    mov     x0, #-100              // AT_FDCWD
    adrp    x1, path
    add     x1, x1, :lo12:path
    mov     x2, #66                // O_RDWR | O_CREAT
    mov     x3, #420               // 0644
    mov     x8, #56                // SYS_OPENAT
    svc     #0
    ret

// do_flock(x0=fd, x1=op) -> x0 = 0 or -errno
do_flock:
    mov     x8, #32                // SYS_FLOCK
    svc     #0
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    // Unlink stale file (ignore errors)
    mov     x0, #-100              // AT_FDCWD
    adrp    x1, path
    add     x1, x1, :lo12:path
    mov     x2, #0
    mov     x8, #35                // SYS_UNLINKAT
    svc     #0

    // --- Test 1: open fd1 + LOCK_EX + write + LOCK_UN ---
    bl      open_rw
    cmp     x0, #0
    b.lt    fail_exit
    mov     x19, x0                // fd1 (callee-saved)

    mov     x0, x19
    mov     x1, #2                 // LOCK_EX
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    // lseek(fd, 0, SEEK_SET)
    mov     x0, x19
    mov     x1, #0
    mov     x2, #0
    mov     x8, #62
    svc     #0

    // write(fd, write_data, 8)
    mov     x0, x19
    adrp    x1, write_data
    add     x1, x1, :lo12:write_data
    mov     x2, #data_len
    mov     x8, #64
    svc     #0
    cmp     x0, #data_len
    b.ne    fail_exit

    mov     x0, x19
    mov     x1, #8                 // LOCK_UN
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    // --- Test 2: LOCK_SH + read + verify roundtrip ---
    mov     x0, x19
    mov     x1, #1                 // LOCK_SH
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    // lseek + read
    mov     x0, x19
    mov     x1, #0
    mov     x2, #0
    mov     x8, #62
    svc     #0

    mov     x0, x19
    adrp    x1, read_buf
    add     x1, x1, :lo12:read_buf
    mov     x2, #data_len
    mov     x8, #63                // SYS_READ
    svc     #0
    cmp     x0, #data_len
    b.ne    fail_exit

    // Compare read_buf vs write_data
    adrp    x1, read_buf
    add     x1, x1, :lo12:read_buf
    ldr     x2, [x1]
    adrp    x1, write_data
    add     x1, x1, :lo12:write_data
    ldr     x3, [x1]
    cmp     x2, x3
    b.ne    fail_exit

    mov     x0, x19
    mov     x1, #8
    bl      do_flock

    // --- Test 3: open fd2, fd1 LOCK_EX, fd2 LOCK_EX|LOCK_NB fails ---
    bl      open_rw
    cmp     x0, #0
    b.lt    fail_exit
    mov     x20, x0                // fd2 (callee-saved)

    mov     x0, x19
    mov     x1, #2
    bl      do_flock

    mov     x0, x20
    mov     x1, #6                 // LOCK_EX | LOCK_NB
    bl      do_flock
    cmp     x0, #0
    b.ge    fail_exit              // must be < 0

    // --- Test 4: release fd1, fd2 acquires ---
    mov     x0, x19
    mov     x1, #8
    bl      do_flock

    mov     x0, x20
    mov     x1, #6
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    mov     x0, x20
    mov     x1, #8
    bl      do_flock

    // --- Test 5: shared locks coexist ---
    mov     x0, x19
    mov     x1, #5                 // LOCK_SH | LOCK_NB
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    mov     x0, x20
    mov     x1, #5
    bl      do_flock
    cmp     x0, #0
    b.ne    fail_exit

    mov     x0, x19
    mov     x1, #8
    bl      do_flock
    mov     x0, x20
    mov     x1, #8
    bl      do_flock

    // Close + unlink
    mov     x0, x19
    mov     x8, #57
    svc     #0
    mov     x0, x20
    mov     x8, #57
    svc     #0

    mov     x0, #-100
    adrp    x1, path
    add     x1, x1, :lo12:path
    mov     x2, #0
    mov     x8, #35
    svc     #0

    // Success
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
