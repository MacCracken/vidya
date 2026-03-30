#!/usr/bin/env bash
# Vidya — Kernel Topics in Shell (Bash)
#
# Shell is how you inspect a running kernel: /proc, /sys, dmesg.
# These examples simulate kernel data structure operations using
# bash arithmetic and bitwise ops. On a real Linux system, you'd
# read actual /proc files — here we simulate for portability.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Page Table Entry bit manipulation ──────────────────────────────────
PTE_PRESENT=1
PTE_WRITABLE=2
PTE_USER=4
PTE_NX=$((1 << 63))  # bash handles 64-bit on 64-bit systems

pte_new() {
    local phys_addr=$1 flags=$2
    echo $(( (phys_addr & 0x000FFFFFFFFFF000) | flags ))
}

pte_is_present() {
    (( ($1 & PTE_PRESENT) != 0 ))
}

pte_phys_addr() {
    echo $(( $1 & 0x000FFFFFFFFFF000 ))
}

entry=$(pte_new 0x1000 $((PTE_PRESENT | PTE_WRITABLE)))
pte_is_present "$entry"
assert_eq "$(pte_phys_addr "$entry")" "4096" "phys addr 0x1000"

unmapped=$(pte_new 0 0)
if pte_is_present "$unmapped"; then
    echo "FAIL: unmapped should not be present" >&2
    exit 1
fi

# ── Virtual address decomposition ─────────────────────────────────────
vaddr_decompose() {
    local vaddr=$1
    local pml4=$(( (vaddr >> 39) & 0x1FF ))
    local pdpt=$(( (vaddr >> 30) & 0x1FF ))
    local pd=$(( (vaddr >> 21) & 0x1FF ))
    local pt=$(( (vaddr >> 12) & 0x1FF ))
    local offset=$(( vaddr & 0xFFF ))
    echo "$pml4 $pdpt $pd $pt $offset"
}

parts=$(vaddr_decompose 0x0000000000001000)
assert_eq "$parts" "0 0 0 1 0" "decompose 0x1000"

# Page at 2MB boundary
parts=$(vaddr_decompose 0x200000)
assert_eq "$parts" "0 0 1 0 0" "decompose 2MB"

# ── MMIO register simulation ──────────────────────────────────────────
declare -A MMIO_REGS

mmio_write() {
    local reg=$1 val=$2
    MMIO_REGS[$reg]=$val
}

mmio_read() {
    echo "${MMIO_REGS[$1]:-0}"
}

mmio_set_bits() {
    local reg=$1 mask=$2
    local cur
    cur=$(mmio_read "$reg")
    mmio_write "$reg" $(( cur | mask ))
}

mmio_clear_bits() {
    local reg=$1 mask=$2
    local cur
    cur=$(mmio_read "$reg")
    mmio_write "$reg" $(( cur & ~mask ))
}

mmio_write "UART_CTRL" 0
mmio_set_bits "UART_CTRL" 3    # enable TX+RX
assert_eq "$(mmio_read "UART_CTRL")" "3" "UART TX+RX enabled"

mmio_clear_bits "UART_CTRL" 2  # disable RX
assert_eq "$(mmio_read "UART_CTRL")" "1" "UART TX only"

# ── Interrupt vector table simulation ──────────────────────────────────
declare -A IRQ_NAMES
declare -A IRQ_HANDLERS

irq_register() {
    local vector=$1 name=$2 handler=$3
    IRQ_NAMES[$vector]=$name
    IRQ_HANDLERS[$vector]=$handler
}

irq_dispatch() {
    local vector=$1
    if [[ -z "${IRQ_HANDLERS[$vector]+x}" ]]; then
        echo "unhandled"
        return 1
    fi
    echo "${IRQ_HANDLERS[$vector]}"
}

irq_register 0 "Divide Error" "handled: #DE"
irq_register 8 "Double Fault" "handled: #DF"
irq_register 14 "Page Fault" "handled: #PF"
irq_register 32 "Timer" "handled: timer"

assert_eq "$(irq_dispatch 0)" "handled: #DE" "dispatch #DE"
assert_eq "$(irq_dispatch 14)" "handled: #PF" "dispatch #PF"
assert_eq "$(irq_dispatch 32)" "handled: timer" "dispatch timer"

if irq_dispatch 255 >/dev/null 2>&1; then
    echo "FAIL: vector 255 should be unhandled" >&2
    exit 1
fi

# ── GDT entry decoding ────────────────────────────────────────────────
gdt_present() {
    local raw=$1
    (( (raw >> 47) & 1 ))
}

gdt_dpl() {
    local raw=$1
    echo $(( (raw >> 45) & 3 ))
}

# Null descriptor
if gdt_present 0; then
    echo "FAIL: null should not be present" >&2
    exit 1
fi

# Kernel code segment: 0x00AF9A000000FFFF
# Need to handle this as hex since it exceeds signed 64-bit
KERNEL_CODE=0x00AF9A000000FFFF
gdt_present $KERNEL_CODE
assert_eq "$(gdt_dpl $KERNEL_CODE)" "0" "kernel code ring 0"

# ── ABI register listing ──────────────────────────────────────────────
SYSV_REGS=("rdi" "rsi" "rdx" "rcx" "r8" "r9")
SYSCALL_REGS=("rax" "rdi" "rsi" "rdx" "r10" "r8" "r9")

assert_eq "${SYSV_REGS[0]}" "rdi" "sysv arg0"
assert_eq "${SYSV_REGS[5]}" "r9" "sysv arg5"
assert_eq "${#SYSV_REGS[@]}" "6" "sysv count"

# Key difference: syscall uses r10 instead of rcx
assert_eq "${SYSCALL_REGS[0]}" "rax" "syscall number"
assert_eq "${SYSCALL_REGS[4]}" "r10" "r10 not rcx"

# ── /proc simulation (kernel info queries) ─────────────────────────────
# On a real system you'd read /proc/interrupts, /proc/meminfo, etc.
# Here we simulate the format

simulate_proc_interrupts() {
    cat <<'PROC'
           CPU0       CPU1
  0:         42          0   IO-APIC   2-edge      timer
  1:        156          0   IO-APIC   1-edge      i8042
 14:          0          0   PCI-MSI 524288-edge      nvme0q0
PROC
}

# Parse interrupt count for vector 0 (timer)
timer_count=$(simulate_proc_interrupts | awk '/timer/ {print $2}')
assert_eq "$timer_count" "42" "timer irq count"

# Parse interrupt controller type
timer_type=$(simulate_proc_interrupts | awk '/timer/ {print $4}')
assert_eq "$timer_type" "IO-APIC" "timer controller"

echo "All kernel topics examples passed."
