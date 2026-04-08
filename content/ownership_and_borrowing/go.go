// Vidya — Ownership and Borrowing in Go
//
// Go has no ownership or borrow checker. Memory safety comes from
// garbage collection instead of compile-time analysis. This file
// shows how Go handles the problems that Rust's ownership model
// solves: dangling pointers (impossible — GC keeps referents alive),
// aliased mutation (runtime races, not compile errors), slice sharing,
// sync.Pool for object reuse, and runtime.SetFinalizer for cleanup.
//
// Key contrast with Rust:
//   Rust: compile-time ownership → zero-cost safety, no GC
//   Go:   runtime GC → simpler code, GC pauses, no lifetime annotations

package main

import (
	"fmt"
	"runtime"
	"sync"
)

func main() {
	testNoDanglingPointers()
	testValueSemantics()
	testSliceAliasing()
	testSliceIndependentCopy()
	testMapReferenceSemantics()
	testClosureCapture()
	testSyncPool()
	testFinalizer()
	testInterfaceOwnership()
	testChannelOwnership()

	fmt.Println("All ownership and borrowing examples passed.")
}

// ── No Dangling Pointers ────────────────────────────────────────────
// In Rust, returning a reference to a local is a compile error.
// In Go, the compiler detects this via escape analysis and moves
// the value to the heap. The GC keeps it alive.

func createPointer() *int {
	x := 42       // escape analysis moves x to heap
	return &x     // safe — GC ensures x lives as long as the pointer
}

func testNoDanglingPointers() {
	p := createPointer()
	assert(*p == 42, "returned pointer is valid")

	// Even after GC runs, the pointer is still valid
	runtime.GC()
	assert(*p == 42, "valid after GC")
}

// ── Value Semantics ─────────────────────────────────────────────────
// Structs in Go are values — assignment copies. This is like Rust's
// Copy trait. If you want shared mutation, use pointers explicitly.

type Point struct{ X, Y int }

func testValueSemantics() {
	a := Point{1, 2}
	b := a       // copy, not move — Go structs are always copyable
	b.X = 99
	assert(a.X == 1, "original unchanged after copy")
	assert(b.X == 99, "copy modified independently")

	// With pointers: shared mutation (like Rust's &mut, but unchecked)
	c := &Point{10, 20}
	d := c       // d and c point to the same value
	d.X = 0
	assert(c.X == 0, "pointer aliasing — both see mutation")
}

// ── Slice Aliasing ──────────────────────────────────────────────────
// Go slices are a (ptr, len, cap) triple. Slicing creates an alias
// to the same backing array. This is the Go equivalent of Rust's
// "can't have &mut and & to the same data" problem — Go doesn't
// prevent it, so you can observe aliased mutation.

func testSliceAliasing() {
	original := []int{1, 2, 3, 4, 5}
	sub := original[1:4] // sub = [2, 3, 4], shares backing array

	// Mutating through sub modifies original
	sub[0] = 99
	assert(original[1] == 99, "slice aliasing — original modified")

	// Rust would reject this at compile time:
	//   let sub = &mut original[1..4];
	//   println!("{}", original[1]); // ERROR: can't borrow as immutable
}

func testSliceIndependentCopy() {
	// To avoid aliasing: make an independent copy
	original := []int{1, 2, 3, 4, 5}
	independent := make([]int, len(original))
	copy(independent, original) // like Rust's .clone()

	independent[0] = -1
	assert(original[0] == 1, "copy is independent")

	// append() may or may not alias depending on capacity
	base := make([]int, 3, 5) // len=3, cap=5
	base[0], base[1], base[2] = 10, 20, 30

	ext := append(base, 40) // fits in capacity — shares backing array
	ext[0] = -1
	assert(base[0] == -1, "append within cap shares array")

	// Once capacity is exceeded, append allocates new backing array
	full := []int{1, 2, 3}
	grown := append(full, 4, 5, 6, 7, 8) // exceeds cap, new array
	grown[0] = -1
	assert(full[0] == 1, "append beyond cap creates new array")
}

// ── Map Reference Semantics ─────────────────────────────────────────
// Maps are reference types — passing to a function shares the map.
// No ownership transfer, no borrowing — just shared mutable state.

func modifyMap(m map[string]int) {
	m["key"] = 42 // modifies caller's map
}

func testMapReferenceSemantics() {
	m := map[string]int{"key": 0}
	modifyMap(m)
	assert(m["key"] == 42, "map passed by reference")

	// Compare to Rust: fn modify(m: &mut HashMap<..>) — explicit &mut
}

// ── Closure Capture ─────────────────────────────────────────────────
// Go closures capture variables by reference. Rust closures can
// capture by value (move) or by reference (&/&mut), enforced by
// the borrow checker.

func testClosureCapture() {
	x := 10

	// Closure captures x by reference (pointer to x on the stack/heap)
	inc := func() { x++ }
	inc()
	inc()
	assert(x == 12, "closure captured by reference")

	// Gotcha: loop variable capture
	funcs := make([]func() int, 5)
	for i := 0; i < 5; i++ {
		i := i // shadow i to capture current value (Go idiom)
		funcs[i] = func() int { return i }
	}
	assert(funcs[0]() == 0, "loop var shadowed correctly")
	assert(funcs[4]() == 4, "each closure got its own i")
}

// ── sync.Pool: Object Reuse Without Ownership ───────────────────────
// sync.Pool provides temporary object reuse to reduce GC pressure.
// This is Go's answer to what Rust does with ownership + arena
// allocators. Objects may be collected between GC cycles.

func testSyncPool() {
	pool := &sync.Pool{
		New: func() any {
			buf := make([]byte, 0, 1024)
			return &buf
		},
	}

	// Get a buffer from the pool (or create one)
	bufPtr := pool.Get().(*[]byte)
	buf := *bufPtr
	buf = append(buf[:0], "hello, pool"...)
	assert(len(buf) == 11, "pool buffer used")
	assert(cap(buf) == 1024, "pool buffer capacity preserved")

	// Return to pool for reuse
	*bufPtr = buf[:0] // reset length, keep capacity
	pool.Put(bufPtr)

	// Next Get may return the same buffer (if GC hasn't cleared pool)
	bufPtr2 := pool.Get().(*[]byte)
	assert(cap(*bufPtr2) == 1024, "reused buffer from pool")
}

// ── runtime.SetFinalizer: Cleanup Notifications ─────────────────────
// Go's finalizer is a callback run when an object is about to be
// collected. Unlike Rust's Drop trait, finalizers are NOT guaranteed
// to run, they run at unpredictable times, and they add GC overhead.

type Resource struct {
	name    string
	cleaned bool
}

var finalizerRan = false

func testFinalizer() {
	r := &Resource{name: "db-conn"}

	runtime.SetFinalizer(r, func(res *Resource) {
		finalizerRan = true
	})

	// In Rust, Drop::drop is called deterministically when the value
	// goes out of scope. In Go, the finalizer runs "eventually" during
	// GC — or never if the program exits first.
	//
	// Best practice: don't rely on finalizers for correctness.
	// Use explicit Close() methods with defer instead.

	// Keep r alive for the assertion
	assert(r.name == "db-conn", "resource exists")

	// Note: we deliberately don't test that the finalizer ran,
	// because that's the whole point — Go finalizers are unreliable.
	// Rust's Drop is reliable. That's the tradeoff.
}

// ── Interface Ownership ─────────────────────────────────────────────
// When a value is stored in an interface, Go copies value types and
// shares pointer types. There's no ownership transfer — the GC
// handles everything.

type Shape interface {
	Area() float64
}

type Circle struct {
	Radius float64
}

func (c Circle) Area() float64 { return 3.14159 * c.Radius * c.Radius }

func testInterfaceOwnership() {
	c := Circle{Radius: 5}
	var s Shape = c // Circle is copied into the interface value

	// Modifying c doesn't affect s — it's a copy
	c.Radius = 0
	assert(s.Area() > 78.0, "interface holds independent copy")

	// With pointer receiver: shared
	c2 := &Circle{Radius: 5}
	var s2 Shape = c2 // pointer stored — shared
	c2.Radius = 10
	assert(s2.Area() > 314.0, "interface holds shared pointer")
}

// ── Channel Ownership Transfer ──────────────────────────────────────
// Channels provide a way to transfer "ownership" by convention:
// once you send a value on a channel, you stop using it. Go doesn't
// enforce this — it's a discipline, not a compiler guarantee.
// Rust enforces it: sending on a channel moves the value.

func testChannelOwnership() {
	ch := make(chan []byte, 1)

	// "Transfer ownership" of a buffer
	buf := make([]byte, 4)
	buf[0], buf[1], buf[2], buf[3] = 'G', 'o', '!', 0
	ch <- buf

	// Convention: stop using buf after sending
	// buf[0] = 'X'  // ← legal but breaks ownership convention

	received := <-ch
	assert(received[0] == 'G', "channel transferred data")
	assert(received[2] == '!', "channel data intact")

	// In Rust: tx.send(buf) would move buf, making further use
	// a compile error. Go relies on programmer discipline.
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
