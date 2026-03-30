// Vidya — Iterators in AArch64 Assembly
//
// AArch64 iteration: load, compare, branch. Post-increment addressing
// modes (ldr x0, [x1], #8) make pointer-based iteration natural.
// The CBZ/CBNZ instructions combine compare-zero with branch.

.global _start

.section .data
numbers:    .word 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
num_count = (. - numbers) / 4

.section .rodata
msg_pass:   .ascii "All iterator examples passed.\n"
msg_len = . - msg_pass

.section .bss
results:    .skip 40

.section .text

_start:
    // ── Sum array with index ───────────────────────────────────────
    mov     w0, #0              // sum = 0
    mov     w1, #0              // i = 0
    adr     x2, numbers
.Lsum_loop:
    cmp     w1, num_count
    b.ge    .Lsum_done
    ldr     w3, [x2, w1, uxtw #2]  // numbers[i]
    add     w0, w0, w3
    add     w1, w1, #1
    b       .Lsum_loop
.Lsum_done:
    cmp     w0, #55
    b.ne    fail

    // ── Sum with pointer iteration ─────────────────────────────────
    adr     x2, numbers
    adr     x3, numbers + num_count * 4
    mov     w0, #0
.Lptr_loop:
    cmp     x2, x3
    b.ge    .Lptr_done
    ldr     w4, [x2], #4       // load and post-increment
    add     w0, w0, w4
    b       .Lptr_loop
.Lptr_done:
    cmp     w0, #55
    b.ne    fail

    // ── Count even numbers (filter) ────────────────────────────────
    mov     w0, #0              // even_count
    mov     w1, #0              // i
    adr     x2, numbers
.Lfilt_loop:
    cmp     w1, num_count
    b.ge    .Lfilt_done
    ldr     w3, [x2, w1, uxtw #2]
    tst     w3, #1              // test bit 0
    b.ne    .Lfilt_skip         // odd, skip
    add     w0, w0, #1
.Lfilt_skip:
    add     w1, w1, #1
    b       .Lfilt_loop
.Lfilt_done:
    cmp     w0, #5              // 2,4,6,8,10
    b.ne    fail

    // ── Square each element (map) ──────────────────────────────────
    mov     w1, #0
    adr     x2, numbers
    adr     x3, results
.Lmap_loop:
    cmp     w1, num_count
    b.ge    .Lmap_done
    ldr     w4, [x2, w1, uxtw #2]
    mul     w4, w4, w4
    str     w4, [x3, w1, uxtw #2]
    add     w1, w1, #1
    b       .Lmap_loop
.Lmap_done:
    // Verify results[0]=1, results[4]=25, results[9]=100
    adr     x3, results
    ldr     w0, [x3]
    cmp     w0, #1
    b.ne    fail
    ldr     w0, [x3, #16]      // results[4]
    cmp     w0, #25
    b.ne    fail
    ldr     w0, [x3, #36]      // results[9]
    cmp     w0, #100
    b.ne    fail

    // ── Product of first 5 (fold) ──────────────────────────────────
    mov     w0, #1              // accumulator
    mov     w1, #0
    adr     x2, numbers
.Lfold_loop:
    cmp     w1, #5
    b.ge    .Lfold_done
    ldr     w3, [x2, w1, uxtw #2]
    mul     w0, w0, w3
    add     w1, w1, #1
    b       .Lfold_loop
.Lfold_done:
    cmp     w0, #120            // 1*2*3*4*5
    b.ne    fail

    // ── Find first > 7 ─────────────────────────────────────────────
    mov     w1, #0
    adr     x2, numbers
.Lfind_loop:
    cmp     w1, num_count
    b.ge    fail
    ldr     w0, [x2, w1, uxtw #2]
    cmp     w0, #7
    b.gt    .Lfind_done
    add     w1, w1, #1
    b       .Lfind_loop
.Lfind_done:
    cmp     w0, #8
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
