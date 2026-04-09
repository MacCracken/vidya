// Vidya — Module Systems in AArch64 Assembly
//
// Assembly "modules" use visibility and sections. .global exports a
// symbol for the linker (public API). Without .global, symbols are
// file-local (private). .section directives organize code and data
// into named regions: .text (code), .data (mutable), .rodata
// (constants), .bss (zero-init). This is the lowest-level module
// system: the linker sees only what you explicitly export.

.global _start

// ── .global symbols: the public API ─────────────────────────────────
// These would be visible to other object files during linking.
// In a multi-file project, other .s files can call these.
.global public_add
.global public_mul

// ── Local symbols: file-private ─────────────────────────────────────
// Symbols without .global are local — invisible to the linker.
// Convention: prefix with . or _local_ to signal intent.
// Labels starting with .L are guaranteed local by the assembler.

.section .rodata
msg_pass:   .ascii "All module systems examples passed.\n"
msg_len = . - msg_pass

// Local read-only data (not exported)
.Llocal_magic:  .word 0xCAFE

// Exported constant (with .global it would be visible to linker)
module_version: .word 1

.section .data
.align 2
// Module-private mutable state
.Llocal_counter:    .word 0

// Exported mutable state
shared_counter:     .word 0

.section .bss
.align 2
// Private buffer — only this file uses it
.Llocal_buffer:     .skip 16

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: call public function ────────────────────────────────
    // public_add is .global — other files could call it too.
    mov     w0, #3
    mov     w1, #4
    bl      public_add
    cmp     w0, #7
    b.ne    fail

    // ── Test 2: call another public function ────────────────────────
    mov     w0, #5
    mov     w1, #6
    bl      public_mul
    cmp     w0, #30
    b.ne    fail

    // ── Test 3: call local (private) function ───────────────────────
    // .Llocal_helper is NOT .global — only this file can call it.
    mov     w0, #10
    bl      .Llocal_helper
    cmp     w0, #20                 // doubles the input
    b.ne    fail

    // ── Test 4: access local .rodata ────────────────────────────────
    adr     x0, .Llocal_magic
    ldr     w1, [x0]
    mov     w2, #0xCAFE
    cmp     w1, w2
    b.ne    fail

    // ── Test 5: access module version ───────────────────────────────
    adr     x0, module_version
    ldr     w1, [x0]
    cmp     w1, #1
    b.ne    fail

    // ── Test 6: local mutable state ─────────────────────────────────
    // Only functions in THIS file can access .Llocal_counter.
    adr     x0, .Llocal_counter
    ldr     w1, [x0]
    cmp     w1, #0                  // initial value
    b.ne    fail

    // Increment through local function
    bl      .Lincrement_local
    bl      .Lincrement_local
    bl      .Lincrement_local

    adr     x0, .Llocal_counter
    ldr     w1, [x0]
    cmp     w1, #3
    b.ne    fail

    // ── Test 7: shared mutable state ────────────────────────────────
    // shared_counter could be accessed from other files if linked.
    adr     x0, shared_counter
    ldr     w1, [x0]
    cmp     w1, #0
    b.ne    fail

    mov     w1, #42
    str     w1, [x0]
    ldr     w2, [x0]
    cmp     w2, #42
    b.ne    fail

    // ── Test 8: local .bss buffer ───────────────────────────────────
    adr     x0, .Llocal_buffer
    ldr     x1, [x0]               // should be zero-initialized
    cbnz    x1, fail

    // Write and read back
    mov     w1, #0xAB
    strb    w1, [x0]
    ldrb    w2, [x0]
    cmp     w2, #0xAB
    b.ne    fail

    // ── Test 9: public function calling private function ────────────
    // A public API function can use private helpers internally.
    mov     w0, #8
    bl      public_double_add
    cmp     w0, #17                 // (8 * 2) + 1
    b.ne    fail

    // ── Test 10: section isolation ──────────────────────────────────
    // Verify that .rodata, .data, and .bss are at different addresses.
    adr     x0, .Llocal_magic      // .rodata
    adr     x1, .Llocal_counter    // .data
    adr     x2, .Llocal_buffer     // .bss
    cmp     x0, x1
    b.eq    fail                    // must be different addresses
    cmp     x1, x2
    b.eq    fail                    // must be different addresses
    cmp     x0, x2
    b.eq    fail

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

// ═══════════════════════════════════════════════════════════════════
// PUBLIC FUNCTIONS (.global — visible to linker)
// ═══════════════════════════════════════════════════════════════════

// ── public_add(w0, w1) -> w0 ────────────────────────────────────────
public_add:
    add     w0, w0, w1
    ret

// ── public_mul(w0, w1) -> w0 ────────────────────────────────────────
public_mul:
    mul     w0, w0, w1
    ret

// ── public_double_add(w0) -> w0 ─────────────────────────────────────
// Public function that uses a private helper internally.
public_double_add:
    stp     x29, x30, [sp, #-16]!
    bl      .Llocal_helper         // private: double the input
    add     w0, w0, #1             // public adds 1
    ldp     x29, x30, [sp], #16
    ret

// ═══════════════════════════════════════════════════════════════════
// LOCAL FUNCTIONS (no .global — file-private)
// ═══════════════════════════════════════════════════════════════════

// ── .Llocal_helper(w0) -> w0 ────────────────────────────────────────
// Private helper: doubles the input. Not exported.
.Llocal_helper:
    lsl     w0, w0, #1
    ret

// ── .Lincrement_local() ─────────────────────────────────────────────
// Private: increments the local counter.
.Lincrement_local:
    adr     x0, .Llocal_counter
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]
    ret
