// Vidya — Bloom and Glow in Go
//
// 1-pixel additive bloom on a 16x16 single-channel intensity buffer.

package main

import "fmt"

const (
	FbW       = 16
	FbH       = 16
	FbSz      = FbW * FbH
	Threshold = 128
	GlowFrac  = 2
)

func fbSet(fb []byte, x, y int, v byte) {
	if x < 0 || x >= FbW || y < 0 || y >= FbH { return }
	fb[y*FbW+x] = v
}

func fbGet(fb []byte, x, y int) byte {
	if x < 0 || x >= FbW || y < 0 || y >= FbH { return 0 }
	return fb[y*FbW+x]
}

func fbAdd(fb []byte, x, y, delta int) {
	if x < 0 || x >= FbW || y < 0 || y >= FbH { return }
	idx := y*FbW + x
	s := int(fb[idx]) + delta
	if s > 255 { s = 255 }
	fb[idx] = byte(s)
}

func applyBloom(src, dst []byte, threshold byte) {
	copy(dst, src)
	for y := 0; y < FbH; y++ {
		for x := 0; x < FbW; x++ {
			v := src[y*FbW+x]
			if v >= threshold {
				glow := int(v) / GlowFrac
				fbAdd(dst, x-1, y, glow)
				fbAdd(dst, x+1, y, glow)
				fbAdd(dst, x, y-1, glow)
				fbAdd(dst, x, y+1, glow)
			}
		}
	}
}

func countLit(fb []byte) int {
	n := 0
	for _, v := range fb {
		if v != 0 { n++ }
	}
	return n
}

func clear(b []byte) { for i := range b { b[i] = 0 } }

func eq(got, want int, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

func main() {
	src := make([]byte, FbSz)
	dst := make([]byte, FbSz)

	applyBloom(src, dst, Threshold)
	eq(countLit(dst), 0, "empty")

	clear(src); fbSet(src, 8, 8, 200)
	applyBloom(src, dst, Threshold)
	eq(int(fbGet(dst, 8, 8)), 200, "src")
	eq(int(fbGet(dst, 7, 8)), 100, "L")
	eq(int(fbGet(dst, 9, 8)), 100, "R")
	eq(int(fbGet(dst, 8, 7)), 100, "U")
	eq(int(fbGet(dst, 8, 9)), 100, "D")
	eq(int(fbGet(dst, 7, 7)), 0, "diag")
	eq(countLit(dst), 5, "single count")

	clear(src); fbSet(src, 8, 8, 200); fbSet(src, 9, 8, 250)
	applyBloom(src, dst, Threshold)
	eq(int(fbGet(dst, 9, 8)), 255, "clamp")
	eq(int(fbGet(dst, 8, 8)), 255, "sum clamp")

	clear(src); fbSet(src, 8, 8, 100)
	applyBloom(src, dst, Threshold)
	eq(int(fbGet(dst, 8, 8)), 100, "dim preserved")
	eq(int(fbGet(dst, 7, 8)), 0, "dim no glow")
	eq(countLit(dst), 1, "dim count")

	clear(src); fbSet(src, 0, 0, 200)
	applyBloom(src, dst, Threshold)
	eq(int(fbGet(dst, 0, 0)), 200, "corner src")
	eq(int(fbGet(dst, 1, 0)), 100, "corner R")
	eq(int(fbGet(dst, 0, 1)), 100, "corner D")
	eq(countLit(dst), 3, "corner count")

	clear(src); fbSet(src, 4, 8, 200); fbSet(src, 6, 8, 200)
	applyBloom(src, dst, Threshold)
	eq(int(fbGet(dst, 5, 8)), 200, "midpoint sum")
	eq(int(fbGet(dst, 3, 8)), 100, "outer L")
	eq(int(fbGet(dst, 7, 8)), 100, "outer R")

	fmt.Println("bloom_and_glow: 20/20 ok")
}
