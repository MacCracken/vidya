#!/bin/bash
# Vidya — Instruction Encoding in Shell (Bash)
#
# x86_64 instructions are variable-length byte sequences. Each instruction
# may have: legacy prefixes, REX prefix, opcode (1-3 bytes), ModR/M,
# SIB, displacement, and immediate. Shell arithmetic and printf let us
# build and verify these byte patterns.
#
# Key concepts:
#   - REX prefix: W, R, X, B bit fields
#   - ModR/M byte: mod(2) | reg(3) | rm(3)
#   - SIB byte: scale(2) | index(3) | base(3)
#   - Instruction length calculation
#   - Little-endian immediate encoding

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

# ── Register code table ─────────────────────────────────────────────
# x86_64 registers are encoded as 3-bit values (0-7).
# Registers r8-r15 use the REX.B/R/X extension bits.

declare -A REG=(
    [rax]=0 [rcx]=1 [rdx]=2 [rbx]=3
    [rsp]=4 [rbp]=5 [rsi]=6 [rdi]=7
    [r8]=0  [r9]=1  [r10]=2 [r11]=3
    [r12]=4 [r13]=5 [r14]=6 [r15]=7
)

# Does this register need the REX extension bit?
reg_needs_rex_ext() {
    case "$1" in
        r8|r9|r10|r11|r12|r13|r14|r15) return 0 ;;
        *) return 1 ;;
    esac
}

assert_eq "${REG[rax]}" "0" "rax = 0"
assert_eq "${REG[rdi]}" "7" "rdi = 7"
assert_eq "${REG[r8]}" "0" "r8 = 0 (extended)"

# ── REX prefix construction ─────────────────────────────────────────
# REX byte: 0100 W R X B
#   W = 64-bit operand size
#   R = extends ModR/M.reg
#   X = extends SIB.index
#   B = extends ModR/M.rm or SIB.base

rex_byte() {
    local w=${1:-0} r=${2:-0} x=${3:-0} b=${4:-0}
    echo $(( 0x40 | (w << 3) | (r << 2) | (x << 1) | b ))
}

# REX.W (64-bit operand) = 0x48
rex=$(rex_byte 1 0 0 0)
assert_eq "$(printf '%02x' "$rex")" "48" "REX.W = 0x48"

# REX.WB (64-bit + extended rm) = 0x49
rex=$(rex_byte 1 0 0 1)
assert_eq "$(printf '%02x' "$rex")" "49" "REX.WB = 0x49"

# REX.WR (64-bit + extended reg) = 0x4C
rex=$(rex_byte 1 1 0 0)
assert_eq "$(printf '%02x' "$rex")" "4c" "REX.WR = 0x4C"

# REX.WRXB (all extension bits) = 0x4F
rex=$(rex_byte 1 1 1 1)
assert_eq "$(printf '%02x' "$rex")" "4f" "REX.WRXB = 0x4F"

# Plain REX (no extensions, just the prefix) = 0x40
rex=$(rex_byte 0 0 0 0)
assert_eq "$(printf '%02x' "$rex")" "40" "REX (plain) = 0x40"

# ── ModR/M byte construction ────────────────────────────────────────
# ModR/M: mod(2 bits) | reg(3 bits) | rm(3 bits)
#   mod=00: [rm] (memory, no displacement)
#   mod=01: [rm+disp8]
#   mod=10: [rm+disp32]
#   mod=11: rm (register direct)

modrm_byte() {
    local mod=$1 reg=$2 rm=$3
    echo $(( (mod << 6) | (reg << 3) | rm ))
}

# Register-to-register: mod=11, reg=src, rm=dst
# ADD rax, rcx → ModR/M = 11 001 000 = 0xC8
modrm=$(modrm_byte 3 ${REG[rcx]} ${REG[rax]})
assert_eq "$(printf '%02x' "$modrm")" "c8" "ModR/M: ADD rax,rcx = 0xC8"

# ADD rbx, rdx → ModR/M = 11 010 011 = 0xD3
modrm=$(modrm_byte 3 ${REG[rdx]} ${REG[rbx]})
assert_eq "$(printf '%02x' "$modrm")" "d3" "ModR/M: ADD rbx,rdx = 0xD3"

# Memory indirect: mod=00, [rsi]
# MOV rax, [rsi] → ModR/M = 00 000 110 = 0x06
modrm=$(modrm_byte 0 ${REG[rax]} ${REG[rsi]})
assert_eq "$(printf '%02x' "$modrm")" "06" "ModR/M: MOV rax,[rsi] = 0x06"

# Memory + disp8: mod=01
# MOV rax, [rbp+8] → ModR/M = 01 000 101 = 0x45
modrm=$(modrm_byte 1 ${REG[rax]} ${REG[rbp]})
assert_eq "$(printf '%02x' "$modrm")" "45" "ModR/M: MOV rax,[rbp+disp8] = 0x45"

# ── SIB byte construction ───────────────────────────────────────────
# SIB: scale(2) | index(3) | base(3)
#   scale: 00=1, 01=2, 10=4, 11=8
# Used for addressing like [base + index*scale + disp]

sib_byte() {
    local scale=$1 index=$2 base=$3
    echo $(( (scale << 6) | (index << 3) | base ))
}

# [rax + rcx*4]: scale=10(4), index=rcx(1), base=rax(0)
sib=$(sib_byte 2 ${REG[rcx]} ${REG[rax]})
assert_eq "$(printf '%02x' "$sib")" "88" "SIB: [rax+rcx*4] = 0x88"

# [rdx + rsi*8]: scale=11(8), index=rsi(6), base=rdx(2)
sib=$(sib_byte 3 ${REG[rsi]} ${REG[rdx]})
assert_eq "$(printf '%02x' "$sib")" "f2" "SIB: [rdx+rsi*8] = 0xF2"

# [rsp + rbx*1]: scale=00(1), index=rbx(3), base=rsp(4)
sib=$(sib_byte 0 ${REG[rbx]} ${REG[rsp]})
assert_eq "$(printf '%02x' "$sib")" "1c" "SIB: [rsp+rbx*1] = 0x1C"

# ── Full instruction encoding ───────────────────────────────────────
# Encode complete x86_64 instructions as hex strings.

encode_add_reg_reg() {
    local dst=$1 src=$2
    local w=1 r=0 b=0

    # Check if src needs REX.R extension
    if reg_needs_rex_ext "$src"; then r=1; fi
    # Check if dst needs REX.B extension
    if reg_needs_rex_ext "$dst"; then b=1; fi

    local rex modrm
    rex=$(rex_byte $w $r 0 $b)
    modrm=$(modrm_byte 3 ${REG[$src]} ${REG[$dst]})

    printf '%02x01%02x' "$rex" "$modrm"
}

# ADD rax, rbx: REX.W(48) + 01 + ModR/M(D8)
result=$(encode_add_reg_reg rax rbx)
assert_eq "$result" "4801d8" "encode ADD rax,rbx"

# ADD r8, rax: REX.WB(49) + 01 + ModR/M(C0)
result=$(encode_add_reg_reg r8 rax)
assert_eq "$result" "4901c0" "encode ADD r8,rax (REX.B for r8)"

# ADD rax, r8: REX.WR(4c) + 01 + ModR/M(C0)
result=$(encode_add_reg_reg rax r8)
assert_eq "$result" "4c01c0" "encode ADD rax,r8 (REX.R for r8)"

# ── Immediate encoding (little-endian) ──────────────────────────────
# x86_64 uses little-endian byte order for immediates.

imm32_le() {
    local val=$1
    printf '%02x%02x%02x%02x' \
        $(( val & 0xFF )) \
        $(( (val >> 8) & 0xFF )) \
        $(( (val >> 16) & 0xFF )) \
        $(( (val >> 24) & 0xFF ))
}

assert_eq "$(imm32_le 1)" "01000000" "imm32 LE: 1"
assert_eq "$(imm32_le 256)" "00010000" "imm32 LE: 256"
assert_eq "$(imm32_le 0x12345678)" "78563412" "imm32 LE: 0x12345678"
assert_eq "$(imm32_le 0xFFFFFFFF)" "ffffffff" "imm32 LE: 0xFFFFFFFF"

imm16_le() {
    local val=$1
    printf '%02x%02x' \
        $(( val & 0xFF )) \
        $(( (val >> 8) & 0xFF ))
}

assert_eq "$(imm16_le 0x0100)" "0001" "imm16 LE: 0x0100"
assert_eq "$(imm16_le 0xBEEF)" "efbe" "imm16 LE: 0xBEEF"

# ── Instruction length calculation ───────────────────────────────────
# x86_64 instructions are variable-length (1-15 bytes).

inst_length() {
    local hex="$1"
    echo $(( ${#hex} / 2 ))
}

assert_eq "$(inst_length "90")" "1" "NOP = 1 byte"
assert_eq "$(inst_length "4801d8")" "3" "ADD rax,rbx = 3 bytes"
assert_eq "$(inst_length "48b80100000000000000")" "10" "MOV rax,imm64 = 10 bytes"

# ── MOV reg, imm32 encoding ─────────────────────────────────────────
# MOV r32, imm32: opcode (0xB8+r) + imm32
# Zero-extends to 64 bits, no REX.W needed.

encode_mov_reg_imm32() {
    local reg=$1 imm=$2
    local opcode=$(( 0xB8 + REG[$reg] ))
    printf '%02x%s' "$opcode" "$(imm32_le "$imm")"
}

result=$(encode_mov_reg_imm32 rax 42)
assert_eq "$result" "b82a000000" "MOV eax, 42"

result=$(encode_mov_reg_imm32 rcx 0xFF)
assert_eq "$result" "b9ff000000" "MOV ecx, 255"

result=$(encode_mov_reg_imm32 rdi 1)
assert_eq "$result" "bf01000000" "MOV edi, 1 (for syscall arg)"

echo "$PASS tests passed"
exit 0
