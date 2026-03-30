// Vidya — Strings in AArch64 Assembly
//
// AArch64 string operations are explicit: load byte, compare, branch.
// Like x86_64, strings are just bytes in memory. AArch64 uses
// load/store architecture — data must be in registers before operating.
// System calls use x8 for syscall number, x0-x5 for arguments.

.global _start

.section .rodata
hello:      .asciz "hello"
hello_len = . - hello - 1       // 5 bytes without null
world:      .ascii "world"
world_len = . - world
msg_pass:   .ascii "All string examples passed.\n"
msg_len = . - msg_pass

.section .bss
buffer:     .skip 128

.section .text

_start:
    // ── String length (count to null terminator) ───────────────────
    adr     x0, hello
    bl      strlen
    cmp     x0, #5
    b.ne    fail

    // ── String comparison ──────────────────────────────────────────
    adr     x0, hello
    adr     x1, hello
    mov     x2, #5
    bl      memcmp
    cbnz    w0, fail            // should be 0 (equal)

    // ── String copy ────────────────────────────────────────────────
    adr     x0, buffer          // dst
    adr     x1, hello           // src
    mov     x2, #5
    bl      memcpy

    // Verify copy
    adr     x0, buffer
    adr     x1, hello
    mov     x2, #5
    bl      memcmp
    cbnz    w0, fail

    // ── String concatenation ───────────────────────────────────────
    // Build "helloworld" in buffer
    adr     x0, buffer
    adr     x1, hello
    mov     x2, #5
    bl      memcpy              // copy "hello"

    adr     x0, buffer
    add     x0, x0, #5         // advance past "hello"
    adr     x1, world
    mov     x2, #5
    bl      memcpy              // append "world"

    // Null terminate
    adr     x0, buffer
    strb    wzr, [x0, #10]

    // Verify length
    adr     x0, buffer
    bl      strlen
    cmp     x0, #10
    b.ne    fail

    // ── Character case conversion ──────────────────────────────────
    // Lowercase to uppercase: clear bit 5
    mov     w0, #'a'
    bic     w0, w0, #0x20       // clear bit 5: 'a' -> 'A'
    cmp     w0, #'A'
    b.ne    fail

    // Uppercase to lowercase: set bit 5
    mov     w0, #'A'
    orr     w0, w0, #0x20       // set bit 5: 'A' -> 'a'
    cmp     w0, #'a'
    b.ne    fail

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64             // sys_write
    mov     x0, #1              // fd = stdout
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    // ── Exit 0 ─────────────────────────────────────────────────────
    mov     x8, #93             // sys_exit
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── strlen: count bytes until null ─────────────────────────────────
// x0 = string pointer, returns x0 = length
strlen:
    mov     x1, x0              // save start
.Lstrlen_loop:
    ldrb    w2, [x0], #1        // load byte, post-increment
    cbnz    w2, .Lstrlen_loop
    sub     x0, x0, x1
    sub     x0, x0, #1          // don't count null
    ret

// ── memcmp: compare x2 bytes at x0 and x1 ─────────────────────────
// returns w0 = 0 if equal
memcmp:
    cbz     x2, .Lmcmp_eq
.Lmcmp_loop:
    ldrb    w3, [x0], #1
    ldrb    w4, [x1], #1
    cmp     w3, w4
    b.ne    .Lmcmp_diff
    subs    x2, x2, #1
    b.ne    .Lmcmp_loop
.Lmcmp_eq:
    mov     w0, #0
    ret
.Lmcmp_diff:
    sub     w0, w3, w4
    ret

// ── memcpy: copy x2 bytes from x1 to x0 ───────────────────────────
memcpy:
    cbz     x2, .Lmcpy_done
.Lmcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    .Lmcpy_loop
.Lmcpy_done:
    ret
