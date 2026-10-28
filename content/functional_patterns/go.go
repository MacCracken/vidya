// Vidya — Functional Patterns — Go port.
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that
// shares structure instead of copying, folds as its recursion scheme, and
// stack depth without tail calls.
//
// Go closures capture VARIABLES, by reference: a closure sees later
// assignments, and one that outlives its frame takes what it captures to
// the heap. Since Go 1.22 each `for` iteration has its own loop variable, so
// the classic loop trap is gone from `for`, though not from a variable
// declared outside one. Go has no immutable fields and no const fns.

package main

import (
	"fmt"
	"os"
	"slices"
)

// --- 1. Purity ---
// A pure function's result depends only on its arguments, and calling it
// changes nothing. Go cannot check that: there is no const fn, and a
// constant is built only from constant expressions (no user function
// runs at compile time), so purity is a discipline.
func pureAdd(a, b int64) int64 { return a + b }

var counter int64 // hidden state impureNext reads and bumps

func impureNext() int64 {
	counter++
	return counter
}

// countedAdd is pureAdd plus a call counter, so a check can see whether
// the underlying function ran (the counter is the test's probe; the value
// is still pureAdd's).
var addCalls int

func countedAdd(a, b int64) int64 {
	addCalls++
	return pureAdd(a, b)
}

// memoize2: cache results by argument. Sound only for a pure function,
// since a cached result must be what a fresh call would return. The key
// is BOTH arguments (an array is comparable, so it can key a map); a key
// of `a` alone would hand (2, 4) the result cached for (2, 3).
func memoize2(f func(a, b int64) int64) func(a, b int64) int64 {
	table := map[[2]int64]int64{}
	return func(a, b int64) int64 {
		key := [2]int64{a, b}
		if v, ok := table[key]; ok {
			return v
		}
		v := f(a, b)
		table[key] = v
		return v
	}
}

// --- 2. Higher-order functions and composition ---
// compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
// pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
// Generic over the types in between.
func addThree(x int64) int64 { return x + 3 }
func timesTwo(x int64) int64 { return x * 2 }

func compose[A, B, C any](f func(B) C, g func(A) B) func(A) C {
	return func(x A) C { return f(g(x)) }
}

func pipe[A, B, C any](f func(A) B, g func(B) C) func(A) C {
	return func(x A) C { return g(f(x)) }
}

// --- 3. Closures and partial application ---
// makeAdder(n) returns a function that remembers n. The closure outlives
// the call, so it is heap-allocated; n is never reassigned, so gc copies
// it into the closure (`go build -gcflags=-m` reports "func literal
// escapes to heap" here but no "moved to heap: n", which makeCounter's n
// gets because its closure assigns it).
func makeAdder(n int64) func(int64) int64 {
	return func(x int64) int64 { return x + n }
}

// Private mutable state: the closure captures n itself, so n++ inside it
// updates the one n. Each makeCounter() call makes a new n, so two
// counters never share a count.
func makeCounter() func() int64 {
	var n int64
	return func() int64 {
		n++
		return n
	}
}

func add3(a, b, c int64) int64 { return a + b + c }

// partial(f, a, b) fixes the first two arguments of a 3-argument
// function. (A method value, x.M, is Go's built-in partial application
// of a receiver.)
func partial(f func(a, b, c int64) int64, a, b int64) func(int64) int64 {
	return func(c int64) int64 { return f(a, b, c) }
}

// --- 4. The capture gotcha: see testCapture ---
// A closure holds the variable, not its value. Before Go 1.22 a `for`
// loop had ONE variable for all its iterations, so closures built in it
// all read its final value, [3 3 3]; the fix was the `i := i` copy. Go
// 1.22 gave each iteration a fresh variable, so the same loop now gives
// [0 1 2]. (This file has no go.mod; `go run` then uses the toolchain's
// own language version.)

// --- 5. Persistent (immutable) list with structural sharing ---
// A cons cell is a head and a pointer to the tail; nil is the empty list.
// cons never copies its tail, so prepending is O(1) and the old list is
// still whole and unchanged. Go cannot make a field read-only: any code
// in the package can write node.head (unexported fields only keep OTHER
// packages out), so the list stays persistent only because no code
// writes a node once others can see it. The garbage collector frees a
// node once no version reaches it.
type Node struct {
	head int64
	tail *Node
}

var consAllocs int // nodes allocated, so checks can count copying

func cons(h int64, t *Node) *Node {
	consAllocs++
	return &Node{head: h, tail: t}
}

func head(xs *Node) int64 { return xs.head }
func tail(xs *Node) *Node { return xs.tail }

func listOf(values ...int64) *Node {
	var xs *Node
	for i := len(values) - 1; i >= 0; i-- {
		xs = cons(values[i], xs)
	}
	return xs
}

func nth(xs *Node, i int) int64 {
	for ; i > 0; i-- {
		xs = xs.tail
	}
	return xs.head
}

// Structural equality: same values in the same order (not the same nodes).
func listEq(a, b *Node) bool {
	for a != nil && b != nil {
		if a.head != b.head {
			return false
		}
		a, b = a.tail, b.tail
	}
	return a == nil && b == nil
}

// Functional update: a new list with element i replaced. It copies the i
// cells in front of i plus the replaced cell (i + 1 allocations) and
// shares everything after it. The original list is not touched.
func updateAt(xs *Node, i int, v int64) *Node {
	if xs == nil {
		return nil
	}
	if i == 0 {
		return cons(v, xs.tail)
	}
	return cons(xs.head, updateAt(xs.tail, i-1, v))
}

// --- 6. Fold as the recursion scheme ---
// foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
// foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
func foldr[A any](f func(int64, A) A, z A, xs *Node) A {
	if xs == nil {
		return z
	}
	return f(xs.head, foldr(f, z, xs.tail))
}

func foldl[A any](f func(A, int64) A, z A, xs *Node) A {
	acc := z
	for p := xs; p != nil; p = p.tail {
		acc = f(acc, p.head)
	}
	return acc
}

func listLength(xs *Node) int {
	return foldl(func(acc int, _ int64) int { return acc + 1 }, 0, xs)
}

func listSum(xs *Node) int64 {
	return foldl(func(acc, x int64) int64 { return acc + x }, 0, xs)
}

func listReverse(xs *Node) *Node {
	return foldl(func(acc *Node, x int64) *Node { return cons(x, acc) }, nil, xs)
}

func listMap(g func(int64) int64, xs *Node) *Node {
	return foldr(func(x int64, acc *Node) *Node { return cons(g(x), acc) }, nil, xs)
}

func sub(a, b int64) int64 { return a - b }

// --- 7. Tail recursion and stack depth ---
// Go does not eliminate tail calls: the spec promises none and the gc
// compiler keeps every frame. Naive recursion 100,000 deep still works,
// and not because a fixed stack happens to be big enough (as C's and
// Rust's 8 MiB main thread is, and Python's 1000-frame limit is not): a
// goroutine stack starts at a few KB and grows by copying itself, up to
// runtime/debug.SetMaxStack's default of 1 GB on 64-bit. Past that the runtime prints "goroutine stack
// exceeds 1000000000-byte limit" and dies of "fatal error: stack
// overflow", which no recover() catches. Every level still costs a frame
// and the growth copies; the accumulator loop costs neither.
func sumToLoop(n int64) int64 {
	var acc int64
	for i := int64(1); i <= n; i++ {
		acc += i
	}
	return acc
}

func sumNaive(n int64) int64 {
	if n == 0 {
		return 0
	}
	return n + sumNaive(n-1) // the + runs after the call returns
}

// === Tests ===

var passCount, failCount int

// check is a stand-in for an assert: Go has none, so we count failures
// and exit non-zero from main if any check failed.
func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func testPurity() {
	r1 := pureAdd(2, 3)
	r2 := pureAdd(2, 3)
	check(r1 == r2, "pureAdd: same arguments, same result")
	check(r1 == 5, "pureAdd(2, 3) = 5")

	counter = 0
	n1 := impureNext()
	n2 := impureNext()
	check(n1 != n2, "impureNext: same call, different results (1, then 2)")
	check(counter == 2, "impureNext left a trace: hidden state bumped twice")
}

func testMemoize() {
	addCalls = 0
	madd := memoize2(countedAdd)
	m1 := madd(2, 3)
	m2 := madd(2, 3)
	check(m1 == 5, "memo: first call computes 2 + 3 = 5")
	check(m2 == 5, "memo: second call returns the cached 5")
	check(addCalls == 1, "memo: second call is a cache hit (1 call, not 2)")
	check(madd(2, 4) == 6, "memo: (2, 4) is a miss, the key is both arguments")
	check(addCalls == 2, "memo: the miss ran the underlying function once more")
}

func testComposition() {
	c := compose(addThree, timesTwo)
	p := pipe(addThree, timesTwo)
	check(c(1) == 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5")
	check(p(1) == 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8")
	check(c(1) != p(1), "order matters: compose != pipe at x = 1")

	// The laws, over a range of x: compose applies g first, and pipe is
	// compose with its arguments swapped.
	cgf := compose(timesTwo, addThree)
	okC, okP := true, true
	for x := int64(-2); x <= 2; x++ {
		if c(x) != addThree(timesTwo(x)) {
			okC = false
		}
		if p(x) != cgf(x) {
			okP = false
		}
	}
	check(okC, "compose(f, g)(x) == f(g(x)) for x in -2..2")
	check(okP, "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2")
}

func testClosures() {
	add5 := makeAdder(5)
	add10 := makeAdder(10)
	check(add5(1) == 6, "makeAdder(5)(1) = 6")
	check(add10(1) == 11, "makeAdder(10)(1) = 11: each adder keeps its own n")

	c1 := makeCounter()
	c2 := makeCounter()
	c1()
	c1()
	check(c1() == 3, "counter 1 counted 1, 2, 3")
	check(c2() == 1, "counter 2 starts at 1: its state is its own")
	check(c1() == 4, "counter 1 carries on at 4, untouched by counter 2")

	add12 := partial(add3, 1, 2)
	check(add12(3) == 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6")
}

func callAll(fs []func() int) []int {
	out := make([]int, len(fs))
	for k, f := range fs {
		out[k] = f()
	}
	return out
}

func testCapture() {
	// Go 1.22+: each iteration's i is a new variable, so each closure
	// holds a different one.
	var fs []func() int
	for i := 0; i < 3; i++ {
		fs = append(fs, func() int { return i })
	}
	check(slices.Equal(callAll(fs), []int{0, 1, 2}), "per-iteration i: closures return [0 1 2]")

	// What every loop did before 1.22: ONE variable for all iterations.
	// Capturing a variable is holding its address, spelled out here as a
	// pointer to the one j. The loop leaves j at 3, so all read 3.
	var refs []func() int
	j := 0
	pj := &j
	for ; j < 3; j++ {
		refs = append(refs, func() int { return *pj })
	}
	check(slices.Equal(callAll(refs), []int{3, 3, 3}), "one shared j: closures return [3 3 3]")

	// The pre-1.22 fix: copy into a variable declared inside the body,
	// which IS new each iteration. `j = 0` reuses the one outer j.
	var copies []func() int
	for j = 0; j < 3; j++ {
		v := j
		copies = append(copies, func() int { return v })
	}
	check(slices.Equal(callAll(copies), []int{0, 1, 2}), "v := j per iteration: closures return [0 1 2]")

	// After the fact: the closure sees a later assignment, unless it
	// captured a copy.
	base := 1
	g := func() int { return base }
	snapshot := base
	gEarly := func() int { return snapshot }
	base = 99
	check(g() == 99, "captured by reference: g sees the later base = 99")
	check(gEarly() == 1, "captured a copy: gEarly kept 1")
}

func testPersistentList() {
	xs := listOf(1, 2, 3)
	ys := cons(0, xs)
	check(tail(ys) == xs, "cons shares: tail(ys) IS xs, the same node")
	check(listEq(ys, listOf(0, 1, 2, 3)), "ys reads [0, 1, 2, 3]")
	check(listEq(xs, listOf(1, 2, 3)), "xs still reads [1, 2, 3] after the cons")

	before := consAllocs
	zs := updateAt(xs, 1, 20)
	check(consAllocs-before == 2, "update at index 1 allocates i + 1 = 2 nodes, not 3")
	check(listEq(zs, listOf(1, 20, 3)), "zs reads [1, 20, 3]")
	check(tail(tail(zs)) == tail(tail(xs)), "the suffix after the updated cell is shared")
	check(tail(zs) != tail(xs), "the updated cell is new, not xs's")
	check(listEq(xs, listOf(1, 2, 3)), "xs still reads [1, 2, 3] after the update")

	// The gotcha: write through a node two versions share and both change.
	// Nothing stops this assignment; persistence is a rule the code keeps.
	vs := listOf(1, 2, 3)
	ws := updateAt(vs, 0, 7) // ws = [7, 2, 3], shares vs's [2, 3]
	tail(vs).head = 99       // in-place write to the shared cell
	check(nth(ws, 1) == 99, "a write through a shared node changes the other version too")
	check(head(ws) == 7, "ws's own first cell is still 7")
}

func testFolds() {
	xs := listOf(1, 2, 3)
	check(listLength(xs) == 3, "length via foldl = 3")
	check(listLength(nil) == 0, "length of the empty list = 0")
	check(listSum(xs) == 6, "sum via foldl = 1 + 2 + 3 = 6")
	check(listEq(listReverse(xs), listOf(3, 2, 1)), "reverse via foldl = [3, 2, 1]")
	tens := func(x int64) int64 { return x * 10 }
	check(listEq(listMap(tens, xs), listOf(10, 20, 30)), "map via foldr keeps order: [10, 20, 30]")
	check(listEq(xs, listOf(1, 2, 3)), "the folds left xs as [1, 2, 3]")

	// Subtraction is not associative, so the fold's direction shows.
	check(foldl(sub, 0, xs) == -6, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6")
	check(foldr(sub, 0, xs) == 2, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2")
}

func testTailCalls() {
	check(sumToLoop(100000) == 5000050000, "accumulator loop: sum 1..100000 = 5000050000")
	check(sumNaive(100000) == 5000050000, "naive recursion 100,000 deep fits: the goroutine stack grew")
}

func main() {
	testPurity()
	testMemoize()
	testComposition()
	testClosures()
	testCapture()
	testPersistentList()
	testFolds()
	testTailCalls()

	if failCount > 0 {
		fmt.Printf("%d passed, %d failed\n", passCount, failCount)
		os.Exit(1)
	}
	fmt.Println("All functional pattern examples passed.")
}
