// Vidya — Sprite Rendering in TypeScript
//
// Software sprite blitting onto a flat 8-bit palette framebuffer.
// `Uint8Array` is the typed-array primitive for byte work in the JS
// runtime: it's a contiguous block of bytes backed by an
// ArrayBuffer, with O(1) indexed get/set and `.fill()` for memset.
// We index it `fb[y * SCREEN_W + x]` so byte offsets line up with the
// C/Cyrius reference and the depth + clipping tests agree.

const SCREEN_W = 320;
const SCREEN_H = 240;
const FB_SIZE = SCREEN_W * SCREEN_H; // 76800
const COLOR_KEY = 0;
const FX_SHIFT = 16;

class Framebuffer {
    pixels: Uint8Array;

    constructor() {
        this.pixels = new Uint8Array(FB_SIZE);
    }

    clear(color: number): void {
        this.pixels.fill(color & 0xff);
    }

    get(x: number, y: number): number {
        if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H) return 0;
        return this.pixels[y * SCREEN_W + x];
    }

    set(x: number, y: number, color: number): void {
        if (x < 0 || x >= SCREEN_W || y < 0 || y >= SCREEN_H) return;
        this.pixels[y * SCREEN_W + x] = color & 0xff;
    }
}

interface Sprite {
    data: Uint8Array;
    width: number;
    height: number;
}

function blit(fb: Framebuffer, sprite: Sprite, dstX: number, dstY: number): void {
    let startX = 0;
    let startY = 0;
    let endX = sprite.width;
    let endY = sprite.height;

    if (dstX < 0) { startX = -dstX; dstX = 0; }
    if (dstY < 0) { startY = -dstY; dstY = 0; }
    if (dstX + (endX - startX) > SCREEN_W) {
        endX = startX + (SCREEN_W - dstX);
    }
    if (dstY + (endY - startY) > SCREEN_H) {
        endY = startY + (SCREEN_H - dstY);
    }

    for (let sy = startY; sy < endY; sy++) {
        for (let sx = startX; sx < endX; sx++) {
            const pixel = sprite.data[sy * sprite.width + sx];
            if (pixel !== COLOR_KEY) {
                const dx = dstX + (sx - startX);
                const dy = dstY + (sy - startY);
                fb.pixels[dy * SCREEN_W + dx] = pixel;
            }
        }
    }
}

function blitScaled(fb: Framebuffer, sprite: Sprite, dstX: number, dstY: number, dstW: number, dstH: number): void {
    if (dstW <= 0 || dstH <= 0) return;
    const stepX = (sprite.width << FX_SHIFT) / dstW | 0;
    const stepY = (sprite.height << FX_SHIFT) / dstH | 0;

    let srcY = 0;
    for (let dy = 0; dy < dstH; dy++) {
        const screenY = dstY + dy;
        if (screenY >= 0 && screenY < SCREEN_H) {
            const rowBase = (srcY >> FX_SHIFT) * sprite.width;
            let srcX = 0;
            for (let dx = 0; dx < dstW; dx++) {
                const screenX = dstX + dx;
                if (screenX >= 0 && screenX < SCREEN_W) {
                    const pixel = sprite.data[rowBase + (srcX >> FX_SHIFT)];
                    if (pixel !== COLOR_KEY) {
                        fb.pixels[screenY * SCREEN_W + screenX] = pixel;
                    }
                }
                srcX += stepX;
            }
        }
        srcY += stepY;
    }
}

function assertEq(got: number, want: number, msg: string): void {
    if (got !== want) {
        throw new Error(`FAIL: ${msg}: got ${got} want ${want}`);
    }
}

function main(): void {
    const fb = new Framebuffer();
    const sprite: Sprite = {
        data: new Uint8Array([
            0, 1, 1, 0,
            1, 2, 2, 1,
            1, 2, 2, 1,
            0, 1, 1, 0,
        ]),
        width: 4,
        height: 4,
    };

    // clear
    fb.clear(42);
    assertEq(fb.get(100, 100), 42, "clear fills framebuffer");
    assertEq(fb.get(0, 0), 42, "clear fills corner");
    assertEq(fb.get(319, 239), 42, "clear fills last pixel");

    // blit opaque
    fb.clear(0);
    blit(fb, sprite, 10, 10);
    assertEq(fb.get(11, 11), 2, "blit center");
    assertEq(fb.get(12, 11), 2, "blit adjacent center");

    // transparency
    fb.clear(99);
    blit(fb, sprite, 10, 10);
    assertEq(fb.get(10, 10), 99, "transparent corner preserves bg");
    assertEq(fb.get(13, 10), 99, "top-right transparent");
    assertEq(fb.get(11, 10), 1, "non-transparent written");

    // clipping right
    fb.clear(0);
    blit(fb, sprite, 318, 0);
    assertEq(fb.get(319, 1), 2, "clipped sprite visible at right edge");
    assertEq(fb.get(318, 0), 0, "clipped transparent pixel");

    // clipping left
    fb.clear(0);
    blit(fb, sprite, -2, 0);
    assertEq(fb.get(0, 1), 2, "left-clipped sprite visible");

    // scaled blit
    fb.clear(0);
    blitScaled(fb, sprite, 20, 20, 8, 8);
    assertEq(fb.get(22, 22), 2, "2x scaled center pixel");
    assertEq(fb.get(23, 23), 2, "2x scaled adjacent center");

    // depth sort
    fb.clear(0);
    blit(fb, sprite, 50, 50);
    assertEq(fb.get(51, 51), 2, "first sprite drawn");
    fb.set(51, 51, 7);
    assertEq(fb.get(51, 51), 7, "later draw overwrites");

    // scaled shrink
    fb.clear(0);
    blitScaled(fb, sprite, 100, 100, 2, 2);
    const anyDrawn =
        fb.get(100, 100) !== 0 ||
        fb.get(101, 100) !== 0 ||
        fb.get(100, 101) !== 0 ||
        fb.get(101, 101) !== 0;
    if (!anyDrawn) throw new Error("FAIL: shrunk sprite has no visible pixels");

    console.log("All sprite_rendering examples passed.");
}

main();
