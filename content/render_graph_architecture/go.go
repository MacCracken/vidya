// Vidya — Render Graph Architecture in Go
//
// Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

package main

import "fmt"

const PassCap = 16

type Graph struct {
	passID    [PassCap]uint64
	reads     [PassCap]uint64
	writes    [PassCap]uint64
	count     int
	topoOrder [PassCap]int
	topoLen   int
}

func (g *Graph) AddPass(id, r, w uint64) int {
	if g.count >= PassCap {
		return -1
	}
	idx := g.count
	g.passID[idx] = id
	g.reads[idx] = r
	g.writes[idx] = w
	g.count++
	return idx
}

func (g *Graph) hasEdge(p, c int) bool {
	return g.writes[p]&g.reads[c] != 0
}

func (g *Graph) TopoSort() int {
	var inDegree [PassCap]int
	for i := 0; i < g.count; i++ {
		for j := 0; j < g.count; j++ {
			if i != j && g.hasEdge(j, i) {
				inDegree[i]++
			}
		}
	}
	g.topoLen = 0
	emitted := 0
	for emitted < g.count {
		picked := -1
		for k := 0; k < g.count; k++ {
			if inDegree[k] == 0 {
				picked = k
				break
			}
		}
		if picked < 0 {
			return g.topoLen
		}
		g.topoOrder[g.topoLen] = picked
		g.topoLen++
		inDegree[picked] = -1
		for c := 0; c < g.count; c++ {
			if c != picked && g.hasEdge(picked, c) && inDegree[c] > 0 {
				inDegree[c]--
			}
		}
		emitted++
	}
	return g.topoLen
}

func (g *Graph) BarrierCount() int {
	count := 0
	for i := 0; i < g.topoLen; i++ {
		for j := i + 1; j < g.topoLen; j++ {
			if g.hasEdge(g.topoOrder[i], g.topoOrder[j]) {
				count++
			}
		}
	}
	return count
}

func (g *Graph) CullDead() int {
	culled := 0
	for i := 0; i < g.count; i++ {
		w := g.writes[i]
		if w == 0 {
			continue
		}
		anyReader := false
		for j := 0; j < g.count; j++ {
			if i != j && w&g.reads[j] != 0 {
				anyReader = true
				break
			}
		}
		if !anyReader {
			g.writes[i] = 0
			g.reads[i] = 0
			culled++
		}
	}
	return culled
}

func eq(got, want int, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

func main() {
	var g Graph

	eq(g.AddPass(100, 0, 1), 0, "a")
	eq(g.AddPass(101, 1, 2), 1, "b")
	eq(g.AddPass(102, 2, 0), 2, "c")

	eq(g.TopoSort(), 3, "topo3")
	eq(g.topoOrder[0], 0, "topo[0]")
	eq(g.topoOrder[1], 1, "topo[1]")
	eq(g.topoOrder[2], 2, "topo[2]")

	eq(g.BarrierCount(), 2, "barriers")

	eq(g.AddPass(103, 0, 4), 3, "d")
	eq(g.CullDead(), 1, "cull")
	if g.writes[3] != 0 {
		panic("writes zeroed")
	}
	eq(g.TopoSort(), 4, "topo4")
	eq(g.BarrierCount(), 2, "barriers post-cull")

	var g2 Graph
	g2.AddPass(200, 1, 2)
	g2.AddPass(201, 2, 1)
	eq(g2.TopoSort(), 0, "cycle")

	fmt.Println("render_graph_architecture: 14/14 ok")
}
