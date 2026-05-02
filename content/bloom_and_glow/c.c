/* Vidya — Bloom and Glow in C
 *
 * 1-pixel additive bloom on a 16x16 single-channel intensity buffer.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FB_W 16
#define FB_H 16
#define FB_BYTES (FB_W * FB_H)
#define THRESHOLD 128
#define GLOW_FRAC 2

static void fb_set(uint8_t *fb, int x, int y, uint8_t v) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
    fb[y * FB_W + x] = v;
}

static uint8_t fb_get(const uint8_t *fb, int x, int y) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
    return fb[y * FB_W + x];
}

static void fb_add(uint8_t *fb, int x, int y, int delta) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
    int idx = y * FB_W + x;
    int s = fb[idx] + delta;
    fb[idx] = (uint8_t)(s > 255 ? 255 : s);
}

static void apply_bloom(const uint8_t *src, uint8_t *dst, uint8_t threshold) {
    memcpy(dst, src, FB_BYTES);
    for (int y = 0; y < FB_H; y++) {
        for (int x = 0; x < FB_W; x++) {
            uint8_t v = src[y * FB_W + x];
            if (v >= threshold) {
                int glow = v / GLOW_FRAC;
                fb_add(dst, x - 1, y, glow);
                fb_add(dst, x + 1, y, glow);
                fb_add(dst, x, y - 1, glow);
                fb_add(dst, x, y + 1, glow);
            }
        }
    }
}

static int count_lit(const uint8_t *fb) {
    int n = 0;
    for (int i = 0; i < FB_BYTES; i++) if (fb[i]) n++;
    return n;
}

int main(void) {
    uint8_t src[FB_BYTES] = {0};
    uint8_t dst[FB_BYTES] = {0};

    apply_bloom(src, dst, THRESHOLD);
    assert(count_lit(dst) == 0);

    memset(src, 0, FB_BYTES); fb_set(src, 8, 8, 200);
    apply_bloom(src, dst, THRESHOLD);
    assert(fb_get(dst, 8, 8) == 200);
    assert(fb_get(dst, 7, 8) == 100);
    assert(fb_get(dst, 9, 8) == 100);
    assert(fb_get(dst, 8, 7) == 100);
    assert(fb_get(dst, 8, 9) == 100);
    assert(fb_get(dst, 7, 7) == 0);
    assert(count_lit(dst) == 5);

    memset(src, 0, FB_BYTES); fb_set(src, 8, 8, 200); fb_set(src, 9, 8, 250);
    apply_bloom(src, dst, THRESHOLD);
    assert(fb_get(dst, 9, 8) == 255);
    assert(fb_get(dst, 8, 8) == 255);

    memset(src, 0, FB_BYTES); fb_set(src, 8, 8, 100);
    apply_bloom(src, dst, THRESHOLD);
    assert(fb_get(dst, 8, 8) == 100);
    assert(fb_get(dst, 7, 8) == 0);
    assert(count_lit(dst) == 1);

    memset(src, 0, FB_BYTES); fb_set(src, 0, 0, 200);
    apply_bloom(src, dst, THRESHOLD);
    assert(fb_get(dst, 0, 0) == 200);
    assert(fb_get(dst, 1, 0) == 100);
    assert(fb_get(dst, 0, 1) == 100);
    assert(count_lit(dst) == 3);

    memset(src, 0, FB_BYTES); fb_set(src, 4, 8, 200); fb_set(src, 6, 8, 200);
    apply_bloom(src, dst, THRESHOLD);
    assert(fb_get(dst, 5, 8) == 200);
    assert(fb_get(dst, 3, 8) == 100);
    assert(fb_get(dst, 7, 8) == 100);

    printf("bloom_and_glow: 20/20 ok\n");
    return 0;
}
