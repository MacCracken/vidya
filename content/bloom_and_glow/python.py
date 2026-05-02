# Vidya — Bloom and Glow in Python
#
# 1-pixel additive bloom on a 16x16 single-channel intensity buffer.

FB_W = 16
FB_H = 16
FB_BYTES = FB_W * FB_H
THRESHOLD = 128
GLOW_FRAC = 2


def fb_set(fb, x, y, v):
    if 0 <= x < FB_W and 0 <= y < FB_H:
        fb[y * FB_W + x] = v


def fb_get(fb, x, y):
    if 0 <= x < FB_W and 0 <= y < FB_H:
        return fb[y * FB_W + x]
    return 0


def fb_add(fb, x, y, delta):
    if 0 <= x < FB_W and 0 <= y < FB_H:
        idx = y * FB_W + x
        fb[idx] = min(fb[idx] + delta, 255)


def apply_bloom(src, dst, threshold):
    for i in range(FB_BYTES):
        dst[i] = src[i]
    for y in range(FB_H):
        for x in range(FB_W):
            v = src[y * FB_W + x]
            if v >= threshold:
                glow = v // GLOW_FRAC
                fb_add(dst, x - 1, y, glow)
                fb_add(dst, x + 1, y, glow)
                fb_add(dst, x, y - 1, glow)
                fb_add(dst, x, y + 1, glow)


def count_lit(fb):
    return sum(1 for v in fb if v != 0)


def main():
    src = bytearray(FB_BYTES)
    dst = bytearray(FB_BYTES)

    apply_bloom(src, dst, THRESHOLD)
    assert count_lit(dst) == 0

    # 2
    for i in range(FB_BYTES): src[i] = 0
    fb_set(src, 8, 8, 200)
    apply_bloom(src, dst, THRESHOLD)
    assert fb_get(dst, 8, 8) == 200
    assert fb_get(dst, 7, 8) == 100
    assert fb_get(dst, 9, 8) == 100
    assert fb_get(dst, 8, 7) == 100
    assert fb_get(dst, 8, 9) == 100
    assert fb_get(dst, 7, 7) == 0
    assert count_lit(dst) == 5

    # 3
    for i in range(FB_BYTES): src[i] = 0
    fb_set(src, 8, 8, 200)
    fb_set(src, 9, 8, 250)
    apply_bloom(src, dst, THRESHOLD)
    assert fb_get(dst, 9, 8) == 255
    assert fb_get(dst, 8, 8) == 255

    # 4
    for i in range(FB_BYTES): src[i] = 0
    fb_set(src, 8, 8, 100)
    apply_bloom(src, dst, THRESHOLD)
    assert fb_get(dst, 8, 8) == 100
    assert fb_get(dst, 7, 8) == 0
    assert count_lit(dst) == 1

    # 5
    for i in range(FB_BYTES): src[i] = 0
    fb_set(src, 0, 0, 200)
    apply_bloom(src, dst, THRESHOLD)
    assert fb_get(dst, 0, 0) == 200
    assert fb_get(dst, 1, 0) == 100
    assert fb_get(dst, 0, 1) == 100
    assert count_lit(dst) == 3

    # 6
    for i in range(FB_BYTES): src[i] = 0
    fb_set(src, 4, 8, 200)
    fb_set(src, 6, 8, 200)
    apply_bloom(src, dst, THRESHOLD)
    assert fb_get(dst, 5, 8) == 200
    assert fb_get(dst, 3, 8) == 100
    assert fb_get(dst, 7, 8) == 100

    print("bloom_and_glow: 20/20 ok")


main()
