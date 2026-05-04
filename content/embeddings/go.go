// Vidya — Embeddings and Vector Search — Go port. Q15 fixed-point.

package main

import (
	"fmt"
	"os"
)

const (
	SCALE    = 15
	ONE      = 32768
	DIM      = 4
	N_CORPUS = 4
)

func qMul(a, b int64) int64 {
	p := a * b
	if p < 0 {
		return -((-p) >> SCALE)
	}
	return p >> SCALE
}

var CORPUS = [N_CORPUS][DIM]int64{
	{32767, 0, 0, 0},
	{0, 32767, 0, 0},
	{16384, 16384, 16384, 16384},
	{-32767, 0, 0, 0},
}

func dot(a, b []int64) int64 {
	var acc int64
	for i := range a {
		acc += qMul(a[i], b[i])
	}
	return acc
}

func corpusSim(query []int64, idx int) int64 {
	return dot(query, CORPUS[idx][:])
}

func nearest(query []int64) int {
	bestIdx := 0
	bestSim := corpusSim(query, 0)
	for i := 1; i < N_CORPUS; i++ {
		s := corpusSim(query, i)
		if s > bestSim {
			bestSim = s
			bestIdx = i
		}
	}
	return bestIdx
}

func topKNeighbors(query []int64, k int) []int {
	marks := make([]bool, N_CORPUS)
	out := []int{}
	for len(out) < k {
		bestIdx := -1
		var bestSim int64
		first := true
		for j := 0; j < N_CORPUS; j++ {
			if !marks[j] {
				s := corpusSim(query, j)
				if first {
					bestIdx, bestSim, first = j, s, false
				} else if s > bestSim {
					bestIdx, bestSim = j, s
				}
			}
		}
		if bestIdx < 0 {
			return out
		}
		marks[bestIdx] = true
		out = append(out, bestIdx)
	}
	return out
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

func intsEq(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func main() {
	for i := 0; i < N_CORPUS; i++ {
		s := corpusSim(CORPUS[i][:], i)
		check(s >= 32760, fmt.Sprintf("v%d self-sim ≈ ONE", i))
	}

	check(corpusSim(CORPUS[0][:], 1) == 0, "v0·v1 = 0")
	{
		s := corpusSim(CORPUS[0][:], 3)
		check(s >= -ONE && s <= -32760, "v0·v3 ≈ -ONE")
	}
	check(corpusSim(CORPUS[2][:], 2) == ONE, "v2 self-sim = ONE")
	{
		s := corpusSim(CORPUS[0][:], 2)
		check(s >= 16380 && s <= 16384, "v0·v2 ≈ 0.5")
	}
	check(dot(CORPUS[0][:], CORPUS[2][:]) == dot(CORPUS[2][:], CORPUS[0][:]), "dot symmetric")

	check(nearest([]int64{29490, 0, 0, 0}) == 0, "near-x → v0")
	check(nearest([]int64{0, 32767, 0, 0}) == 1, "y-axis → v1")
	check(nearest([]int64{16384, 16384, 16384, 16384}) == 2, "diagonal → v2")
	check(nearest([]int64{-29490, 0, 0, 0}) == 3, "negative-x → v3")

	check(intsEq(topKNeighbors([]int64{32767, 0, 0, 0}, 3), []int{0, 2, 1}), "top-3 ranked")
	check(len(topKNeighbors([]int64{32767, 0, 0, 0}, 10)) == 4, "top_k caps at corpus size")

	{
		q := []int64{29490, 0, 0, 0}
		check(nearest(q) == nearest(q), "deterministic")
	}

	fmt.Println("=== embeddings ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
