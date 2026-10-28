#!/usr/bin/env bash
# Vidya — Algorithms in Shell (Bash)
#
# Shell isn't designed for algorithms, but understanding these patterns
# in bash builds intuition. Arrays are 0-indexed, arithmetic uses
# $((...)), and functions return via echo or global variables.
# For real algorithmic work, use a proper language.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── Binary search ──────────────────────────────────────────────────────
# Searches sorted array, prints index or -1
binary_search() {
    local -n arr=$1
    local target=$2
    local lo=0 hi=${#arr[@]} mid

    while (( lo < hi )); do
        mid=$(( lo + (hi - lo) / 2 ))
        if (( arr[mid] == target )); then
            echo "$mid"
            return
        elif (( arr[mid] < target )); then
            lo=$(( mid + 1 ))
        else
            hi=$mid
        fi
    done
    echo "-1"
}

data=(1 3 5 7 9 11 13 15 17 19)
assert_eq "$(binary_search data 7)" "3" "find 7"
assert_eq "$(binary_search data 1)" "0" "find 1"
assert_eq "$(binary_search data 19)" "9" "find 19"
assert_eq "$(binary_search data 4)" "-1" "miss 4"
assert_eq "$(binary_search data 20)" "-1" "miss 20"

# ── Insertion sort ─────────────────────────────────────────────────────
insertion_sort() {
    local -n arr=$1
    local i j key
    for (( i = 1; i < ${#arr[@]}; i++ )); do
        key=${arr[i]}
        j=$((i - 1))
        while (( j >= 0 && arr[j] > key )); do
            arr[j+1]=${arr[j]}
            (( j-- )) || true
        done
        arr[j+1]=$key
    done
}

sort_data=(5 2 8 1 9 3)
insertion_sort sort_data
assert_eq "${sort_data[*]}" "1 2 3 5 8 9" "insertion sort"

already=(1 2 3 4 5)
insertion_sort already
assert_eq "${already[*]}" "1 2 3 4 5" "already sorted"

# ── GCD (Euclidean algorithm) ──────────────────────────────────────────
gcd() {
    local a=$1 b=$2
    while (( b != 0 )); do
        local t=$b
        b=$(( a % b ))
        a=$t
    done
    echo "$a"
}

assert_eq "$(gcd 48 18)" "6" "gcd 48,18"
assert_eq "$(gcd 100 75)" "25" "gcd 100,75"
assert_eq "$(gcd 17 13)" "1" "gcd coprime"
assert_eq "$(gcd 0 5)" "5" "gcd 0,5"
assert_eq "$(gcd 7 0)" "7" "gcd 7,0"

# ── Fibonacci (iterative) ─────────────────────────────────────────────
fibonacci() {
    local n=$1
    if (( n <= 1 )); then
        echo "$n"
        return
    fi
    local a=0 b=1 next
    for (( i = 2; i <= n; i++ )); do
        next=$(( a + b ))
        a=$b
        b=$next
    done
    echo "$b"
}

assert_eq "$(fibonacci 0)" "0" "fib(0)"
assert_eq "$(fibonacci 1)" "1" "fib(1)"
assert_eq "$(fibonacci 10)" "55" "fib(10)"
assert_eq "$(fibonacci 20)" "6765" "fib(20)"

# ── Linear search (the shell-native approach) ─────────────────────────
linear_search() {
    local -n arr=$1
    local target=$2
    for i in "${!arr[@]}"; do
        if [[ "${arr[i]}" == "$target" ]]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

names=("alice" "bob" "carol" "dave")
assert_eq "$(linear_search names "carol")" "2" "find carol"
assert_eq "$(linear_search names "eve")" "-1" "miss eve"

# ── Min/max in single pass ─────────────────────────────────────────────
array_min_max() {
    local -n arr=$1
    local min=${arr[0]} max=${arr[0]}
    for val in "${arr[@]}"; do
        (( val < min )) && min=$val
        (( val > max )) && max=$val
    done
    echo "$min $max"
}

nums=(5 2 8 1 9 3 7)
assert_eq "$(array_min_max nums)" "1 9" "min/max"

# ── Unique elements (hash set via associative array) ───────────────────
unique_elements() {
    local -n arr=$1
    local -A seen
    local result=()
    for val in "${arr[@]}"; do
        if [[ -z "${seen[$val]+x}" ]]; then
            seen[$val]=1
            result+=("$val")
        fi
    done
    echo "${result[*]}"
}

dupes=(3 1 4 1 5 9 2 6 5 3 5)
assert_eq "$(unique_elements dupes)" "3 1 4 5 9 2 6" "unique preserve order"

# ── Two-sum with associative array ─────────────────────────────────────
two_sum() {
    local -n arr=$1
    local target=$2
    local -A seen
    for i in "${!arr[@]}"; do
        local complement=$(( target - arr[i] ))
        if [[ -n "${seen[$complement]+x}" ]]; then
            echo "${seen[$complement]} $i"
            return
        fi
        seen[${arr[i]}]=$i
    done
    echo "-1 -1"
}

ts_data=(2 7 11 15)
assert_eq "$(two_sum ts_data 9)" "0 1" "two sum"
ts_data2=(3 2 4)
assert_eq "$(two_sum ts_data2 6)" "1 2" "two sum mid"
ts_data3=(1 2 3)
assert_eq "$(two_sum ts_data3 7)" "-1 -1" "two sum none"

echo "All algorithms examples passed."
