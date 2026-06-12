// Vidya — Package Resolution — Go port.
//
// Semantic versioning, caret constraint matching, range intersection
// for diamond dependencies, highest-version selection, bounded
// backtracking, and dependency-cycle detection — the core of a
// dependency resolver (npm, cargo, cyrius.cyml's own resolver).
//
// A semver major.minor.patch is encoded as one int64
//   enc = major*1_000_000 + minor*1_000 + patch
// so version comparison IS integer comparison. A constraint is a
// half-open range [lo, hi). A caret ^X.Y.Z allows everything from
// X.Y.Z up to (but not including) the next major: [X.Y.Z, (X+1).0.0).

package main

import (
	"fmt"
	"os"
)

const (
	vMaj int64 = 1000000
	vMin int64 = 1000
)

// --- Semver encode / inspect ---

func sv(maj, min, pat int64) int64 { return maj*vMaj + min*vMin + pat }
func svMajor(v int64) int64        { return v / vMaj }

// --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---

func caretLo(v int64) int64 { return v }
func caretHi(v int64) int64 { return (svMajor(v) + 1) * vMaj }

// --- Constraint satisfaction over a half-open range ---

func satisfies(v, lo, hi int64) bool { return lo <= v && v < hi }

// --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---

func rangeLoMax(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

func rangeHiMin(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

func rangeEmpty(lo, hi int64) bool { return lo >= hi }

// --- Highest version in vers that lies in [lo, hi); -1 if none ---

func bestMatch(vers []int64, lo, hi int64) int64 {
	best := int64(-1)
	for _, v := range vers {
		if satisfies(v, lo, hi) && v > best {
			best = v
		}
	}
	return best
}

// Available versions of the shared dependency C.
func setupC() []int64 {
	return []int64{sv(1, 0, 0), sv(1, 5, 0), sv(2, 0, 0)}
}

// --- Diamond resolution: A requires C ^aBase, B requires C ^bBase.
//     Intersect the two carets and pick the highest C that fits.
//     Returns chosen C version, or -1 if the constraints conflict. ---

func resolveShared(cVers []int64, aBase, bBase int64) int64 {
	lo := rangeLoMax(caretLo(aBase), caretLo(bBase))
	hi := rangeHiMin(caretHi(aBase), caretHi(bBase))
	if rangeEmpty(lo, hi) {
		return -1
	}
	return bestMatch(cVers, lo, hi)
}

// --- Bounded backtracking: A has candidate versions (aVers), each of
//     which requires a different caret on C (aCreq). B requires C
//     ^bBase. The absolute-highest A may force a C constraint that
//     conflicts with B; choose the HIGHEST A for which some C still
//     satisfies both. Also reports the chosen C. -1 if none. ---

func resolveBacktrack(cVers, aVers, aCreq []int64, bBase int64) (chosenA, chosenC int64) {
	chosenA, chosenC = -1, -1
	for i := range aVers {
		aver := aVers[i]
		creq := aCreq[i]
		lo := rangeLoMax(caretLo(creq), caretLo(bBase))
		hi := rangeHiMin(caretHi(creq), caretHi(bBase))
		if rangeEmpty(lo, hi) {
			continue
		}
		c := bestMatch(cVers, lo, hi)
		if c != -1 && aver > chosenA {
			chosenA, chosenC = aver, c
		}
	}
	return chosenA, chosenC
}

// --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
//     some package permanently unplaceable). ---

type Graph struct {
	deps [][]int
}

func newGraph(n int) *Graph { return &Graph{deps: make([][]int, n)} }

func (g *Graph) addDep(p, d int) { g.deps[p] = append(g.deps[p], d) }

func (g *Graph) hasCycle() bool {
	n := len(g.deps)
	placed := make([]bool, n)
	count := 0
	for count < n {
		progress := false
		for p := 0; p < n; p++ {
			if placed[p] {
				continue
			}
			ready := true
			for _, d := range g.deps[p] {
				if !placed[d] {
					ready = false
				}
			}
			if ready {
				placed[p] = true
				count++
				progress = true
			}
		}
		if !progress {
			return true // stuck => cycle
		}
	}
	return false
}

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func main() {
	// Semver encoding and inspection.
	check(sv(1, 2, 3) > sv(1, 2, 0), "patch ordering")
	check(sv(2, 0, 0) > sv(1, 9, 9), "major dominates minor/patch")
	check(svMajor(sv(1, 5, 2)) == 1, "extract major")

	// Caret ranges.
	check(caretLo(sv(1, 2, 0)) == sv(1, 2, 0), "caret lower = base")
	check(caretHi(sv(1, 2, 0)) == sv(2, 0, 0), "caret upper = next major")
	check(satisfies(sv(1, 4, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "1.4.0 in ^1.2.0")
	check(!satisfies(sv(2, 0, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "2.0.0 not in ^1.2.0")
	check(!satisfies(sv(1, 1, 0), caretLo(sv(1, 2, 0)), caretHi(sv(1, 2, 0))), "1.1.0 below ^1.2.0")

	// Range intersection.
	check(rangeLoMax(sv(1, 0, 0), sv(1, 3, 0)) == sv(1, 3, 0), "intersect lo = max")
	check(rangeHiMin(sv(2, 0, 0), sv(3, 0, 0)) == sv(2, 0, 0), "intersect hi = min")
	{
		lo := rangeLoMax(caretLo(sv(1, 0, 0)), caretLo(sv(2, 0, 0)))
		hi := rangeHiMin(caretHi(sv(1, 0, 0)), caretHi(sv(2, 0, 0)))
		check(rangeEmpty(lo, hi), "^1.0.0 and ^2.0.0 are disjoint")
	}

	cVers := setupC()

	// best_match over available C versions.
	check(bestMatch(cVers, caretLo(sv(1, 0, 0)), caretHi(sv(1, 0, 0))) == sv(1, 5, 0), "highest C in ^1.0.0 = 1.5.0")
	check(bestMatch(cVers, caretLo(sv(3, 0, 0)), caretHi(sv(3, 0, 0))) == -1, "no C in ^3.0.0")

	// Diamond resolution — compatible and conflicting.
	check(resolveShared(cVers, sv(1, 0, 0), sv(1, 0, 0)) == sv(1, 5, 0), "A^1 ∩ B^1 picks C 1.5.0")
	check(resolveShared(cVers, sv(1, 0, 0), sv(2, 0, 0)) == -1, "A^1 vs B^2 is unresolvable")

	// Bounded backtracking.
	// A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
	// The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
	{
		aVers := []int64{sv(1, 1, 0), sv(1, 0, 0)}
		aCreq := []int64{sv(2, 0, 0), sv(1, 0, 0)}
		chosenA, chosenC := resolveBacktrack(cVers, aVers, aCreq, sv(1, 0, 0))
		check(chosenA == sv(1, 0, 0), "backtrack picks A 1.0.0, not 1.1.0")
		check(chosenC == sv(1, 5, 0), "and resolves C to 1.5.0")
	}

	// Cycle detection.
	{
		g := newGraph(2)
		g.addDep(0, 1)
		g.addDep(1, 0)
		check(g.hasCycle(), "A↔B is a dependency cycle")
	}
	{
		g := newGraph(3)
		g.addDep(2, 0)
		g.addDep(2, 1) // app → A, B (diamond, acyclic)
		check(!g.hasCycle(), "diamond graph is acyclic")
	}

	if failCount > 0 {
		fmt.Printf("%d passed, %d failed\n", passCount, failCount)
		os.Exit(1)
	}
	fmt.Println("All package_resolution examples passed.")
}
