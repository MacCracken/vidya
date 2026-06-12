// Vidya — Build Systems — Go port.
//
// A minimal build-system core: a DAG of targets, topological build
// order, content-signature dirty-tracking, and ninja-style incremental
// rebuild (only dirty targets run), plus cycle detection.
//
// No real files or compilers: each target carries a source "content
// signature" (an integer). A target's INPUT signature mixes its own
// source with the OUTPUT signatures of its dependencies; if that differs
// from the signature it was last built against, the target is dirty and
// rebuilds. Editing a source changes its signature, which transitively
// re-dirties everything downstream — exactly how mtime/hash-based tools
// (make, ninja, bazel) decide what to redo.

package main

import (
	"fmt"
	"os"
)

const (
	HB = 131     // signature polynomial base
	HM = 1000003 // signature modulus (prime; keeps values < 2^53)
)

// Builder holds the target table as parallel slices.
type Builder struct {
	src   []int64 // source content signature
	deps  [][]int // dependency lists
	built []int64 // signature last built against (-1 = never)
	out   []int64 // current output signature
	order []int   // topological order (target ids)
}

// NewBuilder allocates a table of n targets, each marked never-built.
func NewBuilder(n int) *Builder {
	b := &Builder{
		src:   make([]int64, n),
		deps:  make([][]int, n),
		built: make([]int64, n),
		out:   make([]int64, n),
	}
	for i := 0; i < n; i++ {
		b.built[i] = -1 // never built
	}
	return b
}

func (b *Builder) setSrc(t int, sig int64) { b.src[t] = sig }
func (b *Builder) addDep(t, d int)         { b.deps[t] = append(b.deps[t], d) }

// topo runs a Kahn-style ready-scan: repeatedly place any unplaced
// target whose deps are all placed. It writes target ids into b.order
// and returns how many were ordered; < N ⇒ a cycle left some targets
// unreachable.
func (b *Builder) topo() int {
	n := len(b.src)
	placedFlag := make([]bool, n)
	b.order = b.order[:0]
	placed := 0
	for placed < n {
		progress := false
		for t := 0; t < n; t++ {
			if placedFlag[t] {
				continue
			}
			ready := true // ready iff every dependency is already placed
			for _, d := range b.deps[t] {
				if !placedFlag[d] {
					ready = false
				}
			}
			if ready {
				b.order = append(b.order, t)
				placedFlag[t] = true
				placed++
				progress = true
			}
		}
		if !progress {
			return placed // stuck ⇒ cycle
		}
	}
	return placed
}

// sig computes a target's INPUT signature: mix its own source with the
// output signatures of its dependencies.
func (b *Builder) sig(t int) int64 {
	s := b.src[t] % HM
	for _, d := range b.deps[t] {
		s = (s*HB + b.out[d]) % HM
	}
	return s
}

// build walks the topo order and rebuilds only dirty targets. Output is
// content-addressed (out == input signature), so a target whose inputs
// are unchanged keeps its output and its dependents stay clean. Returns
// the number of targets rebuilt.
func (b *Builder) build() int {
	ordered := b.topo()
	rebuilt := 0
	for i := 0; i < ordered; i++ {
		t := b.order[i]
		s := b.sig(t)
		if s != b.built[t] {
			b.out[t] = s   // produce output
			b.built[t] = s // remember what we built
			rebuilt++
		}
	}
	return rebuilt
}

// orderPos returns the position of target in the topo order, or -1.
func (b *Builder) orderPos(target int) int {
	for i, t := range b.order {
		if t == target {
			return i
		}
	}
	return -1
}

// Classic C build graph: app(2) <- util.o(0), main.o(1)
func buildGraph() *Builder {
	b := NewBuilder(3)
	b.setSrc(0, 1001) // util.c
	b.setSrc(1, 2002) // main.c
	b.setSrc(2, 3003) // link recipe
	b.addDep(2, 0)
	b.addDep(2, 1)
	return b
}

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

func main() {
	// Topological order: all 3 placed, app after both deps.
	{
		b := buildGraph()
		check(b.topo() == 3, "topo orders all 3 targets")
		check(b.orderPos(2) > b.orderPos(0), "app built after util.o")
		check(b.orderPos(2) > b.orderPos(1), "app built after main.o")
	}
	// Cold build rebuilds all.
	{
		b := buildGraph()
		check(b.build() == 3, "cold build rebuilds all 3")
	}
	// No-edit second build rebuilds nothing.
	{
		b := buildGraph()
		b.build() // cold
		check(b.build() == 0, "second build (no edits) rebuilds nothing")
	}
	// Editing a leaf re-dirties it and its dependents.
	{
		b := buildGraph()
		b.build()         // cold: all up to date
		b.setSrc(1, 2999) // edit main.c
		check(b.build() == 2, "edit main.c rebuilds main.o + app")
	}
	// Editing the other leaf skips the untouched sibling.
	{
		b := buildGraph()
		b.build()
		mainBuilt := b.built[1]
		b.setSrc(0, 1999) // edit util.c
		check(b.build() == 2, "edit util.c rebuilds util.o + app")
		check(b.built[1] == mainBuilt, "main.o left untouched")
	}
	// Cycle detection: 0 <-> 1 leaves targets unordered.
	{
		b := NewBuilder(2)
		b.addDep(0, 1)
		b.addDep(1, 0)
		check(b.topo() < 2, "cycle leaves targets unordered")
	}

	if failCount > 0 {
		fmt.Printf("%d passed, %d failed\n", passCount, failCount)
		os.Exit(1)
	}
	fmt.Println("All build_systems examples passed.")
}
