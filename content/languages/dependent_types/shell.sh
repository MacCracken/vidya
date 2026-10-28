#!/usr/bin/env bash
# Vidya — Dependent Types — Bash port.
#
# A dependent type depends on a VALUE: Vec n a is a vector whose length n
# is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
# v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
# values computed at run time; none of vidya's 11 languages can.
#
# Bash has no types at all, so this is runtime invariants only. A "type"
# here is a naming convention plus a validating constructor: vec_make
# proves a length once and records it in NAME_len, percent proves a range
# once, and the functions after them rely on that without checking again.
# Only the convention stops a direct write; `readonly` stops a rewrite.

set -euo pipefail

# Helpers return via the `_RET` global, never via stdout, because `$(...)`
# runs in a subshell and would lose the validation counter (cyrius
# field-note "subshell_clobbers_stateful_helpers").
_RET=0

# Every input is a string, so parsing is the first refinement, and in bash
# a safety one: arithmetic evaluates a string as an expression, so an
# unparsed `(( $2 >= 0 ))` looks up a variable named abc for "abc" and
# runs the command inside 'a[$(cmd)]'. (A leading zero is refused too:
# bash reads 010 as octal 8, and 08 is an error, "value too great for
# base".)
is_int() { [[ $1 =~ ^-?(0|[1-9][0-9]*)$ ]]; }

# --- 1. Length-indexed vector ---
# vec_make NAME N ITEM... builds the array NAME only when exactly N items
# are given, and records N in NAME_len: the vector's "type". Status 1
# means refused, and nothing is built.
vec_make() {
    local name=$1 n=$2
    shift 2
    is_int "$n" && (( n >= 0 && $# == n )) || return 1
    declare -ga "$name"
    local -n _vm_ref=$name
    _vm_ref=("$@")
    printf -v "${name}_len" '%d' "$n"
}

VEC2_LEN=2
VEC3_LEN=3

# The length, read from the recorded "type", not by counting the items.
vlen() {
    local lv="${1}_len"
    _RET=${!lv}
}

# head refuses the empty "type" when it is called: there is no sooner.
head() {
    vlen "$1"
    (( _RET > 0 )) || return 1
    local -n _hd_ref=$1
    _RET=${_hd_ref[0]}
}

# append's result goes through the checked constructor with length
# len(a) + len(b), so its "type" is proved like any other vector's.
append() {
    local la lb
    vlen "$1"; la=$_RET
    vlen "$2"; lb=$_RET
    local -n _ap_a=$1 _ap_b=$2
    vec_make "$3" $(( la + lb )) "${_ap_a[@]}" "${_ap_b[@]}"
}

# A plain array has no recorded length, so head counts it every time.
vec_head() {
    local -n _vh_ref=$1
    (( ${#_vh_ref[@]} > 0 )) || return 1
    _RET=${_vh_ref[0]}
}

# --- 2. Fin n: an index proven in range ---
# fin3 accepts only 0..VEC3_LEN-1, the same constant Vec3's length came
# from, so index_at reads with no check of its own. There are no types to
# tell a fin2 from a fin3: each is a number, and only the convention says
# which vector it was proved for. The check matters here:
# bash's own index does not refuse -1 (it reads from the end), and past
# the end is a fatal "unbound variable" under set -u.
fin2() { is_int "$1" && (( $1 >= 0 && $1 < VEC2_LEN )) || return 1; _RET=$1; }
fin3() { is_int "$1" && (( $1 >= 0 && $1 < VEC3_LEN )) || return 1; _RET=$1; }

index_at() {
    local -n _ix_ref=$1
    _RET=${_ix_ref[$2]}
}

# --- 3. Refinement at the boundary (parse, don't validate) ---
# percent NAME X is the one place the range is checked: it sets NAME only
# for an integer 0..100. discount takes the value and trusts it.
# PERCENT_CHECKS counts validations, so a check can see that.
PERCENT_CHECKS=0

percent() {
    PERCENT_CHECKS=$(( PERCENT_CHECKS + 1 ))
    is_int "$2" && (( $2 >= 0 && $2 <= 100 )) || return 1
    printf -v "$1" '%d' "$2"
}

discount() { _RET=$(( $1 - $1 * $2 / 100 )); }

# --- 4. Σ type (dependent pair) ---
# Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
# the first. In bash a vector from vec_make already is such a pair (NAME,
# NAME_len). sized NAME N DATA records N with an existing array only when
# DATA really holds N items, and sized_sum takes its loop bound from N
# alone.
sized() {
    local -n _sz_data=$3
    is_int "$2" && (( ${#_sz_data[@]} == $2 )) || return 1
    printf -v "${1}_n" '%d' "$2"
    printf -v "${1}_data" '%s' "$3"
}

sized_sum() {
    local nv="${1}_n" dv="${1}_data"
    local n=${!nv}
    local -n _ss_data=${!dv}
    local total=0 i
    for (( i = 0; i < n; i++ )); do
        total=$(( total + _ss_data[i] ))
    done
    _RET=$total
}

# --- 5. The escape hatch ---
# A Percent is a variable holding a number, and any line can write one:
# `forged=150` never meets percent(), and a checked one can be rewritten
# with a plain assignment. `readonly` stops the rewrite (bash refuses it:
# "p_safe: readonly variable"), but nothing stops the forgery. What keeps
# it honest is review of every assignment the convention covers.

# === Tests ===

assert_eq() {
    if [[ "$1" != "$2" ]]; then
        echo "ASSERT FAIL: $3 (got $1, want $2)" >&2
        exit 1
    fi
}

assert_ok() {
    local msg=$1
    shift
    if ! "$@"; then
        echo "ASSERT FAIL: $msg" >&2
        exit 1
    fi
}

assert_refused() {
    local msg=$1
    shift
    if "$@"; then
        echo "ASSERT FAIL: $msg (it was accepted)" >&2
        exit 1
    fi
}

test_length_indexed() {
    assert_ok "Vec0 is built" vec_make empty 0
    assert_ok "Vec2 is built" vec_make a "$VEC2_LEN" 1 2
    assert_ok "Vec3 is built" vec_make b "$VEC3_LEN" 3 4 5
    assert_refused "a Vec2 of three items is refused" vec_make bad "$VEC2_LEN" 1 2 3
    vlen empty; assert_eq "$_RET" 0 "Vec0's type says length 0"
    vlen a; assert_eq "$_RET" 2 "Vec2's type says length 2"
    vlen b; assert_eq "$_RET" 3 "Vec3's type says length 3"
    head a; assert_eq "$_RET" 1 "head([1, 2]) = 1"
    head b; assert_eq "$_RET" 3 "head([3, 4, 5]) = 3"
    assert_refused "head of the empty vector is refused" head empty

    assert_ok "append(Vec2, Vec3) is built" append a b c
    vlen c; assert_eq "$_RET" 5 "append(Vec2, Vec3) has length 2 + 3 = 5"
    assert_eq "${c[*]}" "1 2 3 4 5" "append(Vec2, Vec3) reads [1, 2, 3, 4, 5]"

    # The plain array: the empty case is refused when it happens.
    local -a none=() seven=(7)
    assert_refused "run-time head of an empty array is refused" vec_head none
    vec_head seven; assert_eq "$_RET" 7 "run-time head of [7] is allowed and = 7"
}

test_fin() {
    vec_make a "$VEC2_LEN" 1 2
    vec_make b "$VEC3_LEN" 3 4 5
    assert_refused "fin3(-1) is refused" fin3 -1
    assert_refused "fin3(3) is refused: 3 is not < 3" fin3 3
    index_at b -1; assert_eq "$_RET" 5 "a plain -1 is no error in bash: it reads from the end"

    local accepted=0 i
    for (( i = -1; i <= 3; i++ )); do
        if fin3 "$i"; then
            accepted=$(( accepted + 1 ))
            index_at b "$_RET"; assert_eq "$_RET" $(( 3 + i )) "index3 with fin3($i) reads 3 + $i"
        fi
    done
    assert_eq "$accepted" 3 "fin3 accepts exactly 0, 1, 2 out of -1..3"

    assert_refused "fin2(2) is refused: 2 is not < 2" fin2 2
    assert_ok "fin2(1) is accepted" fin2 1
    index_at a "$_RET"; assert_eq "$_RET" 2 "index2([1, 2], fin2(1)) = 2"
}

test_refinement() {
    PERCENT_CHECKS=0
    assert_refused "percent(-1) is refused" percent p_bad -1
    assert_refused "percent(101) is refused" percent p_bad 101
    assert_ok "percent(0) is accepted" percent p0 0
    assert_ok "percent(100) is accepted" percent p100 100
    assert_ok "percent(25) is accepted" percent p25 25
    assert_eq "$PERCENT_CHECKS" 5 "5 constructions, 5 validations"

    discount 200 "$p25"; assert_eq "$_RET" 150 "discount(200, 25%) = 150"
    discount 200 "$p0"; assert_eq "$_RET" 200 "discount(200, 0%) = 200"
    discount 200 "$p100"; assert_eq "$_RET" 0 "discount(200, 100%) = 0"
    assert_eq "$PERCENT_CHECKS" 5 "discount never re-validated: still 5 checks after 3 calls"
    assert_refused "percent(abc) is refused: not an integer" percent p_bad abc
}

test_sigma() {
    local -a two=(1 2) three=(1 2 3)
    assert_refused "(3, [1, 2]) is refused: the length is 2" sized s 3 two
    assert_refused "(2, [1, 2, 3]) is refused: the length is 3" sized s 2 three
    assert_ok "(3, [1, 2, 3]) is built" sized s 3 three
    assert_eq "$s_n" 3 "the pair's n is 3"
    sized_sum s; assert_eq "$_RET" 6 "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6"
}

test_escape_hatch() {
    assert_refused "the API refuses 150" percent p_bad 150
    local forged=150                     # never met percent()
    discount 200 "$forged"; assert_eq "$_RET" -100 "and discount trusts it: 200 - 300 = -100"

    assert_ok "percent(30) is accepted" percent p30 30
    p30=250                              # rewrites a validated Percent in place
    discount 100 "$p30"; assert_eq "$_RET" -150 "a plain assignment into a checked Percent breaks it too: -150"

    # readonly closes that door. The rewrite is tried in a subshell, because
    # under set -e the failed assignment to a readonly variable ends the
    # shell that tries it.
    assert_ok "percent(30) is accepted" percent p_safe 30
    readonly p_safe
    if ( p_safe=250 ) 2>/dev/null; then
        echo "ASSERT FAIL: readonly must refuse the rewrite of p_safe" >&2
        exit 1
    fi
}

main() {
    test_length_indexed
    test_fin
    test_refinement
    test_sigma
    test_escape_hatch
    echo "All dependent type examples passed."
}

main
exit 0
