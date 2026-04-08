#!/bin/bash
# Vidya — Interrupt Handling in Shell
#
# Interrupts are how hardware and software signal the CPU to handle
# events. Shell can inspect the live interrupt state through
# /proc/interrupts, express PIC/APIC constants as arithmetic, and
# model the x86 exception vector table. Understanding interrupts is
# essential for kernel development and driver writing.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── x86 Exception vector table (vectors 0-31) ────────────────────────
# The first 32 interrupt vectors are reserved by Intel for CPU
# exceptions. These fire on hardware errors and invalid operations.

declare -A EXCEPTION_NAMES=(
    [0]="Divide Error (#DE)"
    [1]="Debug (#DB)"
    [2]="NMI"
    [3]="Breakpoint (#BP)"
    [4]="Overflow (#OF)"
    [5]="Bound Range (#BR)"
    [6]="Invalid Opcode (#UD)"
    [7]="Device Not Available (#NM)"
    [8]="Double Fault (#DF)"
    [10]="Invalid TSS (#TS)"
    [11]="Segment Not Present (#NP)"
    [12]="Stack Fault (#SS)"
    [13]="General Protection (#GP)"
    [14]="Page Fault (#PF)"
    [16]="x87 FPU Error (#MF)"
    [17]="Alignment Check (#AC)"
    [18]="Machine Check (#MC)"
    [19]="SIMD Exception (#XM)"
    [20]="Virtualization (#VE)"
    [21]="Control Protection (#CP)"
)

# Verify critical exception vectors
assert_eq "${EXCEPTION_NAMES[0]}" "Divide Error (#DE)" "vector 0 = divide error"
assert_eq "${EXCEPTION_NAMES[6]}" "Invalid Opcode (#UD)" "vector 6 = #UD"
assert_eq "${EXCEPTION_NAMES[8]}" "Double Fault (#DF)" "vector 8 = double fault"
assert_eq "${EXCEPTION_NAMES[13]}" "General Protection (#GP)" "vector 13 = #GP"
assert_eq "${EXCEPTION_NAMES[14]}" "Page Fault (#PF)" "vector 14 = #PF"

# Exceptions that push an error code onto the stack
ERROR_CODE_VECTORS=(8 10 11 12 13 14 17 21)
assert_eq "${#ERROR_CODE_VECTORS[@]}" "8" "8 exceptions push error codes"
assert_eq "${ERROR_CODE_VECTORS[0]}" "8" "double fault pushes error code"
assert_eq "${ERROR_CODE_VECTORS[4]}" "13" "#GP pushes error code"

# ── Page fault error code bits ────────────────────────────────────────
# When a #PF occurs (vector 14), the CPU pushes an error code with
# specific bit meanings.

PF_PRESENT=$((1 << 0))     # 0=not-present, 1=protection violation
PF_WRITE=$((1 << 1))       # 0=read, 1=write
PF_USER=$((1 << 2))        # 0=supervisor, 1=user mode
PF_RSVD=$((1 << 3))        # reserved bit violation
PF_INSN=$((1 << 4))        # instruction fetch (NX violation)

# Decode example page fault: user-mode write to a not-present page
pf_code=$(( PF_WRITE | PF_USER ))
assert_eq "$(( pf_code & PF_PRESENT ))" "0" "page was not present"
assert_eq "$(( pf_code & PF_WRITE ))" "$PF_WRITE" "was a write"
assert_eq "$(( pf_code & PF_USER ))" "$PF_USER" "from user mode"

# NX violation: user tried to execute from a no-execute page
nx_fault=$(( PF_PRESENT | PF_USER | PF_INSN ))
assert_eq "$(( nx_fault & PF_INSN ))" "$PF_INSN" "instruction fetch fault"
assert_eq "$(( nx_fault & PF_PRESENT ))" "$PF_PRESENT" "page was present (NX)"

# ── 8259 PIC (Programmable Interrupt Controller) ──────────────────────
# Legacy interrupt controller. Two cascaded PICs provide 16 IRQ lines.
# Mostly replaced by APIC, but constants appear in legacy boot code.

PIC1_CMD=0x20       # master PIC command port
PIC1_DATA=0x21      # master PIC data port
PIC2_CMD=0xA0       # slave PIC command port
PIC2_DATA=0xA1      # slave PIC data port

# ICW1: initialization command word 1
ICW1_INIT=0x11      # start initialization + ICW4 needed
# ICW4: 8086 mode
ICW4_8086=0x01

# Standard PIC remapping: IRQs 0-7 → vectors 32-39, IRQs 8-15 → vectors 40-47
PIC1_OFFSET=32      # master PIC starts at vector 32
PIC2_OFFSET=40      # slave PIC starts at vector 40

assert_eq "$(printf '0x%02X' $PIC1_CMD)" "0x20" "master PIC command port"
assert_eq "$(printf '0x%02X' $PIC2_CMD)" "0xA0" "slave PIC command port"
assert_eq "$PIC1_OFFSET" "32" "master PIC offset = 32"
assert_eq "$PIC2_OFFSET" "40" "slave PIC offset = 40"

# IRQ to vector mapping
irq_to_vector() {
    local irq=$1
    if (( irq < 8 )); then
        echo $(( PIC1_OFFSET + irq ))
    else
        echo $(( PIC2_OFFSET + (irq - 8) ))
    fi
}

# Timer = IRQ 0 → vector 32
assert_eq "$(irq_to_vector 0)" "32" "timer IRQ 0 → vector 32"
# Keyboard = IRQ 1 → vector 33
assert_eq "$(irq_to_vector 1)" "33" "keyboard IRQ 1 → vector 33"
# Cascade = IRQ 2 → vector 34 (slave PIC connected here)
assert_eq "$(irq_to_vector 2)" "34" "cascade IRQ 2 → vector 34"
# RTC = IRQ 8 → vector 40
assert_eq "$(irq_to_vector 8)" "40" "RTC IRQ 8 → vector 40"

# End of Interrupt (EOI) command
PIC_EOI=0x20
assert_eq "$(printf '0x%02X' $PIC_EOI)" "0x20" "EOI command = 0x20"

# For slave PIC IRQs, must send EOI to both slave AND master
# (because slave is cascaded through master's IRQ 2)

# ── APIC (Advanced PIC) constants ─────────────────────────────────────
# Modern systems use the Local APIC (per-CPU) and I/O APIC.
# The LAPIC is memory-mapped, typically at 0xFEE00000.

LAPIC_BASE=0xFEE00000
IOAPIC_BASE=0xFEC00000

# LAPIC register offsets (from LAPIC_BASE)
LAPIC_ID=$((0x020))         # Local APIC ID
LAPIC_VERSION=$((0x030))    # Version register
LAPIC_TPR=$((0x080))        # Task Priority Register
LAPIC_EOI=$((0x0B0))        # End of Interrupt
LAPIC_SVR=$((0x0F0))        # Spurious Interrupt Vector
LAPIC_ICR_LO=$((0x300))     # Interrupt Command (low)
LAPIC_ICR_HI=$((0x310))     # Interrupt Command (high)
LAPIC_TIMER=$((0x320))      # LVT Timer
LAPIC_TIMER_INIT=$((0x380)) # Timer Initial Count
LAPIC_TIMER_CUR=$((0x390))  # Timer Current Count
LAPIC_TIMER_DIV=$((0x3E0))  # Timer Divide Config

assert_eq "$(printf '0x%X' $LAPIC_BASE)" "0xFEE00000" "LAPIC base"
assert_eq "$(printf '0x%X' $IOAPIC_BASE)" "0xFEC00000" "IOAPIC base"
assert_eq "$(printf '0x%03X' $LAPIC_EOI)" "0x0B0" "LAPIC EOI offset"

# Spurious vector register: bit 8 enables the APIC
APIC_ENABLE=$((1 << 8))
SPURIOUS_VECTOR=0xFF        # typically 0xFF
svr_value=$(( APIC_ENABLE | SPURIOUS_VECTOR ))
assert_eq "$(( svr_value & APIC_ENABLE ))" "$APIC_ENABLE" "APIC enabled"
assert_eq "$(( svr_value & 0xFF ))" "255" "spurious vector = 0xFF"

# ── Read /proc/interrupts ────────────────────────────────────────────
# Shows hardware interrupt counts per CPU on a running Linux system.

# Count total CPUs from the header line
cpu_count=$(head -1 /proc/interrupts | awk '{print NF}')
if (( cpu_count < 1 )); then
    echo "FAIL: could not determine CPU count from /proc/interrupts" >&2
    exit 1
fi

# Count interrupt sources (lines that start with a number or name)
irq_source_count=$(tail -n +2 /proc/interrupts | wc -l)
if (( irq_source_count < 1 )); then
    echo "FAIL: no interrupt sources found" >&2
    exit 1
fi

# Sum all interrupt counts for the first CPU
total_irqs=0
while IFS= read -r line; do
    # Skip the header line
    count=$(echo "$line" | awk '{print $2}')
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        total_irqs=$(( total_irqs + count ))
    fi
done < <(tail -n +2 /proc/interrupts)

# A running system must have processed some interrupts
if (( total_irqs < 1 )); then
    echo "FAIL: total IRQ count is zero — impossible on a running system" >&2
    exit 1
fi

# ── Look for specific interrupt types ─────────────────────────────────
# Common interrupt sources visible in /proc/interrupts

declare -A found_irqs

while IFS= read -r line; do
    case "$line" in
        *"timer"*|*"Timer"*)    found_irqs["timer"]=1 ;;
        *"NMI"*)                found_irqs["nmi"]=1 ;;
        *"LOC"*)                found_irqs["local_timer"]=1 ;;
        *"RES"*)                found_irqs["reschedule"]=1 ;;
        *"TLB"*)                found_irqs["tlb"]=1 ;;
    esac
done < /proc/interrupts

# Local timer (LOC) is always present on SMP systems
if [[ -z "${found_irqs[local_timer]+x}" ]]; then
    # Single-CPU VMs might not show LOC; that's acceptable
    true
fi

# ── Interrupt descriptor table sizing ─────────────────────────────────
IDT_VECTORS=256
IDT_GATE_SIZE_32=8      # 8 bytes per gate in 32-bit mode
IDT_GATE_SIZE_64=16     # 16 bytes per gate in 64-bit mode

assert_eq "$(( IDT_VECTORS * IDT_GATE_SIZE_64 ))" "4096" "64-bit IDT = 1 page"
assert_eq "$(( IDT_VECTORS * IDT_GATE_SIZE_32 ))" "2048" "32-bit IDT = 2KB"

# Vector ranges:
#   0-31:   CPU exceptions (reserved by Intel)
#   32-47:  legacy PIC IRQs (after remapping)
#   48-255: available for APIC, MSI, software interrupts
EXCEPTIONS_END=31
PIC_RANGE_START=32
PIC_RANGE_END=47
SOFTWARE_START=48

assert_eq "$(( PIC_RANGE_END - PIC_RANGE_START + 1 ))" "16" "16 PIC IRQ lines"
assert_eq "$(( IDT_VECTORS - SOFTWARE_START ))" "208" "208 vectors for APIC/MSI/SW"

# ── Simulate interrupt handler dispatch ──────────────────────────────
# Model a simple IDT with registered handlers.

declare -A idt_handlers

idt_register() {
    local vector=$1 handler=$2
    idt_handlers[$vector]="$handler"
}

idt_dispatch() {
    local vector=$1
    if [[ -n "${idt_handlers[$vector]+x}" ]]; then
        echo "${idt_handlers[$vector]}"
    else
        echo "PANIC: unhandled interrupt $vector"
        return 1
    fi
}

# Register exception handlers
idt_register 0 "divide_error_handler"
idt_register 6 "invalid_opcode_handler"
idt_register 13 "general_protection_handler"
idt_register 14 "page_fault_handler"

# Register IRQ handlers
idt_register 32 "timer_handler"
idt_register 33 "keyboard_handler"

assert_eq "$(idt_dispatch 0)" "divide_error_handler" "dispatch #DE"
assert_eq "$(idt_dispatch 14)" "page_fault_handler" "dispatch #PF"
assert_eq "$(idt_dispatch 32)" "timer_handler" "dispatch timer"
assert_eq "$(idt_dispatch 33)" "keyboard_handler" "dispatch keyboard"

# Unregistered vector should panic
if idt_dispatch 100 >/dev/null 2>&1; then
    echo "FAIL: unregistered vector should fail" >&2
    exit 1
fi

# ── IRQ priority and masking ─────────────────────────────────────────
# PIC masking: each bit in the mask register disables one IRQ.
# Bit 0 = IRQ 0 (timer), bit 1 = IRQ 1 (keyboard), etc.

irq_mask=0x00   # all IRQs enabled

irq_disable() {
    local irq=$1
    irq_mask=$(( irq_mask | (1 << irq) ))
}

irq_enable() {
    local irq=$1
    irq_mask=$(( irq_mask & ~(1 << irq) ))
}

irq_is_masked() {
    local irq=$1
    (( (irq_mask >> irq) & 1 ))
}

# Disable keyboard (IRQ 1) and check
irq_disable 1
irq_is_masked 1
assert_eq "$(( irq_mask ))" "2" "mask = 0x02 (keyboard disabled)"

# Timer should still be enabled
if irq_is_masked 0; then
    echo "FAIL: timer should not be masked" >&2
    exit 1
fi

# Re-enable keyboard
irq_enable 1
if irq_is_masked 1; then
    echo "FAIL: keyboard should be unmasked" >&2
    exit 1
fi
assert_eq "$irq_mask" "0" "all IRQs re-enabled"

echo "All interrupt handling examples passed."
