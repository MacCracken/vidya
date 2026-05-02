// Vidya — Projectile Physics in Go
//
// Semi-implicit Euler integration in 16.16 fixed-point on int64.
// Go's `>>` on signed integers is arithmetic (sign-extending), and
// integer overflow wraps silently — the bounce intermediate
// (vy * RESTITUTION ≈ 3.6e10 worst case) fits in int64 with room to
// spare. No bigint or __int128 needed; plain int64 arithmetic carries
// the day at the cost of being implicit about wraparound.

package main

import "fmt"

const (
	FxShift     = 16
	Gravity     = int64(6554)     // 0.1 per frame
	FloorY      = int64(14745600) // 225.0
	Restitution = int64(45875)    // 0.7 in 16.16
)

type Ball struct {
	x, y, vx, vy int64
}

func physicsStep(b *Ball) {
	// Semi-implicit Euler: velocity first, then position.
	b.vy += Gravity
	b.y += b.vy
	b.x += b.vx
}

func bounceCheck(b *Ball) {
	if b.y > FloorY {
		b.y = FloorY
		// vy = -(vy * restitution) >> 16
		b.vy = -((b.vy * Restitution) >> FxShift)
	}
}

// ── Tests ─────────────────────────────────────────────────────────────

func mustEq(got, want int64, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %d, want %d", msg, got, want))
	}
}

func mustTrue(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func testGravity() {
	b := Ball{0, 0, 0, 0}
	physicsStep(&b)
	mustEq(b.vy, Gravity, "vy == gravity after 1 step")
	mustEq(b.y, Gravity, "y == gravity after 1 step (semi-implicit)")
}

func testParabolicArc() {
	b := Ball{0, 6553600, 0, -1310720} // y=100.0, vy=-20.0
	initialY := b.y

	for i := 0; i < 50; i++ {
		physicsStep(&b)
	}
	mustTrue(b.y < initialY, "ball rises in first 50 frames")

	for i := 0; i < 400; i++ {
		physicsStep(&b)
	}
	mustTrue(b.y > initialY, "ball falls below start after 450 frames")
}

func testBounce() {
	b := Ball{0, FloorY + 1, 0, 655360} // vy=10.0 down, past floor
	bounceCheck(&b)
	mustTrue(b.vy < 0, "vy is negative after bounce")
	mustTrue(-b.vy < 655360, "bounce reduces velocity magnitude")
	mustEq(b.y, FloorY, "position reset to floor on bounce")
}

func testHorizontalUnchanged() {
	vxInitial := int64(131072) // 2.0
	b := Ball{0, 0, vxInitial, 0}
	physicsStep(&b)
	physicsStep(&b)
	physicsStep(&b)
	mustEq(b.vx, vxInitial, "vx unchanged after 3 frames of gravity")
	mustEq(b.x, 3*vxInitial, "x = 3 * vx after 3 frames")
}

func testEnergyDecay() {
	b := Ball{0, 0, 0, 655360} // vy=10.0 down

	// 1000 frames — |vy| plateaus around 2700, well under 2*GRAVITY=13108.
	for i := 0; i < 1000; i++ {
		physicsStep(&b)
		bounceCheck(&b)
	}

	absVy := b.vy
	if absVy < 0 {
		absVy = -absVy
	}
	mustTrue(absVy < Gravity*2, "vy near zero after 1000 bouncing frames")
}

func testSemiImplicitStability() {
	startY := FloorY - 655360               // 10.0 above floor
	b := Ball{0, startY, 0, -655360}        // vy=-10.0 upward
	minY := startY

	for i := 0; i < 500; i++ {
		physicsStep(&b)
		bounceCheck(&b)
		if b.y < minY {
			minY = b.y
		}
	}

	maxRise := int64(1000) * 65536
	mustTrue(minY > startY-maxRise, "semi-implicit euler does not explode")
}

func main() {
	testGravity()
	testParabolicArc()
	testBounce()
	testHorizontalUnchanged()
	testEnergyDecay()
	testSemiImplicitStability()
	fmt.Println("All projectile_physics examples passed.")
}
