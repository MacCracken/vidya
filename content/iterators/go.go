// Vidya — Iterators in Go
//
// Go doesn't have a formal iterator trait like Rust. Instead, it uses
// range loops over slices/maps/channels, and closures for custom iteration.
// Go 1.23+ adds range-over-func (iter.Seq) for composable iterators.

package main

import (
	"fmt"
	"slices"
	"sort"
	"strings"
)

func main() {
	// ── range over slices ──────────────────────────────────────────
	numbers := []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

	// Filter + map: no built-in chain, use loops
	var evenSquares []int
	for _, n := range numbers {
		if n%2 == 0 {
			evenSquares = append(evenSquares, n*n)
		}
	}
	assertSliceEq(evenSquares, []int{4, 16, 36, 64, 100}, "even squares")

	// ── range over maps ────────────────────────────────────────────
	ages := map[string]int{"alice": 30, "bob": 25}
	count := 0
	for range ages {
		count++
	}
	assert(count == 2, "map range count")

	// ── range over strings (iterates runes) ─────────────────────────
	runeCount := 0
	for range "café" {
		runeCount++
	}
	assert(runeCount == 4, "string rune iteration")

	// ── range over channels ─────────────────────────────────────────
	ch := make(chan int, 5)
	for i := 0; i < 5; i++ {
		ch <- i * i
	}
	close(ch)

	var squares []int
	for v := range ch {
		squares = append(squares, v)
	}
	assertSliceEq(squares, []int{0, 1, 4, 9, 16}, "channel range")

	// ── slices package (Go 1.21+) ──────────────────────────────────
	data := []int{3, 1, 4, 1, 5, 9, 2, 6}

	assert(slices.Contains(data, 5), "contains")
	assert(slices.Min(data) == 1, "min")
	assert(slices.Max(data) == 9, "max")
	assert(slices.Index(data, 4) == 2, "index")

	sorted := slices.Clone(data)
	slices.Sort(sorted)
	assertSliceEq(sorted, []int{1, 1, 2, 3, 4, 5, 6, 9}, "sorted")

	// ── Sorting with custom comparator ──────────────────────────────
	words := []string{"banana", "apple", "cherry"}
	sort.Slice(words, func(i, j int) bool {
		return len(words[i]) < len(words[j])
	})
	assertStrSliceEq(words, []string{"apple", "banana", "cherry"}, "sort by length")

	// ── Building functional-style helpers ───────────────────────────
	// Go doesn't have generics-based map/filter in std (yet), but they're easy:

	doubled := mapInts(numbers, func(n int) int { return n * 2 })
	assert(doubled[0] == 2 && doubled[9] == 20, "map helper")

	evens := filterInts(numbers, func(n int) bool { return n%2 == 0 })
	assertSliceEq(evens, []int{2, 4, 6, 8, 10}, "filter helper")

	sum := foldInts(numbers, 0, func(acc, n int) int { return acc + n })
	assert(sum == 55, "fold helper")

	// ── Closure-based iterator pattern ──────────────────────────────
	countdown := makeCountdown(3)
	var collected []int
	for {
		v, ok := countdown()
		if !ok {
			break
		}
		collected = append(collected, v)
	}
	assertSliceEq(collected, []int{3, 2, 1}, "closure iterator")

	// ── strings.NewReader as an io.Reader iterator ──────────────────
	reader := strings.NewReader("hello")
	buf := make([]byte, 5)
	n, _ := reader.Read(buf)
	assert(n == 5, "reader bytes")
	assert(string(buf) == "hello", "reader content")

	// ── Append and grow patterns ───────────────────────────────────
	result := make([]int, 0, 20) // pre-allocate capacity
	for i := 0; i < 20; i++ {
		result = append(result, i)
	}
	assert(len(result) == 20, "preallocated append")

	fmt.Println("All iterator examples passed.")
}

// ── Helper functions ───────────────────────────────────────────────

func mapInts(s []int, f func(int) int) []int {
	result := make([]int, len(s))
	for i, v := range s {
		result[i] = f(v)
	}
	return result
}

func filterInts(s []int, f func(int) bool) []int {
	var result []int
	for _, v := range s {
		if f(v) {
			result = append(result, v)
		}
	}
	return result
}

func foldInts(s []int, init int, f func(int, int) int) int {
	acc := init
	for _, v := range s {
		acc = f(acc, v)
	}
	return acc
}

func makeCountdown(n int) func() (int, bool) {
	current := n
	return func() (int, bool) {
		if current <= 0 {
			return 0, false
		}
		current--
		return current + 1, true
	}
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}

func assertSliceEq(a, b []int, msg string) {
	if len(a) != len(b) {
		panic(fmt.Sprintf("assertion failed (%s): len %d != %d", msg, len(a), len(b)))
	}
	for i := range a {
		if a[i] != b[i] {
			panic(fmt.Sprintf("assertion failed (%s): index %d: %d != %d", msg, i, a[i], b[i]))
		}
	}
}

func assertStrSliceEq(a, b []string, msg string) {
	if len(a) != len(b) {
		panic(fmt.Sprintf("assertion failed (%s): len %d != %d", msg, len(a), len(b)))
	}
	for i := range a {
		if a[i] != b[i] {
			panic(fmt.Sprintf("assertion failed (%s): index %d: %s != %s", msg, i, a[i], b[i]))
		}
	}
}
