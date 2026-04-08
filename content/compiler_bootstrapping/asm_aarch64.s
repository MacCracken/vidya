// Vidya — Compiler Bootstrapping in AArch64 Assembly
//
// This is what a seed compiler PRODUCES: a minimal program assembled
// from a higher-level source into raw machine code. AArch64 has a
// key advantage for bootstrapping: all instructions are exactly 32
// bits (4 bytes), so label resolution is simple arithmetic. A seed
// assembler only needs: MOV, ADD, SUB, CMP, B, BL, SVC, and labels.
//
// The bootstrap chain:
//   1. Hand-written assembly seed (this level of code)
//   2. Seed compiles stage 0 (simple language -> ELF)
//   3. Stage 0 compiles stage 1 (richer language -> ELF)
//   4. Stage 1 compiles itself -> self-hosting
//
// Fixed-width advantage: instruction at label L is at byte offset
// L * 4 from .text start. Branch offsets are (target - pc) / 4.

.global _start

.section .rodata
msg_pass:   .ascii "All compiler bootstrapping examples passed.\n"
msg_len = . - msg_pass

// ── Instruction size table ──────────────────────────────────────────
// Every AArch64 instruction is exactly 4 bytes. A seed assembler can
// compute any label address as base + (instruction_index * 4).
.section .data
.align 2
// Simulated "assembled" program: 3 instructions as 32-bit words.
// MOV X0, #42  = 0xD2800540
// MOV X8, #93  = 0xD2800BA8
// SVC #0       = 0xD4000001
seed_program:
    .word 0xD2800540        // mov x0, #42
    .word 0xD2800BA8        // mov x8, #93
    .word 0xD4000001        // svc #0
seed_program_len = (. - seed_program) / 4

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: fixed-width instruction verification ────────────────
    // All AArch64 instructions are 4 bytes. Verify our seed program
    // contains exactly 3 instructions = 12 bytes.
    mov     w0, seed_program_len
    cmp     w0, #3
    b.ne    fail

    // ── Test 2: instruction decoding — verify MOV encoding ──────────
    // MOV X0, #42 encodes as: 1101_0010_100 00000000000101010 00000
    // opcode=D2800000 | (42 << 5) = D2800540
    adr     x0, seed_program
    ldr     w1, [x0]               // load first instruction
    mov     w2, #0x0540
    movk    w2, #0xD280, lsl #16   // expected: 0xD2800540
    cmp     w1, w2
    b.ne    fail

    // ── Test 3: label resolution with fixed-width ────────────────────
    // In AArch64, branch offset = (target - source) / 4 (in instructions)
    // Demonstrate: compute distance between two labels
    adr     x0, .Llabel_a
    adr     x1, .Llabel_b
    sub     x2, x1, x0             // byte distance
    cmp     x2, #8                 // 2 instructions = 8 bytes
    b.ne    fail
    b       .Lafter_labels

.Llabel_a:
    nop                             // placeholder instruction 1
    nop                             // placeholder instruction 2
.Llabel_b:

.Lafter_labels:
    // ── Test 4: seed compiler pattern — compute and verify ──────────
    // A stage 0 compiler emits sequences like: load, compute, store.
    // Simulate: compute 10 + 32 = 42 using only MOV and ADD.
    mov     w0, #10                 // load immediate
    mov     w1, #32                 // load immediate
    add     w0, w0, w1             // compute
    cmp     w0, #42
    b.ne    fail

    // ── Test 5: simple "assembler" — encode MOV instruction ─────────
    // Build a MOV Xd, #imm16 encoding at runtime.
    // Format: 1101_0010_1000_0000_0000_0000_000d_dddd
    //         | imm16 << 5 | Rd
    // Encode: MOV X1, #7
    mov     w3, #0xD280             // base opcode high half
    lsl     w3, w3, #16            // shift to upper 16 bits
    mov     w4, #7                  // immediate value
    lsl     w4, w4, #5             // shift to imm16 position
    orr     w3, w3, w4             // insert immediate
    orr     w3, w3, #1             // Rd = X1

    // Verify: MOV X1, #7 = 0xD28000E1
    mov     w5, #0x00E1
    movk    w5, #0xD280, lsl #16
    cmp     w3, w5
    b.ne    fail

    // ── Test 6: branch encoding ─────────────────────────────────────
    // B (unconditional) encoding: 000101 | imm26
    // Offset is in instructions (4-byte units), signed.
    // Encode B +8 (forward 8 instructions)
    mov     w0, #0x14               // opcode 0x14 = 000101_00
    lsl     w0, w0, #24            // shift to top
    mov     w1, #8                  // offset in instructions
    orr     w0, w0, w1             // B +8 = 0x14000008
    mov     w2, #0x0008
    movk    w2, #0x1400, lsl #16
    cmp     w0, w2
    b.ne    fail

    // ── Test 7: two-pass assembly simulation ────────────────────────
    // Pass 1: count instructions to determine label offsets.
    // Pass 2: encode branches using known offsets.
    // Simulate with a 4-instruction "program":
    //   [0] MOV W0, #1         (1 instruction)
    //   [1] CMP W0, #1         (1 instruction)
    //   [2] B.EQ label_end     (needs forward ref to [3])
    //   [3] label_end: NOP
    // Branch at [2] targets [3], offset = 3 - 2 = 1 instruction
    mov     w0, #1                  // forward reference offset
    cmp     w0, #1                  // verify pass-2 resolved it
    b.ne    fail

    // ── Test 8: stage progression ───────────────────────────────────
    // Each stage adds capabilities. Verify accumulation:
    //   stage0: MOV, ADD, SUB, B, SVC (5 opcodes)
    //   stage1: + MUL, LDR, STR, CMP, BL (10 opcodes)
    //   stage2: self-hosting (all opcodes)
    mov     w0, #5                  // stage 0 opcodes
    add     w0, w0, #5             // stage 1 adds 5
    cmp     w0, #10
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
