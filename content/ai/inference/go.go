// Vidya — LLM Inference (Decoding) — Go port.

package main

import (
	"fmt"
	"math"
	"os"
)

const (
	VocabSize = 8
	TokUnk    = 0
	TokEos    = 1
)

func initBigram() [VocabSize][VocabSize]int64 {
	var b [VocabSize][VocabSize]int64
	b[2][3] = 1000
	b[2][4] = 100
	b[3][6] = 800
	b[3][5] = 200
	b[4][5] = 700
	b[5][1] = 600
	b[6][7] = 900
	b[6][3] = 100
	b[7][1] = 950
	return b
}

var Bigram = initBigram()

func argmaxLogits(logits []int64) int {
	bestIdx := 0
	bestVal := logits[0]
	for i := 1; i < len(logits); i++ {
		if logits[i] > bestVal {
			bestVal = logits[i]
			bestIdx = i
		}
	}
	return bestIdx
}

// LogitNegInf masks a filtered-out token. Logits are unnormalized and can
// be negative, so masking with 0 would let a "removed" token outrank every
// survivor (and softmax gives e^0 = 1, not 0). The concept's own
// good_example passes NEG_INF.
const LogitNegInf = math.MinInt64

func topkFilter(logits []int64, k int) int {
	marks := make([]bool, len(logits))
	picked := 0
	for picked < k {
		bestIdx := -1
		var bestVal int64
		first := true
		for j := 0; j < len(logits); j++ {
			if !marks[j] {
				if first {
					bestIdx, bestVal = j, logits[j]
					first = false
				} else if logits[j] > bestVal {
					bestIdx, bestVal = j, logits[j]
				}
			}
		}
		if bestIdx < 0 {
			return picked
		}
		marks[bestIdx] = true
		picked++
	}
	for m := 0; m < len(logits); m++ {
		if !marks[m] {
			logits[m] = LogitNegInf
		}
	}
	return picked
}

func bigramLogits(prev int) []int64 {
	out := make([]int64, VocabSize)
	for i := 0; i < VocabSize; i++ {
		out[i] = Bigram[prev][i]
	}
	return out
}

func decodeSequence(start, maxLen int) []int {
	output := []int{}
	current := start
	for len(output) < maxLen {
		nextTok := argmaxLogits(bigramLogits(current))
		output = append(output, nextTok)
		if nextTok == TokEos {
			return output
		}
		current = nextTok
	}
	return output
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
	check(argmaxLogits([]int64{100, 500, 200, 300}) == 1, "argmax picks 1")
	check(argmaxLogits([]int64{100, 500, 500}) == 1, "first-found wins")
	check(argmaxLogits([]int64{-100, -50, -200}) == 1, "argmax over negatives")

	{
		l := []int64{10, 50, 30, 20, 40, 5, 60, 25}
		picked := topkFilter(l, 3)
		check(picked == 3, "topk picked 3")
		check(l[6] == 60 && l[1] == 50 && l[4] == 40, "top 3 kept")
		for _, i := range []int{0, 2, 3, 5, 7} {
			check(l[i] == LogitNegInf, fmt.Sprintf("idx %d masked", i))
		}
	}
	{
		l := []int64{1, 2, 3}
		check(topkFilter(l, 3) == 3, "topk(3,3) keeps all")
		check(l[0] == 1 && l[1] == 2 && l[2] == 3, "all preserved")
	}

	{
		// All-negative logits: a masked token must never win argmax.
		l := []int64{-100, -50, -200, -10}
		topkFilter(l, 2)
		check(argmaxLogits(l) == 3, "masked tokens never win argmax")
	}

	check(argmaxLogits(bigramLogits(2)) == 3, "after hello → world")

	check(intsEq(decodeSequence(2, 10), []int{3, 6, 7, 1}), "hello → world,the,end,EOS")
	check(intsEq(decodeSequence(5, 10), []int{1}), "bar → EOS")
	check(intsEq(decodeSequence(2, 2), []int{3, 6}), "capped at 2")
	// Greedy decoding is deterministic because argmax has a fixed
	// tie-break (first index wins), not because two calls of a pure
	// function agree. UNK's row is all zeros, so every step ties and picks
	// token 0 again: greedy decoding stuck repeating until the length cap.
	check(intsEq(decodeSequence(TokUnk, 3), []int{TokUnk, TokUnk, TokUnk}), "all-tie row → deterministic repeat, capped")

	fmt.Println("=== inference ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
