# Vidya — Boot and Startup in x86_64 Assembly
#
# Real boot code runs in real mode → protected mode → long mode. This
# file demonstrates the DATA STRUCTURES used during that transition:
# GDT (Global Descriptor Table), segment selectors, page table entry
# format, and the multiboot header. These structures are defined in
# .data and verified at runtime — the code itself runs as a normal
# Linux process, but the structures are exactly what a bootloader builds.
#
# Long mode entry sequence (what a real bootloader does):
#   1. Disable interrupts (cli)
#   2. Load GDT with 64-bit code/data segments
#   3. Enable PAE in CR4
#   4. Set up PML4 page table, load into CR3
#   5. Enable long mode in EFER MSR
#   6. Enable paging in CR0
#   7. Far jump to 64-bit code segment

.intel_syntax noprefix
.global _start

.section .data
.align 16

# ── Global Descriptor Table (GDT) ──────────────────────────────────
# Each entry is 8 bytes. The GDT defines memory segments.
# Format of a segment descriptor (8 bytes):
#   Bits  0-15: Limit [0:15]
#   Bits 16-31: Base [0:15]
#   Bits 32-39: Base [16:23]
#   Bits 40-47: Access byte
#               P(1) DPL(2) S(1) Type(4)
#   Bits 48-51: Limit [16:19]
#   Bits 52-55: Flags: G(1) D/B(1) L(1) AVL(1)
#               G=granularity, L=long mode
#   Bits 56-63: Base [24:31]

gdt_start:
gdt_null:                       # Entry 0: mandatory null descriptor
    .quad   0x0000000000000000

gdt_code:                       # Entry 1: 64-bit code segment
    # Base=0, Limit=0xFFFFF (ignored in long mode)
    # Access: P=1, DPL=0, S=1, Type=1010 (execute/read)
    #   = 1 00 1 1010 = 0x9A
    # Flags: G=1, D=0, L=1, AVL=0
    #   = 1 0 1 0 = 0xA (in bits 52-55)
    # Encoded: limit[0:15]=0xFFFF, base[0:15]=0, base[16:23]=0,
    #          access=0x9A, limit[16:19]+flags=0xAF, base[24:31]=0
    .word   0xFFFF              # limit [0:15]
    .word   0x0000              # base [0:15]
    .byte   0x00                # base [16:23]
    .byte   0x9A                # access: present, ring 0, code, exec/read
    .byte   0xAF                # flags (G=1, L=1) + limit [16:19]=0xF
    .byte   0x00                # base [24:31]

gdt_data:                       # Entry 2: 64-bit data segment
    # Access: P=1, DPL=0, S=1, Type=0010 (read/write)
    #   = 1 00 1 0010 = 0x92
    # Flags: G=1, D/B=0, L=0, AVL=0
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0x92                # access: present, ring 0, data, read/write
    .byte   0xCF                # flags (G=1, D/B=1) + limit [16:19]=0xF
    .byte   0x00

gdt_user_code:                  # Entry 3: 64-bit user code (ring 3)
    # Access: P=1, DPL=3, S=1, Type=1010
    #   = 1 11 1 1010 = 0xFA
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0xFA                # access: present, ring 3, code, exec/read
    .byte   0xAF
    .byte   0x00

gdt_user_data:                  # Entry 4: 64-bit user data (ring 3)
    # Access: P=1, DPL=3, S=1, Type=0010
    #   = 1 11 1 0010 = 0xF2
    .word   0xFFFF
    .word   0x0000
    .byte   0x00
    .byte   0xF2                # access: present, ring 3, data, read/write
    .byte   0xCF
    .byte   0x00
gdt_end:

# ── GDT Pointer (GDTR register format) ─────────────────────────────
# lgdt loads this 10-byte structure: 2 bytes size + 8 bytes base
.align 4
gdt_pointer:
    .word   gdt_end - gdt_start - 1     # size (number of bytes - 1)
    .quad   gdt_start                    # base address of GDT

# ── Segment selectors ──────────────────────────────────────────────
# Selector format: Index(13) | TI(1) | RPL(2)
# TI=0 for GDT, RPL=ring level
KERNEL_CODE_SEL = 0x08          # GDT entry 1 (index=1, TI=0, RPL=0)
KERNEL_DATA_SEL = 0x10          # GDT entry 2 (index=2, TI=0, RPL=0)
USER_CODE_SEL   = 0x1B          # GDT entry 3 (index=3, TI=0, RPL=3)
USER_DATA_SEL   = 0x23          # GDT entry 4 (index=4, TI=0, RPL=3)

# ── CR0 / CR4 / EFER bit constants ─────────────────────────────────
# These are the bits a bootloader sets during mode transitions
.align 8
cr0_pe:     .quad   0x00000001  # CR0.PE  — Protected Mode Enable
cr0_pg:     .quad   0x80000000  # CR0.PG  — Paging Enable
cr0_wp:     .quad   0x00010000  # CR0.WP  — Write Protect
cr4_pae:    .quad   0x00000020  # CR4.PAE — Physical Address Extension
cr4_pge:    .quad   0x00000080  # CR4.PGE — Page Global Enable
efer_lme:   .quad   0x00000100  # EFER.LME — Long Mode Enable
efer_sce:   .quad   0x00000001  # EFER.SCE — System Call Enable

# ── Multiboot2 header constants ─────────────────────────────────────
mb2_magic:      .long   0xE85250D6  # Multiboot2 header magic
mb2_arch:       .long   0           # architecture: 0 = i386/x86
mb2_length:     .long   16          # header length
mb2_checksum:   .long   -(0xE85250D6 + 0 + 16)  # checksum (magic+arch+len+check=0)

.section .rodata
msg_pass:   .ascii "All boot and startup examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Verify GDT structure layout ─────────────────────────────────
    # Null descriptor must be all zeros
    mov     rax, [gdt_null]
    test    rax, rax
    jnz     fail

    # Code segment access byte must be 0x9A (present, ring 0, exec/read)
    movzx   eax, byte ptr [gdt_code + 5]   # access byte at offset 5
    cmp     al, 0x9A
    jne     fail

    # Code segment flags byte: must have L=1 (long mode)
    movzx   eax, byte ptr [gdt_code + 6]
    and     al, 0x20            # isolate L bit (bit 5 of flags nibble)
    cmp     al, 0x20
    jne     fail

    # Data segment access byte must be 0x92 (present, ring 0, read/write)
    movzx   eax, byte ptr [gdt_data + 5]
    cmp     al, 0x92
    jne     fail

    # User code DPL must be 3 (ring 3)
    movzx   eax, byte ptr [gdt_user_code + 5]
    cmp     al, 0xFA            # P=1 DPL=11 S=1 Type=1010
    jne     fail

    # ── Verify segment selectors ────────────────────────────────────
    # Kernel code selector: index=1, byte offset = 1*8 = 0x08
    mov     eax, KERNEL_CODE_SEL
    cmp     eax, 0x08
    jne     fail

    # Extract RPL from user code selector: should be 3
    mov     eax, USER_CODE_SEL
    and     eax, 0x03           # RPL is bottom 2 bits
    cmp     eax, 3
    jne     fail

    # Extract GDT index from user code selector: should be 3
    mov     eax, USER_CODE_SEL
    shr     eax, 3              # index is bits [15:3]
    cmp     eax, 3
    jne     fail

    # ── Verify GDT pointer structure ────────────────────────────────
    # Size should be (5 entries × 8 bytes) - 1 = 39
    movzx   eax, word ptr [gdt_pointer]
    cmp     eax, gdt_end - gdt_start - 1
    jne     fail
    cmp     eax, 39             # 5 * 8 - 1
    jne     fail

    # ── Verify CR0 bit constants ────────────────────────────────────
    # Boot sequence sets these in order: PE → PG
    mov     rax, [cr0_pe]
    cmp     rax, 1              # bit 0
    jne     fail

    mov     rax, [cr0_pg]
    bt      rax, 31             # paging bit
    jnc     fail

    # ── Verify PAE bit ──────────────────────────────────────────────
    mov     rax, [cr4_pae]
    bt      rax, 5              # PAE is bit 5 of CR4
    jnc     fail

    # ── Verify EFER.LME ─────────────────────────────────────────────
    mov     rax, [efer_lme]
    bt      rax, 8              # Long Mode Enable is bit 8
    jnc     fail

    # ── Verify Multiboot2 header ────────────────────────────────────
    # Magic must be 0xE85250D6
    mov     eax, [mb2_magic]
    cmp     eax, 0xE85250D6
    jne     fail

    # Checksum: magic + arch + length + checksum must equal 0
    mov     eax, [mb2_magic]
    add     eax, [mb2_arch]
    add     eax, [mb2_length]
    add     eax, [mb2_checksum]
    test    eax, eax            # sum must be 0 (mod 2^32)
    jnz     fail

    # ── Demonstrate what early boot code looks like (as comments) ───
    # A real bootloader would do:
    #   cli                     # disable interrupts
    #   lgdt [gdt_pointer]      # load our GDT
    #   mov cr4, (PAE | PGE)    # enable PAE paging features
    #   mov cr3, pml4_addr      # point to page tables
    #   wrmsr EFER, (LME|SCE)   # enable long mode in EFER MSR
    #   mov cr0, (PE | PG | WP) # enable protected mode + paging
    #   jmp KERNEL_CODE_SEL:long_mode_entry  # far jump activates long mode

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
