// Vidya — Bloom and Glow in TypeScript
//
// 1-pixel additive bloom on a 16x16 single-channel intensity buffer.

const FB_W = 16;
const FB_H = 16;
const FB_BYTES = FB_W * FB_H;
const THRESHOLD = 128;
const GLOW_FRAC = 2;

function fbSet(fb: Uint8Array, x: number, y: number, v: number): void {
  if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
  fb[y * FB_W + x] = v;
}

function fbGet(fb: Uint8Array, x: number, y: number): number {
  if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
  return fb[y * FB_W + x];
}

function fbAdd(fb: Uint8Array, x: number, y: number, delta: number): void {
  if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
  const idx = y * FB_W + x;
  fb[idx] = Math.min(fb[idx] + delta, 255);
}

function applyBloom(src: Uint8Array, dst: Uint8Array, threshold: number): void {
  dst.set(src);
  for (let y = 0; y < FB_H; y++) {
    for (let x = 0; x < FB_W; x++) {
      const v = src[y * FB_W + x];
      if (v >= threshold) {
        const glow = (v / GLOW_FRAC) | 0;
        fbAdd(dst, x - 1, y, glow);
        fbAdd(dst, x + 1, y, glow);
        fbAdd(dst, x, y - 1, glow);
        fbAdd(dst, x, y + 1, glow);
      }
    }
  }
}

function countLit(fb: Uint8Array): number {
  let n = 0;
  for (const v of fb) if (v !== 0) n++;
  return n;
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const src = new Uint8Array(FB_BYTES);
  const dst = new Uint8Array(FB_BYTES);

  applyBloom(src, dst, THRESHOLD);
  eq(countLit(dst), 0, "empty");

  src.fill(0); fbSet(src, 8, 8, 200);
  applyBloom(src, dst, THRESHOLD);
  eq(fbGet(dst, 8, 8), 200, "src");
  eq(fbGet(dst, 7, 8), 100, "L");
  eq(fbGet(dst, 9, 8), 100, "R");
  eq(fbGet(dst, 8, 7), 100, "U");
  eq(fbGet(dst, 8, 9), 100, "D");
  eq(fbGet(dst, 7, 7), 0, "diag");
  eq(countLit(dst), 5, "single count");

  src.fill(0); fbSet(src, 8, 8, 200); fbSet(src, 9, 8, 250);
  applyBloom(src, dst, THRESHOLD);
  eq(fbGet(dst, 9, 8), 255, "clamp");
  eq(fbGet(dst, 8, 8), 255, "sum clamp");

  src.fill(0); fbSet(src, 8, 8, 100);
  applyBloom(src, dst, THRESHOLD);
  eq(fbGet(dst, 8, 8), 100, "dim preserved");
  eq(fbGet(dst, 7, 8), 0, "dim no glow");
  eq(countLit(dst), 1, "dim count");

  src.fill(0); fbSet(src, 0, 0, 200);
  applyBloom(src, dst, THRESHOLD);
  eq(fbGet(dst, 0, 0), 200, "corner src");
  eq(fbGet(dst, 1, 0), 100, "corner R");
  eq(fbGet(dst, 0, 1), 100, "corner D");
  eq(countLit(dst), 3, "corner count");

  src.fill(0); fbSet(src, 4, 8, 200); fbSet(src, 6, 8, 200);
  applyBloom(src, dst, THRESHOLD);
  eq(fbGet(dst, 5, 8), 200, "midpoint sum");
  eq(fbGet(dst, 3, 8), 100, "outer L");
  eq(fbGet(dst, 7, 8), 100, "outer R");

  console.log("bloom_and_glow: 20/20 ok");
}

main();
