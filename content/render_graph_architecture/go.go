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
	culled    [PassCap]bool
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

// TopoSort schedules the live (non-culled) passes; a culled pass must not
// run, so it is not part of the order at all.
func (g *Graph) TopoSort() int {
	var inDegree [PassCap]int
	live := 0
	for i := 0; i < g.count; i++ {
		if g.culled[i] {
			inDegree[i] = -1 // never picked
			continue
		}
		live++
		for j := 0; j < g.count; j++ {
			if i != j && !g.culled[j] && g.hasEdge(j, i) {
				inDegree[i]++
			}
		}
	}
	g.topoLen = 0
	emitted := 0
	for emitted < live {
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

// CullDead removes passes whose outputs no live pass reads (a pass that
// writes nothing is a sink — present, readback — and is kept). It repeats
// until nothing changes: culling a reader can leave its producer dead too,
// so one sweep misses chains like A -> B -> (nobody).
func (g *Graph) CullDead() int {
	culled := 0
	for changed := true; changed; {
		changed = false
		for i := 0; i < g.count; i++ {
			w := g.writes[i]
			if g.culled[i] || w == 0 {
				continue
			}
			anyReader := false
			for j := 0; j < g.count; j++ {
				if i != j && !g.culled[j] && w&g.reads[j] != 0 {
					anyReader = true
					break
				}
			}
			if !anyReader {
				g.culled[i] = true
				g.writes[i] = 0
				g.reads[i] = 0
				culled++
				changed = true
			}
		}
	}
	return culled
}

func eq(got, want int, label string) {
	checks++
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

// checks counts the assertions this file runs, for the final tally.
var checks int

func check(cond bool, label string) {
	checks++
	if !cond {
		panic(label)
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
	check(g.writes[3] == 0, "writes zeroed")
	eq(g.TopoSort(), 3, "culled pass is not scheduled")
	eq(g.BarrierCount(), 2, "barriers post-cull")

	// Dead chain: A feeds only B, B's output is unread. Both go.
	var g3 Graph
	g3.AddPass(300, 0, 1) // A
	g3.AddPass(301, 1, 8) // B
	g3.AddPass(302, 2, 0) // sink, independent
	eq(g3.CullDead(), 2, "cull follows the chain back to A")
	eq(g3.TopoSort(), 1, "only the sink runs")

	var g2 Graph
	g2.AddPass(200, 1, 2)
	g2.AddPass(201, 2, 1)
	eq(g2.TopoSort(), 0, "cycle")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("render_graph_architecture: %d/%d ok\n", checks, checks)
}
