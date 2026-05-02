// Vidya — Explicit GPU Synchronization in Go
//
// Timeline semaphores — monotonic counters with signal/wait/wait_all.

package main

import "fmt"

type Timelines struct{ compute, transfer uint64 }

func (t *Timelines) Signal(sem int, value uint64) bool {
	switch sem {
	case 0:
		if value <= t.compute {
			return false
		}
		t.compute = value
		return true
	case 1:
		if value <= t.transfer {
			return false
		}
		t.transfer = value
		return true
	}
	return false
}

func (t *Timelines) WaitFor(sem int, target uint64) bool {
	switch sem {
	case 0:
		return t.compute >= target
	case 1:
		return t.transfer >= target
	}
	return false
}

func (t *Timelines) WaitAll(c, tr uint64) bool {
	return t.WaitFor(0, c) && t.WaitFor(1, tr)
}

func mustTrue(b bool, label string) {
	if !b {
		panic(label)
	}
}

func mustFalse(b bool, label string) {
	if b {
		panic(label)
	}
}

func main() {
	var t Timelines

	if t.compute != 0 || t.transfer != 0 {
		panic("init")
	}
	mustTrue(t.WaitFor(0, 0), "wait(0,0)")

	mustTrue(t.Signal(0, 5), "signal 5")
	if t.compute != 5 {
		panic("compute=5")
	}

	mustTrue(t.WaitFor(0, 3), "past")
	mustTrue(t.WaitFor(0, 5), "current")
	mustFalse(t.WaitFor(0, 10), "future")

	mustFalse(t.Signal(0, 3), "regress 3")
	if t.compute != 5 {
		panic("after regress")
	}
	mustFalse(t.Signal(0, 5), "regress 5")

	t.Signal(1, 3)
	if t.transfer != 3 {
		panic("transfer=3")
	}
	mustTrue(t.WaitAll(5, 3), "wait_all 5,3")
	mustFalse(t.WaitAll(5, 4), "wait_all 5,4")
	mustFalse(t.WaitAll(6, 3), "wait_all 6,3")
	mustTrue(t.WaitAll(0, 0), "wait_all 0,0")

	var t2 Timelines
	for i := uint64(1); i <= 10; i++ {
		t2.Signal(0, i)
	}
	if t2.compute != 10 {
		panic("monotonic 10")
	}
	mustTrue(t2.WaitFor(0, 10), "final")
	mustFalse(t2.WaitFor(0, 11), "beyond")

	fmt.Println("explicit_gpu_synchronization: 19/19 ok")
}
