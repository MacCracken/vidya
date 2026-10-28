// Vidya — Line Rasterization (Bresenham) in TypeScript
//
// All-octant integer Bresenham on a 16x16 byte framebuffer.

const FB_W = 16;
const FB_H = 16;
const FB_BYTES = FB_W * FB_H;

const fb = new Uint8Array(FB_BYTES);

function fbClear(): void { fb.fill(0); }

function fbSet(x: number, y: number, v: number): void {
  if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return;
  fb[y * FB_W + x] = v;
}

function fbGet(x: number, y: number): number {
  if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) return 0;
  return fb[y * FB_W + x];
}

function countLit(): number {
  let n = 0;
  for (const v of fb) if (v !== 0) n++;
  return n;
}

function sign(v: number): number {
  return v > 0 ? 1 : v < 0 ? -1 : 0;
}

function drawLine(x0: number, y0: number, x1: number, y1: number, v: number): void {
  const dx = Math.abs(x1 - x0);
  const dy = Math.abs(y1 - y0);
  const sx = sign(x1 - x0);
  const sy = sign(y1 - y0);
  let err = dx - dy;
  let x = x0, y = y0;
  for (;;) {
    fbSet(x, y, v);
    if (x === x1 && y === y1) return;
    const e2 = err * 2;
    if (e2 > -dy) { err -= dy; x += sx; }
    if (e2 < dx)  { err += dx; y += sy; }
  }
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  fbClear(); drawLine(2, 5, 8, 5, 1);
  eq(countLit(), 7, "h count");
  eq(fbGet(2, 5), 1, "h L"); eq(fbGet(8, 5), 1, "h R");
  eq(fbGet(5, 5), 1, "h M"); eq(fbGet(5, 6), 0, "h off");

  fbClear(); drawLine(5, 2, 5, 8, 1);
  eq(countLit(), 7, "v count");
  eq(fbGet(5, 2), 1, "v T"); eq(fbGet(5, 8), 1, "v B");
  eq(fbGet(5, 5), 1, "v M"); eq(fbGet(6, 5), 0, "v off");

  fbClear(); drawLine(2, 2, 7, 7, 1);
  eq(countLit(), 6, "+d count");
  eq(fbGet(2, 2), 1, "+d S"); eq(fbGet(7, 7), 1, "+d E");
  eq(fbGet(5, 5), 1, "+d M"); eq(fbGet(5, 4), 0, "+d off");

  fbClear(); drawLine(2, 7, 7, 2, 1);
  eq(countLit(), 6, "-d count");
  eq(fbGet(2, 7), 1, "-d S"); eq(fbGet(7, 2), 1, "-d E");
  eq(fbGet(5, 4), 1, "-d M");

  fbClear(); drawLine(3, 1, 5, 11, 1);
  eq(countLit(), 11, "steep count");
  eq(fbGet(3, 1), 1, "steep S"); eq(fbGet(5, 11), 1, "steep E");

  fbClear(); drawLine(8, 8, 8, 8, 1);
  eq(countLit(), 1, "point count");
  eq(fbGet(8, 8), 1, "point lit");

  fbClear(); drawLine(8, 5, 2, 5, 1);
  eq(countLit(), 7, "rev count");
  eq(fbGet(2, 5), 1, "rev L"); eq(fbGet(8, 5), 1, "rev R");

  console.log("line_rasterization: 27/27 ok");
}

main();
