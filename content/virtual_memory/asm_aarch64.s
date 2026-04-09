// Vidya — Virtual Memory in AArch64 Assembly
//
// AArch64 uses a 4-level page table with 4KB granule (or 3-level with
// 64KB granule). With 4KB pages and 48-bit VA:
//   Level 0 [47:39] — 512 entries, each covers 512 GB
//   Level 1 [38:30] — 512 entries, each covers 1 GB (1GB block possible)
//   Level 2 [29:21] — 512 entries, each covers 2 MB (2MB block possible)
//   Level 3 [20:12] — 512 entries, each covers 4 KB (page descriptor)
//   [11:0]          — page offset (4KB)
//
// AArch64 has TWO page table base registers:
//   TTBR0_EL1 — user space (lower VA range: 0x0000_xxxx_xxxx_xxxx)
//   TTBR1_EL1 — kernel space (upper VA range: 0xFFFF_xxxx_xxxx_xxxx)
//
// Page table entry (PTE) format — 64 bits:
//   Bit 0:    Valid (must be 1 for valid entry)
//   Bit 1:    Table/Block (1=table at L0-L2, 1=page at L3)
//   [4:2]:    AttrIndx — index into MAIR_EL1
//   Bit 5:    NS — Non-Secure (for TrustZone)
//   Bit 6:    AP[1] — 0=RW, 1=RO
//   Bit 7:    AP[2] — 0=EL1 only, 1=EL0 accessible
//   [9:8]:    SH — Shareability (00=non, 10=outer, 11=inner)
//   Bit 10:   AF — Access Flag (must be 1 or hardware sets it)
//   [47:12]:  Output address (physical page frame)
//   Bit 53:   PXN — Privileged Execute Never
//   Bit 54:   UXN/XN — User/Execute Never

.global _start

.section .data
.align 8

// ── Page table entry flag constants ────────────────────────────────
PTE_VALID       = 1 << 0        // 0x001 — entry is valid
PTE_TABLE       = 1 << 1        // 0x002 — table descriptor (L0-L2)
PTE_PAGE        = 1 << 1        // 0x002 — page descriptor (L3)
PTE_ATTRINDX_0  = 0 << 2        // Device memory (MAIR index 0)
PTE_ATTRINDX_1  = 1 << 2        // Normal cacheable (MAIR index 1)
PTE_AP_RW_EL1   = 0 << 6        // Read/Write, EL1 only
PTE_AP_RO_EL1   = 1 << 6        // Read-only, EL1 only
PTE_AP_RW_EL0   = 1 << 7        // EL0 accessible (user)
PTE_SH_INNER    = 3 << 8        // Inner shareable
PTE_SH_OUTER    = 2 << 8        // Outer shareable
PTE_AF          = 1 << 10       // Access Flag (set = accessed)
PTE_PXN         = 1 << 53       // Privileged Execute Never
PTE_UXN         = 1 << 54       // User Execute Never

PAGE_SIZE       = 4096           // 4KB standard page
HUGE_PAGE_SIZE  = 2 * 1024 * 1024  // 2MB huge page (block at Level 2)
GIGA_PAGE_SIZE  = 1024 * 1024 * 1024  // 1GB (block at Level 1)
PAGE_SHIFT      = 12             // log2(4096) = 12
PHYS_ADDR_MASK  = 0x0000FFFFFFFFF000  // bits [47:12] — physical frame

// Common PTE combinations
PTE_KERN_RW  = PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER | PTE_AP_RW_EL1
PTE_KERN_RO  = PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER | PTE_AP_RO_EL1
PTE_USER_RW  = PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER | PTE_AP_RW_EL0
PTE_USER_RO  = PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER | PTE_AP_RO_EL1 | PTE_AP_RW_EL0

// Physical address mask stored in memory (not representable as AArch64 immediate)
.align 8
phys_mask:  .quad PHYS_ADDR_MASK
user_rw_flags: .quad PTE_USER_RW

// Simulated page table entries
.align 8
sample_pte_kern_code:
    .quad 0x0000000000200000 | PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER | PTE_AP_RO_EL1
    // Physical frame at 2MB, kernel read-only code
sample_pte_kern_data:
    .quad 0x0000000000201000 | PTE_KERN_RW
    // Physical frame at 2MB+4KB, kernel RW data
sample_pte_user_code:
    .quad 0x0000000000400000 | PTE_USER_RO
    // Physical frame at 4MB, user read-only
sample_pte_not_present:
    .quad 0x0000000000000000
    // Not valid — will cause translation fault
sample_pte_block:
    .quad 0x0000000000600000 | PTE_VALID | PTE_AF | PTE_ATTRINDX_1 | PTE_SH_INNER
    // 2MB block descriptor at 6MB (no PTE_TABLE bit = block at L2)

// Virtual address decomposition test value
// Address: 0x0000_0000_4020_3ABC
//   L0 [47:39]: 000000000 = 0
//   L1 [38:30]: 000000001 = 1
//   L2 [29:21]: 000000001 = 1   (0x00200000 >> 21 = 1)
//   L3 [20:12]: 000000011 = 3   (0x3000 >> 12 = 3)
//   Offset [11:0]: 0xABC
test_vaddr: .quad 0x0000000040203ABC

// Path for /proc/self/maps
proc_maps_path: .asciz "/proc/self/maps"

.section .bss
.align 8
maps_buf:   .skip 4096

.section .rodata
msg_pass:   .ascii "All virtual memory examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ════════════════════════════════════════════════════════════════
    // 1. Verify PTE flag constants
    // ════════════════════════════════════════════════════════════════
    mov     x0, PTE_VALID
    cmp     x0, #1
    b.ne    fail

    mov     x0, PTE_TABLE
    cmp     x0, #2
    b.ne    fail

    mov     x0, PTE_AF
    mov     x1, #0x400
    cmp     x0, x1              // bit 10
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 2. Extract flags from a PTE
    // ════════════════════════════════════════════════════════════════
    adr     x3, sample_pte_kern_data
    ldr     x0, [x3]

    // Test if valid
    tst     x0, PTE_VALID
    b.eq    fail                // kernel data should be valid

    // Test Access Flag is set
    mov     x1, PTE_AF
    tst     x0, x1
    b.eq    fail

    // Test it's NOT user-accessible (AP[2] = bit 7 should be 0)
    tst     x0, PTE_AP_RW_EL0
    b.ne    fail                // kernel data must not be EL0 accessible

    // ════════════════════════════════════════════════════════════════
    // 3. Extract physical address from PTE
    // ════════════════════════════════════════════════════════════════
    adr     x3, sample_pte_kern_data
    ldr     x0, [x3]
    adr     x4, phys_mask
    ldr     x1, [x4]
    and     x0, x0, x1          // mask off flag bits
    mov     x1, #0x1000
    movk    x1, #0x20, lsl #16  // x1 = 0x201000
    cmp     x0, x1              // should be 2MB + 4KB
    b.ne    fail

    // Extract page frame number (physical address >> 12)
    lsr     x0, x0, PAGE_SHIFT
    cmp     x0, #0x201          // PFN = 0x201
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 4. Build a PTE from physical address + flags
    // ════════════════════════════════════════════════════════════════
    // make_pte(phys=0x300000, flags=USER_RW)
    mov     x0, #0x300000       // physical address (page-aligned)
    movk    x0, #0, lsl #48    // ensure top bits clear
    orr     x0, x0, PTE_USER_RW // add flags
    // Verify the PTE
    and     x1, x0, #0xFFF      // extract low 12 bits (flags)
    mov     x2, PTE_USER_RW
    and     x2, x2, #0xFFF
    cmp     x1, x2
    b.ne    fail

    mov     x1, PHYS_ADDR_MASK
    and     x1, x0, x1
    mov     x2, #0x300000
    cmp     x1, x2
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 5. Virtual address decomposition
    // ════════════════════════════════════════════════════════════════
    // Split 0x0000000040203ABC into page table indices
    adr     x3, test_vaddr
    ldr     x0, [x3]

    // L0 index: bits [47:39]
    lsr     x1, x0, #39
    and     x1, x1, #0x1FF      // 9-bit mask
    cmp     x1, #0               // L0 index = 0
    b.ne    fail

    // L1 index: bits [38:30]
    lsr     x1, x0, #30
    and     x1, x1, #0x1FF
    cmp     x1, #1               // L1 index = 1
    b.ne    fail

    // L2 index: bits [29:21]
    lsr     x1, x0, #21
    and     x1, x1, #0x1FF
    cmp     x1, #1               // L2 index = 1
    b.ne    fail

    // L3 index: bits [20:12]
    lsr     x1, x0, #12
    and     x1, x1, #0x1FF
    cmp     x1, #3               // L3 index = 3
    b.ne    fail

    // Page offset: bits [11:0]
    and     x1, x0, #0xFFF
    mov     x2, #0xABC
    cmp     x1, x2               // offset = 0xABC
    b.ne    fail

    // ════════════════════════════════════════════════════════════════
    // 6. Check block descriptor (2MB huge page)
    // ════════════════════════════════════════════════════════════════
    adr     x3, sample_pte_block
    ldr     x0, [x3]
    tst     x0, PTE_VALID
    b.eq    fail                 // should be valid

    // Block descriptors at L2 do NOT have the Table bit set
    // (bit 1 = 0 for block, 1 for table at L0-L2)
    // But our sample has bit 1 = 0 since we didn't set PTE_TABLE
    // For a 2MB block, the physical address must be 2MB aligned
    mov     x1, PHYS_ADDR_MASK
    and     x0, x0, x1
    mov     x1, #0x1FFFFF       // 2MB - 1
    tst     x0, x1
    b.ne    fail                 // physical address must be 2MB aligned

    // ════════════════════════════════════════════════════════════════
    // 7. Test not-present page detection
    // ════════════════════════════════════════════════════════════════
    adr     x3, sample_pte_not_present
    ldr     x0, [x3]
    tst     x0, PTE_VALID
    b.ne    fail                 // should NOT be valid

    // ════════════════════════════════════════════════════════════════
    // 8. Read /proc/self/maps — see our own virtual memory layout
    // ════════════════════════════════════════════════════════════════
    // openat(AT_FDCWD, path, O_RDONLY)
    mov     x8, #56             // sys_openat (AArch64)
    mov     x0, #-100           // AT_FDCWD
    adr     x1, proc_maps_path
    mov     x2, #0              // O_RDONLY
    mov     x3, #0              // mode (unused)
    svc     #0
    cmp     x0, #0
    b.lt    fail
    mov     x19, x0             // save fd

    // read(fd, buf, 4095)
    mov     x8, #63             // sys_read
    mov     x0, x19
    adr     x1, maps_buf
    mov     x2, #4095
    svc     #0
    cmp     x0, #0
    b.le    fail
    mov     x20, x0             // save bytes read

    // close(fd)
    mov     x8, #57             // sys_close
    mov     x0, x19
    svc     #0

    // Write portion of maps to stdout
    mov     x2, x20
    cmp     x2, #200
    b.le    .maps_write
    mov     x2, #200
.maps_write:
    mov     x8, #64
    mov     x0, #1
    adr     x1, maps_buf
    svc     #0

    // ════════════════════════════════════════════════════════════════
    // 9. AArch64 split address space
    // ════════════════════════════════════════════════════════════════
    // AArch64 uses TTBR0 for low addresses and TTBR1 for high:
    //   User:   0x0000_0000_0000_0000 — 0x0000_FFFF_FFFF_FFFF
    //   Kernel: 0xFFFF_0000_0000_0000 — 0xFFFF_FFFF_FFFF_FFFF
    // Unlike x86_64's canonical form, AArch64 checks top bits directly.
    // Our SP should be in user space (top 16 bits = 0x0000)
    mov     x0, sp
    lsr     x0, x0, #48         // get top 16 bits
    cmp     x0, #0              // should be 0 for user space
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
