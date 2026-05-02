/* Vidya — Line Rasterization (Bresenham) in C
 *
 * All-octant integer Bresenham on a 16x16 byte framebuffer.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FB_W 16
#define FB_H 16
#define FB_BYTES (FB_W * FB_H)

static uint8_t fb[FB_BYTES];

static void fb_clear(void) { memset(fb, 0, FB_BYTES); }
static void fb_set(int x, int y, uint8_t v) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
    fb[y * FB_W + x] = v;
}
static uint8_t fb_get(int x, int y) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
    return fb[y * FB_W + x];
}
static int count_lit(void) {
    int n = 0;
    for (int i = 0; i < FB_BYTES; i++) if (fb[i]) n++;
    return n;
}

static int iabs(int v) { return v < 0 ? -v : v; }
static int sign(int v) { return (v > 0) - (v < 0); }

static void draw_line(int x0, int y0, int x1, int y1, uint8_t v) {
    int dx = iabs(x1 - x0), dy = iabs(y1 - y0);
    int sx = sign(x1 - x0), sy = sign(y1 - y0);
    int err = dx - dy;
    int x = x0, y = y0;
    for (;;) {
        fb_set(x, y, v);
        if (x == x1 && y == y1) return;
        int e2 = err * 2;
        if (e2 > -dy) { err -= dy; x += sx; }
        if (e2 < dx)  { err += dx; y += sy; }
    }
}

int main(void) {
    fb_clear(); draw_line(2, 5, 8, 5, 1);
    assert(count_lit() == 7);
    assert(fb_get(2, 5) == 1); assert(fb_get(8, 5) == 1);
    assert(fb_get(5, 5) == 1); assert(fb_get(5, 6) == 0);

    fb_clear(); draw_line(5, 2, 5, 8, 1);
    assert(count_lit() == 7);
    assert(fb_get(5, 2) == 1); assert(fb_get(5, 8) == 1);
    assert(fb_get(5, 5) == 1); assert(fb_get(6, 5) == 0);

    fb_clear(); draw_line(2, 2, 7, 7, 1);
    assert(count_lit() == 6);
    assert(fb_get(2, 2) == 1); assert(fb_get(7, 7) == 1);
    assert(fb_get(5, 5) == 1); assert(fb_get(5, 4) == 0);

    fb_clear(); draw_line(2, 7, 7, 2, 1);
    assert(count_lit() == 6);
    assert(fb_get(2, 7) == 1); assert(fb_get(7, 2) == 1);
    assert(fb_get(5, 4) == 1);

    fb_clear(); draw_line(3, 1, 5, 11, 1);
    assert(count_lit() == 11);
    assert(fb_get(3, 1) == 1); assert(fb_get(5, 11) == 1);

    fb_clear(); draw_line(8, 8, 8, 8, 1);
    assert(count_lit() == 1);
    assert(fb_get(8, 8) == 1);

    fb_clear(); draw_line(8, 5, 2, 5, 1);
    assert(count_lit() == 7);
    assert(fb_get(2, 5) == 1); assert(fb_get(8, 5) == 1);

    printf("line_rasterization: 27/27 ok\n");
    return 0;
}
