// Vidya — Audio DSP — Go port. Q15 fixed-point throughout.

package main

import (
	"fmt"
	"os"
)

const (
	SCALE = 15
	ONE   = 32768
	SMAX  = 32767
	SMIN  = -32767
)

func qMul(a, b int64) int64 {
	p := a * b
	if p < 0 {
		return -((-p) >> SCALE)
	}
	return p >> SCALE
}

func absI(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

func clip(s int64) int64 {
	if s > SMAX {
		return SMAX
	}
	if s < SMIN {
		return SMIN
	}
	return s
}

type Biquad struct {
	b0, b1, b2, a1, a2 int64
	x1, x2, y1, y2     int64
}

func (b *Biquad) Set(b0, b1, b2, a1, a2 int64) {
	b.b0, b.b1, b.b2, b.a1, b.a2 = b0, b1, b2, a1, a2
	b.x1, b.x2, b.y1, b.y2 = 0, 0, 0, 0
}

func (b *Biquad) Lowpass1Pole(aQ15 int64) {
	b.Set(aQ15, 0, 0, aQ15-ONE, 0)
}

func (b *Biquad) Step(x int64) int64 {
	y := qMul(b.b0, x) + qMul(b.b1, b.x1) + qMul(b.b2, b.x2) -
		qMul(b.a1, b.y1) - qMul(b.a2, b.y2)
	b.x2, b.x1 = b.x1, x
	b.y2, b.y1 = b.y1, y
	return y
}

func firStep(taps, history []int64, xNew int64) int64 {
	for i := len(history) - 1; i > 0; i-- {
		history[i] = history[i-1]
	}
	history[0] = xNew
	var acc int64
	for j := range taps {
		acc += qMul(taps[j], history[j])
	}
	return acc
}

func peak(buffer []int64) int64 {
	var p int64
	for _, s := range buffer {
		if a := absI(s); a > p {
			p = a
		}
	}
	return p
}

func meanAbsolute(buffer []int64) int64 {
	var sum int64
	for _, s := range buffer {
		sum += absI(s)
	}
	return sum / int64(len(buffer))
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
	check(qMul(ONE/2, ONE/2) == ONE/4, "0.5 * 0.5 = 0.25")
	r := qMul(ONE/2, SMAX)
	check(r >= 16383 && r <= 16384, "0.5 * SMAX in [16383,16384]")

	check(clip(50000) == SMAX, "clip(50000) = SMAX")
	check(clip(-50000) == SMIN, "clip(-50000) = SMIN")
	check(clip(1234) == 1234, "clip(1234) unchanged")

	{
		var b Biquad
		b.Lowpass1Pole(3277)
		for i := 0; i < 200; i++ {
			b.Step(30000)
		}
		check(b.y1 >= 29900 && b.y1 <= 30100, "DC settled near 30000")
	}
	{
		var b Biquad
		b.Lowpass1Pole(3277)
		for i := 0; i < 200; i++ {
			x := int64(20000)
			if i&1 == 1 {
				x = -20000
			}
			b.Step(x)
		}
		check(absI(b.y1) < 2000, "Nyquist heavily attenuated")
	}
	{
		taps := []int64{ONE, 0, 0}
		history := []int64{0, 0, 0}
		check(firStep(taps, history, 1234) == 1234, "identity passes 1234")
		check(firStep(taps, history, 5678) == 5678, "identity passes 5678")
	}
	{
		third := int64(ONE / 3)
		taps := []int64{third, third, third}
		history := []int64{0, 0, 0}
		firStep(taps, history, 9000)
		firStep(taps, history, 9000)
		y := firStep(taps, history, 9000)
		check(y >= 8990 && y <= 9010, "moving avg converges to 9000")
	}
	check(peak([]int64{100, -5000, 200, 3000, -1500}) == 5000, "peak = 5000")
	{
		buf := make([]int64, 8)
		for i := range buf {
			buf[i] = 4000
		}
		check(meanAbsolute(buf) == 4000, "mean-abs constant = constant")
	}
	{
		buf := make([]int64, 8)
		for i := range buf {
			if i&1 == 0 {
				buf[i] = 4000
			} else {
				buf[i] = -4000
			}
		}
		check(meanAbsolute(buf) == 4000, "mean-abs alternating ±4000 = 4000")
	}

	fmt.Println("=== audio_dsp ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
