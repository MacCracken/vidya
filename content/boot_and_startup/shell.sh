#!/bin/bash
# Vidya — Boot and Startup in Shell
#
# The x86 boot process involves firmware (BIOS/UEFI), bootloader,
# and mode transitions from real mode to protected to long mode.
# Shell can express the constants, magic numbers, and data structures
# involved using hex arithmetic. This file encodes GDT/IDT layout,
# multiboot headers, CR register flags, and mode transition steps.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Multiboot header magic numbers ────────────────────────────────────
# GRUB and other multiboot-compliant bootloaders check for a magic
# number in the first 8KB of the kernel image.

MULTIBOOT1_MAGIC=0x1BADB002          # magic in header
MULTIBOOT1_BOOTLOADER=0x2BADB002     # magic passed by bootloader in eax
MULTIBOOT2_MAGIC=0xE85250D6          # multiboot2 header magic
MULTIBOOT2_BOOTLOADER=0x36D76289     # multiboot2 bootloader magic

assert_eq "$(printf '0x%X' $MULTIBOOT1_MAGIC)" "0x1BADB002" "multiboot1 header magic"
assert_eq "$(printf '0x%X' $MULTIBOOT1_BOOTLOADER)" "0x2BADB002" "multiboot1 bootloader magic"

# Multiboot1 checksum: magic + flags + checksum = 0 (mod 2^32)
# For flags=0: checksum = -(magic + flags) mod 2^32
multiboot1_flags=0
multiboot1_checksum=$(( (0x100000000 - (MULTIBOOT1_MAGIC + multiboot1_flags)) & 0xFFFFFFFF ))
verify=$(( (MULTIBOOT1_MAGIC + multiboot1_flags + multiboot1_checksum) & 0xFFFFFFFF ))
assert_eq "$verify" "0" "multiboot1 checksum validates to zero"

# Multiboot2 checksum works the same way but includes header_length
multiboot2_header_len=16  # minimum header: magic(4) + arch(4) + len(4) + checksum(4)
multiboot2_arch=0         # 0 = i386 protected mode
mb2_sum=$(( MULTIBOOT2_MAGIC + multiboot2_arch + multiboot2_header_len ))
multiboot2_checksum=$(( (0x100000000 - (mb2_sum & 0xFFFFFFFF)) & 0xFFFFFFFF ))
verify2=$(( (mb2_sum + multiboot2_checksum) & 0xFFFFFFFF ))
assert_eq "$verify2" "0" "multiboot2 checksum validates to zero"

# ── Control Register flags ────────────────────────────────────────────
# CR0, CR3, CR4 control CPU modes. These bits must be set in the
# correct order during the boot transition.

# CR0 flags
CR0_PE=$((1 << 0))     # Protection Enable — enters protected mode
CR0_MP=$((1 << 1))     # Monitor Coprocessor
CR0_ET=$((1 << 4))     # Extension Type (387 present)
CR0_NE=$((1 << 5))     # Numeric Error (native FPU errors)
CR0_WP=$((1 << 16))    # Write Protect (kernel can't write RO pages)
CR0_AM=$((1 << 18))    # Alignment Mask
CR0_PG=$((1 << 31))    # Paging Enable — enables virtual memory

assert_eq "$CR0_PE" "1" "CR0.PE = bit 0"
assert_eq "$CR0_PG" "$((1 << 31))" "CR0.PG = bit 31"

# Entering protected mode: set PE bit
cr0_after_pe=$(( CR0_PE | CR0_ET | CR0_NE ))
assert_eq "$(( cr0_after_pe & CR0_PE ))" "$CR0_PE" "PE bit is set"
assert_eq "$(( cr0_after_pe & CR0_PG ))" "0" "PG not yet set (no paging yet)"

# Enabling paging (long mode requires paging)
cr0_with_paging=$(( cr0_after_pe | CR0_PG | CR0_WP ))
assert_eq "$(( cr0_with_paging & CR0_PG ))" "$CR0_PG" "PG now set"
assert_eq "$(( cr0_with_paging & CR0_WP ))" "$CR0_WP" "WP set for safety"

# CR4 flags
CR4_PAE=$((1 << 5))    # Physical Address Extension — required for long mode
CR4_PGE=$((1 << 7))    # Page Global Enable
CR4_OSFXSR=$((1 << 9)) # SSE support
CR4_OSXMMEXCPT=$((1 << 10))  # SSE exception support

assert_eq "$CR4_PAE" "32" "CR4.PAE = bit 5 = 32"

# PAE must be set before entering long mode
cr4_for_longmode=$(( CR4_PAE | CR4_PGE | CR4_OSFXSR | CR4_OSXMMEXCPT ))
assert_eq "$(( cr4_for_longmode & CR4_PAE ))" "$CR4_PAE" "PAE enabled for long mode"

# ── EFER MSR (Extended Feature Enable Register) ──────────────────────
# MSR 0xC0000080 — must set LME bit to enable long mode
EFER_MSR=0xC0000080
EFER_SCE=$((1 << 0))    # System Call Extensions (SYSCALL/SYSRET)
EFER_LME=$((1 << 8))    # Long Mode Enable
EFER_LMA=$((1 << 10))   # Long Mode Active (set by CPU, read-only)
EFER_NXE=$((1 << 11))   # No-Execute Enable

assert_eq "$(printf '0x%X' $EFER_MSR)" "0xC0000080" "EFER MSR address"
assert_eq "$EFER_LME" "256" "EFER.LME = bit 8"

efer_value=$(( EFER_SCE | EFER_LME | EFER_NXE ))
assert_eq "$(( efer_value & EFER_LME ))" "$EFER_LME" "LME set in EFER"

# ── GDT (Global Descriptor Table) ────────────────────────────────────
# The GDT defines memory segments. In 64-bit mode, most fields are
# ignored — the CPU uses a flat memory model — but the GDT must
# still exist with valid code/data segment descriptors.

# GDT entry structure (8 bytes per entry):
#   Bits 0-15:  Limit[0:15]
#   Bits 16-31: Base[0:15]
#   Bits 32-39: Base[16:23]
#   Bits 40-43: Type
#   Bit  44:    S (descriptor type: 1=code/data)
#   Bits 45-46: DPL (privilege level 0-3)
#   Bit  47:    P (present)
#   Bits 48-51: Limit[16:19]
#   Bit  52:    Available
#   Bit  53:    L (64-bit code segment)
#   Bit  54:    D/B (default operation size)
#   Bit  55:    G (granularity)
#   Bits 56-63: Base[24:31]

# Segment selectors: index into GDT * 8, plus RPL (ring privilege level)
GDT_NULL_SEL=$(( 0x00 ))    # Entry 0: always null
GDT_KCODE_SEL=$(( 0x08 ))  # Entry 1: kernel code (ring 0)
GDT_KDATA_SEL=$(( 0x10 ))  # Entry 2: kernel data (ring 0)
GDT_UCODE_SEL=$(( 0x18 ))  # Entry 3: user code (ring 3) — with RPL=3: 0x1b
GDT_UDATA_SEL=$(( 0x20 ))  # Entry 4: user data (ring 3) — with RPL=3: 0x23

assert_eq "$(( GDT_KCODE_SEL ))" "8" "kernel code selector = 0x08"
assert_eq "$(( GDT_KDATA_SEL ))" "16" "kernel data selector = 0x10"
assert_eq "$(( GDT_UCODE_SEL | 3 ))" "27" "user code selector with RPL=3"
assert_eq "$(( GDT_UDATA_SEL | 3 ))" "35" "user data selector with RPL=3"

# Each entry is 8 bytes; selector / 8 = entry index
assert_eq "$(( GDT_KCODE_SEL / 8 ))" "1" "kernel code = GDT entry 1"
assert_eq "$(( GDT_UCODE_SEL / 8 ))" "3" "user code = GDT entry 3"
assert_eq "$(( GDT_UDATA_SEL / 8 ))" "4" "user data = GDT entry 4"

# 64-bit kernel code segment descriptor: 0x00AF9A000000FFFF
# Decode its access byte (bits 40-47): 0x9A = 10011010
#   P=1, DPL=00, S=1, Type=1010 (execute/read, conforming=0, accessed=0)
KCODE64=0x00AF9A000000FFFF
access_byte=$(( (KCODE64 >> 40) & 0xFF ))
assert_eq "$(printf '0x%02X' $access_byte)" "0x9A" "access byte = 0x9A"

present=$(( (access_byte >> 7) & 1 ))
dpl=$(( (access_byte >> 5) & 3 ))
code_segment=$(( (access_byte >> 3) & 1 ))

assert_eq "$present" "1" "segment is present"
assert_eq "$dpl" "0" "DPL = ring 0"
assert_eq "$code_segment" "1" "is a code segment"

# L bit (bit 53) — must be 1 for 64-bit code segment
l_bit=$(( (KCODE64 >> 53) & 1 ))
assert_eq "$l_bit" "1" "L bit set (64-bit mode)"

# ── IDT (Interrupt Descriptor Table) ─────────────────────────────────
# The IDT maps interrupt/exception vectors (0-255) to handler addresses.
# Each IDT entry (gate descriptor) is 16 bytes in 64-bit mode.

IDT_ENTRIES=256
IDT_ENTRY_SIZE=16     # bytes per gate in long mode
IDT_TOTAL_SIZE=$(( IDT_ENTRIES * IDT_ENTRY_SIZE ))

assert_eq "$IDT_ENTRIES" "256" "IDT has 256 entries"
assert_eq "$IDT_ENTRY_SIZE" "16" "64-bit gate = 16 bytes"
assert_eq "$IDT_TOTAL_SIZE" "4096" "IDT = 4096 bytes = 1 page"

# Gate types (stored in type field of gate descriptor)
GATE_INTERRUPT=0x0E    # interrupts disabled on entry
GATE_TRAP=0x0F         # interrupts remain enabled

assert_eq "$(printf '0x%02X' $GATE_INTERRUPT)" "0x0E" "interrupt gate type"
assert_eq "$(printf '0x%02X' $GATE_TRAP)" "0x0F" "trap gate type"

# ── Mode transition sequence ─────────────────────────────────────────
# The boot process transitions through CPU modes. Each step has
# prerequisites that must be verified.

# Step 1: Real Mode (16-bit) — BIOS starts here
#   - A20 line must be enabled to access >1MB
#   - Load GDT with flat segments
# Step 2: Protected Mode (32-bit) — set CR0.PE
#   - Far jump to reload CS with GDT selector
#   - Reload data segment registers (DS, ES, SS, FS, GS)
# Step 3: Enable PAE — set CR4.PAE
#   - Required prerequisite for long mode
# Step 4: Set up page tables — write PML4 address to CR3
#   - Identity-map at least the kernel region
# Step 5: Enable Long Mode — set EFER.LME via MSR
# Step 6: Enable Paging — set CR0.PG
#   - CPU transitions to compatibility mode (still 32-bit code)
# Step 7: Far jump to 64-bit code segment
#   - CPU now in full 64-bit long mode

declare -a BOOT_STEPS=(
    "enable_a20"
    "load_gdt"
    "set_cr0_pe"
    "far_jump_protected"
    "reload_segments"
    "set_cr4_pae"
    "setup_page_tables"
    "set_efer_lme"
    "set_cr0_pg"
    "far_jump_long_mode"
)

assert_eq "${#BOOT_STEPS[@]}" "10" "10 boot transition steps"
assert_eq "${BOOT_STEPS[0]}" "enable_a20" "first: enable A20"
assert_eq "${BOOT_STEPS[2]}" "set_cr0_pe" "step 3: enter protected mode"
assert_eq "${BOOT_STEPS[9]}" "far_jump_long_mode" "last: enter long mode"

# ── A20 gate ─────────────────────────────────────────────────────────
# The A20 address line must be enabled to access memory above 1MB.
# Without it, bit 20 of physical addresses is forced to zero (wraps).
A20_PORT=0x92          # Fast A20 via system control port
A20_ENABLE_BIT=$((1 << 1))  # bit 1 of port 0x92

assert_eq "$(printf '0x%02X' $A20_PORT)" "0x92" "A20 fast gate port"
assert_eq "$A20_ENABLE_BIT" "2" "A20 enable = bit 1"

# The 1MB boundary
ONE_MB=$(( 1024 * 1024 ))
assert_eq "$ONE_MB" "1048576" "1MB boundary"
assert_eq "$(( ONE_MB ))" "$(( 0x100000 ))" "1MB = 0x100000"

# ── VGA text mode constants ──────────────────────────────────────────
# Early boot output uses VGA text buffer at physical address 0xB8000.
VGA_BUFFER=0xB8000
VGA_COLS=80
VGA_ROWS=25
VGA_CHAR_SIZE=2        # 1 byte char + 1 byte attribute
VGA_BUFFER_SIZE=$(( VGA_COLS * VGA_ROWS * VGA_CHAR_SIZE ))

assert_eq "$(printf '0x%X' $VGA_BUFFER)" "0xB8000" "VGA buffer address"
assert_eq "$VGA_BUFFER_SIZE" "4000" "VGA buffer = 4000 bytes"

# VGA attribute byte: foreground (bits 0-3) + background (bits 4-6) + blink (bit 7)
VGA_WHITE_ON_BLACK=0x0F    # bright white text, black background
VGA_RED_ON_BLACK=0x04      # red text for errors
VGA_GREEN_ON_BLACK=0x02    # green text for success

assert_eq "$(( VGA_WHITE_ON_BLACK & 0x0F ))" "15" "foreground = bright white"
assert_eq "$(( VGA_WHITE_ON_BLACK >> 4 ))" "0" "background = black"

# ── Verify current system boot mode ──────────────────────────────────
# On a running Linux system, /sys/firmware/efi exists if booted via UEFI.
if [[ -d /sys/firmware/efi ]]; then
    boot_mode="UEFI"
else
    boot_mode="BIOS"
fi
# Both are valid — just verify we can detect it
if [[ "$boot_mode" != "UEFI" && "$boot_mode" != "BIOS" ]]; then
    echo "FAIL: unrecognized boot mode" >&2
    exit 1
fi

echo "All boot and startup examples passed."
