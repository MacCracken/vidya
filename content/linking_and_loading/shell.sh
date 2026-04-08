#!/bin/bash
# Vidya — Linking and Loading in Shell (Bash)
#
# A linker combines multiple object files into one executable by:
#   1. Collecting symbol definitions from each object file
#   2. Resolving symbol references (matching uses to definitions)
#   3. Patching relocations (filling in addresses)
#   4. Merging sections (.text, .data)
#
# Shell can model this with temp files as "object files", grep for
# symbol lookup, and arithmetic for address calculation.

set -euo pipefail

PASS=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
    (( ++PASS ))
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ── Object file format ──────────────────────────────────────────────
# Each "object file" is a text file with sections:
#   .symbols — defined and referenced symbols
#   .text    — code bytes (hex strings)
#   .data    — data bytes

# Object file 1: main.o — defines main, references printf and add
cat > "$tmpdir/main.o" << 'OBJ'
.symbols
DEF main .text 0
REF printf
REF add
.text
# main: call add, call printf, return
48c7c72a000000
e800000000
e800000000
c3
.data
OBJ

# Object file 2: math.o — defines add, references nothing
cat > "$tmpdir/math.o" << 'OBJ'
.symbols
DEF add .text 0
.text
# add: add rdi,rsi; mov rax,rdi; ret
4801f7
4889f8
c3
.data
OBJ

# Object file 3: libc.o — defines printf (stub)
cat > "$tmpdir/libc.o" << 'OBJ'
.symbols
DEF printf .text 0
.text
# printf stub: mov rax,1; syscall; ret
48c7c001000000
0f05
c3
.data
OBJ

# ── Symbol collection ───────────────────────────────────────────────
# Pass 1: walk all object files, collect all DEF and REF symbols.

declare -A defined_in    # symbol → object file
declare -A defined_offset # symbol → offset within section
declare -a undefined=()   # symbols referenced but not yet defined

collect_symbols() {
    local objfile="$1"
    local basename
    basename=$(basename "$objfile")
    local in_symbols=0

    while IFS=' ' read -r tag name section offset; do
        if [[ "$tag" == ".symbols" ]]; then
            in_symbols=1
            continue
        fi
        if [[ "$tag" == .* && "$tag" != ".symbols" ]]; then
            in_symbols=0
            continue
        fi
        if (( in_symbols )); then
            if [[ "$tag" == "DEF" ]]; then
                defined_in[$name]=$basename
                defined_offset[$name]=${offset:-0}
            elif [[ "$tag" == "REF" ]]; then
                if [[ -z "${defined_in[$name]+x}" ]]; then
                    undefined+=("$name")
                fi
            fi
        fi
    done < "$objfile"
}

collect_symbols "$tmpdir/main.o"
collect_symbols "$tmpdir/math.o"
collect_symbols "$tmpdir/libc.o"

assert_eq "${defined_in[main]}" "main.o" "main defined in main.o"
assert_eq "${defined_in[add]}" "math.o" "add defined in math.o"
assert_eq "${defined_in[printf]}" "libc.o" "printf defined in libc.o"

# ── Symbol resolution ───────────────────────────────────────────────
# Every REF must have a matching DEF. If not, it's an undefined symbol error.

resolve_symbols() {
    local -a unresolved=()

    for sym in "${undefined[@]}"; do
        if [[ -z "${defined_in[$sym]+x}" ]]; then
            unresolved+=("$sym")
        fi
    done

    if (( ${#unresolved[@]} > 0 )); then
        echo "UNRESOLVED: ${unresolved[*]}"
        return 1
    fi
    echo "ALL_RESOLVED"
    return 0
}

resolution=$(resolve_symbols)
assert_eq "$resolution" "ALL_RESOLVED" "all symbols resolved"

# Test with an unresolved symbol — printf is already in undefined[] from
# collect_symbols (as a REF from main.o). Just remove its definition.
defined_in_backup_printf="${defined_in[printf]}"
unset 'defined_in[printf]'
resolution=$(resolve_symbols || true)
assert_eq "$resolution" "UNRESOLVED: printf" "detect unresolved printf"
# Restore
defined_in[printf]=$defined_in_backup_printf

# ── Section merging ──────────────────────────────────────────────────
# The linker concatenates .text sections from all objects, tracking
# where each object's code starts (its base address).

declare -A section_base  # "objfile:section" → base address in merged output

# merge_text_sections sets section_base[] and MERGED_TEXT as globals.
# We call it directly (not in a subshell) so the associative array updates
# are visible to the rest of the script.
MERGED_TEXT=""

merge_text_sections() {
    local -a objfiles=("$@")
    local offset=0
    MERGED_TEXT=""

    for objfile in "${objfiles[@]}"; do
        local bname
        bname=$(basename "$objfile")
        local in_text=0

        section_base["$bname:.text"]=$offset

        while IFS= read -r line; do
            if [[ "$line" == ".text" ]]; then
                in_text=1
                continue
            fi
            if [[ "$line" == .* && "$line" != ".text" ]]; then
                in_text=0
                continue
            fi
            if (( in_text )) && [[ -n "$line" && ! "$line" =~ ^# ]]; then
                MERGED_TEXT+="$line"
                local clean="${line//[^0-9a-fA-F]/}"
                (( offset += ${#clean} / 2 ))
            fi
        done < "$objfile"
    done
}

merge_text_sections "$tmpdir/main.o" "$tmpdir/math.o" "$tmpdir/libc.o"

assert_eq "${section_base[main.o:.text]}" "0" "main.o .text at offset 0"

# main.o .text bytes: 48c7c72a000000 (7) + e800000000 (5) + e800000000 (5) + c3 (1) = 18
assert_eq "${section_base[math.o:.text]}" "18" "math.o .text at offset 18"

# math.o .text bytes: 4801f7 (3) + 4889f8 (3) + c3 (1) = 7
assert_eq "${section_base[libc.o:.text]}" "25" "libc.o .text at offset 25"

# ── Address calculation ──────────────────────────────────────────────
# Final address of a symbol = section_base[obj:section] + offset_within_section

symbol_address() {
    local sym=$1
    local obj=${defined_in[$sym]}
    local offset=${defined_offset[$sym]}
    local base=${section_base["$obj:.text"]}
    echo $(( base + offset ))
}

main_addr=$(symbol_address main)
add_addr=$(symbol_address add)
printf_addr=$(symbol_address printf)

assert_eq "$main_addr" "0" "main at address 0"
assert_eq "$add_addr" "18" "add at address 18"
assert_eq "$printf_addr" "25" "printf at address 25"

# ── Relocation patching ─────────────────────────────────────────────
# A CALL instruction uses a 32-bit PC-relative offset.
# offset = target_addr - (call_site_addr + 5)  [5 = size of CALL instruction]

calc_relocation() {
    local call_site=$1 target=$2
    local call_size=5
    echo $(( target - (call_site + call_size) ))
}

# In main.o, the first CALL is at offset 7 (after the MOV), targeting "add"
# call_site = 0 (main base) + 7 = 7
# target = 18 (add address)
rel_add=$(calc_relocation 7 18)
assert_eq "$rel_add" "6" "relocation: CALL add from offset 7, rel=6"

# The second CALL is at offset 12, targeting "printf"
# call_site = 12, target = 25
rel_printf=$(calc_relocation 12 25)
assert_eq "$rel_printf" "8" "relocation: CALL printf from offset 12, rel=8"

# ── Duplicate symbol detection ───────────────────────────────────────
# A linker must reject multiple definitions of the same symbol
# (unless one is weak).

detect_duplicates() {
    local -A seen
    local -a dups=()

    for objfile in "$@"; do
        local in_symbols=0
        while IFS=' ' read -r tag name rest; do
            if [[ "$tag" == ".symbols" ]]; then in_symbols=1; continue; fi
            if [[ "$tag" == .* ]]; then in_symbols=0; continue; fi
            if (( in_symbols )) && [[ "$tag" == "DEF" ]]; then
                if [[ -n "${seen[$name]+x}" ]]; then
                    dups+=("$name")
                fi
                seen[$name]=$(basename "$objfile")
            fi
        done < "$objfile"
    done

    if (( ${#dups[@]} > 0 )); then
        echo "DUPLICATE: ${dups[*]}"
    else
        echo "NO_DUPLICATES"
    fi
}

assert_eq "$(detect_duplicates "$tmpdir/main.o" "$tmpdir/math.o" "$tmpdir/libc.o")" \
    "NO_DUPLICATES" "no duplicate symbols"

# Create a conflicting object
cat > "$tmpdir/conflict.o" << 'OBJ'
.symbols
DEF add .text 0
.text
c3
.data
OBJ

assert_eq "$(detect_duplicates "$tmpdir/math.o" "$tmpdir/conflict.o")" \
    "DUPLICATE: add" "detect duplicate symbol: add"

# ── Section size summary ─────────────────────────────────────────────
section_size() {
    local objfile="$1" section="$2"
    local in_section=0
    local total_bytes=0

    while IFS= read -r line; do
        if [[ "$line" == "$section" ]]; then
            in_section=1
            continue
        fi
        if [[ "$line" == .* && "$line" != "$section" ]]; then
            in_section=0
            continue
        fi
        if (( in_section )) && [[ -n "$line" && ! "$line" =~ ^# ]]; then
            local clean="${line//[^0-9a-fA-F]/}"
            (( total_bytes += ${#clean} / 2 ))
        fi
    done < "$objfile"
    echo "$total_bytes"
}

assert_eq "$(section_size "$tmpdir/main.o" ".text")" "18" "main.o .text = 18 bytes"
assert_eq "$(section_size "$tmpdir/math.o" ".text")" "7" "math.o .text = 7 bytes"
assert_eq "$(section_size "$tmpdir/libc.o" ".text")" "10" "libc.o .text = 10 bytes"

# Total linked binary .text size
total_text=$(( 18 + 7 + 10 ))
assert_eq "$total_text" "35" "total .text = 35 bytes"

# ── Load address assignment ─────────────────────────────────────────
# The loader places sections at virtual addresses. .text typically starts
# at a fixed base (e.g., 0x400000 on Linux x86_64).

LOAD_BASE=0x400000

virt_main=$(( LOAD_BASE + main_addr ))
virt_add=$(( LOAD_BASE + add_addr ))
virt_printf=$(( LOAD_BASE + printf_addr ))

assert_eq "$(printf '0x%x' $virt_main)" "0x400000" "main VA = 0x400000"
assert_eq "$(printf '0x%x' $virt_add)" "0x400012" "add VA = 0x400012"
assert_eq "$(printf '0x%x' $virt_printf)" "0x400019" "printf VA = 0x400019"

echo "$PASS tests passed"
exit 0
