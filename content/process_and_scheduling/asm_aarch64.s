// Vidya — Process and Scheduling in AArch64 Assembly
//
// Context save/restore: the fundamental operation behind process switching.
// A context switch saves all general-purpose registers (x0-x30), SP, and
// PSTATE for the current task, then loads the saved state of the next task.
// This file demonstrates the pattern with a simulated process context,
// saving and restoring register state.
//
// AArch64 context frame includes:
//   x0-x30  — 31 general-purpose registers (248 bytes)
//   sp      — stack pointer (8 bytes)
//   pc/elr  — program counter / exception link register (8 bytes)
//   pstate  — processor state / SPSR (8 bytes)
//   Total: 272 bytes
//
// Build: aarch64-linux-gnu-as file.s -o out.o && aarch64-linux-gnu-ld out.o -o out && qemu-aarch64 out

.global _start

// ── Process state constants ──────────────────────────────────────
.equ STATE_READY,    0
.equ STATE_RUNNING,  1
.equ STATE_BLOCKED,  2
.equ STATE_ZOMBIE,   3

// ── Context frame layout (offsets into saved context) ────────────
// We save x0-x28 + x29(FP) + x30(LR) + SP = 32 quadwords = 256 bytes
.equ CTX_X0,    0
.equ CTX_X1,    8
.equ CTX_X2,    16
.equ CTX_X3,    24
.equ CTX_X4,    32
.equ CTX_X5,    40
.equ CTX_X6,    48
.equ CTX_X7,    56
.equ CTX_X8,    64
.equ CTX_X9,    72
.equ CTX_X10,   80
.equ CTX_X11,   88
.equ CTX_X12,   96
.equ CTX_X13,   104
.equ CTX_X14,   112
.equ CTX_X15,   120
.equ CTX_X16,   128
.equ CTX_X17,   136
.equ CTX_X18,   144
.equ CTX_X19,   152
.equ CTX_X20,   160
.equ CTX_X21,   168
.equ CTX_X22,   176
.equ CTX_X23,   184
.equ CTX_X24,   192
.equ CTX_X25,   200
.equ CTX_X26,   208
.equ CTX_X27,   216
.equ CTX_X28,   224
.equ CTX_X29,   232
.equ CTX_X30,   240
.equ CTX_SP,    248
.equ CTX_SIZE,  256

.section .text

_start:
    // ── Test 1: Save context to process A's context block ─────────
    // Load known values into registers we'll test
    mov     x19, #0x1111
    mov     x20, #0x2222
    mov     x21, #0x3333
    mov     x22, #0x4444
    mov     x23, #0x5555
    mov     x24, #0x6666
    mov     x25, #0x7777
    mov     x26, #0x8888
    mov     x27, #0x9999
    mov     x28, #0xAAAA

    // Save context — a real kernel does this in the exception handler
    // Using x0 as the context pointer (would be passed by scheduler)
    adr     x0, ctx_a

    // Save callee-saved registers (x19-x28)
    // A kernel saves ALL registers; we focus on callee-saved for the test
    stp     x19, x20, [x0, #CTX_X19]
    stp     x21, x22, [x0, #CTX_X21]
    stp     x23, x24, [x0, #CTX_X23]
    stp     x25, x26, [x0, #CTX_X25]
    stp     x27, x28, [x0, #CTX_X27]

    // Save FP (x29) and LR (x30)
    stp     x29, x30, [x0, #CTX_X29]

    // Save SP
    mov     x1, sp
    str     x1, [x0, #CTX_SP]

    // ── Test 2: Clobber all registers (simulate running process B)
    mov     x19, #0
    mov     x20, #0
    mov     x21, #0
    mov     x22, #0
    mov     x23, #0
    mov     x24, #0
    mov     x25, #0
    mov     x26, #0
    mov     x27, #0
    mov     x28, #0

    // ── Test 3: Restore context from process A's context block ────
    adr     x0, ctx_a

    // Restore SP first
    ldr     x1, [x0, #CTX_SP]
    mov     sp, x1

    // Restore FP and LR
    ldp     x29, x30, [x0, #CTX_X29]

    // Restore callee-saved registers
    ldp     x19, x20, [x0, #CTX_X19]
    ldp     x21, x22, [x0, #CTX_X21]
    ldp     x23, x24, [x0, #CTX_X23]
    ldp     x25, x26, [x0, #CTX_X25]
    ldp     x27, x28, [x0, #CTX_X27]

    // ── Test 4: Verify all registers were restored correctly ──────
    mov     x0, #0x1111
    cmp     x19, x0
    b.ne    fail
    mov     x0, #0x2222
    cmp     x20, x0
    b.ne    fail
    mov     x0, #0x3333
    cmp     x21, x0
    b.ne    fail
    mov     x0, #0x4444
    cmp     x22, x0
    b.ne    fail
    mov     x0, #0x5555
    cmp     x23, x0
    b.ne    fail
    mov     x0, #0x6666
    cmp     x24, x0
    b.ne    fail
    mov     x0, #0x7777
    cmp     x25, x0
    b.ne    fail
    mov     x0, #0x8888
    cmp     x26, x0
    b.ne    fail
    mov     x0, #0x9999
    cmp     x27, x0
    b.ne    fail
    mov     x0, #0xAAAA
    cmp     x28, x0
    b.ne    fail

    // ── Test 5: Verify process state constants ────────────────────
    mov     x0, STATE_READY
    cmp     x0, #0
    b.ne    fail

    mov     x0, STATE_RUNNING
    cmp     x0, #1
    b.ne    fail

    mov     x0, STATE_BLOCKED
    cmp     x0, #2
    b.ne    fail

    mov     x0, STATE_ZOMBIE
    cmp     x0, #3
    b.ne    fail

    // ── Test 6: Context size sanity ───────────────────────────────
    mov     x0, CTX_SIZE
    mov     x1, #256
    cmp     x0, x1
    b.ne    fail

    // ── Test 7: STP/LDP pair efficiency ───────────────────────────
    // AArch64's STP/LDP stores/loads two 64-bit registers in one
    // instruction, making context save/restore twice as fast as
    // x86_64's individual push/pop per register.
    // Demonstrate with a mini save/restore cycle:
    sub     sp, sp, #32
    mov     x0, #0xBBBB
    mov     x1, #0xCCCC
    mov     x2, #0xDDDD
    mov     x3, #0xEEEE
    stp     x0, x1, [sp]        // save 2 regs in 1 instruction
    stp     x2, x3, [sp, #16]   // save 2 more
    // Clobber
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    // Restore
    ldp     x0, x1, [sp]
    ldp     x2, x3, [sp, #16]
    add     sp, sp, #32

    mov     x4, #0xBBBB
    cmp     x0, x4
    b.ne    fail
    mov     x4, #0xCCCC
    cmp     x1, x4
    b.ne    fail
    mov     x4, #0xDDDD
    cmp     x2, x4
    b.ne    fail
    mov     x4, #0xEEEE
    cmp     x3, x4
    b.ne    fail

    // ── All passed ────────────────────────────────────────────────
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

// ── Context storage ──────────────────────────────────────────────
.section .bss
.align 4
ctx_a:  .skip CTX_SIZE             // Process A context block
ctx_b:  .skip CTX_SIZE             // Process B context block

.section .rodata
msg_pass:
    .ascii "All process and scheduling examples passed.\n"
    msg_len = . - msg_pass
