#!/bin/bash
# Vidya — Code Generation in Shell (Bash)
#
# Code generation is the back end of a compiler: turning IR into machine
# code bytes. Shell can emit raw bytes with printf '\xNN' and manipulate
# hex values with arithmetic. This demonstrates x86_64 instruction
# encoding, stack frame layout, and instruction size calculation.
#
# Key concepts:
#   - Emitting machine code bytes with printf
#   - x86_64 instruction formats and sizes
#   - Stack frame offset calculation
#   - Register encoding in ModR/M bytes

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

# ── Emit x86_64 bytes and verify with hex dump ──────────────────────
# printf '\xNN' writes raw bytes. We capture them as hex for verification.

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# NOP instruction: 0x90
printf '\x90' > "$tmpdir/nop.bin"
nop_hex=$(xxd -p "$tmpdir/nop.bin")
assert_eq "$nop_hex" "90" "NOP = 0x90"

# RET instruction: 0xC3
printf '\xc3' > "$tmpdir/ret.bin"
ret_hex=$(xxd -p "$tmpdir/ret.bin")
assert_eq "$ret_hex" "c3" "RET = 0xC3"

# INT3 breakpoint: 0xCC
printf '\xcc' > "$tmpdir/int3.bin"
int3_hex=$(xxd -p "$tmpdir/int3.bin")
assert_eq "$int3_hex" "cc" "INT3 = 0xCC"

# ── MOV rax, imm64 ──────────────────────────────────────────────────
# REX.W (0x48) + MOV opcode (0xB8+r) + 8-byte immediate
# mov rax, 0x0000000000000001
# REX.W=0x48, opcode=0xB8 (for rax, r=0), imm64=01 00 00 00 00 00 00 00

emit_mov_rax_imm64() {
    local imm=$1
    printf '\x48\xb8'  # REX.W + MOV rax opcode
    # Emit 8 bytes little-endian
    for (( i=0; i<8; i++ )); do
        local byte=$(( (imm >> (i * 8)) & 0xFF ))
        printf "\\x$(printf '%02x' "$byte")"
    done
}

emit_mov_rax_imm64 1 > "$tmpdir/mov_rax.bin"
mov_hex=$(xxd -p "$tmpdir/mov_rax.bin" | tr -d '\n')
assert_eq "$mov_hex" "48b80100000000000000" "MOV rax, 1"

emit_mov_rax_imm64 255 > "$tmpdir/mov_rax_ff.bin"
mov_ff=$(xxd -p "$tmpdir/mov_rax_ff.bin" | tr -d '\n')
assert_eq "$mov_ff" "48b8ff00000000000000" "MOV rax, 255"

# ── Instruction size table ───────────────────────────────────────────
# A code generator must know the size of each instruction it emits
# so it can calculate jump offsets.

declare -A INST_SIZE=(
    [nop]=1
    [ret]=1
    [int3]=1
    [push_reg]=1       # push r64 (no REX needed for rax-rdi)
    [pop_reg]=1        # pop r64
    [mov_reg_imm64]=10 # REX.W + opcode + 8-byte immediate
    [mov_reg_imm32]=5  # opcode + 4-byte immediate (32-bit)
    [add_reg_reg]=3    # REX.W + opcode + ModR/M
    [sub_reg_imm8]=4   # REX.W + opcode + ModR/M + imm8
    [jmp_rel32]=5      # opcode + 4-byte relative offset
    [call_rel32]=5     # opcode + 4-byte relative offset
    [syscall]=2        # 0x0F 0x05
)

# Calculate total code size for a function
calc_code_size() {
    local total=0
    for inst in "$@"; do
        local size=${INST_SIZE[$inst]}
        if [[ -z "$size" ]]; then
            echo "Unknown instruction: $inst" >&2
            return 1
        fi
        (( total += size ))
    done
    echo "$total"
}

# Minimal function: push rbp; ...; pop rbp; ret
size=$(calc_code_size push_reg mov_reg_imm64 add_reg_reg pop_reg ret)
assert_eq "$size" "16" "function size: push(1)+mov64(10)+add(3)+pop(1)+ret(1)"

# Syscall wrapper: mov64(10) + mov64(10) + syscall(2) + ret(1) = 23
size=$(calc_code_size mov_reg_imm64 mov_reg_imm64 syscall ret)
assert_eq "$size" "23" "syscall wrapper: mov64(10)+mov64(10)+syscall(2)+ret(1)"

# ── Stack frame layout ──────────────────────────────────────────────
# x86_64 System V ABI: stack grows downward, 16-byte aligned.
# Local variables are at negative offsets from RBP.

stack_frame_offsets() {
    local -a var_sizes=("$@")
    local offset=0
    local -a offsets=()

    for size in "${var_sizes[@]}"; do
        (( offset += size ))
        # Align offset to the variable's natural alignment
        local align=$size
        (( align > 8 )) && align=8
        local remainder=$(( offset % align ))
        if (( remainder != 0 )); then
            (( offset += align - remainder ))
        fi
        offsets+=("-$offset")
    done

    # Total frame size must be 16-byte aligned
    local total=$offset
    local remainder=$(( total % 16 ))
    if (( remainder != 0 )); then
        (( total += 16 - remainder ))
    fi
    echo "${offsets[*]} total:$total"
}

# Three local variables: int (4 bytes), long (8 bytes), char (1 byte)
frame=$(stack_frame_offsets 4 8 1)
assert_eq "$frame" "-4 -16 -17 total:32" "stack frame: int+long+char with alignment"

# Two 8-byte locals
frame=$(stack_frame_offsets 8 8)
assert_eq "$frame" "-8 -16 total:16" "stack frame: two longs, already aligned"

# ── Register encoding ───────────────────────────────────────────────
# x86_64 registers have 3-bit codes used in ModR/M and REX bytes.

declare -A REG_CODE=(
    [rax]=0 [rcx]=1 [rdx]=2 [rbx]=3
    [rsp]=4 [rbp]=5 [rsi]=6 [rdi]=7
)

# ModR/M byte: mod(2) | reg(3) | rm(3)
# mod=11 means register-to-register
modrm_reg_reg() {
    local dst=$1 src=$2
    local mod=3  # 0b11 = register direct
    local reg=${REG_CODE[$src]}
    local rm=${REG_CODE[$dst]}
    echo $(( (mod << 6) | (reg << 3) | rm ))
}

# ADD rax, rbx → ModR/M = 0xD8 (mod=11, reg=rbx(3), rm=rax(0))
modrm=$(modrm_reg_reg rax rbx)
assert_eq "$modrm" "216" "ModR/M for ADD rax,rbx = 0xD8 = 216"
hex_modrm=$(printf '%02x' "$modrm")
assert_eq "$hex_modrm" "d8" "ModR/M hex for ADD rax,rbx"

# ADD rcx, rdx → ModR/M = 0xD1 (mod=11, reg=rdx(2), rm=rcx(1))
modrm=$(modrm_reg_reg rcx rdx)
assert_eq "$modrm" "209" "ModR/M for ADD rcx,rdx = 0xD1 = 209"

# ── Emit a complete ADD instruction ─────────────────────────────────
# ADD r64, r64 = REX.W (0x48) + opcode (0x01) + ModR/M

emit_add_reg_reg() {
    local dst=$1 src=$2
    local modrm
    modrm=$(modrm_reg_reg "$dst" "$src")
    printf '\x48\x01'
    printf "\\x$(printf '%02x' "$modrm")"
}

emit_add_reg_reg rax rbx > "$tmpdir/add.bin"
add_hex=$(xxd -p "$tmpdir/add.bin" | tr -d '\n')
assert_eq "$add_hex" "4801d8" "ADD rax,rbx = 48 01 D8"

emit_add_reg_reg rcx rdx > "$tmpdir/add2.bin"
add2_hex=$(xxd -p "$tmpdir/add2.bin" | tr -d '\n')
assert_eq "$add2_hex" "4801d1" "ADD rcx,rdx = 48 01 D1"

# ── Jump offset calculation ──────────────────────────────────────────
# JMP rel32: the offset is relative to the NEXT instruction (after the 5-byte JMP).

calc_jump_offset() {
    local from_addr=$1 to_addr=$2
    local jmp_size=5
    echo $(( to_addr - (from_addr + jmp_size) ))
}

offset=$(calc_jump_offset 0x100 0x200)
assert_eq "$offset" "251" "forward jump offset: 0x200 - 0x105 = 251"

offset=$(calc_jump_offset 0x200 0x100)
assert_eq "$offset" "-261" "backward jump offset: 0x100 - 0x205 = -261"

# Zero-distance jump (jump to next instruction)
offset=$(calc_jump_offset 0x100 0x105)
assert_eq "$offset" "0" "jump to next instruction = offset 0"

echo "$PASS tests passed"
exit 0
