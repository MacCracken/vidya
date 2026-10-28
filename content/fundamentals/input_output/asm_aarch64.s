// Vidya — Input/Output in AArch64 Assembly
//
// Linux AArch64 syscalls: read (63), write (64), openat (56),
// close (57). File descriptors work the same as x86_64.
// Syscall number goes in x8, args in x0-x5, return in x0.

.global _start

.section .rodata
hello:      .ascii "hello world\n"
hello_len = . - hello
path:       .asciz "/tmp/vidya_aa64_io_test"
msg_pass:   .ascii "All input/output examples passed.\n"
msg_len = . - msg_pass

.section .bss
read_buf:   .skip 64

.section .text

_start:
    // ── sys_write to stdout ────────────────────────────────────────
    mov     x8, #64             // sys_write
    mov     x0, #1              // fd = stdout
    adr     x1, hello
    mov     x2, hello_len
    svc     #0
    cmp     x0, hello_len
    b.ne    fail

    // ── sys_openat: create file ────────────────────────────────────
    // openat(AT_FDCWD, path, O_WRONLY|O_CREAT|O_TRUNC, 0644)
    mov     x8, #56             // sys_openat
    mov     x0, #-100           // AT_FDCWD
    adr     x1, path
    mov     x2, #0x241          // O_WRONLY|O_CREAT|O_TRUNC
    mov     x3, #0x1A4          // 0644 octal = 420 decimal
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0             // save fd

    // ── sys_write to file ──────────────────────────────────────────
    mov     x8, #64
    mov     x0, x19
    adr     x1, hello
    mov     x2, hello_len
    svc     #0
    cmp     x0, hello_len
    b.ne    fail

    // ── sys_close ──────────────────────────────────────────────────
    mov     x8, #57             // sys_close
    mov     x0, x19
    svc     #0
    cbnz    x0, fail

    // ── sys_openat: read back ──────────────────────────────────────
    mov     x8, #56
    mov     x0, #-100
    adr     x1, path
    mov     x2, #0              // O_RDONLY
    mov     x3, #0
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0

    // ── sys_read ───────────────────────────────────────────────────
    mov     x8, #63             // sys_read
    mov     x0, x19
    adr     x1, read_buf
    mov     x2, #64
    svc     #0
    cmp     x0, hello_len
    b.ne    fail

    // Verify first byte
    adr     x1, read_buf
    ldrb    w2, [x1]
    cmp     w2, #'h'
    b.ne    fail

    // ── sys_close + sys_unlinkat ───────────────────────────────────
    mov     x8, #57
    mov     x0, x19
    svc     #0

    mov     x8, #35             // sys_unlinkat
    mov     x0, #-100           // AT_FDCWD
    adr     x1, path
    mov     x2, #0
    svc     #0
    cbnz    x0, fail

    // ── sys_write to stderr ────────────────────────────────────────
    mov     x8, #64
    mov     x0, #2              // stderr
    adr     x1, hello
    mov     x2, #1
    svc     #0
    cmp     x0, #1
    b.ne    fail

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0
