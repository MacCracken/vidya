// Vidya — Dependent Types — Go port.
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// Go is runtime-checked refinement with one compile-time piece: an array
// type [N]int fixes N, and the compiler will not mix [2]int and [3]int.
// But generics take types, never numbers, so there is no Vec[N] and no
// Vec[N + M]: each length is its own type. Everything else is a checked
// constructor, and unexported fields guard it only across packages.

package main

import (
	"errors"
	"fmt"
	"os"
)

// --- 1. Length-indexed vector ---
// One array type per length. len() of an array type is a compile-time
// constant. A generic over the length does not compile:
//
//	func Head[N int](v [N]int) int
//	invalid array length N
//
// so a generic can only LIST the lengths it accepts, as a type set.
type Vec0 [0]int
type Vec2 [2]int
type Vec3 [3]int
type Vec5 [5]int

type AnyVec interface {
	~[0]int | ~[2]int | ~[3]int | ~[5]int
}

// NonEmpty leaves out [0]int, and it has to: with ~[0]int in the set,
// head's v[0] is refused ("invalid argument: index 0 out of bounds
// [0:0]"). So head of the empty vector does not compile:
//
//	head(empty)
//	Vec0 does not satisfy NonEmpty (Vec0 missing in ~[2]int | ~[3]int | ~[5]int)
type NonEmpty interface {
	~[2]int | ~[3]int | ~[5]int
}

// The length, read from the TYPE of the argument, for any listed vector type.
func vlen[V AnyVec](v V) int { return len(v) }

func head[V NonEmpty](v V) int { return v[0] }

const vec2Len = len(Vec2{})
const vec3Len = len(Vec3{})

// append's lengths are in its signature, so the arguments the wrong way
// round do not compile:
//
//	append23(b, a)
//	cannot use b (variable of array type Vec3) as Vec2 value in argument to append23
//
// For these concrete types Go could compute the length itself, `type
// Vec5 [len(Vec2{}) + len(Vec3{})]int`, but not from type parameters, so
// a generic append has no [N + M]int to return. Go has no static_assert,
// but a constant index out of range is a compile error. So this compiles
// only if len(Vec5) == len(Vec2) + len(Vec3) (the idiom the stringer tool
// generates). With a Vec4 in its place the build stops:
//
//	invalid argument: index len(Vec4{}) - (len(Vec2{}) + len(Vec3{})) (constant -1 of type int) must not be negative
func _() {
	var x [1]struct{}
	_ = x[len(Vec5{})-(len(Vec2{})+len(Vec3{}))]
}

func append23(a Vec2, b Vec3) Vec5 {
	var out Vec5
	copy(out[:], a[:])
	copy(out[vec2Len:], b[:])
	return out
}

// A length known only at run time cannot be in a Go type. A slice carries
// its length as a value, so head checks it at run time and says so with
// the (value, ok) pair.
func vecHead(v []int) (int, bool) {
	if len(v) == 0 {
		return 0, false
	}
	return v[0], true
}

// --- 2. Fin n: an index proven in range ---
// A Fin3 is made only by fin3(), which refuses anything outside 0..2, so
// index3 has no check of its own: k.i < 3 was proved when k was built.
// Its bound is vec3Len, the same constant as Vec3's length. A Fin2 is a
// different type, and using one on a Vec3 does not compile:
//
//	index3(b, k2)
//	cannot use k2 (variable of struct type Fin2) as Fin3 value in argument to index3
//
// The compiler still checks the index at run time: go build
// -gcflags=-d=ssa/check_bce reports "Found IsInBounds" for index3's
// v[k.i] (it cannot see fin3's proof), and none for a constant index.
type Fin2 struct{ i int }
type Fin3 struct{ i int }

func fin2(i int) (Fin2, bool) {
	if i < 0 || i >= vec2Len {
		return Fin2{}, false
	}
	return Fin2{i}, true
}

func fin3(i int) (Fin3, bool) {
	if i < 0 || i >= vec3Len {
		return Fin3{}, false
	}
	return Fin3{i}, true
}

func index2(v Vec2, k Fin2) int { return v[k.i] }
func index3(v Vec3, k Fin3) int { return v[k.i] }

// --- 3. Refinement at the boundary (parse, don't validate) ---
// newPercent() is the one place the range is checked. Everything
// downstream takes a Percent and trusts it: discount never looks at the
// range. percentChecks counts validations, so a check can see that.
type Percent struct{ v int }

var percentChecks = 0

var errPercentRange = errors.New("percent out of range 0..100")

func newPercent(x int) (Percent, error) {
	percentChecks++
	if x < 0 || x > 100 {
		return Percent{}, errPercentRange
	}
	return Percent{x}, nil
}

func discount(price int, p Percent) int { return price - price*p.v/100 }

// --- 4. Σ type (dependent pair) ---
// Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
// the first. A Go type cannot depend on a value, so data is a slice of any
// length and sized() checks the dependency once: it builds a pair only
// when the slice really holds n elements. sizedSum then takes its loop
// bound from n alone. (Each s.data[i] is still bounds-checked; the
// constructor's proof is why it never fails here.)
type Sized struct {
	n    int
	data []int
}

func sized(n int, data []int) (Sized, bool) {
	if len(data) != n {
		return Sized{}, false
	}
	return Sized{n, data}, true
}

func sizedSum(s Sized) int {
	total := 0
	for i := 0; i < s.n; i++ {
		total += s.data[i]
	}
	return total
}

// --- 5. The escape hatch ---
// An unexported field is private to its PACKAGE, and this one-file example
// is one package (main), so a struct literal and a field write compile
// right beside the constructor. Moved to its own package, both stop:
//   refined.Percent{v: 150}
//   cannot refer to unexported field v in struct literal of type refined.Percent
//   p.v = 250
//   p.v undefined (cannot refer to unexported field v)
// What the language does not protect even then: code inside the package,
// the zero value (`var p refined.Percent` compiles anywhere; here that is
// 0%, which is in range), and package unsafe. Keep the type in a package
// of its own and review the package.

// === Tests ===

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func testLengthIndexed() {
	var empty Vec0
	a := Vec2{1, 2}
	b := Vec3{3, 4, 5}
	check(vlen(empty) == 0, "Vec0's type says length 0")
	check(vlen(a) == 2, "Vec2's type says length 2")
	check(vlen(b) == 3, "Vec3's type says length 3")
	check(head(a) == 1, "head([1, 2]) = 1")
	check(head(b) == 3, "head([3, 4, 5]) = 3")

	c := append23(a, b)
	check(vlen(c) == vlen(a)+vlen(b), "append(Vec2, Vec3) has length 2 + 3 = 5")
	check(c == Vec5{1, 2, 3, 4, 5}, "append(Vec2, Vec3) reads [1, 2, 3, 4, 5]")

	// The run-time-length slice: the empty case is refused when it happens.
	_, ok0 := vecHead([]int{})
	h1, ok1 := vecHead([]int{7})
	check(!ok0, "run-time head of an empty slice is refused")
	check(ok1 && h1 == 7, "run-time head of [7] is allowed and = 7")
}

func testFin() {
	a := Vec2{1, 2}
	b := Vec3{3, 4, 5}
	_, ok := fin3(-1)
	check(!ok, "fin3(-1) is refused")
	_, ok = fin3(3)
	check(!ok, "fin3(3) is refused: 3 is not < 3")

	accepted := 0
	reads := true
	for i := -1; i <= 3; i++ {
		if k, ok := fin3(i); ok {
			accepted++
			if index3(b, k) != 3+i {
				reads = false
			}
		}
	}
	check(accepted == 3, "fin3 accepts exactly 0, 1, 2 out of -1..3")
	check(reads, "index3 with each Fin3 reads [3, 4, 5] in order")

	_, ok = fin2(2)
	check(!ok, "fin2(2) is refused: 2 is not < 2")
	k1, ok := fin2(1)
	check(ok && index2(a, k1) == 2, "index2([1, 2], fin2(1)) = 2")
}

func testRefinement() {
	percentChecks = 0
	_, err := newPercent(-1)
	check(errors.Is(err, errPercentRange), "percent(-1) is refused")
	_, err = newPercent(101)
	check(errors.Is(err, errPercentRange), "percent(101) is refused")
	p0, err0 := newPercent(0)
	p100, err100 := newPercent(100)
	p25, err25 := newPercent(25)
	check(err0 == nil && err100 == nil && err25 == nil, "percent accepts 0, 100 and 25")
	check(percentChecks == 5, "5 constructions, 5 validations")

	check(discount(200, p25) == 150, "discount(200, 25%) = 150")
	check(discount(200, p0) == 200, "discount(200, 0%) = 200")
	check(discount(200, p100) == 0, "discount(200, 100%) = 0")
	check(percentChecks == 5, "discount never re-validated: still 5 checks after 3 calls")
}

func testSigma() {
	_, ok := sized(3, []int{1, 2})
	check(!ok, "(3, [1, 2]) is refused: the length is 2")
	_, ok = sized(2, []int{1, 2, 3})
	check(!ok, "(2, [1, 2, 3]) is refused: the length is 3")
	s, ok := sized(3, []int{1, 2, 3})
	check(ok, "(3, [1, 2, 3]) is built")
	check(s.n == 3, "the pair's n is 3")
	check(sizedSum(s) == 6, "sizedSum reads n = 3 elements: 1 + 2 + 3 = 6")
}

func testEscapeHatch() {
	_, err := newPercent(150)
	check(errors.Is(err, errPercentRange), "the API refuses 150")
	forged := Percent{v: 150} // the struct literal skips newPercent()
	check(forged.v == 150, "a struct literal makes a Percent of 150 anyway")
	check(discount(200, forged) == -100, "and discount trusts it: 200 - 300 = -100")

	p, err := newPercent(30)
	check(err == nil, "percent(30) is accepted")
	p.v = 250 // rewrites a validated Percent in place
	check(discount(100, p) == -150, "a field write into a checked Percent breaks it too: -150")
}

func main() {
	testLengthIndexed()
	testFin()
	testRefinement()
	testSigma()
	testEscapeHatch()

	if failCount > 0 {
		fmt.Printf("%d passed, %d failed\n", passCount, failCount)
		os.Exit(1)
	}
	fmt.Println("All dependent type examples passed.")
}
