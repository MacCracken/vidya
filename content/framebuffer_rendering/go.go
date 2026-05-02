// Vidya — Framebuffer Rendering in Go
//
// 16x16 BGRA8888 framebuffer mirroring cyrius.cyr.

package main

import "fmt"

const (
	FbW    = 16
	FbH    = 16
	FbBpp  = 4
	FbSize = FbW * FbH * FbBpp
)

type FrameBuffer struct {
	buf [FbSize]byte
}

func (f *FrameBuffer) Clear() {
	for i := range f.buf {
		f.buf[i] = 0
	}
}

func (f *FrameBuffer) Set(x, y int, color uint32) bool {
	if x < 0 || x >= FbW || y < 0 || y >= FbH {
		return false
	}
	off := (y*FbW + x) * FbBpp
	f.buf[off] = byte(color & 0xFF)
	f.buf[off+1] = byte((color >> 8) & 0xFF)
	f.buf[off+2] = byte((color >> 16) & 0xFF)
	f.buf[off+3] = 255
	return true
}

func (f *FrameBuffer) Get(x, y int) uint32 {
	if x < 0 || x >= FbW || y < 0 || y >= FbH {
		return 0
	}
	off := (y*FbW + x) * FbBpp
	return uint32(f.buf[off+2])<<16 | uint32(f.buf[off+1])<<8 | uint32(f.buf[off])
}

func (f *FrameBuffer) DrawHLine(x, y, length int, color uint32) {
	for i := 0; i < length; i++ {
		f.Set(x+i, y, color)
	}
}

func (f *FrameBuffer) DrawVLine(x, y, length int, color uint32) {
	for i := 0; i < length; i++ {
		f.Set(x, y+i, color)
	}
}

func (f *FrameBuffer) CountLit() int {
	n := 0
	for i := 0; i < FbSize; i += FbBpp {
		if f.buf[i]|f.buf[i+1]|f.buf[i+2] != 0 {
			n++
		}
	}
	return n
}

func mustEq[T comparable](got, want T, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %v want %v", label, got, want))
	}
}

func mustTrue(b bool, label string) {
	if !b {
		panic(label)
	}
}

func main() {
	var fb FrameBuffer

	// 1
	fb.Clear()
	mustEq(fb.CountLit(), 0, "clear")

	// 2
	fb.Set(5, 7, 0xFF0000)
	off := (7*FbW + 5) * FbBpp
	mustEq(fb.buf[off], byte(0), "B")
	mustEq(fb.buf[off+1], byte(0), "G")
	mustEq(fb.buf[off+2], byte(255), "R")
	mustEq(fb.buf[off+3], byte(255), "A")

	// 3
	mustEq(fb.Get(5, 7), uint32(0xFF0000), "get")

	// 4
	before := fb.CountLit()
	fb.Set(-1, 5, 0x00FF00)
	fb.Set(16, 5, 0x00FF00)
	fb.Set(5, -1, 0x00FF00)
	fb.Set(5, 16, 0x00FF00)
	mustEq(fb.CountLit(), before, "OOB")

	// 5
	mustTrue(fb.Set(3, 3, 0x0000FF), "in-bounds true")
	mustTrue(!fb.Set(-5, 3, 0x0000FF), "OOB false")

	// 6
	fb.Clear()
	fb.DrawHLine(2, 8, 4, 0x00FF00)
	mustEq(fb.CountLit(), 4, "hline count")
	mustEq(fb.Get(2, 8), uint32(0x00FF00), "hline (2,8)")
	mustEq(fb.Get(5, 8), uint32(0x00FF00), "hline (5,8)")
	mustEq(fb.Get(6, 8), uint32(0), "hline stops")

	// 7
	fb.Clear()
	fb.DrawVLine(7, 2, 4, 0x0000FF)
	mustEq(fb.CountLit(), 4, "vline count")
	mustEq(fb.Get(7, 2), uint32(0x0000FF), "vline (7,2)")
	mustEq(fb.Get(7, 5), uint32(0x0000FF), "vline (7,5)")
	mustEq(fb.Get(7, 6), uint32(0), "vline stops")

	// 8
	fb.Clear()
	fb.DrawHLine(14, 5, 4, 0xFF0000)
	mustEq(fb.CountLit(), 2, "hline clipped")

	fmt.Println("framebuffer_rendering: 18/18 ok")
}
