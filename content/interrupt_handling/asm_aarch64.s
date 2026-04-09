// Vidya — Interrupt Handling in AArch64 Assembly
//
// AArch64 uses an exception vector table pointed to by VBAR_ELx.
// The table has 4 groups of 4 entries, each entry is 128 bytes
// (32 instructions max). Total table size: 4 * 4 * 128 = 2048 bytes.
//
// Vector table layout (at VBAR_ELx):
//   Offset  Group                           Exception type
//   0x000   Current EL with SP_EL0          Synchronous
//   0x080   Current EL with SP_EL0          IRQ
//   0x100   Current EL with SP_EL0          FIQ
//   0x180   Current EL with SP_EL0          SError
//   0x200   Current EL with SP_ELx          Synchronous
//   0x280   Current EL with SP_ELx          IRQ
//   0x300   Current EL with SP_ELx          FIQ
//   0x380   Current EL with SP_ELx          SError
//   0x400   Lower EL using AArch64          Synchronous
//   0x480   Lower EL using AArch64          IRQ
//   0x500   Lower EL using AArch64          FIQ
//   0x580   Lower EL using AArch64          SError
//   0x600   Lower EL using AArch32          Synchronous
//   0x680   Lower EL using AArch32          IRQ
//   0x700   Lower EL using AArch32          FIQ
//   0x780   Lower EL using AArch32          SError
//
// Exception Syndrome Register (ESR_ELx) identifies the cause:
//   [31:26] EC — Exception Class (what type of exception)
//   [25]    IL — Instruction Length (0=16-bit, 1=32-bit)
//   [24:0]  ISS — Instruction Specific Syndrome
//
// Key EC values:
//   0x00 — Unknown reason
//   0x15 — SVC from AArch64 (syscall)
//   0x20 — Instruction abort from lower EL
//   0x21 — Instruction abort from same EL
//   0x24 — Data abort from lower EL
//   0x25 — Data abort from same EL
//
// Build: aarch64-linux-gnu-as file.s -o out.o && aarch64-linux-gnu-ld out.o -o out && qemu-aarch64 out

.global _start

// ── Exception vector offsets ──────────────────────────────────────
.equ VBAR_ENTRY_SIZE,        128     // each vector entry is 128 bytes
.equ VBAR_ENTRIES_PER_GROUP, 4       // sync, irq, fiq, serror
.equ VBAR_NUM_GROUPS,        4       // 4 groups
.equ VBAR_TABLE_SIZE,        2048    // 4 * 4 * 128

// Vector offsets within table
.equ VEC_CUR_SP0_SYNC,      0x000
.equ VEC_CUR_SP0_IRQ,       0x080
.equ VEC_CUR_SP0_FIQ,       0x100
.equ VEC_CUR_SP0_SERROR,    0x180
.equ VEC_CUR_SPX_SYNC,      0x200
.equ VEC_CUR_SPX_IRQ,       0x280
.equ VEC_CUR_SPX_FIQ,       0x300
.equ VEC_CUR_SPX_SERROR,    0x380
.equ VEC_LOW64_SYNC,        0x400
.equ VEC_LOW64_IRQ,         0x480
.equ VEC_LOW64_FIQ,         0x500
.equ VEC_LOW64_SERROR,      0x580
.equ VEC_LOW32_SYNC,        0x600
.equ VEC_LOW32_IRQ,         0x680
.equ VEC_LOW32_FIQ,         0x700
.equ VEC_LOW32_SERROR,      0x780

// ── ESR_ELx Exception Class values ───────────────────────────────
.equ EC_UNKNOWN,             0x00
.equ EC_SVC_AA64,            0x15    // SVC from AArch64
.equ EC_IABT_LOW,            0x20    // Instruction abort, lower EL
.equ EC_IABT_CUR,            0x21    // Instruction abort, current EL
.equ EC_DABT_LOW,            0x24    // Data abort, lower EL
.equ EC_DABT_CUR,            0x25    // Data abort, current EL
.equ EC_SP_ALIGN,            0x26    // SP alignment fault
.equ EC_BRK,                 0x3C    // BRK instruction (debug)

// ── GIC (Generic Interrupt Controller) constants ──────────────────
// AArch64 uses GIC instead of x86's PIC/APIC
.equ GICD_BASE,              0x08000000  // Distributor base (typical)
.equ GICC_BASE,              0x08010000  // CPU interface base (typical)
.equ GICD_CTLR,              0x000       // Distributor control
.equ GICD_ISENABLER,         0x100       // Interrupt set-enable
.equ GICC_IAR,               0x00C       // Interrupt acknowledge
.equ GICC_EOIR,              0x010       // End of interrupt

.section .data
.align 8

// ── Mock vector table entry metadata ──────────────────────────────
// A real kernel fills these at runtime; here we define the layout
// and verify the structure with constants.

// Mock exception context saved on entry
// A handler saves these before processing:
exception_frame:
    .quad   0xAAAA000000000001       // x0
    .quad   0xAAAA000000000002       // x1
    .quad   0xAAAA000000000003       // x2
    .quad   0xAAAA000000000004       // x3
    .quad   0xAAAA000000000005       // x4
    .quad   0                         // ESR value (filled by handler)
    .quad   0                         // ELR value (filled by handler)
    .quad   0                         // SPSR value (filled by handler)

// Simulated ESR values for testing
mock_esr_svc:    .quad (EC_SVC_AA64 << 26) | (1 << 25) | 0x42
                 // EC=SVC, IL=1 (32-bit), ISS=0x42 (syscall number)
mock_esr_dabt:   .quad (EC_DABT_LOW << 26) | (1 << 25) | 0x07
                 // EC=data abort lower, IL=1, ISS=translation fault L3

.section .rodata
msg_pass:   .ascii "All interrupt handling examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Test 1: Verify vector table layout constants ──────────────
    mov     x0, VBAR_ENTRY_SIZE
    cmp     x0, #128
    b.ne    fail

    mov     x0, VBAR_TABLE_SIZE
    mov     x1, #2048
    cmp     x0, x1
    b.ne    fail

    // Entries per group * groups * entry size = table size
    mov     x0, VBAR_ENTRIES_PER_GROUP
    mov     x1, VBAR_NUM_GROUPS
    mul     x0, x0, x1
    mov     x1, VBAR_ENTRY_SIZE
    mul     x0, x0, x1
    mov     x1, #2048
    cmp     x0, x1
    b.ne    fail

    // ── Test 2: Verify vector offsets ─────────────────────────────
    // Each group starts 0x200 apart, each entry within 0x80 apart
    mov     x0, VEC_CUR_SP0_SYNC
    cmp     x0, #0
    b.ne    fail

    mov     x0, VEC_CUR_SP0_IRQ
    cmp     x0, #0x80
    b.ne    fail

    mov     x0, VEC_CUR_SPX_SYNC
    mov     x1, #0x200
    cmp     x0, x1
    b.ne    fail

    mov     x0, VEC_LOW64_SYNC
    mov     x1, #0x400
    cmp     x0, x1
    b.ne    fail

    mov     x0, VEC_LOW32_SERROR
    mov     x1, #0x780
    cmp     x0, x1
    b.ne    fail

    // ── Test 3: Parse ESR — extract Exception Class ───────────────
    // ESR format: [31:26]=EC, [25]=IL, [24:0]=ISS
    adr     x3, mock_esr_svc
    ldr     x0, [x3]

    // Extract EC (bits [31:26])
    lsr     x1, x0, #26
    and     x1, x1, #0x3F       // 6-bit mask
    cmp     x1, EC_SVC_AA64      // should be 0x15
    b.ne    fail

    // Extract IL (bit 25)
    lsr     x1, x0, #25
    and     x1, x1, #1
    cmp     x1, #1               // 32-bit instruction
    b.ne    fail

    // Extract ISS (bits [24:0])
    mov     x1, #0x1FFFFFF       // 25-bit mask
    and     x1, x0, x1
    cmp     x1, #0x42            // syscall number
    b.ne    fail

    // ── Test 4: Parse data abort ESR ──────────────────────────────
    adr     x3, mock_esr_dabt
    ldr     x0, [x3]
    lsr     x1, x0, #26
    and     x1, x1, #0x3F
    cmp     x1, EC_DABT_LOW      // should be 0x24
    b.ne    fail

    // ── Test 5: Verify EC constants ───────────────────────────────
    mov     x0, EC_UNKNOWN
    cmp     x0, #0
    b.ne    fail

    mov     x0, EC_SVC_AA64
    cmp     x0, #0x15
    b.ne    fail

    mov     x0, EC_DABT_LOW
    cmp     x0, #0x24
    b.ne    fail

    mov     x0, EC_BRK
    cmp     x0, #0x3C
    b.ne    fail

    // ── Test 6: Verify exception frame layout ─────────────────────
    adr     x3, exception_frame
    ldr     x0, [x3]            // x0 from frame
    // Build 0xAAAA000000000001 using movz + movk
    movz    x1, #0x0001              // bits [15:0]
    movk    x1, #0x0000, lsl #16     // bits [31:16]
    movk    x1, #0x0000, lsl #32     // bits [47:32]
    movk    x1, #0xAAAA, lsl #48     // bits [63:48]
    cmp     x0, x1
    b.ne    fail

    ldr     x0, [x3, #8]        // x1 from frame
    // Build 0xAAAA000000000002
    movz    x1, #0x0002
    movk    x1, #0x0000, lsl #16
    movk    x1, #0x0000, lsl #32
    movk    x1, #0xAAAA, lsl #48
    cmp     x0, x1
    b.ne    fail

    // ── Test 7: Verify VBAR alignment requirement ─────────────────
    // VBAR must be 2KB (0x800) aligned
    // Test: any address with low 11 bits zero is valid
    mov     x0, #0x800
    mov     x1, #0x7FF           // alignment mask
    tst     x0, x1
    b.ne    fail                 // 0x800 should be aligned

    mov     x0, #0x1000          // 4KB — also aligned
    tst     x0, x1
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
