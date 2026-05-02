// Vidya — Maze Generation in TypeScript
//
// Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell
// stores a bitmask of present walls (N=1, S=2, E=4, W=8). Generation
// carves passages by clearing the wall bit on both the current and the
// neighbour cell.
//
// JavaScript `number` is double-precision float; bitwise ops collapse
// to 32 bits — neither matches PCG's 64-bit modular arithmetic. We use
// `BigInt` for the state, mask to 64 bits, then drop to a regular
// `number` once the value is in the safe-integer range. Output bytes
// match cyrius byte-for-byte.

const GW = 8;
const GH = 8;
const GN = GW * GH;

const WN = 1;
const WS = 2;
const WE = 4;
const WW = 8;
const WALLS_ALL = 15;

const PCG_MULT = 6364136223846793005n;
const PCG_INC = 1442695040888963407n;
const U64_MASK = (1n << 64n) - 1n;

class Rng {
  private state: bigint;
  constructor(seed: bigint | number = 12345n) {
    this.state = BigInt(seed);
  }
  seed(s: bigint | number): void {
    this.state = BigInt(s);
  }
  next(): number {
    // Explicit u64 mask — BigInt is arbitrary precision, so we have to
    // ask for the wrap that other languages get from native i64
    // overflow.
    this.state = (this.state * PCG_MULT + PCG_INC) & U64_MASK;
    // Top 31 bits — masking keeps the result non-negative and well
    // within Number.MAX_SAFE_INTEGER.
    return Number((this.state >> 33n) & 0x7fffffffn);
  }
  range(max: number): number {
    if (max <= 0) return 0;
    return this.next() % max;
  }
}

const idx = (x: number, y: number) => y * GW + x;

function opposite(d: number): number {
  switch (d) {
    case WN: return WS;
    case WS: return WN;
    case WE: return WW;
    case WW: return WE;
  }
  return 0;
}

interface Neighbour { dir: number; nx: number; ny: number; }

class Maze {
  cells: Uint8Array = new Uint8Array(GN);
  visited: Uint8Array = new Uint8Array(GN);

  constructor() {
    this.reset();
  }
  reset(): void {
    this.cells.fill(WALLS_ALL);
    this.visited.fill(0);
  }
  carve(x: number, y: number, d: number, nx: number, ny: number): void {
    const ci = idx(x, y);
    const ni = idx(nx, ny);
    const od = opposite(d);
    // Clear the wall on both sides — a half-removed wall would break
    // wall-consistency checks.
    this.cells[ci] &= ~d & 0xff;
    this.cells[ni] &= ~od & 0xff;
  }
  collectUnvisited(x: number, y: number): Neighbour[] {
    const out: Neighbour[] = [];
    if (y > 0 && this.visited[idx(x, y - 1)] === 0)
      out.push({ dir: WN, nx: x, ny: y - 1 });
    if (y < GH - 1 && this.visited[idx(x, y + 1)] === 0)
      out.push({ dir: WS, nx: x, ny: y + 1 });
    if (x > 0 && this.visited[idx(x - 1, y)] === 0)
      out.push({ dir: WW, nx: x - 1, ny: y });
    if (x < GW - 1 && this.visited[idx(x + 1, y)] === 0)
      out.push({ dir: WE, nx: x + 1, ny: y });
    return out;
  }
  generate(rng: Rng, sx: number, sy: number): void {
    this.reset();
    const stack: number[] = [];
    stack.push(idx(sx, sy));
    this.visited[idx(sx, sy)] = 1;
    while (stack.length > 0) {
      const top = stack[stack.length - 1];
      const tx = top % GW;
      const ty = Math.floor(top / GW);
      const nbrs = this.collectUnvisited(tx, ty);
      if (nbrs.length === 0) {
        stack.pop();
      } else {
        const pick = rng.range(nbrs.length);
        const n = nbrs[pick];
        this.carve(tx, ty, n.dir, n.nx, n.ny);
        this.visited[idx(n.nx, n.ny)] = 1;
        stack.push(idx(n.nx, n.ny));
      }
    }
  }
  countVisited(): number {
    let n = 0;
    for (const v of this.visited) if (v !== 0) n++;
    return n;
  }
  countRemovedWalls(): number {
    let removed = 0;
    for (let y = 0; y < GH; y++) {
      for (let x = 0; x < GW; x++) {
        const w = this.cells[idx(x, y)];
        if (y > 0 && (w & WN) === 0) removed++;
        if (x > 0 && (w & WW) === 0) removed++;
      }
    }
    return removed;
  }
  wallsConsistent(): boolean {
    for (let y = 0; y < GH; y++) {
      for (let x = 0; x < GW; x++) {
        const w = this.cells[idx(x, y)];
        if (x < GW - 1) {
          const nw = this.cells[idx(x + 1, y)];
          if (((w & WE) === 0) !== ((nw & WW) === 0)) return false;
        }
        if (y < GH - 1) {
          const sw = this.cells[idx(x, y + 1)];
          if (((w & WS) === 0) !== ((sw & WN) === 0)) return false;
        }
      }
    }
    return true;
  }
}

function check(cond: boolean, msg: string): void {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
}

// init state
{
  const m = new Maze();
  check(m.cells[0] === WALLS_ALL, "init: cell 0");
  check(m.cells[63] === WALLS_ALL, "init: cell 63");
  check(m.visited[0] === 0, "init: cell 0 not visited");
}

// full coverage
{
  const rng = new Rng(42n);
  const m = new Maze();
  m.generate(rng, 0, 0);
  check(m.countVisited() === GN, "all 64 cells visited");
}

// perfect maze wall count
{
  const rng = new Rng(42n);
  const m = new Maze();
  m.generate(rng, 0, 0);
  check(m.countRemovedWalls() === GN - 1, "perfect maze: GN-1 walls");
}

// wall consistency
{
  const rng = new Rng(42n);
  const m = new Maze();
  m.generate(rng, 0, 0);
  check(m.wallsConsistent(), "wall pairs consistent");
}

// determinism
{
  const rng = new Rng(42n);
  const a = new Maze();
  a.generate(rng, 0, 0);
  const [c0, c27, c63] = [a.cells[0], a.cells[27], a.cells[63]];
  rng.seed(42n);
  const b = new Maze();
  b.generate(rng, 0, 0);
  check(b.cells[0] === c0, "deterministic: cell 0");
  check(b.cells[27] === c27, "deterministic: cell 27");
  check(b.cells[63] === c63, "deterministic: cell 63");
}

// different seeds differ
{
  const rng = new Rng(1n);
  const a = new Maze();
  a.generate(rng, 0, 0);
  let sum1 = 0;
  for (const v of a.cells) sum1 += v;
  rng.seed(2n);
  const b = new Maze();
  b.generate(rng, 0, 0);
  let sum2 = 0;
  for (const v of b.cells) sum2 += v;
  check(sum1 !== sum2, "different seeds produce different mazes");
}

// starting cell visited
{
  const rng = new Rng(42n);
  const m = new Maze();
  m.generate(rng, 3, 5);
  check(m.visited[idx(3, 5)] === 1, "start cell marked visited");
  check(m.countVisited() === GN, "all cells reachable");
}

// cross-language byte parity (matches cyrius reference)
{
  const rng = new Rng(42n);
  const m = new Maze();
  m.generate(rng, 0, 0);
  check(m.cells[0] === 13, "parity: cell 0 == 13");
  check(m.cells[27] === 12, "parity: cell 27 == 12");
  check(m.cells[63] === 6, "parity: cell 63 == 6");
}

console.log("All maze_generation examples passed.");
