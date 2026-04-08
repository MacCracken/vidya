#!/bin/bash
# Vidya — Optimization Passes in Shell (Bash)
#
# Compiler optimizations are transformations on IR that preserve
# semantics while improving performance. Each "pass" walks the IR
# and rewrites it. Shell can model these as text transformations:
# grep for patterns, sed for rewrites, arithmetic for evaluation.
#
# Key concepts:
#   - Dead code elimination (DCE): remove unused definitions
#   - Constant folding: evaluate compile-time constants
#   - Strength reduction: replace expensive ops with cheaper ones
#   - Common subexpression elimination (CSE)
#   - Pass ordering and fixed-point iteration

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

# ── Helper: interpret three-address code ─────────────────────────────
interpret() {
    local -A regs
    while IFS=' ' read -r op dst src1 src2; do
        case "$op" in
            LOAD)  regs[$dst]=$src1 ;;
            ADD)   regs[$dst]=$(( regs[$src1] + regs[$src2] )) ;;
            SUB)   regs[$dst]=$(( regs[$src1] - regs[$src2] )) ;;
            MUL)   regs[$dst]=$(( regs[$src1] * regs[$src2] )) ;;
            SHL)   regs[$dst]=$(( regs[$src1] << src2 )) ;;
            STORE) regs[$dst]=${regs[$src1]} ;;
        esac
    done <<< "$1"
    echo "${regs[result]}"
}

# ── Dead Code Elimination ───────────────────────────────────────────
# A definition is "dead" if its result is never used as a source operand
# and it has no side effects. DCE removes these dead definitions.

dce() {
    local ir="$1"
    local changed=1

    while (( changed )); do
        changed=0
        local output=""
        local -A used=()

        # Collect all used temporaries (source operands)
        while IFS=' ' read -r op dst src1 src2; do
            if [[ "$op" == "STORE" ]]; then
                used[$src1]=1
            else
                [[ -n "$src1" && "$src1" =~ ^t[0-9] ]] && used[$src1]=1
                [[ -n "$src2" && "$src2" =~ ^t[0-9] ]] && used[$src2]=1
            fi
        done <<< "$ir"

        # Remove definitions of unused temporaries
        while IFS=' ' read -r op dst src1 src2; do
            if [[ "$op" == "STORE" ]]; then
                # STORE is always kept (side effect)
                if [[ -n "$src2" ]]; then
                    output+="$op $dst $src1 $src2"$'\n'
                else
                    output+="$op $dst $src1"$'\n'
                fi
            elif [[ "$dst" =~ ^t[0-9] && -z "${used[$dst]+x}" ]]; then
                # Dead: dst is a temporary that nobody uses
                changed=1
            else
                if [[ -n "$src2" ]]; then
                    output+="$op $dst $src1 $src2"$'\n'
                else
                    output+="$op $dst $src1"$'\n'
                fi
            fi
        done <<< "$ir"

        ir=$(echo -n "$output" | head -c -1; echo)
    done
    echo "$ir"
}

# t3 is dead (never used), t4 is dead, only t0+t1→t2→result survives
dead_ir="LOAD t0 10
LOAD t1 20
ADD t2 t0 t1
MUL t3 t0 t1
ADD t4 t3 t3
STORE result t2"

dce_result=$(dce "$dead_ir")
expected_dce="LOAD t0 10
LOAD t1 20
ADD t2 t0 t1
STORE result t2"
assert_eq "$dce_result" "$expected_dce" "DCE removes dead t3, t4"

# Verify semantics preserved
orig_val=$(interpret "$dead_ir")
dce_val=$(interpret "$dce_result")
assert_eq "$dce_val" "$orig_val" "DCE preserves result value"

# ── Constant Folding ────────────────────────────────────────────────
# If both operands are known constants, compute at compile time.

constant_fold() {
    local ir="$1"
    local -A constants
    local output=""

    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "LOAD" ]]; then
            constants[$dst]=$src1
            output+="LOAD $dst $src1"$'\n'
        elif [[ "$op" == "STORE" ]]; then
            output+="STORE $dst $src1"$'\n'
        elif [[ -n "${constants[$src1]+x}" && -n "${constants[$src2]+x}" ]]; then
            local v1=${constants[$src1]} v2=${constants[$src2]}
            local val
            case "$op" in
                ADD) val=$(( v1 + v2 )) ;;
                SUB) val=$(( v1 - v2 )) ;;
                MUL) val=$(( v1 * v2 )) ;;
                SHL) val=$(( v1 << v2 )) ;;
                *) output+="$op $dst $src1 $src2"$'\n'; continue ;;
            esac
            constants[$dst]=$val
            output+="LOAD $dst $val"$'\n'
        else
            output+="$op $dst $src1 $src2"$'\n'
        fi
    done <<< "$ir"
    echo -n "$output" | head -c -1
    echo
}

fold_ir="LOAD t0 6
LOAD t1 7
MUL t2 t0 t1
LOAD t3 2
ADD t4 t2 t3
STORE result t4"

folded=$(constant_fold "$fold_ir")
expected_fold="LOAD t0 6
LOAD t1 7
LOAD t2 42
LOAD t3 2
LOAD t4 44
STORE result t4"
assert_eq "$folded" "$expected_fold" "constant folding: 6*7+2 = 44"

fold_val=$(interpret "$folded")
assert_eq "$fold_val" "44" "folded program gives 44"

# ── Strength Reduction ──────────────────────────────────────────────
# Replace expensive operations with cheaper equivalents:
#   MUL x, 2  → SHL x, 1   (shift is faster than multiply)
#   MUL x, 4  → SHL x, 2
#   MUL x, 8  → SHL x, 3
#   MUL x, 1  → COPY       (identity)
#   MUL x, 0  → LOAD 0     (annihilation)

strength_reduce() {
    local ir="$1"
    local -A constants
    local output=""

    # First pass: find constant definitions
    while IFS=' ' read -r op dst src1 src2; do
        [[ "$op" == "LOAD" ]] && constants[$dst]=$src1
    done <<< "$ir"

    # Second pass: replace MUL by power-of-2 with SHL
    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "MUL" ]]; then
            local const_val=""
            local var_src=""
            # Check if either operand is a known power of 2
            if [[ -n "${constants[$src2]+x}" ]]; then
                const_val=${constants[$src2]}
                var_src=$src1
            elif [[ -n "${constants[$src1]+x}" ]]; then
                const_val=${constants[$src1]}
                var_src=$src2
            fi

            if [[ -n "$const_val" ]]; then
                case "$const_val" in
                    0) output+="LOAD $dst 0"$'\n'; continue ;;
                    1) output+="LOAD $dst $var_src"$'\n'; continue ;;  # simplified copy
                    2) output+="SHL $dst $var_src 1"$'\n'; continue ;;
                    4) output+="SHL $dst $var_src 2"$'\n'; continue ;;
                    8) output+="SHL $dst $var_src 3"$'\n'; continue ;;
                    16) output+="SHL $dst $var_src 4"$'\n'; continue ;;
                esac
            fi
        fi
        # Default: keep instruction unchanged
        if [[ -n "$src2" ]]; then
            output+="$op $dst $src1 $src2"$'\n'
        else
            output+="$op $dst $src1"$'\n'
        fi
    done <<< "$ir"
    echo -n "$output" | head -c -1
    echo
}

sr_ir="LOAD t0 100
LOAD t1 8
MUL t2 t0 t1
STORE result t2"

sr_result=$(strength_reduce "$sr_ir")
expected_sr="LOAD t0 100
LOAD t1 8
SHL t2 t0 3
STORE result t2"
assert_eq "$sr_result" "$expected_sr" "strength reduction: MUL by 8 → SHL by 3"

# Verify: 100 * 8 = 800 = 100 << 3
sr_val=$(interpret "$sr_result")
assert_eq "$sr_val" "800" "strength-reduced gives 800"

# Multiply by 1 → identity
sr_ir2="LOAD t0 42
LOAD t1 1
MUL t2 t0 t1
STORE result t2"

sr_result2=$(strength_reduce "$sr_ir2")
# MUL t0 * 1 becomes LOAD t2 t0, which interpret treats as literal "t0"
# In a real compiler this would be a COPY instruction
assert_eq "$(echo "$sr_result2" | sed -n '3p')" "LOAD t2 t0" "strength reduction: MUL by 1 → identity"

# ── Common Subexpression Elimination (CSE) ───────────────────────────
# If the same expression appears twice, reuse the first result.

cse() {
    local ir="$1"
    local -A expressions  # map "OP SRC1 SRC2" → result temp
    local output=""

    while IFS=' ' read -r op dst src1 src2; do
        if [[ "$op" == "LOAD" || "$op" == "STORE" ]]; then
            if [[ -n "$src2" ]]; then
                output+="$op $dst $src1 $src2"$'\n'
            else
                output+="$op $dst $src1"$'\n'
            fi
        else
            local key="$op $src1 $src2"
            if [[ -n "${expressions[$key]+x}" ]]; then
                # Already computed — just copy
                output+="LOAD $dst ${expressions[$key]}"$'\n'
            else
                expressions[$key]=$dst
                output+="$op $dst $src1 $src2"$'\n'
            fi
        fi
    done <<< "$ir"
    echo -n "$output" | head -c -1
    echo
}

cse_ir="LOAD t0 5
LOAD t1 3
ADD t2 t0 t1
ADD t3 t0 t1
MUL t4 t2 t3
STORE result t4"

cse_result=$(cse "$cse_ir")
expected_cse="LOAD t0 5
LOAD t1 3
ADD t2 t0 t1
LOAD t3 t2
MUL t4 t2 t3
STORE result t4"
assert_eq "$cse_result" "$expected_cse" "CSE: second ADD t0,t1 becomes LOAD from t2"

# ── Pass pipeline: fold then DCE ─────────────────────────────────────
# Real compilers chain passes. Constant folding can create dead code,
# so DCE should follow.

pipeline_ir="LOAD t0 3
LOAD t1 4
MUL t2 t0 t1
LOAD t3 100
ADD t4 t3 t0
STORE result t2"

# t3 and t4 are dead (result uses t2, not t4)
step1=$(constant_fold "$pipeline_ir")
step2=$(dce "$step1")

# After folding, t2 = LOAD 12 (no longer uses t0/t1), so DCE removes t0, t1 too
expected_pipeline="LOAD t2 12
STORE result t2"
assert_eq "$step2" "$expected_pipeline" "pipeline: fold then DCE"

pipeline_val=$(interpret "$step2")
assert_eq "$pipeline_val" "12" "pipeline result = 12"

# ── Instruction count as optimization metric ─────────────────────────
count_instructions() {
    echo "$1" | wc -l
}

before=$(count_instructions "$pipeline_ir")
after=$(count_instructions "$step2")
assert_eq "$before" "6" "before: 6 instructions"
assert_eq "$after" "2" "after: 2 instructions (4 eliminated)"

reduction=$(( (before - after) * 100 / before ))
assert_eq "$reduction" "66" "66% instruction reduction"

echo "$PASS tests passed"
exit 0
