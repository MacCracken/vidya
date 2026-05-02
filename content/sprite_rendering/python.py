#!/usr/bin/env python3
"""Vidya — Sprite Rendering in Python.

Software sprite blitting onto a flat 8-bit palette framebuffer.
Python's ``bytearray`` is the right primitive for this: it's a mutable
contiguous byte sequence with O(1) index assignment and slice assignment
that maps cleanly to the C/Cyrius ``uint8_t*`` layout. We index it as
``fb[y * SCREEN_W + x]`` so the byte-level layout matches every other
port — clipping/depth tests check the same offsets in every language.
"""

SCREEN_W = 320
SCREEN_H = 240
FB_SIZE = SCREEN_W * SCREEN_H  # 76800
COLOR_KEY = 0
FX_SHIFT = 16


class Framebuffer:
    def __init__(self) -> None:
        self.pixels = bytearray(FB_SIZE)

    def clear(self, color: int) -> None:
        # Single allocation + slice-assign is faster than per-byte loop.
        self.pixels[:] = bytes([color]) * FB_SIZE

    def get(self, x: int, y: int) -> int:
        if x < 0 or x >= SCREEN_W or y < 0 or y >= SCREEN_H:
            return 0
        return self.pixels[y * SCREEN_W + x]

    def set(self, x: int, y: int, color: int) -> None:
        if x < 0 or x >= SCREEN_W or y < 0 or y >= SCREEN_H:
            return
        self.pixels[y * SCREEN_W + x] = color


class Sprite:
    __slots__ = ("data", "width", "height")

    def __init__(self, data: bytes, width: int, height: int) -> None:
        self.data = data
        self.width = width
        self.height = height


def blit(fb: Framebuffer, sprite: Sprite, dst_x: int, dst_y: int) -> None:
    start_x = 0
    start_y = 0
    end_x = sprite.width
    end_y = sprite.height

    if dst_x < 0:
        start_x = -dst_x
        dst_x = 0
    if dst_y < 0:
        start_y = -dst_y
        dst_y = 0
    if dst_x + (end_x - start_x) > SCREEN_W:
        end_x = start_x + (SCREEN_W - dst_x)
    if dst_y + (end_y - start_y) > SCREEN_H:
        end_y = start_y + (SCREEN_H - dst_y)

    sy = start_y
    while sy < end_y:
        sx = start_x
        while sx < end_x:
            pixel = sprite.data[sy * sprite.width + sx]
            if pixel != COLOR_KEY:
                dx = dst_x + (sx - start_x)
                dy = dst_y + (sy - start_y)
                fb.pixels[dy * SCREEN_W + dx] = pixel
            sx += 1
        sy += 1


def blit_scaled(fb: Framebuffer, sprite: Sprite, dst_x: int, dst_y: int,
                dst_w: int, dst_h: int) -> None:
    if dst_w <= 0 or dst_h <= 0:
        return
    step_x = (sprite.width << FX_SHIFT) // dst_w
    step_y = (sprite.height << FX_SHIFT) // dst_h

    src_y = 0
    for dy in range(dst_h):
        screen_y = dst_y + dy
        if 0 <= screen_y < SCREEN_H:
            row_base = (src_y >> FX_SHIFT) * sprite.width
            src_x = 0
            for dx in range(dst_w):
                screen_x = dst_x + dx
                if 0 <= screen_x < SCREEN_W:
                    pixel = sprite.data[row_base + (src_x >> FX_SHIFT)]
                    if pixel != COLOR_KEY:
                        fb.pixels[screen_y * SCREEN_W + screen_x] = pixel
                src_x += step_x
        src_y += step_y


def test_sprite() -> Sprite:
    return Sprite(
        bytes([
            0, 1, 1, 0,
            1, 2, 2, 1,
            1, 2, 2, 1,
            0, 1, 1, 0,
        ]),
        4, 4,
    )


def main() -> None:
    fb = Framebuffer()
    sprite = test_sprite()

    # clear
    fb.clear(42)
    assert fb.get(100, 100) == 42, "clear fills framebuffer"
    assert fb.get(0, 0) == 42, "clear fills corner"
    assert fb.get(319, 239) == 42, "clear fills last pixel"

    # blit opaque
    fb.clear(0)
    blit(fb, sprite, 10, 10)
    assert fb.get(11, 11) == 2, "blit writes center pixel"
    assert fb.get(12, 11) == 2, "blit writes adjacent center pixel"

    # transparency
    fb.clear(99)
    blit(fb, sprite, 10, 10)
    assert fb.get(10, 10) == 99, "transparent corner preserves bg"
    assert fb.get(13, 10) == 99, "top-right transparent"
    assert fb.get(11, 10) == 1, "non-transparent written"

    # clipping right
    fb.clear(0)
    blit(fb, sprite, 318, 0)
    assert fb.get(319, 1) == 2, "clipped sprite visible at right edge"
    assert fb.get(318, 0) == 0, "clipped transparent pixel"

    # clipping left
    fb.clear(0)
    blit(fb, sprite, -2, 0)
    assert fb.get(0, 1) == 2, "left-clipped sprite visible"

    # scaled blit
    fb.clear(0)
    blit_scaled(fb, sprite, 20, 20, 8, 8)
    assert fb.get(22, 22) == 2, "2x scaled center pixel"
    assert fb.get(23, 23) == 2, "2x scaled adjacent center"

    # depth sort (painter's algorithm)
    fb.clear(0)
    blit(fb, sprite, 50, 50)
    assert fb.get(51, 51) == 2, "first sprite drawn"
    fb.set(51, 51, 7)
    assert fb.get(51, 51) == 7, "later draw overwrites"

    # scaled shrink
    fb.clear(0)
    blit_scaled(fb, sprite, 100, 100, 2, 2)
    any_drawn = (
        fb.get(100, 100) != 0
        or fb.get(101, 100) != 0
        or fb.get(100, 101) != 0
        or fb.get(101, 101) != 0
    )
    assert any_drawn, "shrunk sprite has visible pixels"

    print("All sprite_rendering examples passed.")


if __name__ == "__main__":
    main()
