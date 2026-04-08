#!/bin/bash
# Vidya — Binary Formats in Shell
#
# Shell can inspect binary files through hex dump tools (xxd, od)
# and the /proc filesystem. Magic bytes at the start of a file
# identify its format — ELF, PE, Mach-O, shebang, gzip, etc.
# This file demonstrates reading raw bytes, interpreting magic
# numbers, and detecting file formats from the command line.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ── Magic byte constants ──────────────────────────────────────────────
# File formats are identified by their first few bytes (magic numbers).
# These are the canonical signatures for common binary formats.

ELF_MAGIC="7f454c46"       # \x7fELF
PE_MAGIC="4d5a"             # MZ (DOS header, used by PE/COFF)
MACHO_MAGIC_LE="cffaedfe"  # Mach-O 64-bit little-endian
GZIP_MAGIC="1f8b"          # gzip compressed
SHEBANG_MAGIC="2321"       # #! (script)
PDF_MAGIC="25504446"       # %PDF

# Verify magic byte values with hex arithmetic
assert_eq "$(printf '%02x' 0x7f)" "7f" "ELF byte 0"
assert_eq "$(printf '%02x' 0x45)" "45" "ELF byte 1 (E)"
assert_eq "$(printf '%02x' 0x4c)" "4c" "ELF byte 2 (L)"
assert_eq "$(printf '%02x' 0x46)" "46" "ELF byte 3 (F)"

# MZ header: 'M' = 0x4d, 'Z' = 0x5a
assert_eq "$(( 0x4d ))" "77" "M decimal"
assert_eq "$(( 0x5a ))" "90" "Z decimal"

# ── Read ELF magic from /proc/self/exe ────────────────────────────────
# /proc/self/exe is a symlink to the currently running executable.
# For bash, this points to the bash binary itself — always an ELF file
# on Linux.

read_magic_bytes() {
    local file="$1" count="${2:-4}"
    # od: octal dump; -A n = no address; -t x1 = hex bytes; -N = byte count
    od -A n -t x1 -N "$count" "$file" | tr -d ' \n'
}

# The bash interpreter is an ELF binary
bash_magic=$(read_magic_bytes /proc/self/exe 4)
assert_eq "$bash_magic" "$ELF_MAGIC" "/proc/self/exe is ELF"

# ── ELF header field extraction ──────────────────────────────────────
# ELF header layout (first 16 bytes = e_ident):
#   Offset 0x00: magic (4 bytes) — 7f 45 4c 46
#   Offset 0x04: class (1 byte) — 1=32-bit, 2=64-bit
#   Offset 0x05: data  (1 byte) — 1=little-endian, 2=big-endian
#   Offset 0x06: version (1 byte) — 1=current
#   Offset 0x07: OS/ABI (1 byte) — 0=SYSV, 3=Linux

elf_class_byte=$(od -A n -t x1 -j 4 -N 1 /proc/self/exe | tr -d ' \n')
elf_data_byte=$(od -A n -t x1 -j 5 -N 1 /proc/self/exe | tr -d ' \n')
elf_version_byte=$(od -A n -t x1 -j 6 -N 1 /proc/self/exe | tr -d ' \n')
elf_osabi_byte=$(od -A n -t x1 -j 7 -N 1 /proc/self/exe | tr -d ' \n')

# On a 64-bit Linux system, bash is a 64-bit little-endian ELF
assert_eq "$elf_class_byte" "02" "ELF class: 64-bit"
assert_eq "$elf_data_byte" "01" "ELF data: little-endian"
assert_eq "$elf_version_byte" "01" "ELF version: current"

# Decode class
declare -A ELF_CLASS=( [01]="ELF32" [02]="ELF64" )
declare -A ELF_DATA=( [01]="little-endian" [02]="big-endian" )

assert_eq "${ELF_CLASS[$elf_class_byte]}" "ELF64" "class name"
assert_eq "${ELF_DATA[$elf_data_byte]}" "little-endian" "endianness name"

# ── File format detection by magic bytes ──────────────────────────────
# A file format detector reads the first few bytes and matches against
# known magic numbers. This is how `file(1)` works internally.

detect_format() {
    local file="$1"
    local magic
    magic=$(read_magic_bytes "$file" 4)

    case "$magic" in
        "$ELF_MAGIC")       echo "ELF" ;;
        "${PDF_MAGIC}"*)    echo "PDF" ;;
        "${GZIP_MAGIC}"*)   echo "GZIP" ;;
        "${SHEBANG_MAGIC}"*) echo "SCRIPT" ;;
        "${PE_MAGIC}"*)     echo "PE" ;;
        *)                  echo "UNKNOWN" ;;
    esac
}

# Detect /proc/self/exe — must be ELF
detected=$(detect_format /proc/self/exe)
assert_eq "$detected" "ELF" "detect bash as ELF"

# Create test files with known magic bytes
printf '\x7fELF' > "$tmpdir/test.elf"
printf '%%PDF-1.7' > "$tmpdir/test.pdf"
printf '\x1f\x8b' > "$tmpdir/test.gz"
printf '#!/bin/sh\n' > "$tmpdir/test.sh"
printf 'MZ' > "$tmpdir/test.exe"
printf 'JUNK' > "$tmpdir/test.unknown"

assert_eq "$(detect_format "$tmpdir/test.elf")" "ELF" "detect ELF"
assert_eq "$(detect_format "$tmpdir/test.pdf")" "PDF" "detect PDF"
assert_eq "$(detect_format "$tmpdir/test.gz")" "GZIP" "detect GZIP"
assert_eq "$(detect_format "$tmpdir/test.sh")" "SCRIPT" "detect script"
assert_eq "$(detect_format "$tmpdir/test.exe")" "PE" "detect PE"
assert_eq "$(detect_format "$tmpdir/test.unknown")" "UNKNOWN" "detect unknown"

# ── Hex dump formatting ──────────────────────────────────────────────
# Show first 16 bytes of the ELF header in a readable format
format_hex_dump() {
    local file="$1" count="${2:-16}"
    od -A x -t x1z -N "$count" "$file" | head -n 1
}

dump=$(format_hex_dump /proc/self/exe 4)
# The dump should contain our ELF magic bytes
if [[ "$dump" != *"7f"*"45"*"4c"*"46"* ]]; then
    echo "FAIL: hex dump should contain ELF magic" >&2
    exit 1
fi

# ── Byte order and multi-byte field reading ───────────────────────────
# ELF uses the endianness specified in byte 5. On little-endian systems,
# multi-byte fields are stored least-significant byte first.

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

# e_type is at offset 16 in the ELF header (2 bytes, LE)
# 2 = ET_EXEC (executable), 3 = ET_DYN (shared object / PIE)
elf_type=$(read_le16 /proc/self/exe 16)
if (( elf_type != 2 && elf_type != 3 )); then
    echo "FAIL: e_type should be ET_EXEC(2) or ET_DYN(3), got $elf_type" >&2
    exit 1
fi

# e_machine is at offset 18 (2 bytes, LE)
# 0x3e = 62 = EM_X86_64, 0xb7 = 183 = EM_AARCH64
elf_machine=$(read_le16 /proc/self/exe 18)
declare -A MACHINE_NAMES=( [3]="EM_386" [62]="EM_X86_64" [183]="EM_AARCH64" [40]="EM_ARM" )
machine_name="${MACHINE_NAMES[$elf_machine]:-UNKNOWN}"

if [[ "$machine_name" == "UNKNOWN" ]]; then
    echo "FAIL: unrecognized e_machine: $elf_machine" >&2
    exit 1
fi

# ── Binary format size constants ──────────────────────────────────────
# Key sizes in the ELF format, expressed as hex arithmetic
ELF64_HEADER_SIZE=$(( 0x40 ))     # 64 bytes
ELF32_HEADER_SIZE=$(( 0x34 ))     # 52 bytes
ELF_IDENT_SIZE=$(( 0x10 ))        # 16 bytes (e_ident)
PHDR64_SIZE=$(( 0x38 ))           # 56 bytes per program header
SHDR64_SIZE=$(( 0x40 ))           # 64 bytes per section header

assert_eq "$ELF64_HEADER_SIZE" "64" "ELF64 header = 64 bytes"
assert_eq "$ELF32_HEADER_SIZE" "52" "ELF32 header = 52 bytes"
assert_eq "$ELF_IDENT_SIZE" "16" "e_ident = 16 bytes"
assert_eq "$PHDR64_SIZE" "56" "phdr64 = 56 bytes"
assert_eq "$SHDR64_SIZE" "64" "shdr64 = 64 bytes"

# e_ehsize at offset 52 should confirm our header size
elf_ehsize=$(read_le16 /proc/self/exe 52)
assert_eq "$elf_ehsize" "$ELF64_HEADER_SIZE" "e_ehsize matches"

echo "All binary formats examples passed."
