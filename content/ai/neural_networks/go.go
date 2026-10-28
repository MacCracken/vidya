// Vidya — Neural Network Forward Pass — Go port. Q15 fixed-point.

package main

import (
	"fmt"
	"os"
)

const (
	SCALE    = 15
	ONE      = 32768
	N_IN     = 2
	N_HIDDEN = 3
	N_OUT    = 2
)

func qMul(a, b int64) int64 {
	p := a * b
	if p < 0 {
		return -((-p) >> SCALE)
	}
	return p >> SCALE
}

// Weight matrix convention: W[j][i] = weight from input i to output j.
// Stored row-major (n_out rows × n_in cols, flat).

var wHidden = [...]int64{
	16384, -16384,
	-16384, 16384,
	16384, 16384,
}
var bHidden = [...]int64{0, 0, 0}

var wOutput = [...]int64{
	16384, 0, 0,
	0, 16384, 0,
}
var bOutput = [...]int64{0, 0}

func dense(W, b, x []int64, nIn, nOut int) []int64 {
	out := make([]int64, nOut)
	for j := 0; j < nOut; j++ {
		acc := b[j]
		for i := 0; i < nIn; i++ {
			acc += qMul(W[j*nIn+i], x[i])
		}
		out[j] = acc
	}
	return out
}

func relu(x []int64) []int64 {
	out := make([]int64, len(x))
	for i, v := range x {
		if v > 0 {
			out[i] = v
		}
	}
	return out
}

func argmax(x []int64) int {
	bestIdx := 0
	bestVal := x[0]
	for i := 1; i < len(x); i++ {
		if x[i] > bestVal {
			bestVal = x[i]
			bestIdx = i
		}
	}
	return bestIdx
}

var lastHidden, lastOutput []int64

func forward(input []int64) int {
	hidden := dense(wHidden[:], bHidden[:], input, N_IN, N_HIDDEN)
	hidden = relu(hidden)
	lastHidden = hidden
	output := dense(wOutput[:], bOutput[:], hidden, N_HIDDEN, N_OUT)
	lastOutput = output
	return argmax(output)
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
	check(qMul(ONE, 100) == 100, "ONE * 100 = 100")
	check(qMul(16384, 16384) == 8192, "0.5 * 0.5 = 0.25")
	check(qMul(-16384, 16384) == -8192, "-0.5 * 0.5 = -0.25")

	{
		W := []int64{16384, 16384, 8192, 24576}
		b := []int64{0, 0}
		x := []int64{32767, 32767}
		y := dense(W, b, x, 2, 2)
		check(y[0] >= 32765 && y[0] <= 32769, "dense y[0] ~= 1.0")
		check(y[1] >= 32765 && y[1] <= 32769, "dense y[1] ~= 1.0")
	}
	{
		W := []int64{0, 0}
		b := []int64{12345}
		x := []int64{32767, 32767}
		y := dense(W, b, x, 2, 1)
		check(y[0] == 12345, "bias passes through")
	}
	{
		out := relu([]int64{-100, 200, -300, 400})
		expected := []int64{0, 200, 0, 400}
		matches := true
		for i := range out {
			if out[i] != expected[i] {
				matches = false
			}
		}
		check(matches, "relu clips negatives")
	}
	check(relu([]int64{0})[0] == 0, "relu(0) = 0")
	check(argmax([]int64{100, 500, 200, 300}) == 1, "argmax picks index 1")
	check(argmax([]int64{100, 500, 500}) == 1, "first-found wins on ties")

	check(forward([]int64{26214, 6553}) == 0, "x=[0.8,0.2] → class 0")
	check(forward([]int64{6553, 26214}) == 1, "x=[0.2,0.8] → class 1")
	check(forward([]int64{32767, 0}) == 0, "x=[1.0,0.0] → class 0")
	check(forward([]int64{0, 32767}) == 1, "x=[0.0,1.0] → class 1")
	{
		forward([]int64{32767, 0})
		check(lastHidden[1] == 0, "relu zeroed hidden[1]")
		check(lastHidden[0] > 0, "hidden[0] passed through")
	}

	fmt.Println("=== neural_networks ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
