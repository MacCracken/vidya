// Vidya — Instruction Encoding in AArch64 Assembly
//
// AArch64 uses fixed-width 32-bit (4-byte) instructions, unlike x86_64's
// variable-length 1-15 byte encoding. Every instruction is exactly 4 bytes,
// naturally aligned on 4-byte boundaries. This simplifies instruction fetch,
// decode, and branch target calculation.
//
// Instruction format groups (bits [28:25] select the group):
//   Data processing (immediate): 100x
//   Branches:                    101x
//   Loads and stores:            x1x0
//   Data processing (register):  x101
//
// Common encoding fields:
//   [31]    sf — 0 = 32-bit (W registers), 1 = 64-bit (X registers)
//   [30:29] opc — operation variant
//   [28:25] op0 — major group selector
//   [24:21] varies by instruction class
//   [4:0]   Rd — destination register
//   [9:5]   Rn — first source register
//   [20:16] Rm — second source register (register forms)

.global _start

.section .data
.align 8
value:      .quad 42
array:      .quad 10, 20, 30, 40, 50

.section .rodata
msg_pass:   .ascii "All instruction encoding examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ════════════════════════════════════════════════════════════════
    // 1. MOV immediate — uses MOVZ (move wide with zero)
    // ════════════════════════════════════════════════════════════════
    // mov x0, #42                → 0xD2800540
    //   [31]    sf=1 (64-bit)
    //   [30:29] opc=10 (MOVZ)
    //   [28:23] 100101 (move wide immediate class)
    //   [22:21] hw=00 (shift=0, bits [15:0])
    //   [20:5]  imm16=42 (0x002A)
    //   [4:0]   Rd=00000 (x0)
    mov     x0, #42
    cmp     x0, #42
    b.ne    fail

    // mov w1, #1                 → 0x52800021
    //   sf=0 (32-bit W register)
    //   opc=10 (MOVZ)
    //   imm16=1, Rd=00001 (w1)
    mov     w1, #1
    cmp     w1, #1
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 2. ADD immediate — data processing immediate
    // ════════════════════════════════════════════════════════════════
    // add x2, x0, #8             → 0x91002002
    //   [31]    sf=1 (64-bit)
    //   [30:29] op=00 (ADD)
    //   [28:24] 10001 (add/sub immediate class)
    //   [23:22] shift=00 (no shift of immediate)
    //   [21:10] imm12=8
    //   [9:5]   Rn=00000 (x0)
    //   [4:0]   Rd=00010 (x2)
    mov     x0, #42
    add     x2, x0, #8
    cmp     x2, #50
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 3. ADD register — data processing register
    // ════════════════════════════════════════════════════════════════
    // add x3, x0, x1             → 0x8B010003
    //   [31]    sf=1
    //   [30]    op=0 (ADD)
    //   [28:24] 01011 (add/sub register class)
    //   [23:22] shift=00 (LSL #0)
    //   [20:16] Rm=00001 (x1)
    //   [15:10] imm6=000000 (shift amount=0)
    //   [9:5]   Rn=00000 (x0)
    //   [4:0]   Rd=00011 (x3)
    mov     x0, #30
    mov     x1, #12
    add     x3, x0, x1
    cmp     x3, #42
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 4. SUB — same format as ADD, different opcode bit
    // ════════════════════════════════════════════════════════════════
    // sub x4, x3, #2             → 0xD1000864
    //   [30] op=1 (SUB vs ADD)
    //   Otherwise same encoding as ADD immediate
    sub     x4, x3, #2
    cmp     x4, #40
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 5. LDR (immediate offset) — load/store class
    // ════════════════════════════════════════════════════════════════
    // ldr x5, [x6, #8]           → 0xF94004C5
    //   [31:30] size=11 (64-bit)
    //   [29:27] 111 (load/store unsigned offset class)
    //   [26]    V=0 (not SIMD)
    //   [25:24] 01
    //   [23:22] opc=01 (LDR)
    //   [21:10] imm12 = offset/8 (scaled by access size)
    //   [9:5]   Rn = base register
    //   [4:0]   Rt = destination register
    adr     x6, array
    ldr     x5, [x6, #8]       // array[1] = 20
    cmp     x5, #20
    b.ne    fail

    ldr     x5, [x6, #32]      // array[4] = 50
    cmp     x5, #50
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 6. STR (immediate offset) — store to memory
    // ════════════════════════════════════════════════════════════════
    // str x0, [x6]               → 0xF90000C0
    //   Same class as LDR, opc=00 (STR)
    mov     x0, #99
    sub     sp, sp, #16
    str     x0, [sp]
    ldr     x5, [sp]
    add     sp, sp, #16
    cmp     x5, #99
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 7. B (unconditional branch) — branch class
    // ════════════════════════════════════════════════════════════════
    // b target                   → 0x14xxxxxx
    //   [31:26] 000101 (unconditional branch)
    //   [25:0]  imm26 = signed offset / 4
    //   Range: +/- 128 MB
    b       .skip_trap
    mov     x8, #93             // should never execute
    mov     x0, #1
    svc     #0
.skip_trap:

    // ════════════════════════════════════════════════════════════════
    // 8. BL (branch with link) — function call
    // ════════════════════════════════════════════════════════════════
    // bl target                  → 0x94xxxxxx
    //   [31:26] 100101 (branch with link)
    //   [25:0]  imm26 = signed offset / 4
    //   Sets x30 (LR) = address of next instruction
    mov     x0, #10
    mov     x1, #20
    bl      helper_add
    cmp     x0, #30
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 9. B.cond (conditional branch) — compare and branch
    // ════════════════════════════════════════════════════════════════
    // b.eq target                → 0x54xxxxxx
    //   [31:25] 0101010
    //   [24]    0
    //   [23:5]  imm19 = signed offset / 4
    //   [4]     0
    //   [3:0]   cond = condition code
    //     EQ=0000, NE=0001, LT=1011, GE=1010, LE=1101, GT=1100
    mov     x0, #5
    cmp     x0, #5
    b.ne    fail            // cond=0001 (NE)

    cmp     x0, #10
    b.ge    fail            // cond=1010 (GE) — 5 < 10, should not branch

    // ════════════════════════════════════════════════════════════════
    // 10. CBZ/CBNZ — compare and branch on zero/nonzero
    // ════════════════════════════════════════════════════════════════
    // cbz x0, target             → 0xB4xxxxxx
    //   [31] sf=1 (64-bit)
    //   [30:25] 011010
    //   [24] op=0 (CBZ) or 1 (CBNZ)
    //   [23:5]  imm19
    //   [4:0]   Rt = register to test
    mov     x0, #0
    cbnz    x0, fail        // x0 is zero, should NOT branch

    mov     x0, #1
    cbz     x0, fail        // x0 is nonzero, should NOT branch

    // ════════════════════════════════════════════════════════════════
    // 11. ADRP + ADD — PC-relative address generation
    // ════════════════════════════════════════════════════════════════
    // adrp x0, symbol            → 0x90xxxxxx
    //   [31] op=1
    //   [30:29] immlo (2 bits)
    //   [28:24] 10000
    //   [23:5]  immhi (19 bits)
    //   [4:0]   Rd
    //   Computes: Rd = (PC & ~0xFFF) + (imm21 << 12)
    //   Then ADD refines to exact address within the page
    //
    // For small programs, adr (single instruction) suffices:
    adr     x0, value
    ldr     x1, [x0]
    cmp     x1, #42
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 12. Shifted register operand
    // ════════════════════════════════════════════════════════════════
    // add x0, x1, x2, lsl #3    → multiply x2 by 8 and add
    //   shift field [23:22]: 00=LSL, 01=LSR, 10=ASR
    //   imm6 [15:10]: shift amount
    mov     x1, #100
    mov     x2, #5
    add     x0, x1, x2, lsl #3     // 100 + 5*8 = 140
    cmp     x0, #140
    b.ne    fail

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

// ── helper_add ─────────────────────────────────────────────────────
// Args: x0 = a, x1 = b
// Returns: x0 = a + b
helper_add:
    add     x0, x0, x1
    ret
