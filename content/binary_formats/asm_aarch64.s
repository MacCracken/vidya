// Vidya — Binary Formats in AArch64 Assembly
//
// ELF for AArch64: e_machine = 0xB7 (EM_AARCH64 = 183). Unlike x86
// with its variable-length instructions (1-15 bytes), AArch64 uses
// fixed-width 32-bit instructions. This simplifies binary analysis:
// instruction N is always at offset N*4 from section start. No
// disassembly ambiguity, no instruction boundary problems.
//
// Key ELF constants for AArch64:
//   e_machine  = 0xB7 (183)
//   ELFCLASS64 = 2
//   ELFDATA2LSB = 1 (little-endian)
//   EI_OSABI   = 0 (ELFOSABI_NONE for Linux)

.global _start

.section .rodata
msg_pass:   .ascii "All binary formats examples passed.\n"
msg_len = . - msg_pass

// ── ELF header constants ────────────────────────────────────────────
.equ ELFCLASS64,     2
.equ ELFDATA2LSB,    1          // AArch64 is little-endian
.equ EM_AARCH64,     0xB7      // 183 decimal
.equ ET_EXEC,        2         // executable
.equ EI_MAG0,        0x7F      // ELF magic byte 0
.equ ELF_E,          0x45      // 'E'
.equ ELF_L,          0x4C      // 'L'
.equ ELF_F,          0x46      // 'F'

// ── AArch64 instruction format constants ────────────────────────────
.equ INSN_SIZE,      4          // every instruction is 4 bytes
.equ MOVZ_OPC,      0xD2800000 // MOVZ Xd, #imm16

// Section type constants
.equ SHT_PROGBITS,  1
.equ SHT_NOBITS,    8          // .bss

.section .data
.align 2

// Simulated ELF header fields (first 20 bytes of interest)
elf_header_sim:
    .byte   EI_MAG0             // e_ident[0] = 0x7F
    .byte   ELF_E               // e_ident[1] = 'E'
    .byte   ELF_L               // e_ident[2] = 'L'
    .byte   ELF_F               // e_ident[3] = 'F'
    .byte   ELFCLASS64          // e_ident[4] = class (64-bit)
    .byte   ELFDATA2LSB         // e_ident[5] = data (little-endian)
    .byte   1                   // e_ident[6] = version (EV_CURRENT)
    .byte   0                   // e_ident[7] = OS/ABI
    .byte   0,0,0,0,0,0,0,0    // e_ident[8..15] = padding
    .hword  ET_EXEC             // e_type = executable
    .hword  EM_AARCH64          // e_machine = AArch64

// Sample "code section": 3 fixed-width instructions
.align 2
code_section:
    .word   0xD2800540          // MOV X0, #42
    .word   0xD2800BA8          // MOV X8, #93
    .word   0xD4000001          // SVC #0
code_section_insns = (. - code_section) / INSN_SIZE

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: ELF magic bytes ─────────────────────────────────────
    adr     x0, elf_header_sim
    ldrb    w1, [x0, #0]
    cmp     w1, #0x7F
    b.ne    fail

    ldrb    w1, [x0, #1]
    cmp     w1, #'E'
    b.ne    fail

    ldrb    w1, [x0, #2]
    cmp     w1, #'L'
    b.ne    fail

    ldrb    w1, [x0, #3]
    cmp     w1, #'F'
    b.ne    fail

    // ── Test 2: ELF class = 64-bit ──────────────────────────────────
    ldrb    w1, [x0, #4]
    cmp     w1, ELFCLASS64
    b.ne    fail

    // ── Test 3: ELF data = little-endian ────────────────────────────
    ldrb    w1, [x0, #5]
    cmp     w1, ELFDATA2LSB
    b.ne    fail

    // ── Test 4: e_machine = EM_AARCH64 (0xB7) ──────────────────────
    ldrh    w1, [x0, #18]          // e_machine at offset 18
    cmp     w1, EM_AARCH64
    b.ne    fail

    // ── Test 5: e_type = ET_EXEC ────────────────────────────────────
    ldrh    w1, [x0, #16]          // e_type at offset 16
    cmp     w1, ET_EXEC
    b.ne    fail

    // ── Test 6: fixed-width instruction count ───────────────────────
    // Total bytes / 4 = instruction count. No ambiguity.
    mov     w0, code_section_insns
    cmp     w0, #3
    b.ne    fail

    // ── Test 7: instruction at index N is at byte offset N*4 ────────
    // Instruction 0 at offset 0
    adr     x0, code_section
    ldr     w1, [x0, #0]           // insn[0]
    mov     w2, #0x0540
    movk    w2, #0xD280, lsl #16   // MOV X0, #42 = 0xD2800540
    cmp     w1, w2
    b.ne    fail

    // Instruction 2 at offset 8 (2 * 4)
    ldr     w1, [x0, #8]           // insn[2]
    mov     w2, #0x0001
    movk    w2, #0xD400, lsl #16   // SVC #0 = 0xD4000001
    cmp     w1, w2
    b.ne    fail

    // ── Test 8: extract rd from MOV instruction ─────────────────────
    // MOVZ encoding: bits [4:0] = Rd
    ldr     w1, [x0, #0]           // MOV X0, #42
    and     w2, w1, #0x1F          // extract Rd
    cmp     w2, #0                 // Rd = X0
    b.ne    fail

    ldr     w1, [x0, #4]           // MOV X8, #93
    and     w2, w1, #0x1F
    cmp     w2, #8                 // Rd = X8
    b.ne    fail

    // ── Test 9: extract immediate from MOVZ ─────────────────────────
    // MOVZ encoding: bits [20:5] = imm16
    ldr     w1, [x0, #0]           // MOV X0, #42
    ubfx    w2, w1, #5, #16        // extract bits [20:5]
    cmp     w2, #42
    b.ne    fail

    // ── Test 10: section type constants ─────────────────────────────
    mov     w0, SHT_PROGBITS
    cmp     w0, #1
    b.ne    fail

    mov     w0, SHT_NOBITS
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
