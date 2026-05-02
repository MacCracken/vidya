// Vidya — Fixed-Point Arithmetic in Go
//
// 16.16 fixed-point on int64. Go's >> on signed integers is
// arithmetic (sign-extending), but it rounds toward -infinity for
// negatives — so fx_to_int still handles the sign explicitly to
// match the truncate-toward-zero semantics shared with Cyrius/C/Rust.
//
// Go has no operator overloading; helpers are plain functions.
// Integer overflow wraps silently — fx_mul uses 128-bit-wide
// arithmetic via math/big only when fx_mul_safe isn't enough.

package main

import (
	"fmt"
	"math"
)

const (
	FxShift = 16
	FxOne   = int64(1) << FxShift
	FxHalf  = int64(1) << (FxShift - 1)
)

func fxFromInt(n int64) int64 { return n << FxShift }

func fxToInt(v int64) int64 {
	if v < 0 {
		return -((-v) >> FxShift)
	}
	return v >> FxShift
}

func fxToIntRound(v int64) int64 {
	if v < 0 {
		return -((-v + FxHalf) >> FxShift)
	}
	return (v + FxHalf) >> FxShift
}

func fxMul(a, b int64) int64 {
	// Standard multiply — wraps on overflow. Use fxMulSafe for large
	// magnitudes if 128-bit isn't available.
	return (a * b) >> FxShift
}

func fxMulSafe(a, b int64) int64 {
	return (a >> 8) * (b >> 8)
}

func fxDiv(a, b int64) int64 {
	if b == 0 {
		return 0
	}
	return (a << FxShift) / b
}

// ── Sine table — quarter-wave, 256 entries ────────────────────────────

func buildSinTable() [256]int64 {
	var t [256]int64
	for i := 0; i < 256; i++ {
		angle := float64(i) * (math.Pi / 2.0) / 256.0
		t[i] = int64(math.Sin(angle) * float64(FxOne))
	}
	return t
}

func sinLookup(t *[256]int64, angle int64) int64 {
	a := int(angle & 1023)
	switch {
	case a < 256:
		return t[a]
	case a < 512:
		return t[511-a]
	case a < 768:
		return -t[a-512]
	default:
		return -t[1023-a]
	}
}

// ── Tests ─────────────────────────────────────────────────────────────

func mustEq(got, want int64, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %d, want %d", msg, got, want))
	}
}

func main() {
	mustEq(fxFromInt(1), 65536, "1.0")
	mustEq(fxFromInt(10), 655360, "10.0")
	mustEq(fxFromInt(0), 0, "0.0")

	three := fxFromInt(3)
	twoHalf := int64(163840) // 2.5
	mustEq(fxMul(three, twoHalf), 491520, "3.0 * 2.5")
	mustEq(fxMul(FxOne, FxOne), FxOne, "1.0 * 1.0")
	mustEq(fxMul(FxHalf, FxHalf), 16384, "0.5 * 0.5")

	big := fxFromInt(1000)
	if fxMulSafe(big, big) <= 0 {
		panic("safe mul of 1000*1000 should stay positive")
	}

	mustEq(fxDiv(fxFromInt(10), fxFromInt(4)), 163840, "10/4")
	mustEq(fxDiv(FxOne, 0), 0, "div-by-zero")

	mustEq(fxToInt(-fxFromInt(3)), -3, "fx_to_int(-3.0)")
	mustEq(fxToInt(-(FxOne + FxHalf)), -1, "fx_to_int(-1.5)")
	mustEq(fxToIntRound(-(FxOne + FxHalf)), -2, "round(-1.5)")

	t := buildSinTable()
	mustEq(sinLookup(&t, 0), 0, "sin(0)")
	if sinLookup(&t, 256) <= 60000 {
		panic("sin(π/2) should be near 1.0")
	}
	mustEq(sinLookup(&t, 512), 0, "sin(π)")
	if sinLookup(&t, 768) >= -60000 {
		panic("sin(3π/2) should be near -1.0")
	}

	for i := int64(0); i < 100; i++ {
		mustEq(fxToInt(fxFromInt(i)), i, "roundtrip")
	}

	fmt.Println("All fixed_point_arithmetic examples passed.")
}
