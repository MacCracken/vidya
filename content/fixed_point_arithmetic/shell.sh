#!/usr/bin/env bash
# Vidya — Fixed-Point Arithmetic in Shell (Bash)
#
# Bash $((...)) is signed 64-bit on every platform Vidya runs on.
# `>>` is arithmetic on negatives (sign-preserving), and integer
# overflow wraps silently — same caveats as C. Bash has no float
# math, so the sine table is generated via awk at startup.
#
# Shell is the wrong tool for serious fixed-point work; this exists
# to show the patterns translate.

set -euo pipefail

readonly FX_SHIFT=16
readonly FX_ONE=$((1 << FX_SHIFT))
readonly FX_HALF=$((1 << (FX_SHIFT - 1)))

assert_eq() {
    local got="$1" want="$2" msg="$3"
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $msg: got '$got', want '$want'" >&2
        exit 1
    fi
}

fx_from_int() { echo $(( $1 << FX_SHIFT )); }

fx_to_int() {
    local v=$1
    if (( v < 0 )); then
        echo $(( -((-v) >> FX_SHIFT) ))
    else
        echo $(( v >> FX_SHIFT ))
    fi
}

fx_to_int_round() {
    local v=$1
    if (( v < 0 )); then
        echo $(( -((-v + FX_HALF) >> FX_SHIFT) ))
    else
        echo $(( (v + FX_HALF) >> FX_SHIFT ))
    fi
}

fx_mul() { echo $(( ($1 * $2) >> FX_SHIFT )); }
fx_mul_safe() { echo $(( ($1 >> 8) * ($2 >> 8) )); }

fx_div() {
    if (( $2 == 0 )); then echo 0; return; fi
    echo $(( ($1 << FX_SHIFT) / $2 ))
}

# ── Sine table — generated once via awk into a bash array ─────────────
declare -a SIN_TABLE
build_sin_table() {
    local line
    while IFS= read -r line; do
        SIN_TABLE+=("$line")
    done < <(awk -v one="$FX_ONE" 'BEGIN {
        pi = 3.14159265358979323846
        for (i = 0; i < 256; i++) {
            printf "%d\n", int(sin(i * pi / 2 / 256) * one)
        }
    }')
}

sin_lookup() {
    local angle=$(( $1 & 1023 ))
    if   (( angle < 256 )); then echo "${SIN_TABLE[$angle]}"
    elif (( angle < 512 )); then echo "${SIN_TABLE[$((511 - angle))]}"
    elif (( angle < 768 )); then echo $(( -${SIN_TABLE[$((angle - 512))]} ))
    else                         echo $(( -${SIN_TABLE[$((1023 - angle))]} ))
    fi
}

# ── Tests ─────────────────────────────────────────────────────────────

assert_eq "$(fx_from_int 1)"  "65536"  "1.0"
assert_eq "$(fx_from_int 10)" "655360" "10.0"
assert_eq "$(fx_from_int 0)"  "0"      "0.0"

three=$(fx_from_int 3)
two_half=163840   # 2.5
assert_eq "$(fx_mul "$three" "$two_half")" "491520" "3.0 * 2.5"
assert_eq "$(fx_mul "$FX_ONE" "$FX_ONE")"  "$FX_ONE" "1.0 * 1.0"
assert_eq "$(fx_mul "$FX_HALF" "$FX_HALF")" "16384"  "0.5 * 0.5"

big=$(fx_from_int 1000)
safe=$(fx_mul_safe "$big" "$big")
(( safe > 0 )) || { echo "FAIL: safe mul of 1000*1000" >&2; exit 1; }

assert_eq "$(fx_div "$(fx_from_int 10)" "$(fx_from_int 4)")" "163840" "10/4"
assert_eq "$(fx_div "$FX_ONE" 0)" "0" "div-by-zero"

neg_three=$(( -$(fx_from_int 3) ))
assert_eq "$(fx_to_int "$neg_three")" "-3" "fx_to_int(-3.0)"

neg_1_5=$(( -(FX_ONE + FX_HALF) ))
assert_eq "$(fx_to_int       "$neg_1_5")" "-1" "fx_to_int(-1.5)"
assert_eq "$(fx_to_int_round "$neg_1_5")" "-2" "round(-1.5)"

build_sin_table
assert_eq "$(sin_lookup 0)"   "0" "sin(0)"
peak=$(sin_lookup 256);  (( peak > 60000 ))    || { echo "FAIL: sin(π/2)"   >&2; exit 1; }
assert_eq "$(sin_lookup 512)" "0" "sin(π)"
trough=$(sin_lookup 768); (( trough < -60000 )) || { echo "FAIL: sin(3π/2)" >&2; exit 1; }

for i in $(seq 0 99); do
    assert_eq "$(fx_to_int "$(fx_from_int "$i")")" "$i" "roundtrip $i"
done

echo "All fixed_point_arithmetic examples passed."
