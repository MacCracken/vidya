// Vidya — Game Loop Architecture in Go
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loopStep` takes an elapsed-microsecond delta and returns the number
// of fixed-step updates fired this frame. Go's `int64` matches the
// other ports' wrap behavior (~292 years for microsecond ticks). A
// production loop would source deltas from time.Now().UnixNano(); the
// tests below use deterministic deltas for reproducibility.

package main

import "fmt"

const (
	DTUS     int64 = 16667
	MaxAccum int64 = 5 * DTUS // 83335
)

type GameLoop struct {
	Accum       int64
	UpdateCount int64
	RenderCount int64
}

func loopStep(g *GameLoop, elapsedUs int64) int64 {
	accum := g.Accum + elapsedUs
	// Spiral-of-death cap: never let the accumulator exceed MaxAccum.
	if accum > MaxAccum {
		accum = MaxAccum
	}
	var updates int64 = 0
	for accum >= DTUS {
		accum -= DTUS
		updates++
	}
	g.Accum = accum
	g.UpdateCount += updates
	g.RenderCount++
	return updates
}

func mustEq[T comparable](got, want T, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %v, want %v", msg, got, want))
	}
}

func mustTrue(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func testExactDtFiresOneUpdate() {
	g := GameLoop{}
	u := loopStep(&g, DTUS)
	mustEq(u, int64(1), "exactly one update per dt")
	mustEq(g.UpdateCount, int64(1), "update_count = 1")
}

func testUnderDtNoUpdate() {
	g := GameLoop{}
	u := loopStep(&g, DTUS/2)
	mustEq(u, int64(0), "no update when elapsed < dt")
}

func testCatchup50ms() {
	g := GameLoop{}
	u := loopStep(&g, 50000)
	mustEq(u, int64(2), "50ms produces 2 fixed-step updates")
}

func testSpiralOfDeathCap() {
	g := GameLoop{}
	u := loopStep(&g, 1000000)
	mustEq(u, int64(5), "spiral cap: exactly 5 updates per call")
}

func testRenderPerFrame() {
	g := GameLoop{}
	loopStep(&g, DTUS)
	loopStep(&g, DTUS)
	loopStep(&g, DTUS)
	mustEq(g.RenderCount, int64(3), "3 renders for 3 frames")
	mustEq(g.UpdateCount, int64(3), "3 updates total")
}

func testAccumulatorRemainder() {
	g := GameLoop{}
	oneAndHalf := DTUS + DTUS/2
	loopStep(&g, oneAndHalf)
	mustTrue(g.Accum > DTUS/4, "remainder is positive")
	mustTrue(g.Accum < DTUS, "remainder < full dt")
}

func testInputUpdateRenderSeparation() {
	g := GameLoop{}
	loopStep(&g, 30000)
	loopStep(&g, 5000)
	loopStep(&g, 30000)
	mustEq(g.UpdateCount, int64(3), "3 updates from 65ms total")
	mustEq(g.RenderCount, int64(3), "3 renders from 3 frames")
}

func main() {
	testExactDtFiresOneUpdate()
	testUnderDtNoUpdate()
	testCatchup50ms()
	testSpiralOfDeathCap()
	testRenderPerFrame()
	testAccumulatorRemainder()
	testInputUpdateRenderSeparation()
	fmt.Println("All game_loop_architecture examples passed.")
}
