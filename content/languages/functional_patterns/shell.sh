#!/usr/bin/env bash
# Vidya — Functional Patterns — Bash port.
#
# Pure functions and memoization, compose and pipe, partial application,
# closures, what a function sees of a variable, a persistent cons list
# that shares structure instead of copying, folds as loops, and stack depth.
#
# Bash functions are not values and not closures: a function is a NAME,
# and it reads variables when it RUNS, never when it was defined. So a
# "function value" here is a command prefix (a name plus bound arguments)
# called unquoted, and a closure is a function GENERATED with eval around
# a value baked into its body. Results come back in _RET, not on stdout.

set -euo pipefail

# Helpers return via _RET, never via stdout: $(...) runs in a subshell,
# which would throw away the counters, tables and arena writes these
# functions exist to show (cyrius field note
# bash_subshell_clobbers_stateful_helpers).
_RET=0

# A function value is a string of words, `name arg...`, expanded UNQUOTED
# so it splits into the name and its bound arguments: `$f "$x"`. That is
# safe here because every word is a function name or an integer.

# --- 1. Purity ---
# A pure function's result depends only on its arguments, and calling it
# changes nothing. Bash cannot check that: any function can assign any
# global, and `local` is dynamically scoped, so a function even sees (and
# can assign) its CALLER's locals. Purity is a discipline.
pure_add() { _RET=$(( $1 + $2 )); }

counter=0 # hidden state impure_next reads and bumps
impure_next() {
    counter=$(( counter + 1 ))
    _RET=$counter
}

# counted_add is pure_add plus a call counter, so a check can see whether
# the underlying function ran (the counter is the test's probe; the value
# is still pure_add's).
add_calls=0
counted_add() {
    add_calls=$(( add_calls + 1 ))
    pure_add "$1" "$2"
}

# memo_call TABLE F A B: cache F's result by argument, in the associative
# array named TABLE. Sound only for a pure F. The key is BOTH arguments;
# a key of A alone would hand (2, 4) the result cached for (2, 3).
memo_call() {
    local -n table=$1
    local f=$2 key="$3,$4"
    if [[ -v table[$key] ]]; then
        _RET=${table[$key]}
        return 0
    fi
    $f "$3" "$4"
    table[$key]=$_RET
}

# memoize2 F NAME: define a function NAME that owns a table of its own.
# printf %q quotes each baked-in word, so a value can never become code.
memoize2() {
    local f=$1 name=$2 body
    declare -gA "_memo_${name}=()"
    printf -v body 'memo_call %q %q "$@"' "_memo_${name}" "$f"
    eval "${name}() { ${body}; }"
}

# --- 2. Higher-order functions and composition ---
# compose F G X: _RET = F(G(X))   (right to left, as in maths: f . g)
# pipe F G X:    _RET = G(F(X))   (left to right, reading order)
# The composed function itself is the prefix "compose F G": call it with
# X appended. F and G may themselves be prefixes (they expand unquoted).
add_three() { _RET=$(( $1 + 3 )); }
times_two() { _RET=$(( $1 * 2 )); }

compose() {
    local f=$1 g=$2
    $g "$3"
    $f "$_RET"
}

pipe() {
    local f=$1 g=$2
    $f "$3"
    $g "$_RET"
}

# --- 3. Closures and partial application ---
# make_adder NAME N: generate NAME() { _RET=$(( $1 + N )); } with N's
# VALUE written into the body (early binding: a later change to the
# caller's variable cannot reach it).
make_adder() {
    local name=$1 body
    printf -v body '_RET=$(( $1 + %q ))' "$2"
    eval "${name}() { ${body}; }"
}

# make_counter NAME: generate NAME() over a state variable _count_NAME.
# Each counter gets its own variable, so two never share a count, but it
# is "private" by naming convention only: any code can assign it.
make_counter() {
    local name=$1 body
    declare -g "_count_${name}=0"
    printf -v body '_count_%s=$(( _count_%s + 1 )); _RET=$_count_%s' "$name" "$name" "$name"
    eval "${name}() { ${body}; }"
}

add3() { _RET=$(( $1 + $2 + $3 )); }

# partial F A B: partial application is appending arguments to a command
# prefix, so the result is the prefix "F A B" (in _RET).
partial() { _RET="$*"; }

# --- 4. The capture gotcha: see test_capture ---
# A function that reads a global reads it when CALLED (late binding), so
# functions defined in a loop that read the loop variable all see what
# the loop left behind. A function generated with the value baked in
# (printf %q, then eval) keeps the value it was built with.

# --- 5. Persistent (immutable) list with structural sharing ---
# The arena is two parallel arrays: heads[k] and tails[k] describe cell
# k, and a list is the index of its first cell. NIL (-1) is the empty
# list, and node identity is index equality. cons only appends, so
# prepending is O(1) and the old list is still whole and unchanged.
# `declare -r` cannot protect one cell: it would freeze the whole array,
# and cons could no longer append, so persistence is a rule the code keeps.
NIL=-1
declare -a heads=()
declare -a tails=()

cons() {
    heads+=("$1")
    tails+=("$2")
    _RET=$(( ${#heads[@]} - 1 ))
}

head() { _RET=${heads[$1]}; }
tail() { _RET=${tails[$1]}; }

list_of() {
    local xs=$NIL k
    for (( k = $#; k >= 1; k-- )); do
        cons "${!k}" "$xs"
        xs=$_RET
    done
    _RET=$xs
}

nth() {
    local p=$1 k
    for (( k = 0; k < $2; k++ )); do p=${tails[p]}; done
    _RET=${heads[p]}
}

# list_str XS: _RET = the values as "[1, 2, 3]", for structural checks
# (same values in the same order, not the same cells).
list_str() {
    local p=$1 out=""
    while (( p != NIL )); do
        out+="${out:+, }${heads[p]}"
        p=${tails[p]}
    done
    _RET="[$out]"
}

# Functional update: a new list with element I replaced. It copies the I
# cells in front of I plus the replaced cell (I + 1 allocations) and
# shares everything after it. The original list is not touched.
update_at() {
    local xs=$1 i=$2 v=$3
    if (( xs == NIL )); then
        _RET=$NIL
        return 0
    fi
    if (( i == 0 )); then
        cons "$v" "${tails[xs]}"
        return 0
    fi
    update_at "${tails[xs]}" $(( i - 1 )) "$v"
    cons "${heads[xs]}" "$_RET"
}

# --- 6. Fold as the recursion scheme ---
# foldr F Z XS = F(a, F(b, F(c, Z)))   (recursion: a bash frame per cell)
# foldl F Z XS = F(F(F(Z, a), b), c)   (a loop)
# F is a function value, called as `$f x acc` (foldr) or `$f acc x` (foldl).
foldr() {
    local f=$1 z=$2 xs=$3
    if (( xs == NIL )); then
        _RET=$z
        return 0
    fi
    foldr "$f" "$z" "${tails[xs]}"
    $f "${heads[xs]}" "$_RET"
}

foldl() {
    local f=$1 acc=$2 p=$3
    while (( p != NIL )); do
        $f "$acc" "${heads[p]}"
        acc=$_RET
        p=${tails[p]}
    done
    _RET=$acc
}

count_step() { _RET=$(( $1 + 1 )); }
add() { _RET=$(( $1 + $2 )); }
sub() { _RET=$(( $1 - $2 )); }
rev_step() { cons "$2" "$1"; } # acc x -> cons x acc
map_step() { # map_step G x acc -> cons (G x) acc
    local g=$1 x=$2 acc=$3
    $g "$x"
    cons "$_RET" "$acc"
}
times_ten() { _RET=$(( $1 * 10 )); }

list_length() { foldl count_step 0 "$1"; }
list_sum() { foldl add 0 "$1"; }
list_reverse() { foldl rev_step "$NIL" "$1"; }
list_map() { foldr "map_step $1" "$NIL" "$2"; } # "map_step G" is a partial application

# --- 7. Tail recursion and stack depth ---
# Bash has no tail calls: every function call, in tail position or not,
# nests inside the interpreter's own C stack. Measured here, bash 5.3
# died with SIGSEGV at about 5,400 levels of a one-line recursive
# function (8 MiB stack), so 100,000 would be about 18 times too deep. Setting
# FUNCNEST=N turns that crash into a clean error ("maximum function
# nesting level exceeded") at depth N. Loops are the only safe recursion.
# Bash arithmetic is 64-bit, so 5000050000 fits.
sum_to_loop() {
    local n=$1 acc=0 i
    for (( i = 1; i <= n; i++ )); do acc=$(( acc + i )); done
    _RET=$acc
}

# === Test harness ===
pass_count=0
fail_count=0
assert_eq() {
    # assert_eq actual expected message
    if [[ "$1" == "$2" ]]; then
        pass_count=$(( pass_count + 1 ))
    else
        fail_count=$(( fail_count + 1 ))
        echo "  FAIL: $3 (got $1, want $2)" >&2
    fi
}

test_purity() {
    local r1 r2 n1 n2
    pure_add 2 3; r1=$_RET
    pure_add 2 3; r2=$_RET
    assert_eq "$r1" "$r2" "pure_add: same arguments, same result"
    assert_eq "$r1" 5 "pure_add 2 3 = 5"

    counter=0
    impure_next; n1=$_RET
    impure_next; n2=$_RET
    assert_eq "$(( n1 != n2 ))" 1 "impure_next: same call, different results (1, then 2)"
    assert_eq "$counter" 2 "impure_next left a trace: hidden state bumped twice"
}

test_memoize() {
    local m1 m2
    add_calls=0
    memoize2 counted_add madd
    madd 2 3; m1=$_RET
    madd 2 3; m2=$_RET
    assert_eq "$m1" 5 "memo: first call computes 2 + 3 = 5"
    assert_eq "$m2" 5 "memo: second call returns the cached 5"
    assert_eq "$add_calls" 1 "memo: second call is a cache hit (1 call, not 2)"
    madd 2 4
    assert_eq "$_RET" 6 "memo: (2, 4) is a miss, the key is both arguments"
    assert_eq "$add_calls" 2 "memo: the miss ran the underlying function once more"
}

test_composition() {
    local c="compose add_three times_two"
    local p="pipe add_three times_two"
    local cgf="compose times_two add_three"
    local cv pv x want ok_c=1 ok_p=1
    $c 1; cv=$_RET
    $p 1; pv=$_RET
    assert_eq "$cv" 5 "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5"
    assert_eq "$pv" 8 "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8"
    assert_eq "$(( cv != pv ))" 1 "order matters: compose != pipe at x = 1"

    # The laws, over a range of x: compose applies g first, and pipe is
    # compose with its arguments swapped.
    for (( x = -2; x <= 2; x++ )); do
        times_two "$x"; add_three "$_RET"; want=$_RET
        $c "$x"
        if (( _RET != want )); then ok_c=0; fi
        $cgf "$x"; want=$_RET
        $p "$x"
        if (( _RET != want )); then ok_p=0; fi
    done
    assert_eq "$ok_c" 1 "compose(f, g)(x) == f(g(x)) for x in -2..2"
    assert_eq "$ok_p" 1 "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2"
}

test_closures() {
    local add_1_2
    make_adder add5 5
    make_adder add10 10
    add5 1
    assert_eq "$_RET" 6 "make_adder 5: add5 1 = 6"
    add10 1
    assert_eq "$_RET" 11 "make_adder 10: add10 1 = 11, each adder keeps its own n"

    make_counter c1
    make_counter c2
    c1
    c1
    c1
    assert_eq "$_RET" 3 "counter 1 counted 1, 2, 3"
    c2
    assert_eq "$_RET" 1 "counter 2 starts at 1: its state is its own"
    c1
    assert_eq "$_RET" 4 "counter 1 carries on at 4, untouched by counter 2"

    partial add3 1 2; add_1_2=$_RET
    $add_1_2 3
    assert_eq "$_RET" 6 "partial add3 1 2, then 3: 1 + 2 + 3 = 6"
}

# Globals the generated functions read: j, w and base.
j=0
w=0
base=0

calls3() { # calls3 PREFIX: _RET = "r0 r1 r2" from PREFIX_0, PREFIX_1, PREFIX_2
    local k out=""
    for k in 0 1 2; do
        "${1}_$k"
        out+="${out:+ }$_RET"
    done
    _RET=$out
}

test_capture() {
    local body
    # Early binding: each function has the value j had, baked in.
    # Late binding: each function reads the global j when called.
    for (( j = 0; j < 3; j++ )); do
        printf -v body '_RET=%q' "$j"
        eval "early_${j}() { ${body}; }"
        eval "late_${j}() { _RET=\$j; }"
    done
    calls3 early
    assert_eq "$_RET" "0 1 2" "baked-in values: early_0..2 return 0 1 2"
    calls3 late
    assert_eq "$_RET" "3 3 3" "global j read at call time: the C-style loop left it at 3"

    # A `for w in LIST` loop stops ON its last item, so late binding
    # gives Python's answer here, not JavaScript's.
    for w in 0 1 2; do
        eval "word_${w}() { _RET=\$w; }"
    done
    calls3 word
    assert_eq "$_RET" "2 2 2" "global w read at call time: the for-in loop left it at 2"

    # After the fact: base = 1, build both kinds, then base = 99.
    base=1
    get_base() { _RET=$base; }
    printf -v body '_RET=%q' "$base"
    eval "get_base_early() { ${body}; }"
    base=99
    get_base
    assert_eq "$_RET" 99 "late binding: get_base sees the later base=99"
    get_base_early
    assert_eq "$_RET" 1 "early binding: get_base_early kept the 1 it was built with"
}

test_persistent_list() {
    local xs ys zs vs ws before t1 t2
    list_of 1 2 3; xs=$_RET
    cons 0 "$xs"; ys=$_RET
    tail "$ys"
    assert_eq "$_RET" "$xs" "cons shares: tail(ys) IS xs, the same cell index"
    list_str "$ys"
    assert_eq "$_RET" "[0, 1, 2, 3]" "ys reads [0, 1, 2, 3]"
    list_str "$xs"
    assert_eq "$_RET" "[1, 2, 3]" "xs still reads [1, 2, 3] after the cons"

    before=${#heads[@]}
    update_at "$xs" 1 20; zs=$_RET
    assert_eq "$(( ${#heads[@]} - before ))" 2 "update at index 1 allocates i + 1 = 2 cells, not 3"
    list_str "$zs"
    assert_eq "$_RET" "[1, 20, 3]" "zs reads [1, 20, 3]"
    tail "$zs"; tail "$_RET"; t1=$_RET
    tail "$xs"; tail "$_RET"; t2=$_RET
    assert_eq "$t1" "$t2" "the suffix after the updated cell is shared"
    tail "$zs"; t1=$_RET
    tail "$xs"; t2=$_RET
    assert_eq "$(( t1 != t2 ))" 1 "the updated cell is new, not xs's"
    list_str "$xs"
    assert_eq "$_RET" "[1, 2, 3]" "xs still reads [1, 2, 3] after the update"

    # The gotcha: write through a cell two versions share and both change.
    list_of 1 2 3; vs=$_RET
    update_at "$vs" 0 7; ws=$_RET # ws = [7, 2, 3], shares vs's [2, 3]
    tail "$vs"
    heads[_RET]=99 # in-place write to the shared cell
    nth "$ws" 1
    assert_eq "$_RET" 99 "a write through a shared cell changes the other version too"
}

test_folds() {
    local xs
    list_of 1 2 3; xs=$_RET
    list_length "$xs"
    assert_eq "$_RET" 3 "length via foldl = 3"
    list_length "$NIL"
    assert_eq "$_RET" 0 "length of the empty list = 0"
    list_sum "$xs"
    assert_eq "$_RET" 6 "sum via foldl = 1 + 2 + 3 = 6"
    list_reverse "$xs"; list_str "$_RET"
    assert_eq "$_RET" "[3, 2, 1]" "reverse via foldl = [3, 2, 1]"
    list_map times_ten "$xs"; list_str "$_RET"
    assert_eq "$_RET" "[10, 20, 30]" "map via foldr keeps order: [10, 20, 30]"
    list_str "$xs"
    assert_eq "$_RET" "[1, 2, 3]" "the folds left xs as [1, 2, 3]"

    # Subtraction is not associative, so the fold's direction shows.
    foldl sub 0 "$xs"
    assert_eq "$_RET" -6 "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6"
    foldr sub 0 "$xs"
    assert_eq "$_RET" 2 "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2"
}

test_tail_calls() {
    sum_to_loop 100000
    assert_eq "$_RET" 5000050000 "accumulator loop: sum 1..100000 = 5000050000"
}

test_purity
test_memoize
test_composition
test_closures
test_capture
test_persistent_list
test_folds
test_tail_calls

echo "=== functional_patterns ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
echo "All functional pattern examples passed."
exit 0
