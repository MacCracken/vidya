// Vidya — Grid Pathfinding in TypeScript
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
// TS uses plain `number[]` arrays for the grid + visited (Number is
// fine: 8*8 = 64 cells fits trivially), an array-as-deque for BFS
// (`shift()` is O(N) but N <= 64, so fine here), and a hand-rolled
// binary min-heap for A*'s open set ordered by f-score. Manhattan
// distance is the heuristic.

const GW = 8;
const GH = 8;
const GN = GW * GH;

function idx(x: number, y: number): number { return y * GW + x; }

function manhattan(ax: number, ay: number, bx: number, by: number): number {
    return Math.abs(ax - bx) + Math.abs(ay - by);
}

function neighbours(curr: number): number[] {
    const cx = curr % GW, cy = (curr / GW) | 0;
    const out: number[] = [];
    if (cy > 0)      out.push(curr - GW);
    if (cy < GH - 1) out.push(curr + GW);
    if (cx > 0)      out.push(curr - 1);
    if (cx < GW - 1) out.push(curr + 1);
    return out;
}

function gridClear(): number[] { return new Array(GN).fill(0); }
function gridBlock(g: number[], x: number, y: number): void { g[idx(x, y)] = 1; }

function bfs(grid: number[], start: number, goal: number): number {
    if (start === goal) return 0;
    const visited = new Array<boolean>(GN).fill(false);
    const dist = new Array<number>(GN).fill(-1);
    const q: number[] = [start];
    visited[start] = true;
    dist[start] = 0;
    while (q.length > 0) {
        const curr = q.shift()!;
        if (curr === goal) return dist[curr];
        for (const n of neighbours(curr)) {
            if (!visited[n] && grid[n] === 0) {
                visited[n] = true;
                dist[n] = dist[curr] + 1;
                q.push(n);
            }
        }
    }
    return -1;
}

// --- Min-heap over [f, cell] tuples (f is the comparator key) ---
class MinHeap {
    data: [number, number][] = [];
    push(x: [number, number]): void {
        this.data.push(x);
        this.siftUp(this.data.length - 1);
    }
    pop(): [number, number] | undefined {
        const n = this.data.length;
        if (n === 0) return undefined;
        const top = this.data[0];
        const last = this.data.pop()!;
        if (n > 1) {
            this.data[0] = last;
            this.siftDown(0);
        }
        return top;
    }
    get size(): number { return this.data.length; }
    private siftUp(i: number): void {
        while (i > 0) {
            const p = (i - 1) >> 1;
            if (this.data[p][0] <= this.data[i][0]) break;
            [this.data[p], this.data[i]] = [this.data[i], this.data[p]];
            i = p;
        }
    }
    private siftDown(i: number): void {
        const n = this.data.length;
        while (true) {
            const l = 2 * i + 1, r = 2 * i + 2;
            let s = i;
            if (l < n && this.data[l][0] < this.data[s][0]) s = l;
            if (r < n && this.data[r][0] < this.data[s][0]) s = r;
            if (s === i) break;
            [this.data[s], this.data[i]] = [this.data[i], this.data[s]];
            i = s;
        }
    }
}

function astar(grid: number[], sx: number, sy: number, gx: number, gy: number): number {
    const start = idx(sx, sy), goal = idx(gx, gy);
    const gScore = new Array<number>(GN).fill(Number.MAX_SAFE_INTEGER);
    const closed = new Array<boolean>(GN).fill(false);
    gScore[start] = 0;
    const open = new MinHeap();
    open.push([manhattan(sx, sy, gx, gy), start]);

    while (open.size > 0) {
        const [, curr] = open.pop()!;
        if (curr === goal) return gScore[goal];
        if (closed[curr]) continue;
        closed[curr] = true;
        const tg = gScore[curr] + 1;
        for (const n of neighbours(curr)) {
            if (closed[n] || grid[n] !== 0) continue;
            if (tg < gScore[n]) {
                gScore[n] = tg;
                const nx = n % GW, ny = (n / GW) | 0;
                const f = tg + manhattan(nx, ny, gx, gy);
                open.push([f, n]);
            }
        }
    }
    return -1;
}

function mustEq(got: number, want: number, msg: string): void {
    if (got !== want) throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
}

function main(): void {
    // manhattan
    mustEq(manhattan(0, 0, 0, 0), 0, "m(0,0,0,0)");
    mustEq(manhattan(0, 0, 3, 4), 7, "m(0,0,3,4)");
    mustEq(manhattan(7, 7, 0, 0), 14, "m(7,7,0,0)");
    mustEq(manhattan(2, 5, 5, 2), 6, "m(2,5,5,2)");

    // bfs empty
    let g = gridClear();
    mustEq(bfs(g, idx(0, 0), idx(7, 7)), 14, "bfs empty");

    // bfs same
    g = gridClear();
    mustEq(bfs(g, idx(3, 3), idx(3, 3)), 0, "bfs same");

    // bfs around wall
    g = gridClear();
    for (let y = 0; y < 7; y++) gridBlock(g, 4, y);
    mustEq(bfs(g, idx(0, 0), idx(7, 0)), 21, "bfs around wall");

    // bfs unreachable
    g = gridClear();
    gridBlock(g, 6, 7);
    gridBlock(g, 7, 6);
    mustEq(bfs(g, idx(0, 0), idx(7, 7)), -1, "bfs unreachable");

    // astar empty
    g = gridClear();
    mustEq(astar(g, 0, 0, 7, 7), 14, "astar empty");

    // astar matches bfs (wall)
    g = gridClear();
    for (let y = 0; y < 7; y++) gridBlock(g, 4, y);
    const bfsLen = bfs(g, idx(0, 0), idx(7, 0));
    const astarLen = astar(g, 0, 0, 7, 0);
    mustEq(astarLen, bfsLen, "astar == bfs (wall)");
    mustEq(astarLen, 21, "astar wall");

    // astar unreachable
    g = gridClear();
    gridBlock(g, 6, 7);
    gridBlock(g, 7, 6);
    mustEq(astar(g, 0, 0, 7, 7), -1, "astar unreachable");

    console.log("All grid_pathfinding examples passed.");
}

main();
