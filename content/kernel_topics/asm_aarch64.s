// Vidya — Kernel Topics in AArch64 Assembly
//
// AArch64 kernel assembly: page table entry construction, virtual
// address decomposition, MMIO register manipulation, GDT-equivalent
// (TCR/MAIR), and AAPCS64 calling convention. AArch64 uses a
// different privilege model (EL0-EL3) than x86's ring 0-3.

.global _start

.section .rodata
msg_pass:   .ascii "All kernel topics examples passed.\n"
msg_len = . - msg_pass

.section .bss
scratch:    .skip 64

.section .text

_start:
    // ── Test 1: Page Table Entry construction ─────────────────────────
    // Build PTE: phys_addr=0x1000, flags=PRESENT|WRITABLE (0x3)
    mov     x0, #0x1000
    orr     x0, x0, #0x3       // PRESENT | WRITABLE
    // Verify present bit
    tst     x0, #1
    b.eq    fail
    // Verify writable bit
    tst     x0, #2
    b.eq    fail
    // Extract physical address (bits 12-51)
    mov     x1, #0x000F
    movk    x1, #0xFFFF, lsl #16
    movk    x1, #0xFFFF, lsl #32
    lsl     x2, x1, #12        // build ADDR_MASK
    // Simpler: just mask low 12 bits to get page-aligned addr
    and     x1, x0, #~0xFFF
    cmp     x1, #0x1000
    b.ne    fail

    // ── Test 2: Virtual address decomposition ─────────────────────────
    // Decompose address to get PML4 index (bits 39-47)
    mov     x0, #0xFFFF
    movk    x0, #0xFFFF, lsl #16
    movk    x0, #0x7FFF, lsl #32
    // PML4 index = (addr >> 39) & 0x1FF
    lsr     x1, x0, #39
    and     x1, x1, #0x1FF
    cmp     x1, #0xFF          // should be 255
    b.ne    fail

    // ── Test 3: MMIO register simulation ──────────────────────────────
    adr     x0, scratch
    // Initialize to 0
    str     wzr, [x0]
    // Set bits 0-1 (OR)
    ldr     w1, [x0]
    orr     w1, w1, #0x3
    str     w1, [x0]
    ldr     w2, [x0]
    cmp     w2, #3
    b.ne    fail
    // Clear bit 1 (AND NOT)
    ldr     w1, [x0]
    bic     w1, w1, #0x2       // bit clear instruction
    str     w1, [x0]
    ldr     w2, [x0]
    cmp     w2, #1
    b.ne    fail

    // ── Test 4: AAPCS64 calling convention ────────────────────────────
    // Args in x0-x7, return in x0 (and x1 for 128-bit)
    mov     x0, #42
    mov     x1, #58
    bl      add_two
    cmp     x0, #100
    b.ne    fail

    // ── Test 5: Syscall via SVC ───────────────────────────────────────
    // Linux AArch64 syscall: number in x8, args in x0-x5
    // sys_getpid = 172
    mov     x8, #172
    svc     #0
    cmp     x0, #0
    b.eq    fail                // pid > 0

    // ── Test 6: Callee-saved register preservation ────────────────────
    // AAPCS64: x19-x28 are callee-saved
    mov     x19, #0xDEAD
    mov     x20, #0xBEEF
    bl      clobber_caller_saved
    mov     x9, #0xDEAD
    cmp     x19, x9
    b.ne    fail
    mov     x9, #0xBEEF
    cmp     x20, x9
    b.ne    fail

    // ── Test 7: Exception level concept ───────────────────────────────
    // AArch64 has 4 exception levels:
    // EL0 = user, EL1 = kernel, EL2 = hypervisor, EL3 = secure monitor
    // We can't read CurrentEL from EL0, but we verify the constants
    // EL0 = 0b00 << 2 = 0x0
    // EL1 = 0b01 << 2 = 0x4
    // EL2 = 0b10 << 2 = 0x8
    // EL3 = 0b11 << 2 = 0xC
    mov     w0, #0x0            // EL0
    mov     w1, #0x4            // EL1
    mov     w2, #0x8            // EL2
    mov     w3, #0xC            // EL3
    cmp     w1, #0x4
    b.ne    fail
    cmp     w3, #0xC
    b.ne    fail

    // ── All passed ───────────────────────────────────────────────────
    mov     x8, #64             // sys_write
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93             // sys_exit
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── add_two(x0=a, x1=b) → x0 ────────────────────────────────────────
// AAPCS64: args in x0-x7, return in x0
add_two:
    add     x0, x0, x1
    ret

// ── clobber_caller_saved() ───────────────────────────────────────────
// Clobbers x0-x18 (caller-saved) but preserves x19-x28 (callee-saved)
clobber_caller_saved:
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x9, #0
    mov     x10, #0
    mov     x11, #0
    ret
