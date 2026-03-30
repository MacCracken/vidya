// Vidya — Performance in Go
//
// Go is fast by default — compiled, statically linked, with an efficient
// GC. Key optimization levers: reduce allocations, use appropriate data
// structures, pre-allocate slices, and understand escape analysis.

package main

import (
	"fmt"
	"strings"
	"unsafe"
)

func main() {
	// ── Pre-allocation: make with capacity ─────────────────────────
	// Growing a slice doubles capacity each time, copying all elements.
	// Pre-allocate when you know the size.

	n := 10_000

	// GOOD: pre-allocated
	preallocated := make([]int, 0, n)
	for i := 0; i < n; i++ {
		preallocated = append(preallocated, i)
	}
	assert(len(preallocated) == n, "preallocated len")

	// BAD: growing from zero — multiple reallocations
	// var growing []int
	// for i := 0; i < n; i++ { growing = append(growing, i) }

	// ── strings.Builder for concatenation ──────────────────────────
	// GOOD: Builder pre-allocates, O(n)
	var b strings.Builder
	b.Grow(n * 4)
	for i := 0; i < 1000; i++ {
		fmt.Fprintf(&b, "%d,", i)
	}
	result := b.String()
	assert(len(result) > 0, "builder result")

	// BAD: string += in a loop is O(n²)
	// s := ""; for i := 0; i < 1000; i++ { s += fmt.Sprintf("%d,", i) }

	// ── Avoid unnecessary allocations ──────────────────────────────
	// String to []byte and back allocates — reuse buffers

	buf := make([]byte, 0, 64)
	for i := 0; i < 10; i++ {
		buf = buf[:0] // reuse, no allocation
		buf = append(buf, fmt.Sprintf("item%d", i)...)
	}

	// ── Struct size and alignment ──────────────────────────────────
	// Field ordering affects struct size due to alignment padding

	type BadLayout struct {
		A bool   // 1 byte + 7 padding
		B int64  // 8 bytes
		C bool   // 1 byte + 7 padding
	}
	// Total: 24 bytes

	type GoodLayout struct {
		B int64 // 8 bytes
		A bool  // 1 byte
		C bool  // 1 byte + 6 padding
	}
	// Total: 16 bytes

	assert(unsafe.Sizeof(BadLayout{}) >= unsafe.Sizeof(GoodLayout{}), "layout optimization")

	// ── Map pre-allocation ─────────────────────────────────────────
	// make(map, hint) avoids rehashing for known sizes
	m := make(map[int]int, 1000)
	for i := 0; i < 1000; i++ {
		m[i] = i * i
	}
	assert(m[500] == 250000, "preallocated map")

	// ── Slice vs map for small collections ─────────────────────────
	// For < ~50 elements, linear search in a slice beats map lookup

	type KV struct {
		Key   int
		Value string
	}

	small := []KV{{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}, {5, "five"}}

	found := ""
	for _, kv := range small {
		if kv.Key == 3 {
			found = kv.Value
			break
		}
	}
	assert(found == "three", "linear search")

	// ── Avoid interface{} / any in hot paths ───────────────────────
	// Interface values require boxing (heap allocation for small types)
	// Use concrete types or generics in performance-sensitive code

	sumConcrete := sumInts([]int{1, 2, 3, 4, 5})
	assert(sumConcrete == 15, "concrete sum")

	// ── Stack allocation via escape analysis ───────────────────────
	// Values that don't escape the function stay on the stack (fast)
	// Use `go build -gcflags='-m'` to see escape analysis decisions

	x := 42           // stays on stack
	_ = x
	p := newOnHeap()  // escapes to heap (returned pointer)
	assert(*p > 0, "heap alloc")

	// ── Sync.Pool for reducing GC pressure ─────────────────────────
	// (Demonstrated in concurrency topic)
	// Reuses allocated objects instead of creating new ones

	// ── Avoid defer in tight loops ─────────────────────────────────
	// defer has a small overhead (~35ns). In tight loops, call cleanup directly
	total := 0
	for i := 0; i < 1000; i++ {
		// Don't: defer cleanup()
		// Do: call cleanup at end of iteration
		total += i
	}
	assert(total == 499500, "loop sum")

	// ── Use index access over range when you need speed ────────────
	data := make([]int, 1000)
	for i := range data {
		data[i] = i
	}

	sum := 0
	for i := 0; i < len(data); i++ {
		sum += data[i]
	}
	assert(sum == 499500, "index iteration")

	fmt.Println("All performance examples passed.")
}

func sumInts(nums []int) int {
	total := 0
	for _, n := range nums {
		total += n
	}
	return total
}

func newOnHeap() *int {
	x := 42
	return &x // x escapes to heap
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
