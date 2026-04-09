// Vidya — Linking and Loading in AArch64 Assembly
//
// At the assembly level, linking resolves symbols to addresses. AArch64
// uses ADRP+ADD for PC-relative addressing (the foundation of position-
// independent code), BL for function calls, and has rich relocation types.
//
// Key AArch64 relocation types:
//   R_AARCH64_ADR_PREL_PG_HI21  — ADRP: page-relative high 21 bits
//   R_AARCH64_ADD_ABS_LO12_NC   — ADD: low 12 bits within page
//   R_AARCH64_CALL26            — BL: 26-bit PC-relative call
//   R_AARCH64_JUMP26            — B: 26-bit PC-relative branch
//
// ADRP+ADD pattern:
//   adrp x0, symbol   // x0 = (PC & ~0xFFF) + (symbol_page_offset << 12)
//   add  x0, x0, :lo12:symbol  // x0 += low 12 bits of symbol address
//   Together these form a 33-bit PC-relative address (+/- 4GB range)

.global _start

.section .rodata
msg_pass:   .ascii "All linking and loading examples passed.\n"
msg_len = . - msg_pass

local_str:  .ascii "local"      // no .global — only visible in this file
local_str_len = . - local_str

.section .data
.align 8
// ── Global data symbol ────────────────────────────────────────────
.global exported_value
exported_value: .quad 42        // visible to other object files

// ── File-local data ───────────────────────────────────────────────
internal_counter:   .quad 0     // no .global — file-private
another_local:      .quad 100

.section .bss
.align 12                       // 4096-byte (page) alignment
// ── BSS: zero-initialized, occupies no space in object file ───────
// The loader allocates and zeros this at load time
.global bss_buffer
bss_buffer:     .skip 4096      // 4KB zero-initialized buffer

.section .text

// ════════════════════════════════════════════════════════════════════
// _start — entry point (global symbol, linker resolves this)
// ════════════════════════════════════════════════════════════════════
_start:
    // ── ADR: single-instruction PC-relative address ───────────────
    // ADR computes address within +/- 1MB of PC
    // The assembler emits R_AARCH64_ADR_PREL_LO21 relocation
    adr     x0, exported_value
    ldr     x1, [x0]
    cmp     x1, #42
    b.ne    fail

    // ── ADRP+ADD: page-relative addressing for larger range ───────
    // ADRP loads the page base (4KB aligned) of the target
    // ADD refines to the exact offset within that page
    // Together they reach +/- 4GB from PC
    //
    // For static executables, the linker resolves these at link time.
    // For shared libraries, they work without fixups (PIC by design).
    adrp    x0, exported_value
    add     x0, x0, :lo12:exported_value
    ldr     x1, [x0]
    cmp     x1, #42
    b.ne    fail

    // ── LEA equivalent: ADR for address computation ───────────────
    // Unlike x86_64's LEA, AArch64 uses ADR (or ADRP+ADD) to get
    // addresses. No dereference — just address computation.
    adr     x19, exported_value     // x19 = &exported_value
    adr     x20, internal_counter   // x20 = &internal_counter

    // Verify they point to different locations
    cmp     x19, x20
    b.eq    fail

    // Verify we can dereference both
    ldr     x0, [x19]
    cmp     x0, #42
    b.ne    fail
    ldr     x0, [x20]
    cmp     x0, #0
    b.ne    fail

    // ── BL: function call with link ───────────────────────────────
    // BL generates R_AARCH64_CALL26 relocation — 26-bit signed offset
    // Range: +/- 128 MB. Stores return address in x30 (LR).
    mov     x0, #10
    mov     x1, #20
    bl      local_helper            // linker resolves to relative offset
    cmp     x0, #30
    b.ne    fail

    // ── Multiple calls to file-local function ─────────────────────
    bl      increment_counter
    bl      increment_counter
    bl      increment_counter
    adr     x0, internal_counter
    ldr     x0, [x0]
    cmp     x0, #3
    b.ne    fail

    // ── Verify .rodata is readable ────────────────────────────────
    adr     x0, local_str
    ldrb    w1, [x0]
    cmp     w1, #'l'            // first byte of "local"
    b.ne    fail

    // ── Verify .bss is zero-initialized ───────────────────────────
    adr     x0, bss_buffer
    ldr     x1, [x0]
    cbnz    x1, fail            // must be zero

    // Write to .bss (it's in a writable segment)
    mov     x1, #0xDEAD
    movk    x1, #0xBEEF, lsl #16   // x1 = 0xBEEFDEAD
    str     x1, [x0]
    ldr     x2, [x0]
    cmp     x2, x1
    b.ne    fail

    // ── Symbol address relationships ──────────────────────────────
    // Symbols in the same section have fixed relative offsets.
    // The linker preserves these when laying out the section.
    adr     x0, exported_value
    adr     x1, internal_counter
    sub     x2, x1, x0
    cmp     x2, #8              // exported_value is 8 bytes, followed by counter
    b.ne    fail

    // ── Weak symbol ───────────────────────────────────────────────
    // .weak symbol — linker won't error if undefined (resolves to 0)
    // .global symbol — strong symbol, linker errors on duplicates
.weak optional_plugin

    // ── Print success ─────────────────────────────────────────────
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

// ════════════════════════════════════════════════════════════════════
// local_helper — file-private function (not exported)
// No .global directive = invisible to the linker from other objects
// ════════════════════════════════════════════════════════════════════
local_helper:
    add     x0, x0, x1          // return a + b
    ret

// ════════════════════════════════════════════════════════════════════
// increment_counter — accesses file-local data
// Demonstrates: function modifying private module state
// ════════════════════════════════════════════════════════════════════
increment_counter:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, internal_counter
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    ldp     x29, x30, [sp], #16
    ret
