#!/bin/bash
# Vidya — ELF and Executable Formats in Shell
#
# The Executable and Linkable Format (ELF) is the standard binary
# format on Linux/Unix. This file parses an ELF binary using only
# shell tools (od, printf, arithmetic), producing readelf-style
# output without relying on readelf itself. Understanding ELF
# structure is essential for systems programming, debugging, and
# security analysis.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Low-level byte readers ────────────────────────────────────────────
# ELF fields are little-endian on x86/ARM. We read raw bytes with od
# and reassemble them in host byte order.

read_byte() {
    local file="$1" offset="$2"
    od -A n -t x1 -j "$offset" -N 1 "$file" | tr -d ' \n'
}

read_le16() {
    local file="$1" offset="$2"
    local bytes
    bytes=($(od -A n -t x1 -j "$offset" -N 2 "$file"))
    echo $(( 16#${bytes[1]}${bytes[0]} ))
}

read_le32() {
    local file="$1" offset="$2"
    local bytes
    bytes=($(od -A n -t x1 -j "$offset" -N 4 "$file"))
    echo $(( 16#${bytes[3]}${bytes[2]}${bytes[1]}${bytes[0]} ))
}

read_le64() {
    local file="$1" offset="$2"
    local bytes
    bytes=($(od -A n -t x1 -j "$offset" -N 8 "$file"))
    # Build in two 32-bit halves to avoid overflow in some bash versions
    local hi=$(( 16#${bytes[7]}${bytes[6]}${bytes[5]}${bytes[4]} ))
    local lo=$(( 16#${bytes[3]}${bytes[2]}${bytes[1]}${bytes[0]} ))
    echo $(( (hi << 32) | lo ))
}

# ── Use /proc/self/exe as our test binary ─────────────────────────────
# This is always a valid ELF on Linux — it's the bash interpreter.
ELF="/proc/self/exe"

# ── Parse e_ident (bytes 0-15) ────────────────────────────────────────
# The first 16 bytes of every ELF file are the identification array.
#
#   Offset  Field        Meaning
#   0x00    EI_MAG0-3    Magic: 0x7f 'E' 'L' 'F'
#   0x04    EI_CLASS     1=32-bit, 2=64-bit
#   0x05    EI_DATA      1=LE, 2=BE
#   0x06    EI_VERSION   Must be 1 (EV_CURRENT)
#   0x07    EI_OSABI     0=SYSV, 3=Linux, 9=FreeBSD

magic0=$(read_byte "$ELF" 0)
magic1=$(read_byte "$ELF" 1)
magic2=$(read_byte "$ELF" 2)
magic3=$(read_byte "$ELF" 3)

assert_eq "$magic0" "7f" "EI_MAG0"
assert_eq "$magic1" "45" "EI_MAG1 (E)"
assert_eq "$magic2" "4c" "EI_MAG2 (L)"
assert_eq "$magic3" "46" "EI_MAG3 (F)"

ei_class=$(read_byte "$ELF" 4)
ei_data=$(read_byte "$ELF" 5)
ei_version=$(read_byte "$ELF" 6)
ei_osabi=$(read_byte "$ELF" 7)

assert_eq "$ei_class" "02" "EI_CLASS: 64-bit"
assert_eq "$ei_data" "01" "EI_DATA: little-endian"
assert_eq "$ei_version" "01" "EI_VERSION: current"

# ── Decode e_ident fields to human-readable strings ───────────────────
declare -A CLASS_MAP=( [01]="ELF32" [02]="ELF64" )
declare -A DATA_MAP=( [01]="2's complement, little endian" [02]="2's complement, big endian" )
declare -A OSABI_MAP=( [00]="UNIX - System V" [03]="UNIX - Linux" [09]="UNIX - FreeBSD" )

class_name="${CLASS_MAP[$ei_class]}"
data_name="${DATA_MAP[$ei_data]}"
osabi_name="${OSABI_MAP[$ei_osabi]:-Other ($ei_osabi)}"

assert_eq "$class_name" "ELF64" "class name"

# ── Parse ELF header fields (64-bit layout) ───────────────────────────
# After e_ident (16 bytes), the ELF64 header continues:
#
#   Offset  Size  Field         Description
#   0x10    2     e_type        Object file type
#   0x12    2     e_machine     Target architecture
#   0x14    4     e_version     ELF version
#   0x18    8     e_entry       Entry point virtual address
#   0x20    8     e_phoff       Program header table offset
#   0x28    8     e_shoff       Section header table offset
#   0x30    4     e_flags       Processor-specific flags
#   0x34    2     e_ehsize      ELF header size
#   0x36    2     e_phentsize   Program header entry size
#   0x38    2     e_phnum       Number of program headers
#   0x3a    2     e_shentsize   Section header entry size
#   0x3c    2     e_shnum       Number of section headers
#   0x3e    2     e_shstrndx    Section name string table index

e_type=$(read_le16 "$ELF" $((0x10)))
e_machine=$(read_le16 "$ELF" $((0x12)))
e_version=$(read_le32 "$ELF" $((0x14)))
e_entry=$(read_le64 "$ELF" $((0x18)))
e_phoff=$(read_le64 "$ELF" $((0x20)))
e_shoff=$(read_le64 "$ELF" $((0x28)))
e_flags=$(read_le32 "$ELF" $((0x30)))
e_ehsize=$(read_le16 "$ELF" $((0x34)))
e_phentsize=$(read_le16 "$ELF" $((0x36)))
e_phnum=$(read_le16 "$ELF" $((0x38)))
e_shentsize=$(read_le16 "$ELF" $((0x3a)))
e_shnum=$(read_le16 "$ELF" $((0x3c)))
e_shstrndx=$(read_le16 "$ELF" $((0x3e)))

# ── Decode e_type ─────────────────────────────────────────────────────
declare -A TYPE_MAP=( [0]="NONE" [1]="REL" [2]="EXEC" [3]="DYN" [4]="CORE" )
type_name="${TYPE_MAP[$e_type]:-UNKNOWN}"

# Bash is typically ET_DYN (PIE executable) or ET_EXEC
if [[ "$type_name" != "EXEC" && "$type_name" != "DYN" ]]; then
    echo "FAIL: e_type should be EXEC or DYN, got $type_name ($e_type)" >&2
    exit 1
fi

# ── Decode e_machine ──────────────────────────────────────────────────
declare -A MACHINE_MAP=(
    [3]="Intel 80386"
    [40]="ARM"
    [62]="Advanced Micro Devices X86-64"
    [183]="AArch64"
    [243]="RISC-V"
)
machine_name="${MACHINE_MAP[$e_machine]:-Unknown ($e_machine)}"

# Must be a recognized architecture
if [[ "$machine_name" == Unknown* ]]; then
    echo "FAIL: unrecognized e_machine: $e_machine" >&2
    exit 1
fi

# ── Validate header consistency ───────────────────────────────────────
assert_eq "$e_ehsize" "64" "ELF64 header size = 64 bytes"
assert_eq "$e_version" "1" "e_version = EV_CURRENT"

# Program header entry size for ELF64 is always 56 bytes
assert_eq "$e_phentsize" "56" "phentsize = 56"

# Section header entry size for ELF64 is always 64 bytes
assert_eq "$e_shentsize" "64" "shentsize = 64"

# e_phoff should be right after the ELF header (typically 64)
assert_eq "$e_phoff" "64" "phoff = 64 (immediately after header)"

# Entry point must be nonzero for executables
if (( e_entry == 0 )); then
    echo "FAIL: entry point should not be zero" >&2
    exit 1
fi

# Section header string table index must be within bounds
if (( e_shstrndx >= e_shnum && e_shstrndx != 0xffff )); then
    echo "FAIL: shstrndx out of bounds" >&2
    exit 1
fi

# ── Produce readelf-style output ──────────────────────────────────────
# This replicates the format of `readelf -h` using our parsed values.

readelf_output=$(cat <<HEADER
ELF Header:
  Magic:   7f 45 4c 46 $ei_class $ei_data $ei_version $(printf '%02x' 0) 00 00 00 00 00 00 00 00
  Class:                             $class_name
  Data:                              $data_name
  Version:                           $e_version (current)
  OS/ABI:                            $osabi_name
  Type:                              $type_name ($(if [[ "$type_name" == "DYN" ]]; then echo "Position-Independent Executable"; else echo "Executable file"; fi))
  Machine:                           $machine_name
  Version:                           0x$e_version
  Entry point address:               $(printf '0x%x' "$e_entry")
  Start of program headers:          $e_phoff (bytes into file)
  Start of section headers:          $e_shoff (bytes into file)
  Flags:                             0x$(printf '%x' "$e_flags")
  Size of this header:               $e_ehsize (bytes)
  Size of program headers:           $e_phentsize (bytes)
  Number of program headers:         $e_phnum
  Size of section headers:           $e_shentsize (bytes)
  Number of section headers:         $e_shnum
  Section header string table index: $e_shstrndx
HEADER
)

# Verify our output contains critical fields
if [[ "$readelf_output" != *"ELF Header:"* ]]; then
    echo "FAIL: missing ELF Header label" >&2
    exit 1
fi
if [[ "$readelf_output" != *"$class_name"* ]]; then
    echo "FAIL: missing class in output" >&2
    exit 1
fi
if [[ "$readelf_output" != *"$machine_name"* ]]; then
    echo "FAIL: missing machine in output" >&2
    exit 1
fi

# ── Program header types ──────────────────────────────────────────────
# Each program header describes a segment loaded into memory.
# p_type (4 bytes at the start of each phdr) identifies the segment.

declare -A PHDR_TYPES=(
    [0]="PT_NULL"
    [1]="PT_LOAD"
    [2]="PT_DYNAMIC"
    [3]="PT_INTERP"
    [4]="PT_NOTE"
    [6]="PT_PHDR"
    [1685382480]="PT_GNU_EH_FRAME"
    [1685382481]="PT_GNU_STACK"
    [1685382482]="PT_GNU_RELRO"
    [1685382483]="PT_GNU_PROPERTY"
)

# Parse first program header's p_type
first_phdr_type=$(read_le32 "$ELF" "$e_phoff")
first_phdr_name="${PHDR_TYPES[$first_phdr_type]:-UNKNOWN}"

# First program header is typically PT_PHDR (type 6) for dynamic executables
if [[ "$type_name" == "DYN" ]]; then
    assert_eq "$first_phdr_type" "6" "first phdr is PT_PHDR for PIE"
fi

# ── ELF size constants as hex arithmetic ──────────────────────────────
# Verify relationships between ELF structural sizes

total_phdr_size=$(( e_phentsize * e_phnum ))
total_shdr_size=$(( e_shentsize * e_shnum ))

# Program headers and section headers should not overlap
if (( e_phoff + total_phdr_size > e_shoff && e_shoff != 0 )); then
    echo "FAIL: program and section headers overlap" >&2
    exit 1
fi

# Verify hex constant relationships
assert_eq "$(( 0x40 ))" "64" "ELF64 header = 0x40"
assert_eq "$(( 0x38 ))" "56" "phdr64 entry = 0x38"
assert_eq "$(( 0x40 ))" "64" "shdr64 entry = 0x40"

# ELF64 header ends where program headers begin
assert_eq "$(( 0x40 ))" "$e_phoff" "header end = phdr start"

echo "All ELF and executable formats examples passed."
