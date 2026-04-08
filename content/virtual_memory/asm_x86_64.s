# Vidya — Virtual Memory in x86_64 Assembly
#
# x86_64 uses 4-level page tables (5-level with LA57). Virtual addresses
# are 48 bits (canonical form: bits 63:48 = copy of bit 47). Each page
# table has 512 entries (9 bits per level × 4 = 36 bits + 12-bit offset).
#
# Address breakdown (48-bit):
#   [47:39] PML4 index    (Page Map Level 4)
#   [38:30] PDPT index    (Page Directory Pointer Table)
#   [29:21] PD index      (Page Directory)
#   [20:12] PT index      (Page Table)
#   [11:0]  Page offset   (4KB page)
#
# Page Table Entry (PTE) format (64 bits):
#   Bit 0:  Present (P)
#   Bit 1:  Read/Write (R/W)
#   Bit 2:  User/Supervisor (U/S)
#   Bit 3:  Page Write-Through (PWT)
#   Bit 4:  Page Cache Disable (PCD)
#   Bit 5:  Accessed (A)
#   Bit 6:  Dirty (D)
#   Bit 7:  Page Size (PS) — 1=huge page (2MB in PD, 1GB in PDPT)
#   Bit 8:  Global (G)
#   Bits 12-51: Physical page frame number
#   Bit 63: No Execute (NX/XD)

.intel_syntax noprefix
.global _start

.section .data
.align 8

# ── Page Table Entry flag constants ─────────────────────────────────
PTE_PRESENT     = 1 << 0        # 0x001 — page is present in memory
PTE_WRITABLE    = 1 << 1        # 0x002 — page is writable
PTE_USER        = 1 << 2        # 0x004 — accessible from ring 3
PTE_PWT         = 1 << 3        # 0x008 — write-through caching
PTE_PCD         = 1 << 4        # 0x010 — cache disabled
PTE_ACCESSED    = 1 << 5        # 0x020 — page has been read
PTE_DIRTY       = 1 << 6        # 0x040 — page has been written
PTE_HUGE        = 1 << 7        # 0x080 — 2MB (PD) or 1GB (PDPT) page
PTE_GLOBAL      = 1 << 8        # 0x100 — don't flush on CR3 write
PTE_NX          = 1 << 63       # No Execute bit (highest bit)

PAGE_SIZE       = 4096           # 4KB standard page
HUGE_PAGE_SIZE  = 2 * 1024 * 1024  # 2MB huge page
PAGE_SHIFT      = 12             # log2(4096) = 12
PHYS_ADDR_MASK  = 0x000FFFFFFFFFF000  # bits [51:12] — physical frame

# Common PTE flag combinations
PTE_KERN_RW     = PTE_PRESENT | PTE_WRITABLE           # 0x003
PTE_KERN_RO     = PTE_PRESENT                          # 0x001
PTE_USER_RW     = PTE_PRESENT | PTE_WRITABLE | PTE_USER # 0x007
PTE_USER_RO     = PTE_PRESENT | PTE_USER                # 0x005

# Simulated page table entries (as a kernel would build them)
.align 8
sample_pte_kern_code:   .quad 0x0000000000200000 | PTE_PRESENT
                        # Physical frame at 2MB, read-only kernel code
sample_pte_kern_data:   .quad 0x0000000000201000 | PTE_KERN_RW
                        # Physical frame at 2MB+4KB, writable kernel data
sample_pte_user_code:   .quad 0x0000000000400000 | PTE_USER_RO
                        # Physical frame at 4MB, user read-only
sample_pte_user_stack:  .quad 0x0000000000800000 | PTE_USER_RW
                        # Physical frame at 8MB, user read/write
sample_pte_not_present: .quad 0x0000000000000000
                        # Not present — will cause page fault
sample_pte_huge:        .quad 0x0000000000600000 | PTE_PRESENT | PTE_WRITABLE | PTE_HUGE
                        # 2MB huge page at 6MB

# Virtual address decomposition test value
# Address: 0x0000_0000_4020_3ABC
#   PML4  [47:39]: 000000000 = 0
#   PDPT  [38:30]: 000000001 = 1      (bit 30 set from 0x40000000)
#   PD    [29:21]: 000000000 = 0
#   PT    [20:12]: 000000011 = 3      (0x3000 >> 12 = 3)
#   Offset[11:0]:  101010111100 = 0xABC
test_vaddr: .quad 0x0000000040003ABC

# Path for /proc/self/maps
proc_maps_path: .ascii "/proc/self/maps"
proc_maps_path_len = . - proc_maps_path
                    .byte 0     # null terminator for open()

.section .bss
.align 8
maps_buf:   .skip 4096          # buffer for reading /proc/self/maps

.section .rodata
msg_pass:   .ascii "All virtual memory examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ════════════════════════════════════════════════════════════════
    # 1. Verify PTE flag constants
    # ════════════════════════════════════════════════════════════════
    mov     rax, PTE_PRESENT
    cmp     rax, 0x001
    jne     fail

    mov     rax, PTE_WRITABLE
    cmp     rax, 0x002
    jne     fail

    mov     rax, PTE_USER
    cmp     rax, 0x004
    jne     fail

    mov     rax, PTE_HUGE
    cmp     rax, 0x080
    jne     fail

    # NX bit is bit 63 — verify it's the sign bit
    mov     rax, PTE_NX
    bt      rax, 63
    jnc     fail

    # ════════════════════════════════════════════════════════════════
    # 2. Extract flags from a PTE
    # ════════════════════════════════════════════════════════════════
    mov     rax, [sample_pte_kern_data]

    # Test if present
    test    rax, PTE_PRESENT
    jz      fail                # kernel data should be present

    # Test if writable
    test    rax, PTE_WRITABLE
    jz      fail                # kernel data should be writable

    # Test it's NOT user-accessible
    test    rax, PTE_USER
    jnz     fail                # kernel data must not be user-accessible

    # ════════════════════════════════════════════════════════════════
    # 3. Extract physical address from PTE
    # ════════════════════════════════════════════════════════════════
    mov     rax, [sample_pte_kern_data]
    mov     rcx, PHYS_ADDR_MASK
    and     rax, rcx            # mask off flag bits
    # rax now contains the physical frame address (4KB aligned)
    cmp     rax, 0x201000       # should be 2MB + 4KB
    jne     fail

    # Extract page frame number (physical address >> 12)
    shr     rax, PAGE_SHIFT
    cmp     rax, 0x201          # PFN = 0x201
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 4. Build a PTE from physical address + flags
    # ════════════════════════════════════════════════════════════════
    # Equivalent of: make_pte(phys=0x300000, flags=USER_RW)
    mov     rax, 0x300000       # physical address (must be page-aligned)
    or      rax, PTE_USER_RW    # add flags
    # Verify the PTE
    mov     rcx, rax
    and     rcx, 0xFFF          # extract flags
    cmp     rcx, PTE_USER_RW    # should be P|W|U = 0x007
    jne     fail
    mov     rcx, rax
    mov     rdx, PHYS_ADDR_MASK
    and     rcx, rdx
    cmp     rcx, 0x300000
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 5. Virtual address decomposition
    # ════════════════════════════════════════════════════════════════
    # Split 0x0000000040003ABC into page table indices
    mov     rax, [test_vaddr]

    # PML4 index: bits [47:39]
    mov     rcx, rax
    shr     rcx, 39
    and     rcx, 0x1FF          # 9-bit mask
    cmp     rcx, 0              # PML4 index = 0
    jne     fail

    # PDPT index: bits [38:30]
    mov     rcx, rax
    shr     rcx, 30
    and     rcx, 0x1FF
    cmp     rcx, 1              # PDPT index = 1
    jne     fail

    # PD index: bits [29:21]
    mov     rcx, rax
    shr     rcx, 21
    and     rcx, 0x1FF
    cmp     rcx, 0              # PD index = 0
    jne     fail

    # PT index: bits [20:12]
    mov     rcx, rax
    shr     rcx, 12
    and     rcx, 0x1FF
    cmp     rcx, 3              # PT index = 3
    jne     fail

    # Page offset: bits [11:0]
    mov     rcx, rax
    and     rcx, 0xFFF
    cmp     rcx, 0xABC          # offset = 0xABC
    jne     fail

    # ════════════════════════════════════════════════════════════════
    # 6. Check huge page bit and size
    # ════════════════════════════════════════════════════════════════
    mov     rax, [sample_pte_huge]
    test    rax, PTE_HUGE
    jz      fail                # should have huge bit set

    # For huge pages, bits [20:12] are part of the physical address
    # (no PT level), so the page is 2MB aligned
    mov     rcx, PHYS_ADDR_MASK
    and     rax, rcx
    mov     rcx, rax
    and     rcx, 0x1FFFFF       # 2MB - 1
    test    rcx, rcx
    jnz     fail                # physical address must be 2MB aligned

    # ════════════════════════════════════════════════════════════════
    # 7. Test not-present page detection
    # ════════════════════════════════════════════════════════════════
    mov     rax, [sample_pte_not_present]
    test    rax, PTE_PRESENT
    jnz     fail                # should NOT be present

    # ════════════════════════════════════════════════════════════════
    # 8. Read /proc/self/maps — see our own virtual memory layout
    # ════════════════════════════════════════════════════════════════
    # open("/proc/self/maps", O_RDONLY)
    mov     rax, 2              # sys_open
    lea     rdi, [proc_maps_path]
    xor     rsi, rsi            # O_RDONLY = 0
    xor     rdx, rdx            # mode (unused for O_RDONLY)
    syscall
    test    rax, rax
    js      fail                # open failed
    mov     r12, rax            # save fd

    # read(fd, buf, 4096)
    mov     rax, 0              # sys_read
    mov     rdi, r12            # fd
    lea     rsi, [maps_buf]     # buffer
    mov     rdx, 4095           # count (leave room for null)
    syscall
    test    rax, rax
    jle     fail                # read failed or empty
    mov     r13, rax            # save bytes read

    # close(fd)
    mov     rax, 3              # sys_close
    mov     rdi, r12
    syscall

    # Write a portion of maps to stdout to show it works
    # (truncate to first 200 bytes or actual length, whichever is less)
    mov     rdx, r13
    cmp     rdx, 200
    jle     .maps_write
    mov     rdx, 200
.maps_write:
    mov     rax, 1              # sys_write
    mov     rdi, 1              # stdout
    lea     rsi, [maps_buf]
    syscall

    # ════════════════════════════════════════════════════════════════
    # 9. Verify canonical address form
    # ════════════════════════════════════════════════════════════════
    # Valid x86_64 addresses: bits [63:48] must all be copies of bit 47
    # Kernel addresses: 0xFFFF_8000_0000_0000 and above (bit 47 = 1)
    # User addresses:   0x0000_0000_0000_0000 to 0x0000_7FFF_FFFF_FFFF

    # Test: is our stack pointer in user canonical space?
    mov     rax, rsp
    shr     rax, 47             # get bits [63:47]
    test    rax, rax            # should be 0 for user space
    jnz     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall
