// Vidya — Performance in Go
//
// Go is fast by default — compiled, statically linked, with an efficient
// GC. Key optimization levers: reduce allocations, use appropriate data
// structures, pre-allocate slices, and understand escape analysis.

package main

import (
	"fmt"
	"strings"
	"testing"
	"unsafe"
)

func main() {
	// ── Pre-allocation: make with capacity ─────────────────────────
	// Growing a slice reallocates and copies all elements: capacity
	// doubles while small, then grows by ~1.25-1.5x past 256 elements
	// (runtime.growslice; e.g. 1280→1792→2560→3408 here). Pre-allocate
	// when you know the size.

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

	// Reusing buf only helps if nothing else allocates: append(buf,
	// fmt.Sprintf(...)...) still builds a fresh string every iteration
	// (10 allocs per 10 items); fmt.Appendf (Go 1.19) formats straight into
	// buf (0 allocs).
	buf := make([]byte, 0, 64)
	viaSprintf := testing.AllocsPerRun(10, func() {
		for i := 0; i < 10; i++ {
			buf = buf[:0]                                  // reuse the backing array...
			buf = append(buf, fmt.Sprintf("item%d", i)...) // ...but not the string
		}
	})
	viaAppendf := testing.AllocsPerRun(10, func() {
		for i := 0; i < 10; i++ {
			buf = buf[:0]
			buf = fmt.Appendf(buf, "item%d", i)
		}
	})
	assert(viaAppendf < viaSprintf, fmt.Sprintf("Appendf (%v allocs) beats Sprintf (%v)", viaAppendf, viaSprintf))

	// ── Struct size and alignment ──────────────────────────────────
	// Field ordering affects struct size due to alignment padding

	type BadLayout struct {
		A bool  // 1 byte + 7 padding
		B int64 // 8 bytes
		C bool  // 1 byte + 7 padding
	}
	// Total: 24 bytes

	type GoodLayout struct {
		B int64 // 8 bytes
		A bool  // 1 byte
		C bool  // 1 byte + 6 padding
	}
	// Total: 16 bytes

	// Strict: ">=" would also pass if reordering saved nothing.
	assert(unsafe.Sizeof(BadLayout{}) > unsafe.Sizeof(GoodLayout{}), "layout optimization")

	// ── Map pre-allocation ─────────────────────────────────────────
	// make(map, hint) avoids rehashing for known sizes
	m := make(map[int]int, 1000)
	for i := 0; i < 1000; i++ {
		m[i] = i * i
	}
	assert(m[500] == 250000, "preallocated map")

	// ── Slice vs map for small collections ─────────────────────────
	// A linear scan of a small slice can beat a map lookup: a map access
	// pays a hash plus a bucket probe on every call (~7 ns flat here),
	// while the scan pays only ~0.3 ns per element compared.
	//
	// But the crossover is NOT one number — it moves with the workload,
	// so don't memorize a threshold. Measured on the KV type below
	// (24 B/elem), go1.26 amd64, Ryzen 7 5800H, `go test -bench`:
	//   lookups all MISS  (scan all n):      crossover ≈ 14 elements
	//   lookups all HIT   (scan n/2 avg):    crossover ≈ 37 elements
	// Element size, hit rate, and key type each shift it. Benchmark the
	// shape you actually have — including against the numbers above.

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

	x := 42 // stays on stack
	_ = x
	// newOnHeap's x escapes ITS frame ("moved to heap: x"), but the call is
	// inlined here and p never leaves main, so -m reports no heap move at
	// this call site. Escape analysis runs after inlining.
	p := newOnHeap()
	assert(*p > 0, "pointer from inlined call")

	// ── Sync.Pool for reducing GC pressure ─────────────────────────
	// (Demonstrated in concurrency topic)
	// Reuses allocated objects instead of creating new ones

	// ── Avoid defer in tight loops ─────────────────────────────────
	// Not for speed: since Go 1.14 open-coded defers cost ~1-2 ns (the old
	// ~35 ns figure is pre-1.14). The reason is semantics: a deferred call
	// runs when the FUNCTION returns, not at the end of the iteration, so
	// N iterations pile up N pending calls (N open files). Call cleanup
	// directly, or move the loop body into its own function.
	total := 0
	for i := 0; i < 1000; i++ {
		// Don't: defer cleanup()
		// Do: call cleanup at end of iteration
		total += i
	}
	assert(total == 499500, "loop sum")

	// ── range vs index: the copy is the cost, not the range ────────
	// Myth: "index loops are faster than range loops." For a slice of a
	// small element type they are the SAME loop. Verified on go1.26 amd64
	// by putting the two bodies below in standalone funcs over []int and
	// running `go build -gcflags=-S`: both compile to 27 bytes of
	// byte-identical machine code, inner loop
	// `ADDQ (AX)(CX*8), DX / INCQ CX / CMPQ BX, CX / JGT`.
	data := make([]int, 1000)
	for i := range data {
		data[i] = i
	}

	sum := 0
	for i := 0; i < len(data); i++ {
		sum += data[i]
	}
	assert(sum == 499500, "index iteration")

	rangeSum := 0
	for _, v := range data { // identical codegen to the loop above
		rangeSum += v
	}
	assert(rangeSum == sum, "range iteration matches index iteration")

	// What actually costs: the value variable in `for _, v := range` is a
	// COPY of each element. Free for an int, expensive for a big struct.
	// Measured on []struct{ID int; Pad [32]int64} (264 B/elem), 4096 elems:
	//   for _, v := range s { t += v.ID }    17.8 µs  ← copies 264 B/iter
	//   for i := range s    { t += s[i].ID }  2.0 µs  ← copies nothing
	// Same `range`, 8x apart. So when elements are large, range over the
	// INDEX (or hold []*T) — the fix is dropping the copy, not dropping
	// range for a C-style loop.
	type Wide struct {
		ID  int
		Pad [32]int64
	}
	wide := make([]Wide, 8)
	for i := range wide {
		wide[i].ID = i
	}
	idSum := 0
	for i := range wide { // index-only range: no element is copied
		idSum += wide[i].ID
	}
	assert(idSum == 28, "index-only range over wide elements")

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
