// Vidya — Distributed Systems Foundations — Go port.

package main

import (
	"fmt"
	"os"
)

const (
	NNodes = 3
	W      = 2
	R      = 2
)

const (
	VCLess       = 1
	VCEqual      = 2
	VCGreater    = 3
	VCConcurrent = 4
)

type VClock [NNodes]int64

func (v *VClock) Tick(node int)       { v[node]++ }
func (v *VClock) Merge(from *VClock) {
	for i := 0; i < NNodes; i++ {
		if from[i] > v[i] {
			v[i] = from[i]
		}
	}
}

func vcCompare(a, b *VClock) int {
	anyLT, anyGT := false, false
	for i := 0; i < NNodes; i++ {
		if a[i] < b[i] {
			anyLT = true
		}
		if a[i] > b[i] {
			anyGT = true
		}
	}
	switch {
	case !anyLT && !anyGT:
		return VCEqual
	case !anyLT:
		return VCGreater
	case !anyGT:
		return VCLess
	default:
		return VCConcurrent
	}
}

type QCluster struct {
	accounts  [NNodes]int64
	writeSeq  [NNodes]int64
	alive     [NNodes]int
	globalSeq int64
}

func NewQCluster() *QCluster {
	c := &QCluster{}
	for i := 0; i < NNodes; i++ {
		c.alive[i] = 1
	}
	return c
}

func (c *QCluster) Partition(n int) { c.alive[n] = 0 }
func (c *QCluster) Heal(n int)      { c.alive[n] = 1 }
func (c *QCluster) AliveCount() int {
	n := 0
	for i := 0; i < NNodes; i++ {
		n += c.alive[i]
	}
	return n
}

func (c *QCluster) Write(value int64) int {
	if c.AliveCount() < W {
		return 0
	}
	c.globalSeq++
	for i := 0; i < NNodes; i++ {
		if c.alive[i] == 1 {
			c.accounts[i] = value
			c.writeSeq[i] = c.globalSeq
		}
	}
	return 1
}

func (c *QCluster) Read() int64 {
	if c.AliveCount() < R {
		return -1
	}
	var bestSeq, bestValue int64
	for i := 0; i < NNodes; i++ {
		if c.alive[i] == 1 && c.writeSeq[i] > bestSeq {
			bestSeq = c.writeSeq[i]
			bestValue = c.accounts[i]
		}
	}
	return bestValue
}

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func main() {
	{
		var v VClock
		check(v == VClock{0, 0, 0}, "vc init zero")
	}
	{
		var v VClock
		v.Tick(1); v.Tick(1); v.Tick(2)
		check(v == VClock{0, 2, 1}, "tick")
	}
	{
		var a, b VClock
		a.Tick(0); a.Tick(0)
		b.Tick(1); b.Tick(2)
		a.Merge(&b)
		check(a == VClock{2, 1, 1}, "merge max")
	}
	{
		var a, b VClock
		b.Tick(0)
		check(vcCompare(&a, &b) == VCLess, "less")
	}
	{
		var a, b VClock
		a.Tick(0); a.Tick(0); b.Tick(0)
		check(vcCompare(&a, &b) == VCGreater, "greater")
	}
	{
		var a, b VClock
		a.Tick(1); b.Tick(1)
		check(vcCompare(&a, &b) == VCEqual, "equal")
	}
	{
		var a, b VClock
		a.Tick(0); b.Tick(1)
		check(vcCompare(&a, &b) == VCConcurrent, "concurrent")
		check(vcCompare(&b, &a) == VCConcurrent, "concurrent symmetric")
	}
	{
		c := NewQCluster()
		check(c.Write(100) == 1, "write ok full")
		check(c.accounts == [NNodes]int64{100, 100, 100}, "all wrote")
	}
	{
		c := NewQCluster()
		c.Partition(2)
		check(c.Write(200) == 1, "write ok with 1 partitioned")
		check(c.accounts[0] == 200 && c.accounts[1] == 200, "0,1 wrote")
		check(c.accounts[2] == 0, "2 untouched")
	}
	{
		c := NewQCluster()
		c.Partition(1); c.Partition(2)
		check(c.Write(300) == 0, "write fails with 2 partitioned")
		check(c.accounts[0] == 0, "no replica wrote")
	}
	{
		c := NewQCluster()
		c.Partition(2); c.Write(500); c.Heal(2)
		c.Partition(0)
		check(c.Read() == 500, "intersection: read sees latest")
	}
	{
		c := NewQCluster()
		c.Write(700)
		c.Partition(0); c.Partition(1)
		check(c.Read() == -1, "read sentinel when below R")
	}

	fmt.Println("=== distributed_systems ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
