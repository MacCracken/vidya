/* Vidya — Sprite Rendering in C
 *
 * Software sprite blitting against a flat 8-bit palette framebuffer.
 * The framebuffer is a `uint8_t*` heap allocation (matching the Cyrius
 * port's `_fb = alloc(FB_SIZE)`); we index it as `fb[y*SCREEN_W + x]`.
 * Every pixel op is a byte read or byte write — no struct overhead, no
 * RGB packing, no atomics. malloc/free; assert from <assert.h> drives
 * the test harness.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SCREEN_W 320
#define SCREEN_H 240
#define FB_SIZE (SCREEN_W * SCREEN_H)
#define COLOR_KEY 0
#define FX_SHIFT 16

static uint8_t *fb = NULL;

static void fb_init(void) {
    fb = (uint8_t *)malloc(FB_SIZE);
    assert(fb != NULL);
    memset(fb, 0, FB_SIZE);
}

static void fb_free(void) {
    free(fb);
    fb = NULL;
}

static void fb_clear(uint8_t color) {
    memset(fb, color, FB_SIZE);
}

static uint8_t fb_get(int x, int y) {
    if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H) return 0;
    return fb[y * SCREEN_W + x];
}

static void fb_set(int x, int y, uint8_t color) {
    if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H) return;
    fb[y * SCREEN_W + x] = color;
}

typedef struct {
    const uint8_t *data;
    int width;
    int height;
} Sprite;

static void blit(const Sprite *s, int dst_x, int dst_y) {
    int start_x = 0;
    int start_y = 0;
    int end_x = s->width;
    int end_y = s->height;

    if (dst_x < 0) { start_x = -dst_x; dst_x = 0; }
    if (dst_y < 0) { start_y = -dst_y; dst_y = 0; }
    if (dst_x + (end_x - start_x) > SCREEN_W) {
        end_x = start_x + (SCREEN_W - dst_x);
    }
    if (dst_y + (end_y - start_y) > SCREEN_H) {
        end_y = start_y + (SCREEN_H - dst_y);
    }

    for (int sy = start_y; sy < end_y; sy++) {
        for (int sx = start_x; sx < end_x; sx++) {
            uint8_t pixel = s->data[sy * s->width + sx];
            if (pixel != COLOR_KEY) {
                int dx = dst_x + (sx - start_x);
                int dy = dst_y + (sy - start_y);
                fb[dy * SCREEN_W + dx] = pixel;
            }
        }
    }
}

static void blit_scaled(const Sprite *s, int dst_x, int dst_y, int dst_w, int dst_h) {
    if (dst_w <= 0 || dst_h <= 0) return;
    int step_x = (s->width << FX_SHIFT) / dst_w;
    int step_y = (s->height << FX_SHIFT) / dst_h;

    int src_y = 0;
    for (int dy = 0; dy < dst_h; dy++) {
        int screen_y = dst_y + dy;
        if (screen_y >= 0 && screen_y < SCREEN_H) {
            int row_base = (src_y >> FX_SHIFT) * s->width;
            int src_x = 0;
            for (int dx = 0; dx < dst_w; dx++) {
                int screen_x = dst_x + dx;
                if (screen_x >= 0 && screen_x < SCREEN_W) {
                    uint8_t pixel = s->data[row_base + (src_x >> FX_SHIFT)];
                    if (pixel != COLOR_KEY) {
                        fb[screen_y * SCREEN_W + screen_x] = pixel;
                    }
                }
                src_x += step_x;
            }
        }
        src_y += step_y;
    }
}

int main(void) {
    fb_init();

    static const uint8_t test_data[16] = {
        0, 1, 1, 0,
        1, 2, 2, 1,
        1, 2, 2, 1,
        0, 1, 1, 0,
    };
    Sprite sprite = { test_data, 4, 4 };

    /* clear */
    fb_clear(42);
    assert(fb_get(100, 100) == 42);
    assert(fb_get(0, 0) == 42);
    assert(fb_get(319, 239) == 42);

    /* blit opaque */
    fb_clear(0);
    blit(&sprite, 10, 10);
    assert(fb_get(11, 11) == 2);
    assert(fb_get(12, 11) == 2);

    /* transparency */
    fb_clear(99);
    blit(&sprite, 10, 10);
    assert(fb_get(10, 10) == 99);
    assert(fb_get(13, 10) == 99);
    assert(fb_get(11, 10) == 1);

    /* clipping right */
    fb_clear(0);
    blit(&sprite, 318, 0);
    assert(fb_get(319, 1) == 2);
    assert(fb_get(318, 0) == 0);

    /* clipping left */
    fb_clear(0);
    blit(&sprite, -2, 0);
    assert(fb_get(0, 1) == 2);

    /* scaled blit (2x magnification) */
    fb_clear(0);
    blit_scaled(&sprite, 20, 20, 8, 8);
    assert(fb_get(22, 22) == 2);
    assert(fb_get(23, 23) == 2);

    /* depth sort (painter's algorithm) */
    fb_clear(0);
    blit(&sprite, 50, 50);
    assert(fb_get(51, 51) == 2);
    fb_set(51, 51, 7);
    assert(fb_get(51, 51) == 7);

    /* scaled shrink */
    fb_clear(0);
    blit_scaled(&sprite, 100, 100, 2, 2);
    int any_drawn = fb_get(100, 100) != 0
                  || fb_get(101, 100) != 0
                  || fb_get(100, 101) != 0
                  || fb_get(101, 101) != 0;
    assert(any_drawn);

    fb_free();
    printf("All sprite_rendering examples passed.\n");
    return 0;
}
