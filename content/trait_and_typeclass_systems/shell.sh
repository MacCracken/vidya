#!/bin/bash
# Vidya — Trait and Typeclass Systems in Shell (Bash)
#
# Shell has no type system — everything is a string. There are no
# interfaces, traits, or typeclasses. We simulate these patterns using:
#   - Naming conventions for "method" dispatch (shape_area_circle)
#   - Variable indirection for dynamic dispatch
#   - Associative arrays as vtables
#   - Convention-based "interface" compliance

set -euo pipefail

PASS=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
    PASS=$((PASS + 1))
}

# ── Static dispatch via naming convention ─────────────────────────
# "Trait": Shape with methods area and perimeter
# "Types": circle, rect, triangle
# Convention: {trait}_{method}_{type} args...

shape_area_circle() {
    local radius="$1"
    # area = pi * r^2 (integer approximation: pi ~= 314/100)
    echo $(( (314 * radius * radius) / 100 ))
}

shape_area_rect() {
    local width="$1" height="$2"
    echo $(( width * height ))
}

shape_area_triangle() {
    local base="$1" height="$2"
    echo $(( (base * height) / 2 ))
}

shape_perimeter_circle() {
    local radius="$1"
    # perimeter = 2 * pi * r
    echo $(( (628 * radius) / 100 ))
}

shape_perimeter_rect() {
    local width="$1" height="$2"
    echo $(( 2 * (width + height) ))
}

assert_eq "$(shape_area_circle 10)" "314" "circle area"
assert_eq "$(shape_area_rect 3 4)" "12" "rect area"
assert_eq "$(shape_area_triangle 6 4)" "12" "triangle area"
assert_eq "$(shape_perimeter_circle 10)" "62" "circle perimeter"
assert_eq "$(shape_perimeter_rect 3 4)" "14" "rect perimeter"

# ── Dynamic dispatch via variable indirection ─────────────────────
# Store the "type" as a string, dispatch at runtime by constructing
# the function name from type + method.

dispatch_area() {
    local type="$1"
    shift
    # Build function name and call it
    "shape_area_${type}" "$@"
}

dispatch_perimeter() {
    local type="$1"
    shift
    "shape_perimeter_${type}" "$@"
}

# Polymorphic calls — the type is a runtime value
for shape_spec in "circle 10" "rect 3 4" "triangle 6 4"; do
    read -r type args <<< "$shape_spec"
    # shellcheck disable=SC2086
    area=$(dispatch_area "$type" $args)
    assert_eq "$((area > 0))" "1" "dynamic dispatch $type"
done

# ── Vtable with associative arrays ───────────────────────────────
# An associative array maps method names to function names,
# simulating a vtable (virtual method table).

declare -A dog_vtable=(
    [speak]="dog_speak"
    [name]="dog_name"
)

declare -A cat_vtable=(
    [speak]="cat_speak"
    [name]="cat_name"
)

dog_speak() { echo "woof"; }
dog_name() { echo "Dog"; }
cat_speak() { echo "meow"; }
cat_name() { echo "Cat"; }

# Dispatch through vtable
vtable_call() {
    local -n vtable="$1"
    local method="$2"
    shift 2
    "${vtable[$method]}" "$@"
}

assert_eq "$(vtable_call dog_vtable speak)" "woof" "vtable dog speak"
assert_eq "$(vtable_call cat_vtable speak)" "meow" "vtable cat speak"
assert_eq "$(vtable_call dog_vtable name)" "Dog" "vtable dog name"
assert_eq "$(vtable_call cat_vtable name)" "Cat" "vtable cat name"

# Polymorphic loop over "objects"
sounds=""
for animal in dog_vtable cat_vtable; do
    s=$(vtable_call "$animal" speak)
    sounds="${sounds}${s} "
done
assert_eq "$sounds" "woof meow " "polymorphic vtable loop"

# ── "Interface" compliance check ──────────────────────────────────
# Verify that a "type" implements all required "methods"

implements_shape() {
    local type="$1"
    for method in area perimeter; do
        if ! declare -F "shape_${method}_${type}" > /dev/null; then
            echo "no"
            return
        fi
    done
    echo "yes"
}

assert_eq "$(implements_shape circle)" "yes" "circle implements Shape"
assert_eq "$(implements_shape rect)" "yes" "rect implements Shape"
assert_eq "$(implements_shape hexagon)" "no" "hexagon missing methods"

# ── "Default methods" via fallback functions ──────────────────────
# A trait can provide default implementations that types may override

describable_describe() {
    local type="$1"
    shift
    # Check for type-specific override
    if declare -F "describe_${type}" > /dev/null; then
        "describe_${type}" "$@"
    else
        # Default implementation
        echo "A ${type}"
    fi
}

describe_circle() {
    echo "A circle with radius $1"
}
# No describe_rect — will use default

assert_eq "$(describable_describe circle 5)" "A circle with radius 5" "override method"
assert_eq "$(describable_describe rect 3 4)" "A rect" "default method"

# ── "Trait objects" — heterogeneous collection ────────────────────
# Process a list of differently-typed items through the same interface

shapes=("circle:10" "rect:3:4" "triangle:6:4")
total_area=0

for shape in "${shapes[@]}"; do
    IFS=: read -r type args_str <<< "$shape"
    # Convert colon-separated args to space-separated
    args="${args_str//:/ }"
    # shellcheck disable=SC2086
    area=$(dispatch_area "$type" $args)
    total_area=$((total_area + area))
done

# 314 + 12 + 12 = 338
assert_eq "$total_area" "338" "trait object total area"

# ── "Newtype" pattern with prefixed variables ─────────────────────
# Simulate different types wrapping the same underlying data

meters_value=1000
kilometers_value=1

meters_to_km() { echo "$(( $1 / 1000 ))"; }
km_to_meters() { echo "$(( $1 * 1000 ))"; }

assert_eq "$(meters_to_km $meters_value)" "$kilometers_value" "newtype convert"
assert_eq "$(km_to_meters $kilometers_value)" "$meters_value" "newtype reverse"

# ── Summary ───────────────────────────────────────────────────────
# Shell has no traits/typeclasses, but the patterns map:
#
#   Rust/Haskell concept    Shell simulation
#   ────────────────────    ─────────────────────────────────
#   Trait / Typeclass       Naming convention (prefix_method_type)
#   impl Trait for Type     Define shape_area_circle function
#   dyn Trait               Variable indirection dispatch
#   Vtable                  Associative array of function names
#   Default method          Fallback function with declare -F check
#   Trait bound check       implements_* function
#   Trait object collection Iterate with dynamic dispatch

echo "All trait and typeclass examples passed ($PASS assertions)."
exit 0
