// Vidya — Grid Pathfinding in Go
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
// Go uses a fixed-size [64]byte for the grid, a slice as the BFS
// frontier (`q[0]` / `q = q[1:]` is fine for 64 cells), and the
// standard-library `container/heap` for A*'s open set as a binary
// min-heap of (f, idx). Manhattan distance is the heuristic.

package main

import (
	"container/heap"
	"fmt"
	"math"
)

const (
	GW = 8
	GH = 8
	GN = GW * GH
)

func idx(x, y int) int { return y*GW + x }

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func manhattan(ax, ay, bx, by int) int { return abs(ax-bx) + abs(ay-by) }

func neighbours(curr int, out *[4]int) int {
	cx, cy := curr%GW, curr/GW
	n := 0
	if cy > 0 {
		out[n] = curr - GW
		n++
	}
	if cy < GH-1 {
		out[n] = curr + GW
		n++
	}
	if cx > 0 {
		out[n] = curr - 1
		n++
	}
	if cx < GW-1 {
		out[n] = curr + 1
		n++
	}
	return n
}

func gridClear() *[GN]byte { return &[GN]byte{} }
func gridBlock(g *[GN]byte, x, y int) { g[idx(x, y)] = 1 }

func bfs(grid *[GN]byte, start, goal int) int64 {
	if start == goal {
		return 0
	}
	var visited [GN]bool
	var dist [GN]int64
	for i := range dist {
		dist[i] = -1
	}
	q := make([]int, 0, GN)
	q = append(q, start)
	visited[start] = true
	dist[start] = 0
	var nb [4]int
	for len(q) > 0 {
		curr := q[0]
		q = q[1:]
		if curr == goal {
			return dist[curr]
		}
		nc := neighbours(curr, &nb)
		for i := 0; i < nc; i++ {
			n := nb[i]
			if !visited[n] && grid[n] == 0 {
				visited[n] = true
				dist[n] = dist[curr] + 1
				q = append(q, n)
			}
		}
	}
	return -1
}

// --- A* min-heap over (f, cell) ---

type item struct {
	f, cell int64
}
type minHeap []item

func (h minHeap) Len() int            { return len(h) }
func (h minHeap) Less(i, j int) bool  { return h[i].f < h[j].f }
func (h minHeap) Swap(i, j int)       { h[i], h[j] = h[j], h[i] }
func (h *minHeap) Push(x interface{}) { *h = append(*h, x.(item)) }
func (h *minHeap) Pop() interface{} {
	old := *h
	n := len(old)
	x := old[n-1]
	*h = old[:n-1]
	return x
}

func astar(grid *[GN]byte, sx, sy, gx, gy int) int64 {
	start, goal := idx(sx, sy), idx(gx, gy)
	var g_score [GN]int64
	var closed [GN]bool
	for i := range g_score {
		g_score[i] = math.MaxInt64
	}
	g_score[start] = 0

	open := &minHeap{}
	heap.Init(open)
	heap.Push(open, item{f: int64(manhattan(sx, sy, gx, gy)), cell: int64(start)})

	var nb [4]int
	for open.Len() > 0 {
		it := heap.Pop(open).(item)
		curr := int(it.cell)
		if curr == goal {
			return g_score[goal]
		}
		if closed[curr] {
			continue
		}
		closed[curr] = true
		tg := g_score[curr] + 1
		nc := neighbours(curr, &nb)
		for i := 0; i < nc; i++ {
			n := nb[i]
			if closed[n] || grid[n] != 0 {
				continue
			}
			if tg < g_score[n] {
				g_score[n] = tg
				nx, ny := n%GW, n/GW
				f := tg + int64(manhattan(nx, ny, gx, gy))
				heap.Push(open, item{f: f, cell: int64(n)})
			}
		}
	}
	return -1
}

// --- Tests ---

func mustEq(got, want int64, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %d, want %d", msg, got, want))
	}
}

func main() {
	// manhattan
	mustEq(int64(manhattan(0, 0, 0, 0)), 0, "m(0,0,0,0)")
	mustEq(int64(manhattan(0, 0, 3, 4)), 7, "m(0,0,3,4)")
	mustEq(int64(manhattan(7, 7, 0, 0)), 14, "m(7,7,0,0)")
	mustEq(int64(manhattan(2, 5, 5, 2)), 6, "m(2,5,5,2)")

	// bfs empty
	g := gridClear()
	mustEq(bfs(g, idx(0, 0), idx(7, 7)), 14, "bfs empty 14")

	// bfs same
	g = gridClear()
	mustEq(bfs(g, idx(3, 3), idx(3, 3)), 0, "bfs same 0")

	// bfs around wall
	g = gridClear()
	for y := 0; y < 7; y++ {
		gridBlock(g, 4, y)
	}
	mustEq(bfs(g, idx(0, 0), idx(7, 0)), 21, "bfs around wall 21")

	// bfs unreachable
	g = gridClear()
	gridBlock(g, 6, 7)
	gridBlock(g, 7, 6)
	mustEq(bfs(g, idx(0, 0), idx(7, 7)), -1, "bfs unreachable -1")

	// astar empty
	g = gridClear()
	mustEq(astar(g, 0, 0, 7, 7), 14, "astar empty 14")

	// astar matches bfs around wall
	g = gridClear()
	for y := 0; y < 7; y++ {
		gridBlock(g, 4, y)
	}
	bfsLen := bfs(g, idx(0, 0), idx(7, 0))
	astarLen := astar(g, 0, 0, 7, 0)
	mustEq(astarLen, bfsLen, "astar == bfs (wall)")
	mustEq(astarLen, 21, "astar wall 21")

	// astar unreachable
	g = gridClear()
	gridBlock(g, 6, 7)
	gridBlock(g, 7, 6)
	mustEq(astar(g, 0, 0, 7, 7), -1, "astar unreachable -1")

	fmt.Println("All grid_pathfinding examples passed.")
}
