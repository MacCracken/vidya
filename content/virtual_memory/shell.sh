#!/bin/bash
# Vidya — Virtual Memory in Shell
#
# Virtual memory gives each process its own address space, mapping
# virtual addresses to physical pages through multi-level page tables.
# Shell can inspect the live virtual memory layout through /proc/self/maps,
# query page sizes with getconf, and decompose addresses with bit arithmetic.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Page size fundamentals ────────────────────────────────────────────
# The page is the smallest unit of virtual memory. x86_64 supports
# 4KB, 2MB, and 1GB pages. The default is 4KB.

PAGE_SIZE=$(getconf PAGE_SIZE)
assert_eq "$PAGE_SIZE" "4096" "default page size = 4KB"

# Page size as powers of 2
PAGE_SHIFT=12           # 2^12 = 4096
LARGE_PAGE_SHIFT=21     # 2^21 = 2MB (huge page)
GIANT_PAGE_SHIFT=30     # 2^30 = 1GB (gigantic page)

assert_eq "$(( 1 << PAGE_SHIFT ))" "4096" "2^12 = 4KB"
assert_eq "$(( 1 << LARGE_PAGE_SHIFT ))" "2097152" "2^21 = 2MB"
assert_eq "$(( 1 << GIANT_PAGE_SHIFT ))" "1073741824" "2^30 = 1GB"

# Page mask: used to extract page number from address
PAGE_MASK=$(( ~(PAGE_SIZE - 1) ))
PAGE_OFFSET_MASK=$(( PAGE_SIZE - 1 ))

assert_eq "$(( PAGE_OFFSET_MASK ))" "4095" "offset mask = 0xFFF"
assert_eq "$(( 0x12345678 & PAGE_OFFSET_MASK ))" "$(( 0x678 ))" "extract page offset"
assert_eq "$(( 0x12345678 & PAGE_MASK ))" "$(( 0x12345000 ))" "extract page base"

# ── Address space layout ─────────────────────────────────────────────
# x86_64 uses 48-bit virtual addresses (or 57-bit with LA57).
# Canonical addresses: bits 48-63 must match bit 47.
#   User space:   0x0000000000000000 — 0x00007FFFFFFFFFFF
#   Kernel space: 0xFFFF800000000000 — 0xFFFFFFFFFFFFFFFF
#   Hole:         0x0000800000000000 — 0xFFFF7FFFFFFFFFFF (non-canonical)

USER_SPACE_END=0x00007FFFFFFFFFFF
KERNEL_SPACE_START=$(( 0xFFFF800000000000 ))  # this wraps to negative in bash

# User space is 128TB
user_space_size=$(( USER_SPACE_END + 1 ))
user_space_tb=$(( user_space_size / (1024 * 1024 * 1024 * 1024) ))
assert_eq "$user_space_tb" "128" "user space = 128 TB"

# ── Virtual address decomposition (4-level paging) ───────────────────
# A 48-bit virtual address is split into 5 fields:
#   [47:39] PML4 index    — 9 bits — selects page map level 4 entry
#   [38:30] PDPT index    — 9 bits — selects page directory pointer
#   [29:21] PD index      — 9 bits — selects page directory entry
#   [20:12] PT index      — 9 bits — selects page table entry
#   [11:0]  Page offset   — 12 bits — byte within page

vaddr_decompose() {
    local vaddr=$1
    local pml4=$(( (vaddr >> 39) & 0x1FF ))
    local pdpt=$(( (vaddr >> 30) & 0x1FF ))
    local pd=$(( (vaddr >> 21) & 0x1FF ))
    local pt=$(( (vaddr >> 12) & 0x1FF ))
    local offset=$(( vaddr & 0xFFF ))
    echo "$pml4 $pdpt $pd $pt $offset"
}

# Address 0x1000 — second page in memory
parts=$(vaddr_decompose 0x1000)
assert_eq "$parts" "0 0 0 1 0" "0x1000: PT index=1, offset=0"

# Address at 2MB boundary — triggers PD index
parts=$(vaddr_decompose 0x200000)
assert_eq "$parts" "0 0 1 0 0" "2MB: PD index=1"

# Address at 1GB boundary — triggers PDPT index
parts=$(vaddr_decompose 0x40000000)
assert_eq "$parts" "0 1 0 0 0" "1GB: PDPT index=1"

# Address with offset
parts=$(vaddr_decompose 0x12345678)
pml4=$(echo "$parts" | awk '{print $1}')
offset=$(echo "$parts" | awk '{print $5}')
assert_eq "$pml4" "0" "0x12345678: PML4=0 (low address)"
assert_eq "$offset" "$(( 0x678 ))" "0x12345678: offset=0x678"

# ── Page table entry flags ────────────────────────────────────────────
# Each PTE is 64 bits. Lower 12 bits are flags, bits 12-51 are the
# physical page frame number.

PTE_PRESENT=$((1 << 0))     # page is in memory
PTE_WRITABLE=$((1 << 1))    # page is writable
PTE_USER=$((1 << 2))        # accessible from ring 3
PTE_PWT=$((1 << 3))         # page-level write-through
PTE_PCD=$((1 << 4))         # page-level cache disable
PTE_ACCESSED=$((1 << 5))    # CPU has read this page
PTE_DIRTY=$((1 << 6))       # CPU has written to this page
PTE_HUGE=$((1 << 7))        # 2MB/1GB page (in PD/PDPT entry)
PTE_GLOBAL=$((1 << 8))      # don't flush from TLB on CR3 switch
PTE_NX=$((1 << 63))         # No-Execute (requires EFER.NXE)

# Build a typical kernel code PTE: present, global, not writable, not user
kernel_code_pte=$(( PTE_PRESENT | PTE_GLOBAL | PTE_ACCESSED ))
assert_eq "$(( kernel_code_pte & PTE_PRESENT ))" "$PTE_PRESENT" "kernel code: present"
assert_eq "$(( kernel_code_pte & PTE_WRITABLE ))" "0" "kernel code: read-only"
assert_eq "$(( kernel_code_pte & PTE_USER ))" "0" "kernel code: supervisor only"

# Build a user data PTE: present, writable, user, NX
user_data_pte=$(( PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NX ))
assert_eq "$(( user_data_pte & PTE_USER ))" "$PTE_USER" "user data: user accessible"
assert_eq "$(( user_data_pte & PTE_NX ))" "$PTE_NX" "user data: no execute"

# Extract physical page frame from PTE
pte_phys_page() {
    local pte=$1
    echo $(( (pte >> 12) & 0xFFFFFFFFF ))  # bits 12-51
}

# PTE with physical address 0x1000 (page frame 1)
test_pte=$(( (1 << 12) | PTE_PRESENT ))
assert_eq "$(pte_phys_page $test_pte)" "1" "page frame number = 1"

# PTE with physical address 0x200000 (page frame 512)
test_pte2=$(( (512 << 12) | PTE_PRESENT ))
assert_eq "$(pte_phys_page $test_pte2)" "512" "page frame number = 512"

# ── Parse /proc/self/maps ────────────────────────────────────────────
# Format: start-end perms offset dev inode pathname
# Example: 55a4c8200000-55a4c8230000 r--p 00000000 fe:01 1234 /usr/bin/bash

# Snapshot maps — /proc/self resolves per-open, so cat captures it
# for the bash process before any redirection forks occur.
maps_snapshot=$(</proc/self/maps)

declare -A region_types
region_count=0
total_mapped=0

while IFS= read -r line; do
    addr_range=$(echo "$line" | awk '{print $1}')
    perms=$(echo "$line" | awk '{print $2}')
    pathname=$(echo "$line" | awk '{print $6}')

    start_hex="${addr_range%-*}"
    end_hex="${addr_range#*-}"

    # Skip kernel-space addresses (vsyscall) that overflow signed 64-bit
    if [[ ${#start_hex} -ge 16 && "$start_hex" > "7fffffffffffffff" ]]; then
        region_count=$(( region_count + 1 ))
        continue
    fi

    start_dec=$(( 16#$start_hex ))
    end_dec=$(( 16#$end_hex ))
    size=$(( end_dec - start_dec ))
    total_mapped=$(( total_mapped + size ))

    # Classify by pathname
    case "$pathname" in
        "[stack]")  region_types["stack"]=$(( ${region_types["stack"]:-0} + size )) ;;
        "[heap]")   region_types["heap"]=$(( ${region_types["heap"]:-0} + size )) ;;
        "[vdso]")   region_types["vdso"]=$(( ${region_types["vdso"]:-0} + size )) ;;
        "[vvar]")   region_types["vvar"]=$(( ${region_types["vvar"]:-0} + size )) ;;
        "[vvar_vclock]") region_types["vvar"]=$(( ${region_types["vvar"]:-0} + size )) ;;
        "")         region_types["anon"]=$(( ${region_types["anon"]:-0} + size )) ;;
        *)          region_types["file"]=$(( ${region_types["file"]:-0} + size )) ;;
    esac
    region_count=$(( region_count + 1 ))
done <<< "$maps_snapshot"

# Sanity checks
if (( region_count < 5 )); then
    echo "FAIL: too few memory regions: $region_count" >&2
    exit 1
fi

# Total mapped memory should be at least a few MB (bash + libs)
total_mapped_kb=$(( total_mapped / 1024 ))
if (( total_mapped_kb < 100 )); then
    echo "FAIL: total mapped memory suspiciously low: ${total_mapped_kb}KB" >&2
    exit 1
fi

# Stack must exist
if [[ -z "${region_types[stack]+x}" ]]; then
    echo "FAIL: no stack region found" >&2
    exit 1
fi

# ── Permission analysis ──────────────────────────────────────────────
# Count regions by permission pattern to understand memory layout.

declare -A perm_pattern_count

while IFS= read -r line; do
    perms=$(echo "$line" | awk '{print $2}')
    perm_pattern_count[$perms]=$(( ${perm_pattern_count[$perms]:-0} + 1 ))
done <<< "$maps_snapshot"

# Every process should have r-xp (code) and rw-p (data) regions
has_code=false
has_data=false
for p in "${!perm_pattern_count[@]}"; do
    [[ "$p" == *"x"* ]] && has_code=true
    [[ "$p" == "rw-p" ]] && has_data=true
done

assert_eq "$has_code" "true" "executable regions exist"
assert_eq "$has_data" "true" "writable data regions exist"

# W^X check: no region should be both writable AND executable
while IFS= read -r line; do
    perms=$(echo "$line" | awk '{print $2}')
    if [[ "$perms" == *w*x* || "$perms" == *x*w* ]]; then
        # rwx regions exist in some JIT/special cases but are a red flag
        pathname=$(echo "$line" | awk '{print $6}')
        if [[ -z "$pathname" || "$pathname" == "[stack]" ]]; then
            echo "WARNING: W+X anonymous region detected (potential security issue)" >&2
        fi
    fi
done <<< "$maps_snapshot"

# ── Address alignment checks ─────────────────────────────────────────
# All mapping boundaries must be page-aligned.

misaligned=0
while IFS= read -r line; do
    addr_range=$(echo "$line" | awk '{print $1}')
    start_hex="${addr_range%-*}"
    end_hex="${addr_range#*-}"

    # Skip kernel-space addresses that overflow signed 64-bit
    if [[ ${#start_hex} -ge 16 && "$start_hex" > "7fffffffffffffff" ]]; then
        continue
    fi

    start_dec=$(( 16#$start_hex ))
    end_dec=$(( 16#$end_hex ))

    if (( (start_dec & PAGE_OFFSET_MASK) != 0 )); then
        (( misaligned++ ))
    fi
    if (( (end_dec & PAGE_OFFSET_MASK) != 0 )); then
        (( misaligned++ ))
    fi
done <<< "$maps_snapshot"

assert_eq "$misaligned" "0" "all mappings are page-aligned"

# ── TLB and page table sizes ─────────────────────────────────────────
# Constants that govern page table structure

ENTRIES_PER_TABLE=512                           # 2^9 entries per level
ENTRY_SIZE=8                                    # 8 bytes per PTE
TABLE_SIZE=$(( ENTRIES_PER_TABLE * ENTRY_SIZE ))  # 4KB = one page

assert_eq "$ENTRIES_PER_TABLE" "512" "512 entries per page table"
assert_eq "$TABLE_SIZE" "4096" "page table = one page"

# Coverage per level:
# PT:   512 * 4KB = 2MB
# PD:   512 * 2MB = 1GB
# PDPT: 512 * 1GB = 512GB
# PML4: 512 * 512GB = 256TB
pt_coverage=$(( ENTRIES_PER_TABLE * PAGE_SIZE ))
pd_coverage=$(( ENTRIES_PER_TABLE * pt_coverage ))
pdpt_coverage=$(( ENTRIES_PER_TABLE * pd_coverage ))

assert_eq "$pt_coverage" "$(( 2 * 1024 * 1024 ))" "PT covers 2MB"
assert_eq "$pd_coverage" "$(( 1024 * 1024 * 1024 ))" "PD covers 1GB"

# ── Huge pages ────────────────────────────────────────────────────────
# Check if transparent huge pages are available on this system.

HUGE_PAGE_SIZE=$(( 2 * 1024 * 1024 ))   # 2MB
assert_eq "$HUGE_PAGE_SIZE" "2097152" "huge page = 2MB"

# Number of 4KB pages in one huge page
pages_per_huge=$(( HUGE_PAGE_SIZE / PAGE_SIZE ))
assert_eq "$pages_per_huge" "512" "512 small pages per huge page"

# Check system huge page configuration if available
if [[ -f /proc/meminfo ]]; then
    huge_total=$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo)
    huge_size=$(awk '/^Hugepagesize:/ {print $2}' /proc/meminfo)
    # These are informational — values depend on system configuration
    if [[ -n "$huge_size" ]]; then
        assert_eq "$huge_size" "2048" "system hugepage size = 2048 kB"
    fi
fi

echo "All virtual memory examples passed."
