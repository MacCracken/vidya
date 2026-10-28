// Vidya — Filesystems in AArch64 Assembly
//
// File operations via AArch64 Linux syscalls: openat, write, read, close,
// unlinkat. Creates a temporary file, writes data, reads it back, verifies
// the content matches, then removes the file.
//
// AArch64 syscall numbers differ from x86_64:
//   openat  = 56  (x86_64 uses open=2 or openat=257)
//   close   = 57  (x86_64: 3)
//   read    = 63  (x86_64: 0)
//   write   = 64  (x86_64: 1)
//   lseek   = 62  (x86_64: 8)
//   unlinkat = 35 (x86_64: unlink=87 or unlinkat=263)
//
// AArch64 Linux does NOT have plain open/unlink syscalls — it uses
// openat/unlinkat with AT_FDCWD (-100) for current directory behavior.
//
// Build: aarch64-linux-gnu-as file.s -o out.o && aarch64-linux-gnu-ld out.o -o out && qemu-aarch64 out

.global _start

// ── Syscall numbers (AArch64 Linux) ─────────────────────────────
.equ SYS_UNLINKAT,  35
.equ SYS_OPENAT,    56
.equ SYS_CLOSE,     57
.equ SYS_LSEEK,     62
.equ SYS_READ,      63
.equ SYS_WRITE,     64
.equ SYS_EXIT,      93

// ── openat() flags ──────────────────────────────────────────────
.equ AT_FDCWD,     -100          // use current working directory
.equ O_RDONLY,      0x0000
.equ O_WRONLY,      0x0001
.equ O_RDWR,        0x0002
.equ O_CREAT,       0x0040
.equ O_TRUNC,       0x0200
.equ AT_REMOVEDIR,  0x0200       // flag for unlinkat to remove directory

// ── File mode ───────────────────────────────────────────────────
.equ MODE_RW,       0644         // rw-r--r--

// ── Data constants ──────────────────────────────────────────────
.equ WRITE_LEN,     14           // length of write_data

.section .text

_start:
    // ── Step 1: Create and open file for writing ──────────────────
    // openat(AT_FDCWD, path, O_WRONLY | O_CREAT | O_TRUNC, 0644)
    mov     x8, SYS_OPENAT
    mov     x0, AT_FDCWD            // dirfd = AT_FDCWD (current directory)
    adr     x1, filepath             // pathname
    mov     x2, (O_WRONLY | O_CREAT | O_TRUNC)
    mov     x3, MODE_RW
    svc     #0

    // Check open succeeded (fd >= 0)
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0                  // save fd in callee-saved register

    // ── Step 2: Write data to file ────────────────────────────────
    // write(fd, buf, len)
    mov     x8, SYS_WRITE
    mov     x0, x19                  // fd
    adr     x1, write_data           // buf
    mov     x2, WRITE_LEN            // count
    svc     #0

    // Verify all bytes were written
    cmp     x0, WRITE_LEN
    b.ne    fail_close

    // ── Step 3: Close the file ────────────────────────────────────
    mov     x8, SYS_CLOSE
    mov     x0, x19
    svc     #0
    cbnz    x0, fail

    // ── Step 4: Reopen file for reading ───────────────────────────
    mov     x8, SYS_OPENAT
    mov     x0, AT_FDCWD
    adr     x1, filepath
    mov     x2, O_RDONLY
    mov     x3, #0
    svc     #0

    cmp     x0, #0
    b.lt    fail
    mov     x19, x0                  // save new fd

    // ── Step 5: Read data back ────────────────────────────────────
    // read(fd, buf, len)
    mov     x8, SYS_READ
    mov     x0, x19
    adr     x1, read_buf
    mov     x2, WRITE_LEN
    svc     #0

    // Verify correct number of bytes read
    cmp     x0, WRITE_LEN
    b.ne    fail_close

    // ── Step 6: Verify data matches ───────────────────────────────
    // Compare write_data and read_buf byte by byte
    adr     x1, write_data
    adr     x2, read_buf
    mov     x3, #0                   // index = 0

verify_loop:
    cmp     x3, WRITE_LEN
    b.eq    verify_done
    ldrb    w4, [x1, x3]
    ldrb    w5, [x2, x3]
    cmp     w4, w5
    b.ne    fail_close
    add     x3, x3, #1
    b       verify_loop

verify_done:
    // ── Step 7: Close the file ────────────────────────────────────
    mov     x8, SYS_CLOSE
    mov     x0, x19
    svc     #0
    cbnz    x0, fail

    // ── Step 8: Unlink (delete) the file ──────────────────────────
    // unlinkat(AT_FDCWD, path, 0)
    // flags=0 means unlink a file (not a directory)
    mov     x8, SYS_UNLINKAT
    mov     x0, AT_FDCWD
    adr     x1, filepath
    mov     x2, #0                   // flags = 0 (not AT_REMOVEDIR)
    svc     #0
    cbnz    x0, fail

    // ── Step 9: Verify file is gone (open should fail) ────────────
    mov     x8, SYS_OPENAT
    mov     x0, AT_FDCWD
    adr     x1, filepath
    mov     x2, O_RDONLY
    mov     x3, #0
    svc     #0

    // Should return negative (ENOENT = -2)
    cmp     x0, #0
    b.ge    fail                     // if non-negative, file still exists

    // ── All passed ────────────────────────────────────────────────
    mov     x8, SYS_WRITE
    mov     x0, #1                   // stdout
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, SYS_EXIT
    mov     x0, #0
    svc     #0

fail_close:
    // Close fd before failing
    mov     x8, SYS_CLOSE
    mov     x0, x19
    svc     #0
    // Attempt cleanup: unlink the file
    mov     x8, SYS_UNLINKAT
    mov     x0, AT_FDCWD
    adr     x1, filepath
    mov     x2, #0
    svc     #0
    // Fall through to fail

fail:
    mov     x8, SYS_EXIT
    mov     x0, #1
    svc     #0

// ── Data ────────────────────────────────────────────────────────
.section .data
filepath:
    .asciz  "/tmp/vidya_fs_test_a64.tmp"

write_data:
    .ascii  "Hello, vidya!\n"        // 14 bytes

read_buf:
    .skip   64                       // buffer for reading back

.section .rodata
msg_pass:
    .ascii "All filesystems examples passed.\n"
    msg_len = . - msg_pass
