/* Vidya — Framebuffer Rendering in C
 *
 * 16x16 BGRA8888 framebuffer mirroring cyrius.cyr.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FB_W 16
#define FB_H 16
#define FB_BPP 4
#define FB_BYTES (FB_W * FB_H * FB_BPP)

static uint8_t fb_buf[FB_BYTES];

static void fb_clear(void) { memset(fb_buf, 0, FB_BYTES); }

static int fb_set(int x, int y, uint32_t color) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
    int off = (y * FB_W + x) * FB_BPP;
    fb_buf[off]     = color & 0xFF;
    fb_buf[off + 1] = (color >> 8) & 0xFF;
    fb_buf[off + 2] = (color >> 16) & 0xFF;
    fb_buf[off + 3] = 255;
    return 1;
}

static uint32_t fb_get(int x, int y) {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
    int off = (y * FB_W + x) * FB_BPP;
    return ((uint32_t)fb_buf[off + 2] << 16)
         | ((uint32_t)fb_buf[off + 1] << 8)
         |  (uint32_t)fb_buf[off];
}

static void draw_hline(int x, int y, int len, uint32_t color) {
    for (int i = 0; i < len; i++) fb_set(x + i, y, color);
}

static void draw_vline(int x, int y, int len, uint32_t color) {
    for (int i = 0; i < len; i++) fb_set(x, y + i, color);
}

static int count_lit(void) {
    int n = 0;
    for (int i = 0; i < FB_BYTES; i += FB_BPP) {
        if (fb_buf[i] || fb_buf[i + 1] || fb_buf[i + 2]) n++;
    }
    return n;
}

int main(void) {
    /* 1 */
    fb_clear();
    assert(count_lit() == 0 && "clear → 0 lit");

    /* 2: red at (5,7) */
    fb_set(5, 7, 0xFF0000);
    int off = (7 * FB_W + 5) * FB_BPP;
    assert(fb_buf[off] == 0     && "B=0");
    assert(fb_buf[off + 1] == 0 && "G=0");
    assert(fb_buf[off + 2] == 255 && "R=255");
    assert(fb_buf[off + 3] == 255 && "A=255");

    /* 3 */
    assert(fb_get(5, 7) == 0xFF0000U && "get red");

    /* 4: bounds */
    int lit_before = count_lit();
    fb_set(-1, 5, 0x00FF00);
    fb_set(16, 5, 0x00FF00);
    fb_set(5, -1, 0x00FF00);
    fb_set(5, 16, 0x00FF00);
    assert(count_lit() == lit_before && "OOB rejected");

    /* 5 */
    assert(fb_set(3, 3, 0x0000FF) == 1 && "in-bounds 1");
    assert(fb_set(-5, 3, 0x0000FF) == 0 && "OOB 0");

    /* 6: hline */
    fb_clear();
    draw_hline(2, 8, 4, 0x00FF00);
    assert(count_lit() == 4);
    assert(fb_get(2, 8) == 0x00FF00U);
    assert(fb_get(5, 8) == 0x00FF00U);
    assert(fb_get(6, 8) == 0);

    /* 7: vline */
    fb_clear();
    draw_vline(7, 2, 4, 0x0000FF);
    assert(count_lit() == 4);
    assert(fb_get(7, 2) == 0x0000FFU);
    assert(fb_get(7, 5) == 0x0000FFU);
    assert(fb_get(7, 6) == 0);

    /* 8: hline clipped */
    fb_clear();
    draw_hline(14, 5, 4, 0xFF0000);
    assert(count_lit() == 2);

    printf("framebuffer_rendering: 18/18 ok\n");
    return 0;
}
