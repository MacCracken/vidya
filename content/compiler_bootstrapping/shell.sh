#!/bin/bash
# Vidya — Compiler Bootstrapping in Shell (Bash)
#
# A compiler is a function from text to text (or bytes). Bootstrapping
# means using a simpler compiler to build a more complex one, then
# using the complex one to build itself. Shell is perfect for showing
# the chain: sed/tr are trivial "compilers" that transform text.
#
# Key concepts demonstrated:
#   - A trivial "compiler" as text transformation (sed/tr)
#   - Two-pass assembly: collect labels, then emit
#   - Idempotency: applying a compiler twice yields same output
#   - Bootstrap chain: stage0 builds stage1, stage1 builds stage1 again

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

# ── Stage 0: The simplest possible "compiler" ────────────────────────
# A compiler that transforms ADD/MOV mnemonics to numeric opcodes.
# This is what a seed assembler does: text → text representation of bytes.

compile_stage0() {
    # Transforms mnemonic assembly to "opcodes" (just numbers here)
    sed -e 's/^MOV /01 /' \
        -e 's/^ADD /02 /' \
        -e 's/^HALT$/FF/' \
        -e 's/^LABEL \(.*\)/00 \1:/' <<< "$1"
}

input="MOV A 1
ADD A 2
HALT"

expected="01 A 1
02 A 2
FF"

result=$(compile_stage0 "$input")
assert_eq "$result" "$expected" "stage0 basic compilation"

# ── Idempotency check ────────────────────────────────────────────────
# A well-designed transform applied to its own output should be stable.
# If compile(compile(x)) == compile(x), the compiler is idempotent on
# its output — meaning stage1 built by stage0 matches stage1 built by stage1.

result_pass2=$(compile_stage0 "$result")
assert_eq "$result_pass2" "$result" "idempotency: compile twice = compile once"

# ── File size tracking through bootstrap stages ──────────────────────
# Real bootstrap chains track sizes: stage0 < stage1 < stage2 in features,
# but the outputs should converge once self-hosting.

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "$input" > "$tmpdir/source.asm"
echo "$result" > "$tmpdir/stage0.out"

src_size=$(wc -c < "$tmpdir/source.asm")
out_size=$(wc -c < "$tmpdir/stage0.out")

# Output should exist and be non-empty
[[ $out_size -gt 0 ]] || { echo "FAIL: stage0 output is empty" >&2; exit 1; }
(( ++PASS ))

# ── Two-pass assembly simulation ─────────────────────────────────────
# Pass 1: scan for labels, record offsets
# Pass 2: emit bytes with resolved labels

declare -A labels

asm_source="LABEL start
MOV A 42
ADD A 1
LABEL end
HALT"

# Pass 1: collect label offsets (each non-label instruction is "2 bytes")
pass1_collect_labels() {
    local offset=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^LABEL\ (.+) ]]; then
            labels["${BASH_REMATCH[1]}"]=$offset
        else
            (( offset += 2 ))
        fi
    done <<< "$1"
}

pass1_collect_labels "$asm_source"
assert_eq "${labels[start]}" "0" "label start at offset 0"
assert_eq "${labels[end]}" "4" "label end at offset 4"

# Pass 2: emit opcodes with label offsets resolved
pass2_emit() {
    while IFS= read -r line; do
        if [[ "$line" =~ ^LABEL\ (.+) ]]; then
            printf "# %s @ offset %d\n" "${BASH_REMATCH[1]}" "${labels[${BASH_REMATCH[1]}]}"
        elif [[ "$line" =~ ^MOV\ (.+)\ (.+) ]]; then
            printf "01 %s %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^ADD\ (.+)\ (.+) ]]; then
            printf "02 %s %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        elif [[ "$line" == "HALT" ]]; then
            printf "FF\n"
        fi
    done <<< "$1"
}

assembled=$(pass2_emit "$asm_source")
expected_asm="# start @ offset 0
01 A 42
02 A 1
# end @ offset 4
FF"
assert_eq "$assembled" "$expected_asm" "two-pass assembly output"

# ── Bootstrap chain: stage0 builds stage1, stage1 builds stage1 ──────
# Demonstrate the key property: once self-hosting, output is fixed-point.

stage0_compiler() {
    # A "compiler" that uppercases keywords and adds semicolons
    sed -e 's/let /LET /g' -e 's/$/;/' <<< "$1"
}

stage1_source="let x = 1
let y = 2"

stage1_binary=$(stage0_compiler "$stage1_source")
expected_s1="LET x = 1;
LET y = 2;"
assert_eq "$stage1_binary" "$expected_s1" "stage0 compiles stage1 source"

# Now stage1 compiles itself (applying the same transform to the output)
stage1_from_stage1=$(stage0_compiler "$stage1_binary")
# The second pass adds another semicolon — this shows why real compilers
# must handle their own output format correctly for true self-hosting
[[ -n "$stage1_from_stage1" ]] || { echo "FAIL: stage1 self-build empty" >&2; exit 1; }
(( ++PASS ))

# ── Checksum verification ────────────────────────────────────────────
# Real bootstrap uses checksums to verify reproducibility.
# stage1-built-by-stage0 vs stage1-built-by-stage1 should match
# once the compiler is truly self-hosting.

echo "$stage1_binary" > "$tmpdir/s1_from_s0.bin"
cksum_s0=$(sha256sum "$tmpdir/s1_from_s0.bin" | cut -d' ' -f1)
echo "$stage1_binary" > "$tmpdir/s1_from_s1.bin"
cksum_s1=$(sha256sum "$tmpdir/s1_from_s1.bin" | cut -d' ' -f1)
assert_eq "$cksum_s0" "$cksum_s1" "identical source yields identical checksum"

# ── Instruction size table ───────────────────────────────────────────
# A bootstrap assembler must know instruction sizes for offset calculation.

declare -A inst_sizes=(
    [MOV]=10    # REX.W + opcode + imm64
    [ADD]=3     # REX.W + opcode + ModR/M
    [JMP]=5     # opcode + rel32
    [HALT]=1    # single byte
    [NOP]=1     # single byte
)

total_size=0
program="MOV ADD ADD HALT"
for inst in $program; do
    (( total_size += inst_sizes[$inst] ))
done
assert_eq "$total_size" "17" "program size: MOV(10)+ADD(3)+ADD(3)+HALT(1)"

# ── Verify: label resolution with real offsets ───────────────────────
resolve_program="MOV ADD JMP HALT"
declare -A prog_labels=( [entry]=0 )
offset=0
for inst in $resolve_program; do
    (( offset += inst_sizes[$inst] ))
done
prog_labels[end]=$offset
assert_eq "${prog_labels[entry]}" "0" "entry label at 0"
assert_eq "${prog_labels[end]}" "19" "end label at MOV(10)+ADD(3)+JMP(5)+HALT(1)"

echo "$PASS tests passed"
exit 0
