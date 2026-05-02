// Vidya — Line Rasterization (Bresenham) in Go
//
// All-octant integer Bresenham on a 16x16 byte framebuffer.

package main

import "fmt"

const (
	FbW   = 16
	FbH   = 16
	FbSz  = FbW * FbH
)

var fb [FbSz]byte

func fbClear() {
	for i := range fb {
		fb[i] = 0
	}
}

func fbSet(x, y int, v byte) {
	if x < 0 || x >= FbW || y < 0 || y >= FbH {
		return
	}
	fb[y*FbW+x] = v
}

func fbGet(x, y int) byte {
	if x < 0 || x >= FbW || y < 0 || y >= FbH {
		return 0
	}
	return fb[y*FbW+x]
}

func countLit() int {
	n := 0
	for _, v := range fb {
		if v != 0 {
			n++
		}
	}
	return n
}

func iabs(v int) int { if v < 0 { return -v }; return v }
func sign(v int) int { if v > 0 { return 1 }; if v < 0 { return -1 }; return 0 }

func drawLine(x0, y0, x1, y1 int, v byte) {
	dx, dy := iabs(x1-x0), iabs(y1-y0)
	sx, sy := sign(x1-x0), sign(y1-y0)
	err := dx - dy
	x, y := x0, y0
	for {
		fbSet(x, y, v)
		if x == x1 && y == y1 {
			return
		}
		e2 := err * 2
		if e2 > -dy { err -= dy; x += sx }
		if e2 < dx  { err += dx; y += sy }
	}
}

func eq(got, want int, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

func main() {
	fbClear(); drawLine(2, 5, 8, 5, 1)
	eq(countLit(), 7, "h count")
	eq(int(fbGet(2, 5)), 1, "h L")
	eq(int(fbGet(8, 5)), 1, "h R")
	eq(int(fbGet(5, 5)), 1, "h M")
	eq(int(fbGet(5, 6)), 0, "h off")

	fbClear(); drawLine(5, 2, 5, 8, 1)
	eq(countLit(), 7, "v count")
	eq(int(fbGet(5, 2)), 1, "v T")
	eq(int(fbGet(5, 8)), 1, "v B")
	eq(int(fbGet(5, 5)), 1, "v M")
	eq(int(fbGet(6, 5)), 0, "v off")

	fbClear(); drawLine(2, 2, 7, 7, 1)
	eq(countLit(), 6, "+d count")
	eq(int(fbGet(2, 2)), 1, "+d S")
	eq(int(fbGet(7, 7)), 1, "+d E")
	eq(int(fbGet(5, 5)), 1, "+d M")
	eq(int(fbGet(5, 4)), 0, "+d off")

	fbClear(); drawLine(2, 7, 7, 2, 1)
	eq(countLit(), 6, "-d count")
	eq(int(fbGet(2, 7)), 1, "-d S")
	eq(int(fbGet(7, 2)), 1, "-d E")
	eq(int(fbGet(5, 4)), 1, "-d M")

	fbClear(); drawLine(3, 1, 5, 11, 1)
	eq(countLit(), 11, "steep count")
	eq(int(fbGet(3, 1)), 1, "steep S")
	eq(int(fbGet(5, 11)), 1, "steep E")

	fbClear(); drawLine(8, 8, 8, 8, 1)
	eq(countLit(), 1, "point count")
	eq(int(fbGet(8, 8)), 1, "point lit")

	fbClear(); drawLine(8, 5, 2, 5, 1)
	eq(countLit(), 7, "rev count")
	eq(int(fbGet(2, 5)), 1, "rev L")
	eq(int(fbGet(8, 5)), 1, "rev R")

	fmt.Println("line_rasterization: 27/27 ok")
}
