// Vidya — Boot and Startup in AArch64 Assembly
//
// AArch64 boot concepts are fundamentally different from x86_64. Instead
// of real/protected/long mode transitions, AArch64 has Exception Levels:
//   EL3 — Secure Monitor (firmware/TrustZone)
//   EL2 — Hypervisor
//   EL1 — OS Kernel
//   EL0 — User applications
//
// At reset, the CPU starts at the highest implemented EL (typically EL3).
// Boot firmware drops to EL2, hypervisor drops to EL1, kernel drops to EL0.
//
// Key system registers:
//   SCTLR_EL1 — System Control Register (MMU enable, caches, alignment)
//   VBAR_EL1  — Vector Base Address Register (exception table base)
//   MAIR_EL1  — Memory Attribute Indirection Register
//   TCR_EL1   — Translation Control Register (page table config)
//   TTBR0_EL1 — Translation Table Base Register 0 (user space)
//   TTBR1_EL1 — Translation Table Base Register 1 (kernel space)
//
// This file defines the DATA STRUCTURES and CONSTANTS a bootloader uses.
// The code runs as a normal Linux process but the constants are exactly
// what a real AArch64 kernel initializes.

.global _start

.section .data
.align 8

// ── Exception Level constants ─────────────────────────────────────
// CurrentEL register bits [3:2] indicate current EL
EL0 = 0             // bits [3:2] = 00
EL1 = 4             // bits [3:2] = 01 (value 4 = 0b0100)
EL2 = 8             // bits [3:2] = 10 (value 8 = 0b1000)
EL3 = 12            // bits [3:2] = 11 (value 12 = 0b1100)

// ── SCTLR_EL1 bit definitions ────────────────────────────────────
// System Control Register — controls MMU, caches, alignment checks
SCTLR_M   = 1 << 0          // 0x001 — MMU enable
SCTLR_A   = 1 << 1          // 0x002 — Alignment check enable
SCTLR_C   = 1 << 2          // 0x004 — Data cache enable
SCTLR_I   = 1 << 12         // 0x1000 — Instruction cache enable
SCTLR_WXN = 1 << 19         // Write execute never
SCTLR_EE  = 1 << 25         // Exception endianness (0=LE)

sctlr_m:   .quad SCTLR_M
sctlr_a:   .quad SCTLR_A
sctlr_c:   .quad SCTLR_C
sctlr_i:   .quad SCTLR_I

// ── TCR_EL1 fields ───────────────────────────────────────────────
// Translation Control Register — configures page table walks
//   T0SZ [5:0]   — size offset of TTBR0 region (64 - VA bits)
//   T1SZ [21:16] — size offset of TTBR1 region
//   TG0  [15:14] — TTBR0 granule: 00=4KB, 01=64KB, 10=16KB
//   TG1  [31:30] — TTBR1 granule: 10=4KB, 01=16KB, 11=64KB
//   IPS  [34:32] — intermediate physical address size
TCR_T0SZ_48 = 16             // 64 - 48 = 16 for 48-bit VA
TCR_T1SZ_48 = 16 << 16      // same for TTBR1
TCR_TG0_4K  = 0 << 14       // 4KB granule for TTBR0
TCR_TG1_4K  = 2 << 30       // 4KB granule for TTBR1 (encoding: 10)

tcr_t0sz:  .quad TCR_T0SZ_48
tcr_t1sz:  .quad TCR_T1SZ_48

// ── MAIR_EL1 — Memory Attribute Indirection Register ──────────────
// Defines memory types indexed by page table attribute bits
//   Attr0 = 0x00 — Device-nGnRnE (device memory, strongly ordered)
//   Attr1 = 0xFF — Normal, outer/inner write-back cacheable
//   Attr2 = 0x44 — Normal, outer/inner non-cacheable
MAIR_DEVICE = 0x00
MAIR_NORMAL = 0xFF
MAIR_NC     = 0x44
MAIR_VALUE  = MAIR_DEVICE | (MAIR_NORMAL << 8) | (MAIR_NC << 16)

mair_val:  .quad MAIR_VALUE

// ── VBAR_EL1 — Vector Base Address Register ──────────────────────
// Points to the exception vector table. Must be 2KB (0x800) aligned.
// The table has 4 groups of 4 entries, each entry is 128 bytes (32 instructions).
//   Group 0: Current EL with SP_EL0 (sync, irq, fiq, serror)
//   Group 1: Current EL with SP_ELx (sync, irq, fiq, serror)
//   Group 2: Lower EL using AArch64 (sync, irq, fiq, serror)
//   Group 3: Lower EL using AArch32 (sync, irq, fiq, serror)
VBAR_ALIGNMENT = 0x800       // 2KB alignment required

// ── SPSR_EL1 — Saved Program Status Register ─────────────────────
// Set when dropping from EL1 to EL0 via ERET
//   [3:0] M — target exception level and SP selection
//   [6]   F — FIQ mask
//   [7]   I — IRQ mask
//   [8]   A — SError mask
//   [9]   D — Debug mask
SPSR_EL0  = 0x00             // target EL0, use SP_EL0
SPSR_DAIF = 0x3C0            // mask all async exceptions (D|A|I|F)

// ── Stack setup constants ─────────────────────────────────────────
KERNEL_STACK_SIZE = 4 * 4096         // 16KB kernel stack
KERNEL_STACK_BASE = 0xFFFF000000000000  // typical kernel VA

.section .rodata
msg_pass:   .ascii "All boot and startup examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Verify Exception Level constants ──────────────────────────
    // CurrentEL register returns EL in bits [3:2]
    mov     x0, EL0
    cmp     x0, #0
    b.ne    fail

    mov     x0, EL1
    cmp     x0, #4              // bits [3:2] = 01
    b.ne    fail

    mov     x0, EL2
    cmp     x0, #8              // bits [3:2] = 10
    b.ne    fail

    mov     x0, EL3
    cmp     x0, #12             // bits [3:2] = 11
    b.ne    fail

    // ── Verify SCTLR bit positions ────────────────────────────────
    // Boot sequence: enable caches first, then MMU
    adr     x4, sctlr_m
    ldr     x0, [x4]
    cmp     x0, #1              // bit 0 — MMU enable
    b.ne    fail

    adr     x4, sctlr_c
    ldr     x0, [x4]
    cmp     x0, #4              // bit 2 — data cache
    b.ne    fail

    adr     x4, sctlr_i
    ldr     x0, [x4]
    mov     x1, #0x1000
    cmp     x0, x1              // bit 12 — instruction cache
    b.ne    fail

    // ── Verify TCR_EL1 T0SZ for 48-bit VA ─────────────────────────
    // T0SZ = 64 - 48 = 16
    adr     x4, tcr_t0sz
    ldr     x0, [x4]
    cmp     x0, #16
    b.ne    fail

    // ── Verify MAIR attribute values ──────────────────────────────
    adr     x4, mair_val
    ldr     x0, [x4]
    // Extract Attr0 (bits [7:0]): should be 0x00 (device memory)
    and     x1, x0, #0xFF
    cmp     x1, #0x00
    b.ne    fail

    // Extract Attr1 (bits [15:8]): should be 0xFF (normal cacheable)
    lsr     x1, x0, #8
    and     x1, x1, #0xFF
    cmp     x1, #0xFF
    b.ne    fail

    // Extract Attr2 (bits [23:16]): should be 0x44 (non-cacheable)
    lsr     x1, x0, #16
    and     x1, x1, #0xFF
    cmp     x1, #0x44
    b.ne    fail

    // ── Verify VBAR alignment requirement ─────────────────────────
    mov     x0, VBAR_ALIGNMENT
    mov     x1, #0x800
    cmp     x0, x1
    b.ne    fail
    // Alignment check: VBAR & (0x800 - 1) must be 0
    sub     x2, x1, #1          // mask = 0x7FF
    tst     x0, x2              // aligned VBAR & mask should be 0
    b.ne    fail

    // ── Verify SPSR values ────────────────────────────────────────
    mov     x0, SPSR_EL0
    cmp     x0, #0              // EL0 target
    b.ne    fail

    mov     x0, SPSR_DAIF
    mov     x1, #0x3C0
    cmp     x0, x1
    b.ne    fail

    // ── Demonstrate what AArch64 boot code does (as comments) ─────
    // A real AArch64 bootloader at EL1 would do:
    //   mrs x0, CurrentEL         // check current exception level
    //   msr VBAR_EL1, x1          // set exception vector base
    //   msr MAIR_EL1, x2          // set memory attributes
    //   msr TCR_EL1, x3           // configure translation
    //   msr TTBR0_EL1, x4         // set user page tables
    //   msr TTBR1_EL1, x5         // set kernel page tables
    //   isb                        // instruction synchronization barrier
    //   mrs x0, SCTLR_EL1         // read system control
    //   orr x0, x0, #SCTLR_M      // enable MMU
    //   orr x0, x0, #SCTLR_C      // enable data cache
    //   orr x0, x0, #SCTLR_I      // enable instruction cache
    //   msr SCTLR_EL1, x0         // write back
    //   isb                        // ensure changes take effect
    //   msr SPSR_EL1, xzr         // clear saved program status
    //   msr ELR_EL1, x6           // set return address for ERET
    //   eret                       // drop to EL0

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
