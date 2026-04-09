// Vidya — ELF and Executable Formats in AArch64 Assembly
//
// AArch64 ELF specifics: .text for code, .data for mutable data,
// .rodata for constants, .bss for zero-initialized data. The linker
// resolves ADRP+ADD pairs for PC-relative addressing. AArch64 uses
// RELA relocations (with explicit addend). Key relocation types:
//   R_AARCH64_ADR_PREL_PG_HI21 — page-relative high 21 bits (ADRP)
//   R_AARCH64_ADD_ABS_LO12_NC  — low 12 bits (ADD after ADRP)

.global _start

// ── .rodata section: read-only constants ────────────────────────────
.section .rodata
msg_pass:   .ascii "All ELF and executable formats examples passed.\n"
msg_len = . - msg_pass

rodata_val:     .word 0xDEADBEEF    // constant in read-only section
.align 3
rodata_str:     .ascii "RODATA"
rodata_str_len = . - rodata_str

// ── .data section: mutable initialized data ─────────────────────────
.section .data
.align 2
data_counter:   .word 0             // mutable counter
.align 3
data_array:     .word 10, 20, 30    // initialized array

// ── .bss section: zero-initialized mutable data ─────────────────────
// .bss takes no space in the ELF file — only a size annotation.
// The OS zero-fills it at load time.
.section .bss
.align 2
bss_buffer:     .skip 16            // 16 bytes of zeros at runtime
.align 2
bss_counter:    .skip 4             // 4 bytes (one word) of zeros

// ── .text section: executable code ──────────────────────────────────
.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: read from .rodata ───────────────────────────────────
    // ADRP+ADD is the standard AArch64 pattern for addressing data.
    // ADRP loads the page address (top bits), ADD adds the page offset.
    // For small programs, ADR can reach all data directly.
    adr     x0, rodata_val
    ldr     w1, [x0]
    mov     w2, #0xBEEF
    movk    w2, #0xDEAD, lsl #16
    cmp     w1, w2
    b.ne    fail

    // ── Test 2: verify .rodata string ───────────────────────────────
    adr     x0, rodata_str
    ldrb    w1, [x0]
    cmp     w1, #'R'
    b.ne    fail

    ldrb    w1, [x0, #5]
    cmp     w1, #'A'
    b.ne    fail

    // ── Test 3: read/write .data ────────────────────────────────────
    adr     x0, data_counter
    ldr     w1, [x0]               // should be 0 (initialized)
    cmp     w1, #0
    b.ne    fail

    // Write to .data (mutable)
    mov     w1, #42
    str     w1, [x0]
    ldr     w2, [x0]
    cmp     w2, #42
    b.ne    fail

    // ── Test 4: .data array access ──────────────────────────────────
    adr     x0, data_array
    ldr     w1, [x0, #0]           // 10
    cmp     w1, #10
    b.ne    fail

    ldr     w1, [x0, #4]           // 20
    cmp     w1, #20
    b.ne    fail

    ldr     w1, [x0, #8]           // 30
    cmp     w1, #30
    b.ne    fail

    // Sum the array
    ldr     w1, [x0, #0]
    ldr     w2, [x0, #4]
    ldr     w3, [x0, #8]
    add     w1, w1, w2
    add     w1, w1, w3
    cmp     w1, #60                 // 10 + 20 + 30
    b.ne    fail

    // ── Test 5: .bss is zero-initialized ────────────────────────────
    adr     x0, bss_buffer
    ldr     x1, [x0]               // first 8 bytes should be 0
    cbnz    x1, fail

    ldr     x1, [x0, #8]           // next 8 bytes should be 0
    cbnz    x1, fail

    adr     x0, bss_counter
    ldr     w1, [x0]               // should be 0
    cbnz    w1, fail

    // ── Test 6: write to .bss ───────────────────────────────────────
    adr     x0, bss_counter
    mov     w1, #99
    str     w1, [x0]
    ldr     w2, [x0]
    cmp     w2, #99
    b.ne    fail

    // ── Test 7: .bss buffer write and readback ──────────────────────
    adr     x0, bss_buffer
    mov     w1, #0xAB
    strb    w1, [x0, #0]
    mov     w1, #0xCD
    strb    w1, [x0, #1]
    ldrb    w2, [x0, #0]
    cmp     w2, #0xAB
    b.ne    fail
    ldrb    w2, [x0, #1]
    cmp     w2, #0xCD
    b.ne    fail

    // ── Test 8: PC-relative addressing demonstration ────────────────
    // ADR computes address relative to PC. This is how AArch64 avoids
    // absolute addresses — everything is position-independent.
    adr     x0, msg_pass
    ldrb    w1, [x0]               // first byte of message
    cmp     w1, #'A'               // "All elf..."
    b.ne    fail

    // ── Test 9: section alignment verification ──────────────────────
    // .data is typically 4 or 8 byte aligned. Verify alignment.
    adr     x0, data_array
    tst     x0, #3                 // check 4-byte alignment
    b.ne    fail

    // ── Test 10: function in .text section ──────────────────────────
    // .text is executable. Functions live here.
    mov     w0, #5
    mov     w1, #3
    bl      elf_add
    cmp     w0, #8
    b.ne    fail

    // ── Print success ────────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    ldp     x29, x30, [sp], #16
    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── elf_add(w0, w1) -> w0 ───────────────────────────────────────────
// A function in .text — the executable section.
elf_add:
    add     w0, w0, w1
    ret
