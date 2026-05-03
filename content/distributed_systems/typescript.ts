// Vidya — Distributed Systems Foundations — TypeScript port.

const N_NODES = 3;
const W = 2;
const R = 2;

const enum VC { Less = 1, Equal = 2, Greater = 3, Concurrent = 4 }

class VClock {
    c: number[] = [0, 0, 0];
    tick(node: number): void { this.c[node] += 1; }
    merge(from: VClock): void {
        for (let i = 0; i < N_NODES; i++) {
            if (from.c[i] > this.c[i]) this.c[i] = from.c[i];
        }
    }
    compare(other: VClock): VC {
        let anyLT = false, anyGT = false;
        for (let i = 0; i < N_NODES; i++) {
            if (this.c[i] < other.c[i]) anyLT = true;
            if (this.c[i] > other.c[i]) anyGT = true;
        }
        if (!anyLT && !anyGT) return VC.Equal;
        if (!anyLT) return VC.Greater;
        if (!anyGT) return VC.Less;
        return VC.Concurrent;
    }
}

class QCluster {
    accounts: number[] = [0, 0, 0];
    writeSeq: number[] = [0, 0, 0];
    alive: boolean[] = [true, true, true];
    globalSeq: number = 0;

    partition(n: number): void { this.alive[n] = false; }
    heal(n: number): void { this.alive[n] = true; }
    aliveCount(): number { return this.alive.filter(a => a).length; }

    write(value: number): boolean {
        if (this.aliveCount() < W) return false;
        this.globalSeq += 1;
        for (let i = 0; i < N_NODES; i++) {
            if (this.alive[i]) {
                this.accounts[i] = value;
                this.writeSeq[i] = this.globalSeq;
            }
        }
        return true;
    }
    read(): number | null {
        if (this.aliveCount() < R) return null;
        let bestSeq = 0, bestValue = 0;
        for (let i = 0; i < N_NODES; i++) {
            if (this.alive[i] && this.writeSeq[i] > bestSeq) {
                bestSeq = this.writeSeq[i];
                bestValue = this.accounts[i];
            }
        }
        return bestValue;
    }
}

let passCount = 0, failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

function arrEq(a: number[], b: number[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    return true;
}

{
    const v = new VClock();
    check(arrEq(v.c, [0, 0, 0]), "vc init");
}
{
    const v = new VClock();
    v.tick(1); v.tick(1); v.tick(2);
    check(arrEq(v.c, [0, 2, 1]), "tick");
}
{
    const a = new VClock(); const b = new VClock();
    a.tick(0); a.tick(0);
    b.tick(1); b.tick(2);
    a.merge(b);
    check(arrEq(a.c, [2, 1, 1]), "merge max");
}
{
    const a = new VClock(); const b = new VClock();
    b.tick(0);
    check(a.compare(b) === VC.Less, "less");
}
{
    const a = new VClock(); const b = new VClock();
    a.tick(0); a.tick(0); b.tick(0);
    check(a.compare(b) === VC.Greater, "greater");
}
{
    const a = new VClock(); const b = new VClock();
    a.tick(1); b.tick(1);
    check(a.compare(b) === VC.Equal, "equal");
}
{
    const a = new VClock(); const b = new VClock();
    a.tick(0); b.tick(1);
    check(a.compare(b) === VC.Concurrent, "concurrent");
    check(b.compare(a) === VC.Concurrent, "concurrent symmetric");
}
{
    const c = new QCluster();
    check(c.write(100), "write ok full");
    check(arrEq(c.accounts, [100, 100, 100]), "all wrote");
}
{
    const c = new QCluster();
    c.partition(2);
    check(c.write(200), "write ok 2 alive");
    check(c.accounts[0] === 200 && c.accounts[1] === 200, "0,1 wrote");
    check(c.accounts[2] === 0, "2 untouched");
}
{
    const c = new QCluster();
    c.partition(1); c.partition(2);
    check(!c.write(300), "write fails 1 alive");
    check(c.accounts[0] === 0, "no replica wrote");
}
{
    const c = new QCluster();
    c.partition(2); c.write(500); c.heal(2);
    c.partition(0);
    check(c.read() === 500, "intersection: read sees latest");
}
{
    const c = new QCluster();
    c.write(700);
    c.partition(0); c.partition(1);
    check(c.read() === null, "read null below R");
}

console.log("=== distributed_systems ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
