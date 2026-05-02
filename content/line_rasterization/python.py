# Vidya — Line Rasterization (Bresenham) in Python
#
# All-octant integer Bresenham on a 16x16 byte framebuffer.

FB_W = 16
FB_H = 16
FB_BYTES = FB_W * FB_H


class Fb:
    def __init__(self):
        self.buf = bytearray(FB_BYTES)

    def clear(self):
        for i in range(FB_BYTES):
            self.buf[i] = 0

    def set(self, x, y, val):
        if 0 <= x < FB_W and 0 <= y < FB_H:
            self.buf[y * FB_W + x] = val

    def get(self, x, y):
        if 0 <= x < FB_W and 0 <= y < FB_H:
            return self.buf[y * FB_W + x]
        return 0

    def count_lit(self):
        return sum(1 for v in self.buf if v != 0)


def sign(v):
    return (v > 0) - (v < 0)


def draw_line(fb, x0, y0, x1, y1, val):
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = sign(x1 - x0)
    sy = sign(y1 - y0)
    err = dx - dy
    x, y = x0, y0
    while True:
        fb.set(x, y, val)
        if x == x1 and y == y1:
            return
        e2 = err * 2
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def main():
    fb = Fb()

    fb.clear()
    draw_line(fb, 2, 5, 8, 5, 1)
    assert fb.count_lit() == 7
    assert fb.get(2, 5) == 1
    assert fb.get(8, 5) == 1
    assert fb.get(5, 5) == 1
    assert fb.get(5, 6) == 0

    fb.clear()
    draw_line(fb, 5, 2, 5, 8, 1)
    assert fb.count_lit() == 7
    assert fb.get(5, 2) == 1
    assert fb.get(5, 8) == 1
    assert fb.get(5, 5) == 1
    assert fb.get(6, 5) == 0

    fb.clear()
    draw_line(fb, 2, 2, 7, 7, 1)
    assert fb.count_lit() == 6
    assert fb.get(2, 2) == 1
    assert fb.get(7, 7) == 1
    assert fb.get(5, 5) == 1
    assert fb.get(5, 4) == 0

    fb.clear()
    draw_line(fb, 2, 7, 7, 2, 1)
    assert fb.count_lit() == 6
    assert fb.get(2, 7) == 1
    assert fb.get(7, 2) == 1
    assert fb.get(5, 4) == 1

    fb.clear()
    draw_line(fb, 3, 1, 5, 11, 1)
    assert fb.count_lit() == 11
    assert fb.get(3, 1) == 1
    assert fb.get(5, 11) == 1

    fb.clear()
    draw_line(fb, 8, 8, 8, 8, 1)
    assert fb.count_lit() == 1
    assert fb.get(8, 8) == 1

    fb.clear()
    draw_line(fb, 8, 5, 2, 5, 1)
    assert fb.count_lit() == 7
    assert fb.get(2, 5) == 1
    assert fb.get(8, 5) == 1

    print("line_rasterization: 27/27 ok")


main()
