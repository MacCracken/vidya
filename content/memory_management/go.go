// Vidya — Memory Management in Go
//
// Go uses garbage collection — you don't free memory manually. But
// understanding allocation (stack vs heap), escape analysis, and the
// GC's behavior is critical for performance-sensitive code.

package main

import (
	"fmt"
	"runtime"
)

func main() {
	// ── Stack vs heap: escape analysis decides ─────────────────────
	// Go's compiler determines whether a value escapes to the heap.
	// Local values that don't escape stay on the stack (fast, no GC).

	// Stays on stack — no allocation
	x := 42
	assert(x == 42, "stack value")

	// Escapes to heap — returned pointer
	p := newInt(42)
	assert(*p == 42, "heap pointer")

	// ── Slices: length, capacity, and reallocation ─────────────────
	s := make([]int, 0, 10) // length 0, capacity 10
	assert(len(s) == 0, "initial len")
	assert(cap(s) == 10, "initial cap")

	for i := 0; i < 10; i++ {
		s = append(s, i)
	}
	assert(len(s) == 10, "filled len")
	// No reallocation — stayed within capacity

	// Appending beyond capacity triggers reallocation
	s = append(s, 99)
	assert(cap(s) > 10, "grew capacity")

	// ── Slice gotcha: shared underlying array ──────────────────────
	original := []int{1, 2, 3, 4, 5}
	sub := original[1:3] // sub shares original's memory
	sub[0] = 99
	assert(original[1] == 99, "shared backing array") // original modified!

	// To get an independent copy:
	independent := make([]int, len(original))
	copy(independent, original)
	independent[0] = -1
	assert(original[0] == 1, "copy is independent")

	// ── Maps: reference semantics ──────────────────────────────────
	m := map[string]int{"a": 1}
	modifyMap(m)
	assert(m["a"] == 99, "maps are references")

	// ── nil slices and maps ────────────────────────────────────────
	var nilSlice []int
	assert(nilSlice == nil, "nil slice")
	assert(len(nilSlice) == 0, "nil slice len")
	nilSlice = append(nilSlice, 1) // safe to append to nil
	assert(len(nilSlice) == 1, "append to nil")

	var nilMap map[string]int
	assert(nilMap == nil, "nil map")
	// nilMap["key"] = 1  // ← panic! must initialize first
	nilMap = make(map[string]int)
	nilMap["key"] = 1
	assert(nilMap["key"] == 1, "initialized map")

	// ── Garbage collector ──────────────────────────────────────────
	// Force a GC cycle (normally you don't do this)
	runtime.GC()

	// Read GC stats
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	assert(stats.NumGC > 0, "GC has run")

	// ── sync.Pool for reusable objects ─────────────────────────────
	// (Covered in concurrency topic — reduces GC pressure)

	// ── Pointers: explicit but no arithmetic ───────────────────────
	val := 42
	ptr := &val
	*ptr = 100
	assert(val == 100, "pointer mutation")

	// No pointer arithmetic in Go (unlike C)
	// Go pointers are safe — they can't dangle (GC keeps referents alive)

	// ── Struct value semantics ─────────────────────────────────────
	type Point struct{ X, Y int }

	p1 := Point{1, 2}
	p2 := p1  // copy, not reference
	p2.X = 99
	assert(p1.X == 1, "struct copy independence")

	// Use pointer for large structs or when mutation is needed
	type Coord struct{ X, Y int }
	c1 := &Coord{3, 4}
	c1.X = 0 // direct mutation through pointer
	assert(c1.X == 0, "pointer struct mutation")

	// ── defer for cleanup ──────────────────────────────────────────
	// defer ensures cleanup runs even on panic
	cleaned := false
	func() {
		defer func() { cleaned = true }()
	}()
	assert(cleaned, "defer cleanup")

	fmt.Println("All memory management examples passed.")
}

func newInt(n int) *int {
	return &n // n escapes to heap because pointer is returned
}

func modifyMap(m map[string]int) {
	m["a"] = 99
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
