// Vidya — Sprite Rendering in Go
//
// Software sprite blitting onto a flat 8-bit palette framebuffer.
// Go's `[]byte` is a slice header (ptr, len, cap) over a contiguous
// heap allocation — the same memory layout as a C `uint8_t*`. We
// index it `fb[y*SCREEN_W + x]` so byte offsets agree with every
// other port. `copy(fb, ...)` and `for i := range fb` give us the
// fast path for clear/blit without resorting to unsafe.

package main

import "fmt"

const (
	ScreenW  = 320
	ScreenH  = 240
	FBSize   = ScreenW * ScreenH // 76800
	ColorKey = 0
	FXShift  = 16
)

type Framebuffer struct {
	pixels []byte
}

func NewFramebuffer() *Framebuffer {
	return &Framebuffer{pixels: make([]byte, FBSize)}
}

func (fb *Framebuffer) Clear(color byte) {
	for i := range fb.pixels {
		fb.pixels[i] = color
	}
}

func (fb *Framebuffer) Get(x, y int) byte {
	if x < 0 || x >= ScreenW || y < 0 || y >= ScreenH {
		return 0
	}
	return fb.pixels[y*ScreenW+x]
}

func (fb *Framebuffer) Set(x, y int, color byte) {
	if x < 0 || x >= ScreenW || y < 0 || y >= ScreenH {
		return
	}
	fb.pixels[y*ScreenW+x] = color
}

type Sprite struct {
	Data   []byte
	Width  int
	Height int
}

func blit(fb *Framebuffer, s *Sprite, dstX, dstY int) {
	startX, startY := 0, 0
	endX, endY := s.Width, s.Height

	if dstX < 0 {
		startX = -dstX
		dstX = 0
	}
	if dstY < 0 {
		startY = -dstY
		dstY = 0
	}
	if dstX+(endX-startX) > ScreenW {
		endX = startX + (ScreenW - dstX)
	}
	if dstY+(endY-startY) > ScreenH {
		endY = startY + (ScreenH - dstY)
	}

	for sy := startY; sy < endY; sy++ {
		for sx := startX; sx < endX; sx++ {
			pixel := s.Data[sy*s.Width+sx]
			if pixel != ColorKey {
				dx := dstX + (sx - startX)
				dy := dstY + (sy - startY)
				fb.pixels[dy*ScreenW+dx] = pixel
			}
		}
	}
}

func blitScaled(fb *Framebuffer, s *Sprite, dstX, dstY, dstW, dstH int) {
	if dstW <= 0 || dstH <= 0 {
		return
	}
	stepX := (s.Width << FXShift) / dstW
	stepY := (s.Height << FXShift) / dstH

	srcY := 0
	for dy := 0; dy < dstH; dy++ {
		screenY := dstY + dy
		if screenY >= 0 && screenY < ScreenH {
			rowBase := (srcY >> FXShift) * s.Width
			srcX := 0
			for dx := 0; dx < dstW; dx++ {
				screenX := dstX + dx
				if screenX >= 0 && screenX < ScreenW {
					pixel := s.Data[rowBase+(srcX>>FXShift)]
					if pixel != ColorKey {
						fb.pixels[screenY*ScreenW+screenX] = pixel
					}
				}
				srcX += stepX
			}
		}
		srcY += stepY
	}
}

func assertEq(got, want int, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %d want %d", msg, got, want))
	}
}

func main() {
	fb := NewFramebuffer()
	sprite := &Sprite{
		Data: []byte{
			0, 1, 1, 0,
			1, 2, 2, 1,
			1, 2, 2, 1,
			0, 1, 1, 0,
		},
		Width:  4,
		Height: 4,
	}

	// clear
	fb.Clear(42)
	assertEq(int(fb.Get(100, 100)), 42, "clear fills framebuffer")
	assertEq(int(fb.Get(0, 0)), 42, "clear fills corner")
	assertEq(int(fb.Get(319, 239)), 42, "clear fills last pixel")

	// blit opaque
	fb.Clear(0)
	blit(fb, sprite, 10, 10)
	assertEq(int(fb.Get(11, 11)), 2, "blit center")
	assertEq(int(fb.Get(12, 11)), 2, "blit adjacent center")

	// transparency
	fb.Clear(99)
	blit(fb, sprite, 10, 10)
	assertEq(int(fb.Get(10, 10)), 99, "transparent corner preserves bg")
	assertEq(int(fb.Get(13, 10)), 99, "top-right transparent")
	assertEq(int(fb.Get(11, 10)), 1, "non-transparent written")

	// clipping right
	fb.Clear(0)
	blit(fb, sprite, 318, 0)
	assertEq(int(fb.Get(319, 1)), 2, "clipped sprite visible at right edge")
	assertEq(int(fb.Get(318, 0)), 0, "clipped transparent pixel")

	// clipping left
	fb.Clear(0)
	blit(fb, sprite, -2, 0)
	assertEq(int(fb.Get(0, 1)), 2, "left-clipped sprite visible")

	// scaled blit
	fb.Clear(0)
	blitScaled(fb, sprite, 20, 20, 8, 8)
	assertEq(int(fb.Get(22, 22)), 2, "2x scaled center pixel")
	assertEq(int(fb.Get(23, 23)), 2, "2x scaled adjacent center")

	// depth sort
	fb.Clear(0)
	blit(fb, sprite, 50, 50)
	assertEq(int(fb.Get(51, 51)), 2, "first sprite drawn")
	fb.Set(51, 51, 7)
	assertEq(int(fb.Get(51, 51)), 7, "later draw overwrites")

	// scaled shrink
	fb.Clear(0)
	blitScaled(fb, sprite, 100, 100, 2, 2)
	anyDrawn := fb.Get(100, 100) != 0 ||
		fb.Get(101, 100) != 0 ||
		fb.Get(100, 101) != 0 ||
		fb.Get(101, 101) != 0
	if !anyDrawn {
		panic("FAIL: shrunk sprite has no visible pixels")
	}

	fmt.Println("All sprite_rendering examples passed.")
}
