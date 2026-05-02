// Vidya — GPU Memory Pooling in Go
//
// Bump allocator over a 1024-byte pool.

package main

import "fmt"

const PoolSize int64 = 1024

type Pool struct{ bump int64 }

func (p *Pool) Reset()         { p.bump = 0 }
func (p *Pool) Used() int64    { return p.bump }
func (p *Pool) Free() int64    { return PoolSize - p.bump }

func (p *Pool) Alloc(size int64) int64 {
	if size == 0 {
		return p.bump
	}
	if p.bump+size > PoolSize {
		return -1
	}
	off := p.bump
	p.bump += size
	return off
}

func (p *Pool) AllocAligned(size, align int64) int64 {
	mask := align - 1
	aligned := (p.bump + mask) &^ mask
	if aligned+size > PoolSize {
		return -1
	}
	p.bump = aligned + size
	return aligned
}

func eq(got, want int64, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

func main() {
	var p Pool
	eq(p.Used(), 0, "init used")
	eq(p.Free(), 1024, "init free")

	eq(p.Alloc(100), 0, "alloc1")
	eq(p.Used(), 100, "used1")

	eq(p.Alloc(200), 100, "alloc2")
	eq(p.Used(), 300, "used2")

	eq(p.Alloc(1000), -1, "exhausted")
	eq(p.Used(), 300, "used unchanged")

	p.Reset()
	eq(p.Used(), 0, "reset used")
	eq(p.Free(), 1024, "reset free")
	eq(p.Alloc(50), 0, "alloc post-reset")

	eq(p.AllocAligned(32, 16), 64, "aligned 64")
	eq(p.Used(), 96, "used 96")

	eq(p.Alloc(0), 96, "noop alloc(0)")
	eq(p.Used(), 96, "noop used")

	p.Reset()
	for i := 0; i < 10; i++ {
		p.Alloc(8)
	}
	eq(p.Used(), 80, "10x8")

	fmt.Println("gpu_memory_pooling: 16/16 ok")
}
