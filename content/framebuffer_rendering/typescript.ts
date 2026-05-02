// Vidya — Framebuffer Rendering in TypeScript
//
// 16x16 BGRA8888 framebuffer mirroring cyrius.cyr.

const FB_W = 16;
const FB_H = 16;
const FB_BPP = 4;
const FB_BYTES = FB_W * FB_H * FB_BPP;

class FrameBuffer {
  buf = new Uint8Array(FB_BYTES);

  clear(): void { this.buf.fill(0); }

  set(x: number, y: number, color: number): boolean {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return false;
    const off = (y * FB_W + x) * FB_BPP;
    this.buf[off]     = color & 0xFF;
    this.buf[off + 1] = (color >>> 8) & 0xFF;
    this.buf[off + 2] = (color >>> 16) & 0xFF;
    this.buf[off + 3] = 255;
    return true;
  }

  get(x: number, y: number): number {
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
    const off = (y * FB_W + x) * FB_BPP;
    return (this.buf[off + 2] << 16) | (this.buf[off + 1] << 8) | this.buf[off];
  }

  drawHLine(x: number, y: number, len: number, color: number): void {
    for (let i = 0; i < len; i++) this.set(x + i, y, color);
  }

  drawVLine(x: number, y: number, len: number, color: number): void {
    for (let i = 0; i < len; i++) this.set(x, y + i, color);
  }

  countLit(): number {
    let n = 0;
    for (let i = 0; i < FB_BYTES; i += FB_BPP) {
      if (this.buf[i] || this.buf[i + 1] || this.buf[i + 2]) n++;
    }
    return n;
  }
}

function eq<T>(got: T, want: T, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function ok(b: boolean, label: string): void {
  if (!b) throw new Error(label);
}

function main(): void {
  const fb = new FrameBuffer();

  fb.clear();
  eq(fb.countLit(), 0, "clear");

  fb.set(5, 7, 0xFF0000);
  const off = (7 * FB_W + 5) * FB_BPP;
  eq(fb.buf[off], 0, "B");
  eq(fb.buf[off + 1], 0, "G");
  eq(fb.buf[off + 2], 255, "R");
  eq(fb.buf[off + 3], 255, "A");

  eq(fb.get(5, 7), 0xFF0000, "get");

  const before = fb.countLit();
  fb.set(-1, 5, 0x00FF00);
  fb.set(16, 5, 0x00FF00);
  fb.set(5, -1, 0x00FF00);
  fb.set(5, 16, 0x00FF00);
  eq(fb.countLit(), before, "OOB");

  ok(fb.set(3, 3, 0x0000FF), "in-bounds");
  ok(!fb.set(-5, 3, 0x0000FF), "OOB false");

  fb.clear();
  fb.drawHLine(2, 8, 4, 0x00FF00);
  eq(fb.countLit(), 4, "hline count");
  eq(fb.get(2, 8), 0x00FF00, "hline (2,8)");
  eq(fb.get(5, 8), 0x00FF00, "hline (5,8)");
  eq(fb.get(6, 8), 0, "hline stops");

  fb.clear();
  fb.drawVLine(7, 2, 4, 0x0000FF);
  eq(fb.countLit(), 4, "vline count");
  eq(fb.get(7, 2), 0x0000FF, "vline (7,2)");
  eq(fb.get(7, 5), 0x0000FF, "vline (7,5)");
  eq(fb.get(7, 6), 0, "vline stops");

  fb.clear();
  fb.drawHLine(14, 5, 4, 0xFF0000);
  eq(fb.countLit(), 2, "hline clipped");

  console.log("framebuffer_rendering: 18/18 ok");
}

main();
