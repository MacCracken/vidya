# Vidya — Framebuffer Rendering in Python
#
# 16×16 BGRA8888 framebuffer mirroring cyrius.cyr.

FB_W = 16
FB_H = 16
FB_BPP = 4
FB_BYTES = FB_W * FB_H * FB_BPP


class FrameBuffer:
    def __init__(self):
        self.buf = bytearray(FB_BYTES)

    def clear(self):
        for i in range(FB_BYTES):
            self.buf[i] = 0

    def set(self, x, y, color):
        if x < 0 or x >= FB_W or y < 0 or y >= FB_H:
            return False
        off = (y * FB_W + x) * FB_BPP
        self.buf[off] = color & 0xFF
        self.buf[off + 1] = (color >> 8) & 0xFF
        self.buf[off + 2] = (color >> 16) & 0xFF
        self.buf[off + 3] = 255
        return True

    def get(self, x, y):
        if x < 0 or x >= FB_W or y < 0 or y >= FB_H:
            return 0
        off = (y * FB_W + x) * FB_BPP
        return (self.buf[off + 2] << 16) | (self.buf[off + 1] << 8) | self.buf[off]

    def draw_hline(self, x, y, length, color):
        for i in range(length):
            self.set(x + i, y, color)

    def draw_vline(self, x, y, length, color):
        for i in range(length):
            self.set(x, y + i, color)

    def count_lit(self):
        n = 0
        for i in range(0, FB_BYTES, FB_BPP):
            if self.buf[i] or self.buf[i + 1] or self.buf[i + 2]:
                n += 1
        return n


def main():
    fb = FrameBuffer()

    # Test 1
    fb.clear()
    assert fb.count_lit() == 0, "clear → 0 lit"

    # Test 2: red at (5, 7)
    fb.set(5, 7, 0xFF0000)
    off = (7 * FB_W + 5) * FB_BPP
    assert fb.buf[off] == 0, "B=0"
    assert fb.buf[off + 1] == 0, "G=0"
    assert fb.buf[off + 2] == 255, "R=255"
    assert fb.buf[off + 3] == 255, "A=255"

    # Test 3
    assert fb.get(5, 7) == 0xFF0000, "get red"

    # Test 4: bounds check
    lit_before = fb.count_lit()
    fb.set(-1, 5, 0x00FF00)
    fb.set(16, 5, 0x00FF00)
    fb.set(5, -1, 0x00FF00)
    fb.set(5, 16, 0x00FF00)
    assert fb.count_lit() == lit_before, "OOB rejected"

    # Test 5
    assert fb.set(3, 3, 0x0000FF), "in-bounds true"
    assert not fb.set(-5, 3, 0x0000FF), "OOB false"

    # Test 6: hline
    fb.clear()
    fb.draw_hline(2, 8, 4, 0x00FF00)
    assert fb.count_lit() == 4
    assert fb.get(2, 8) == 0x00FF00
    assert fb.get(5, 8) == 0x00FF00
    assert fb.get(6, 8) == 0

    # Test 7: vline
    fb.clear()
    fb.draw_vline(7, 2, 4, 0x0000FF)
    assert fb.count_lit() == 4
    assert fb.get(7, 2) == 0x0000FF
    assert fb.get(7, 5) == 0x0000FF
    assert fb.get(7, 6) == 0

    # Test 8: hline clipped
    fb.clear()
    fb.draw_hline(14, 5, 4, 0xFF0000)
    assert fb.count_lit() == 2

    print("framebuffer_rendering: 18/18 ok")


main()
