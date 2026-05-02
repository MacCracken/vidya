// Vidya — Maze Generation in Go
//
// Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell is a
// bitmask of present walls (N=1, S=2, E=4, W=8). Generation carves
// passages by clearing the wall bit on both the current and neighbour
// cell.
//
// Go's `int64` (and `uint64`) wraps silently on overflow — exactly what
// PCG needs for the multiply-add step. No special wrapping helpers
// required, the byte output matches cyrius's signed-i64 wrap.

package main

import (
	"fmt"
	"os"
)

const (
	GW        = 8
	GH        = 8
	GN        = GW * GH
	WN  uint8 = 1
	WS  uint8 = 2
	WE  uint8 = 4
	WW  uint8 = 8
	WallsAll uint8 = 15

	pcgMult uint64 = 6364136223846793005
	pcgInc  uint64 = 1442695040888963407
)

type RNG struct {
	state uint64
}

func newRNG(seed uint64) *RNG { return &RNG{state: seed} }

func (r *RNG) Seed(s uint64) { r.state = s }

// Next returns the next pseudo-random value as a non-negative int64.
// uint64 multiply/add wraps silently — that *is* the modular arithmetic
// PCG expects.
func (r *RNG) Next() int64 {
	r.state = r.state*pcgMult + pcgInc
	return int64((r.state >> 33) & 0x7fffffff)
}

func (r *RNG) Range(max int64) int64 {
	if max <= 0 {
		return 0
	}
	return r.Next() % max
}

func idx(x, y int) int { return y*GW + x }

func opposite(d uint8) uint8 {
	switch d {
	case WN:
		return WS
	case WS:
		return WN
	case WE:
		return WW
	case WW:
		return WE
	}
	return 0
}

type Maze struct {
	cells   [GN]uint8
	visited [GN]bool
}

func NewMaze() *Maze {
	m := &Maze{}
	for i := range m.cells {
		m.cells[i] = WallsAll
	}
	return m
}

func (m *Maze) reset() {
	for i := range m.cells {
		m.cells[i] = WallsAll
		m.visited[i] = false
	}
}

func (m *Maze) carve(x, y int, d uint8, nx, ny int) {
	ci, ni := idx(x, y), idx(nx, ny)
	od := opposite(d)
	// Clear the wall on both cells; otherwise the maze looks half-open.
	m.cells[ci] &^= d
	m.cells[ni] &^= od
}

type neighbour struct {
	dir    uint8
	nx, ny int
}

func (m *Maze) collectUnvisited(x, y int, buf []neighbour) []neighbour {
	buf = buf[:0]
	if y > 0 && !m.visited[idx(x, y-1)] {
		buf = append(buf, neighbour{WN, x, y - 1})
	}
	if y < GH-1 && !m.visited[idx(x, y+1)] {
		buf = append(buf, neighbour{WS, x, y + 1})
	}
	if x > 0 && !m.visited[idx(x-1, y)] {
		buf = append(buf, neighbour{WW, x - 1, y})
	}
	if x < GW-1 && !m.visited[idx(x+1, y)] {
		buf = append(buf, neighbour{WE, x + 1, y})
	}
	return buf
}

func (m *Maze) Generate(rng *RNG, sx, sy int) {
	m.reset()
	stack := make([]int, 0, GN)
	stack = append(stack, idx(sx, sy))
	m.visited[idx(sx, sy)] = true
	buf := make([]neighbour, 0, 4)
	for len(stack) > 0 {
		top := stack[len(stack)-1]
		tx, ty := top%GW, top/GW
		buf = m.collectUnvisited(tx, ty, buf)
		if len(buf) == 0 {
			stack = stack[:len(stack)-1]
		} else {
			pick := int(rng.Range(int64(len(buf))))
			n := buf[pick]
			m.carve(tx, ty, n.dir, n.nx, n.ny)
			m.visited[idx(n.nx, n.ny)] = true
			stack = append(stack, idx(n.nx, n.ny))
		}
	}
}

func (m *Maze) CountVisited() int {
	n := 0
	for _, v := range m.visited {
		if v {
			n++
		}
	}
	return n
}

func (m *Maze) CountRemovedWalls() int {
	removed := 0
	for y := 0; y < GH; y++ {
		for x := 0; x < GW; x++ {
			w := m.cells[idx(x, y)]
			if y > 0 && (w&WN) == 0 {
				removed++
			}
			if x > 0 && (w&WW) == 0 {
				removed++
			}
		}
	}
	return removed
}

func (m *Maze) WallsConsistent() bool {
	for y := 0; y < GH; y++ {
		for x := 0; x < GW; x++ {
			w := m.cells[idx(x, y)]
			if x < GW-1 {
				nw := m.cells[idx(x+1, y)]
				if ((w & WE) == 0) != ((nw & WW) == 0) {
					return false
				}
			}
			if y < GH-1 {
				sw := m.cells[idx(x, y+1)]
				if ((w & WS) == 0) != ((sw & WN) == 0) {
					return false
				}
			}
		}
	}
	return true
}

func check(cond bool, msg string) {
	if !cond {
		fmt.Fprintln(os.Stderr, "FAIL:", msg)
		os.Exit(1)
	}
}

func main() {
	// init state
	m0 := NewMaze()
	check(m0.cells[0] == WallsAll, "init: cell 0")
	check(m0.cells[63] == WallsAll, "init: cell 63")
	check(!m0.visited[0], "init: cell 0 not visited")

	// full coverage
	rng := newRNG(42)
	m := NewMaze()
	m.Generate(rng, 0, 0)
	check(m.CountVisited() == GN, "all 64 cells visited")

	// perfect maze wall count
	rng.Seed(42)
	m.Generate(rng, 0, 0)
	check(m.CountRemovedWalls() == GN-1, "perfect maze: GN-1 walls")

	// wall consistency
	rng.Seed(42)
	m.Generate(rng, 0, 0)
	check(m.WallsConsistent(), "wall pairs consistent")

	// determinism
	rng.Seed(42)
	a := NewMaze()
	a.Generate(rng, 0, 0)
	c0, c27, c63 := a.cells[0], a.cells[27], a.cells[63]

	rng.Seed(42)
	b := NewMaze()
	b.Generate(rng, 0, 0)
	check(b.cells[0] == c0, "deterministic: cell 0")
	check(b.cells[27] == c27, "deterministic: cell 27")
	check(b.cells[63] == c63, "deterministic: cell 63")

	// different seeds differ
	rng.Seed(1)
	x := NewMaze()
	x.Generate(rng, 0, 0)
	sum1 := 0
	for _, v := range x.cells {
		sum1 += int(v)
	}
	rng.Seed(2)
	y := NewMaze()
	y.Generate(rng, 0, 0)
	sum2 := 0
	for _, v := range y.cells {
		sum2 += int(v)
	}
	check(sum1 != sum2, "different seeds produce different mazes")

	// starting cell visited
	rng.Seed(42)
	s := NewMaze()
	s.Generate(rng, 3, 5)
	check(s.visited[idx(3, 5)], "start cell marked visited")
	check(s.CountVisited() == GN, "all cells reachable")

	// cross-language byte parity (matches cyrius reference)
	rng.Seed(42)
	p := NewMaze()
	p.Generate(rng, 0, 0)
	check(p.cells[0] == 13, "parity: cell 0 == 13")
	check(p.cells[27] == 12, "parity: cell 27 == 12")
	check(p.cells[63] == 6, "parity: cell 63 == 6")

	fmt.Println("All maze_generation examples passed.")
}
