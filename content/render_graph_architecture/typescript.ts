// Vidya — Render Graph Architecture in TypeScript
//
// Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

const PASS_CAP = 16;

class Graph {
  passId = new Array<number>(PASS_CAP).fill(0);
  reads = new Array<number>(PASS_CAP).fill(0);
  writes = new Array<number>(PASS_CAP).fill(0);
  count = 0;
  topoOrder = new Array<number>(PASS_CAP).fill(0);
  topoLen = 0;

  addPass(id: number, r: number, w: number): number {
    if (this.count >= PASS_CAP) return -1;
    const idx = this.count++;
    this.passId[idx] = id;
    this.reads[idx] = r;
    this.writes[idx] = w;
    return idx;
  }

  hasEdge(p: number, c: number): boolean {
    return (this.writes[p] & this.reads[c]) !== 0;
  }

  topoSort(): number {
    const inDegree = new Array<number>(PASS_CAP).fill(0);
    for (let i = 0; i < this.count; i++) {
      for (let j = 0; j < this.count; j++) {
        if (i !== j && this.hasEdge(j, i)) inDegree[i]++;
      }
    }
    this.topoLen = 0;
    let emitted = 0;
    while (emitted < this.count) {
      let picked = -1;
      for (let k = 0; k < this.count; k++) {
        if (inDegree[k] === 0) { picked = k; break; }
      }
      if (picked < 0) return this.topoLen;
      this.topoOrder[this.topoLen++] = picked;
      inDegree[picked] = -1;
      for (let c = 0; c < this.count; c++) {
        if (c !== picked && this.hasEdge(picked, c) && inDegree[c] > 0) {
          inDegree[c]--;
        }
      }
      emitted++;
    }
    return this.topoLen;
  }

  barrierCount(): number {
    let count = 0;
    for (let i = 0; i < this.topoLen; i++) {
      for (let j = i + 1; j < this.topoLen; j++) {
        if (this.hasEdge(this.topoOrder[i], this.topoOrder[j])) count++;
      }
    }
    return count;
  }

  cullDead(): number {
    let culled = 0;
    for (let i = 0; i < this.count; i++) {
      const w = this.writes[i];
      if (w === 0) continue;
      let anyReader = false;
      for (let j = 0; j < this.count; j++) {
        if (i !== j && (w & this.reads[j]) !== 0) { anyReader = true; break; }
      }
      if (!anyReader) {
        this.writes[i] = 0;
        this.reads[i] = 0;
        culled++;
      }
    }
    return culled;
  }
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const g = new Graph();

  eq(g.addPass(100, 0, 1), 0, "a");
  eq(g.addPass(101, 1, 2), 1, "b");
  eq(g.addPass(102, 2, 0), 2, "c");

  eq(g.topoSort(), 3, "topo3");
  eq(g.topoOrder[0], 0, "topo[0]");
  eq(g.topoOrder[1], 1, "topo[1]");
  eq(g.topoOrder[2], 2, "topo[2]");

  eq(g.barrierCount(), 2, "barriers");

  eq(g.addPass(103, 0, 4), 3, "d");
  eq(g.cullDead(), 1, "cull");
  if (g.writes[3] !== 0) throw new Error("writes zeroed");
  eq(g.topoSort(), 4, "topo4");
  eq(g.barrierCount(), 2, "barriers post-cull");

  const g2 = new Graph();
  g2.addPass(200, 1, 2);
  g2.addPass(201, 2, 1);
  eq(g2.topoSort(), 0, "cycle");

  console.log("render_graph_architecture: 14/14 ok");
}

main();
