// Vidya — 2D Collision Detection in Go
//
// All coordinates in 16.16 fixed-point on int64. Squared-distance
// comparisons avoid sqrt. The Cyrius reference pre-shifts deltas by
// 4 to keep the squared sum inside an i64 — we mirror that pattern.
// Go has no operator overloading and no implicit numeric conversions,
// so every shift and clamp is spelled out. Integer overflow wraps
// silently — use math/big if you need true 128-bit intermediates.

package main

import "fmt"

const (
	FxShift = 16
	FxOne   = int64(1) << FxShift
)

func fx(n int64) int64 { return n << FxShift }

func distSq(x1, y1, x2, y2 int64) int64 {
	dx := (x2 - x1) >> 4
	dy := (y2 - y1) >> 4
	return dx*dx + dy*dy
}

func circleCircle(x1, y1, r1, x2, y2, r2 int64) bool {
	d2 := distSq(x1, y1, x2, y2)
	sumR := (r1 + r2) >> 4
	return d2 <= sumR*sumR
}

func aabbOverlap(l1, t1, r1, b1, l2, t2, r2, b2 int64) bool {
	if l1 >= r2 {
		return false
	}
	if r1 <= l2 {
		return false
	}
	if t1 >= b2 {
		return false
	}
	if b1 <= t2 {
		return false
	}
	return true
}

func pointInRect(px, py, left, top, right, bottom int64) bool {
	return px >= left && px < right && py >= top && py < bottom
}

func clampI64(v, lo, hi int64) int64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func circleAabb(cx, cy, cr, left, top, right, bottom int64) bool {
	cxc := clampI64(cx, left, right)
	cyc := clampI64(cy, top, bottom)
	d2 := distSq(cx, cy, cxc, cyc)
	r := cr >> 4
	return d2 <= r*r
}

func pointInCircle(px, py, cx, cy, cr int64) bool {
	d2 := distSq(px, py, cx, cy)
	r := cr >> 4
	return d2 <= r*r
}

func pushApartX(x1, x2, overlap int64) int64 {
	dx := x2 - x1
	half := overlap >> 1
	if dx > 0 {
		return -half
	}
	return half
}

func absI64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

func sweptAabbX(al, ar, vx, bl, br int64) int64 {
	if vx == 0 {
		return FxOne
	}
	var enterDist, exitDist int64
	if vx > 0 {
		enterDist, exitDist = bl-ar, br-al
	} else {
		enterDist, exitDist = br-al, bl-ar
	}
	absV := absI64(vx)
	enter := (absI64(enterDist) << FxShift) / absV
	exit_ := (absI64(exitDist) << FxShift) / absV
	if enter > exit_ || enter > FxOne {
		return FxOne
	}
	return enter
}

// ── Tests ─────────────────────────────────────────────────────────────

func mustTrue(b bool, msg string) {
	if !b {
		panic("FAIL: " + msg)
	}
}

func mustFalse(b bool, msg string) {
	if b {
		panic("FAIL: " + msg)
	}
}

func main() {
	mustTrue(circleCircle(fx(10), fx(10), fx(5), fx(13), fx(10), fx(5)),
		"overlapping circles")
	mustFalse(circleCircle(fx(0), fx(0), fx(1), fx(100), fx(100), fx(1)),
		"distant circles")
	mustTrue(circleCircle(fx(0), fx(0), fx(5), fx(10), fx(0), fx(5)),
		"touching circles")

	mustTrue(aabbOverlap(fx(0), fx(0), fx(10), fx(10),
		fx(5), fx(5), fx(15), fx(15)), "overlapping AABBs")
	mustFalse(aabbOverlap(fx(0), fx(0), fx(5), fx(5),
		fx(10), fx(10), fx(20), fx(20)), "separated AABBs")
	mustFalse(aabbOverlap(fx(0), fx(0), fx(10), fx(10),
		fx(10), fx(0), fx(20), fx(10)), "edge-adjacent AABBs")

	mustTrue(pointInRect(fx(5), fx(5), fx(0), fx(0), fx(10), fx(10)), "inside")
	mustFalse(pointInRect(fx(15), fx(5), fx(0), fx(0), fx(10), fx(10)), "outside")
	mustTrue(pointInRect(fx(0), fx(5), fx(0), fx(0), fx(10), fx(10)), "left edge")
	mustFalse(pointInRect(fx(10), fx(5), fx(0), fx(0), fx(10), fx(10)), "right edge")

	mustTrue(circleAabb(fx(5), fx(5), fx(3), fx(0), fx(0), fx(10), fx(10)),
		"circle inside AABB")
	mustFalse(circleAabb(fx(20), fx(20), fx(3), fx(0), fx(0), fx(10), fx(10)),
		"circle far from AABB")

	mustTrue(pointInCircle(fx(1), fx(1), fx(0), fx(0), fx(5)),
		"point inside circle")
	mustFalse(pointInCircle(fx(100), fx(100), fx(0), fx(0), fx(5)),
		"point outside circle")

	if distSq(fx(0), fx(0), fx(3), fx(4)) <= 0 {
		panic("FAIL: 3-4-5 triangle dist²")
	}

	if pushApartX(fx(0), fx(4), fx(2)) >= 0 {
		panic("FAIL: push-apart direction")
	}

	toi := sweptAabbX(fx(0), fx(2), fx(8), fx(6), fx(10))
	if toi <= 0 || toi >= FxOne {
		panic("FAIL: swept AABB TOI")
	}
	toi2 := sweptAabbX(fx(0), fx(2), -fx(1), fx(6), fx(10))
	if toi2 != FxOne {
		panic("FAIL: moving away yields no impact")
	}

	fmt.Println("All collision_detection_2d examples passed.")
}
