#!/bin/bash
# Vidya — Intermediate Representations in Shell (Bash)
#
# An IR sits between source language and machine code. The most common
# form is three-address code (TAC): "op dst src1 src2". Shell can model
# this as text lines, parse them with read, and transform them with
# sed/awk — showing that IR optimization is fundamentally text processing.
#
# Key concepts:
#   - Three-address code as text
#   - SSA (Static Single Assignment) numbering
#   - Constant folding as text substitution
#   - Basic block identification
#   - IR pretty-printing and validation

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

# ── Three-address code representation ────────────────────────────────
# Format: "OP DST SRC1 SRC2" — one operation per line.
# This is what compilers produce after parsing: a flat list of simple ops.

IR_PROGRAM="LOAD t0 42
LOAD t1 10
ADD t2 t0 t1
MUL t3 t2 t0
STORE result t3"

# Count instructions
line_count=$(echo "$IR_PROGRAM" | wc -l)
assert_eq "$line_count" "5" "program has 5 instructions"

# ── Parse and interpret three-address code ───────────────────────────
# Walk each instruction, maintain a register file (associative array).

interpret_tac() {
    local -A regs
    while IFS=' ' read -r op dst src1 src2; do
        case "$op" in
            LOAD)
                regs[$dst]=$src1
                ;;
            ADD)
                regs[$dst]=$(( regs[$src1] + regs[$src2] ))
                ;;
            SUB)
                regs[$dst]=$(( regs[$src1] - regs[$src2] ))
                ;;
            MUL)
                regs[$dst]=$(( regs[$src1] * regs[$src2] ))
                ;;
            STORE)
                regs[$dst]=${regs[$src1]}
                ;;
        esac
    done <<< "$1"
    echo "${regs[result]}"
}

result=$(interpret_tac "$IR_PROGRAM")
# t0=42, t1=10, t2=42+10=52, t3=52*42=2184, result=2184
assert_eq "$result" "2184" "interpret TAC program"

# ── Constant folding ────────────────────────────────────────────────
# If both operands of an instruction are constants, replace with LOAD.
# This is the simplest IR optimization — pure text substitution.

constant_fold() {
    local ir="$1"
    local -A constants  # track which temporaries hold known constants
    local output=""

    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "LOAD" ]]; then
            constants[$dst]=$src1
            output+="$op $dst $src1"$'\n'
        elif [[ "$op" == "STORE" ]]; then
            output+="$op $dst $src1"$'\n'
        elif [[ -n "${constants[$src1]+x}" && -n "${constants[$src2]+x}" ]]; then
            # Both operands are constants — fold!
            local v1=${constants[$src1]} v2=${constants[$src2]}
            local result
            case "$op" in
                ADD) result=$(( v1 + v2 )) ;;
                SUB) result=$(( v1 - v2 )) ;;
                MUL) result=$(( v1 * v2 )) ;;
            esac
            constants[$dst]=$result
            output+="LOAD $dst $result"$'\n'
        else
            output+="$op $dst $src1 $src2"$'\n'
        fi
    done <<< "$1"
    # Remove trailing newline
    echo -n "$output" | head -c -1
    echo
}

folded=$(constant_fold "$IR_PROGRAM")
# All values are constants, so everything should fold
expected_folded="LOAD t0 42
LOAD t1 10
LOAD t2 52
LOAD t3 2184
STORE result t3"
assert_eq "$folded" "$expected_folded" "constant folding"

# Verify folded program produces same result
result_folded=$(interpret_tac "$folded")
assert_eq "$result_folded" "2184" "folded program gives same result"

# ── SSA numbering ────────────────────────────────────────────────────
# Static Single Assignment: each variable is assigned exactly once.
# We rename variables so each definition gets a unique version number.

to_ssa() {
    local ir="$1"
    local -A version_count
    local -A current_version
    local output=""

    while IFS=' ' read -r op dst src1 src2; do
        # Rename source operands to their current versions
        local ssa_src1="$src1"
        local ssa_src2="$src2"
        if [[ -n "${current_version[$src1]+x}" ]]; then
            ssa_src1="${src1}.${current_version[$src1]}"
        fi
        if [[ -n "$src2" && -n "${current_version[$src2]+x}" ]]; then
            ssa_src2="${src2}.${current_version[$src2]}"
        fi

        # Create new version for destination
        local ver=${version_count[$dst]:-0}
        version_count[$dst]=$(( ver + 1 ))
        current_version[$dst]=$ver
        local ssa_dst="${dst}.${ver}"

        if [[ "$op" == "LOAD" || "$op" == "STORE" ]]; then
            output+="$op $ssa_dst $ssa_src1"$'\n'
        else
            output+="$op $ssa_dst $ssa_src1 $ssa_src2"$'\n'
        fi
    done <<< "$1"
    echo -n "$output" | head -c -1
    echo
}

ssa_input="LOAD x 1
LOAD y 2
ADD x x y
ADD x x y"

ssa_output=$(to_ssa "$ssa_input")
expected_ssa="LOAD x.0 1
LOAD y.0 2
ADD x.1 x.0 y.0
ADD x.2 x.1 y.0"
assert_eq "$ssa_output" "$expected_ssa" "SSA conversion"

# ── Basic block identification ───────────────────────────────────────
# A basic block is a maximal sequence of instructions with:
#   - No branches except possibly the last instruction
#   - No labels except possibly the first instruction
# Blocks are the unit of local optimization.

count_basic_blocks() {
    local ir="$1"
    local blocks=1  # start with one block

    while IFS=' ' read -r op dst src1 src2; do
        case "$op" in
            JMP|BR|BEQ|BNE)
                (( blocks++ ))
                ;;
            LABEL)
                # A label starts a new block (unless it's the first instruction)
                (( blocks++ ))
                ;;
        esac
    done <<< "$1"
    echo "$blocks"
}

block_ir="LOAD t0 1
ADD t1 t0 t0
BEQ t1 done
LABEL loop
MUL t2 t1 t0
SUB t1 t1 t0
BNE t1 loop
LABEL done
STORE result t2"

blocks=$(count_basic_blocks "$block_ir")
assert_eq "$blocks" "5" "5 basic blocks (entry + 2 branches + 2 labels)"

# ── IR instruction counting by type ─────────────────────────────────
count_by_opcode() {
    local ir="$1"
    local opcode="$2"
    local count=0
    while IFS=' ' read -r op rest; do
        [[ "$op" == "$opcode" ]] && (( count++ ))
    done <<< "$ir"
    echo "$count"
}

assert_eq "$(count_by_opcode "$IR_PROGRAM" "LOAD")" "2" "2 LOADs in program"
assert_eq "$(count_by_opcode "$IR_PROGRAM" "ADD")" "1" "1 ADD in program"
assert_eq "$(count_by_opcode "$IR_PROGRAM" "STORE")" "1" "1 STORE in program"

# ── Use-def chain: find where a temporary is defined and used ────────
find_def() {
    local ir="$1" var="$2"
    local line_num=0
    while IFS=' ' read -r op dst rest; do
        if [[ "$dst" == "$var" ]]; then
            echo "$line_num"
            return
        fi
        (( line_num++ ))
    done <<< "$ir"
    echo "-1"
}

count_uses() {
    local ir="$1" var="$2"
    local count=0
    while IFS=' ' read -r op dst src1 src2; do
        [[ "$src1" == "$var" ]] && (( count++ ))
        [[ "$src2" == "$var" ]] && (( count++ ))
    done <<< "$ir"
    echo "$count"
}

assert_eq "$(find_def "$IR_PROGRAM" "t2")" "2" "t2 defined at line 2"
assert_eq "$(count_uses "$IR_PROGRAM" "t0")" "2" "t0 used twice (ADD and MUL)"
assert_eq "$(count_uses "$IR_PROGRAM" "t3")" "1" "t3 used once (STORE)"
assert_eq "$(count_uses "$IR_PROGRAM" "result")" "0" "result never used as source"

# ── Copy propagation ────────────────────────────────────────────────
# If we have "COPY t2 t1", replace all uses of t2 with t1.

copy_propagate() {
    local ir="$1"
    local -A copies  # copies[dst] = src for COPY instructions
    local output=""

    # First pass: find all copies
    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "COPY" ]]; then
            copies[$dst]=$src1
        fi
    done <<< "$ir"

    # Second pass: substitute
    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "COPY" ]]; then
            continue  # remove the copy
        fi
        # Replace source operands
        [[ -n "${copies[$src1]+x}" ]] && src1=${copies[$src1]}
        [[ -n "$src2" && -n "${copies[$src2]+x}" ]] && src2=${copies[$src2]}

        if [[ -n "$src2" ]]; then
            output+="$op $dst $src1 $src2"$'\n'
        else
            output+="$op $dst $src1"$'\n'
        fi
    done <<< "$ir"
    echo -n "$output" | head -c -1
    echo
}

copy_ir="LOAD t0 5
COPY t1 t0
ADD t2 t1 t0
STORE result t2"

propagated=$(copy_propagate "$copy_ir")
expected_prop="LOAD t0 5
ADD t2 t0 t0
STORE result t2"
assert_eq "$propagated" "$expected_prop" "copy propagation removes COPY, substitutes uses"

echo "$PASS tests passed"
exit 0
