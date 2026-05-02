// Vidya — Direct DRM GPU Compute in Go
//
// In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

package main

import "fmt"

const (
	BoCap = 32
	VaCap = 32
)

type Device struct {
	fd            int64
	boSize        [BoCap]uint64
	nextBO        uint32
	vaAddr        [VaCap]uint64
	vaBO          [VaCap]uint32
	vaCount       int
	nextSeq       uint64
	completedSeq  uint64
}

func newDevice() *Device { return &Device{nextBO: 1, nextSeq: 1} }

func (d *Device) OpenRenderNode() int64 { d.fd = 42; return d.fd }

func (d *Device) GemCreate(size uint64) uint32 {
	if d.nextBO >= BoCap {
		return 0
	}
	h := d.nextBO
	d.nextBO++
	d.boSize[h] = size
	return h
}

func (d *Device) GemDestroy(handle uint32) bool {
	if handle == 0 || handle >= BoCap {
		return false
	}
	if d.boSize[handle] == 0 {
		return false
	}
	d.boSize[handle] = 0
	for i := 0; i < d.vaCount; i++ {
		if d.vaBO[i] == handle {
			d.vaBO[i] = 0
		}
	}
	return true
}

func (d *Device) GemVaMap(handle uint32, va uint64) bool {
	if handle == 0 || handle >= BoCap {
		return false
	}
	if d.boSize[handle] == 0 {
		return false
	}
	if d.vaCount >= VaCap {
		return false
	}
	d.vaAddr[d.vaCount] = va
	d.vaBO[d.vaCount] = handle
	d.vaCount++
	return true
}

func (d *Device) VaLookup(va uint64) uint32 {
	for i := 0; i < d.vaCount; i++ {
		if d.vaAddr[i] == va && d.vaBO[i] != 0 {
			return d.vaBO[i]
		}
	}
	return 0
}

func (d *Device) Submit(handle uint32) uint64 {
	if handle == 0 || handle >= BoCap {
		return 0
	}
	if d.boSize[handle] == 0 {
		return 0
	}
	seq := d.nextSeq
	d.nextSeq++
	d.completedSeq = seq
	return seq
}

func (d *Device) SyncobjWait(seq uint64) bool {
	return d.completedSeq >= seq
}

func eq[T comparable](got, want T, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %v want %v", label, got, want))
	}
}

func tru(b bool, label string) {
	if !b {
		panic(label)
	}
}

func main() {
	d := newDevice()

	if d.OpenRenderNode() == 0 {
		panic("fd")
	}

	b1 := d.GemCreate(4096)
	b2 := d.GemCreate(8192)
	b3 := d.GemCreate(16384)
	eq(b1, uint32(1), "b1")
	eq(b2, uint32(2), "b2")
	eq(b3, uint32(3), "b3")

	tru(d.GemVaMap(b1, 0x1000), "map b1")
	tru(d.GemVaMap(b2, 0x2000), "map b2")

	eq(d.VaLookup(0x1000), b1, "lookup b1")
	eq(d.VaLookup(0x2000), b2, "lookup b2")
	eq(d.VaLookup(0x9000), uint32(0), "lookup unmapped")

	tru(!d.GemVaMap(99, 0x3000), "map invalid")
	tru(!d.GemVaMap(0, 0x3000), "map handle 0")

	eq(d.Submit(b1), uint64(1), "seq 1")
	eq(d.Submit(b2), uint64(2), "seq 2")
	eq(d.Submit(b3), uint64(3), "seq 3")

	tru(d.SyncobjWait(1), "wait 1")
	tru(d.SyncobjWait(3), "wait 3")
	tru(!d.SyncobjWait(99), "wait future")

	d.GemDestroy(b1)
	eq(d.VaLookup(0x1000), uint32(0), "destroyed va")

	eq(d.Submit(b1), uint64(0), "submit destroyed")
	eq(d.Submit(b2), uint64(4), "next valid")

	fmt.Println("direct_drm_gpu_compute: 20/20 ok")
}
