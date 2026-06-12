// Vidya — Build Systems — TypeScript port.
//
// A minimal build-system core: a DAG of targets, topological build order,
// content-signature dirty-tracking, and ninja-style incremental rebuild
// (only dirty targets run), plus cycle detection.
//
// No real files or compilers: each target carries a source "content
// signature" (a number). A target's INPUT signature mixes its own source
// with the OUTPUT signatures of its dependencies; if that differs from the
// signature it was last built against, the target is dirty and rebuilds.
// Editing a source changes its signature, which transitively re-dirties
// everything downstream — exactly how mtime/hash-based tools (make, ninja,
// bazel) decide what to redo.
//
// All signatures stay < 2^53 (HB=131, HM=1000003 keep products < 1.4e8),
// so plain number arithmetic is exact — no BigInt needed.

const HB = 131;        // signature polynomial base
const HM = 1000003;    // signature modulus (prime; keeps values < 2^53)

class BuildSystem {
    src: number[] = [];      // source content signature
    deps: number[][] = [];   // dependency lists
    built: number[] = [];    // signature last built against (-1 = never)
    out: number[] = [];      // current output signature
    order: number[] = [];    // topological order (target ids)

    constructor(n: number) {
        for (let i = 0; i < n; i++) {
            this.src.push(0);
            this.deps.push([]);
            this.built.push(-1);   // never built
            this.out.push(0);
        }
    }

    get nTargets(): number { return this.src.length; }

    setSrc(t: number, sig: number): void { this.src[t] = sig; }
    addDep(t: number, d: number): void { this.deps[t].push(d); }

    // Topological sort (Kahn-style ready-scan). Writes target ids into
    // order and returns how many were ordered; < nTargets ⇒ a cycle left
    // some targets unreachable.
    topo(): number {
        const placed = new Array<boolean>(this.nTargets).fill(false);
        this.order = [];
        while (this.order.length < this.nTargets) {
            let progress = false;
            for (let t = 0; t < this.nTargets; t++) {
                if (placed[t]) continue;
                // ready iff every dependency is already placed
                let ready = true;
                for (const d of this.deps[t]) {
                    if (!placed[d]) ready = false;
                }
                if (ready) {
                    this.order.push(t);
                    placed[t] = true;
                    progress = true;
                }
            }
            if (!progress) return this.order.length;   // stuck ⇒ cycle
        }
        return this.order.length;
    }

    // Input signature: mix this target's source with deps' outputs.
    sig(t: number): number {
        let s = this.src[t] % HM;
        for (const d of this.deps[t]) {
            s = (s * HB + this.out[d]) % HM;
        }
        return s;
    }

    // Incremental build: walk topo order, rebuild only dirty targets.
    // Output is content-addressed (out == input signature), so a target
    // whose inputs are unchanged keeps its output and its dependents stay
    // clean. Returns the number of targets rebuilt.
    build(): number {
        const ordered = this.topo();
        let rebuilt = 0;
        for (let i = 0; i < ordered; i++) {
            const t = this.order[i];
            const s = this.sig(t);
            if (s !== this.built[t]) {
                this.out[t] = s;     // produce output
                this.built[t] = s;   // remember what we built
                rebuilt++;
            }
        }
        return rebuilt;
    }

    orderPos(target: number): number {
        return this.order.indexOf(target);
    }
}

// Classic C build graph:  app(2) <- util.o(0), main.o(1)
function buildGraph(): BuildSystem {
    const bs = new BuildSystem(3);
    bs.setSrc(0, 1001);   // util.c
    bs.setSrc(1, 2002);   // main.c
    bs.setSrc(2, 3003);   // link recipe
    bs.addDep(2, 0);
    bs.addDep(2, 1);
    return bs;
}

function assert(cond: boolean, name: string): void {
    if (!cond) throw new Error("FAIL: " + name);
}

// --- Tests ---

{
    // topo orders all 3 targets, with app after both deps
    const bs = buildGraph();
    assert(bs.topo() === 3, "topo orders all 3 targets");
    assert(bs.orderPos(2) > bs.orderPos(0), "app built after util.o");
    assert(bs.orderPos(2) > bs.orderPos(1), "app built after main.o");
}
{
    // cold build rebuilds all 3
    const bs = buildGraph();
    assert(bs.build() === 3, "cold build rebuilds all 3");
}
{
    // second build (no edits) rebuilds nothing
    const bs = buildGraph();
    bs.build();
    assert(bs.build() === 0, "no-op build rebuilds nothing");
}
{
    // edit main.c rebuilds main.o + app
    const bs = buildGraph();
    bs.build();
    bs.setSrc(1, 2999);   // edit main.c
    assert(bs.build() === 2, "edit main.c rebuilds main.o + app");
}
{
    // edit util.c rebuilds util.o + app, leaves main.o untouched
    const bs = buildGraph();
    bs.build();
    const mainBuilt = bs.built[1];
    bs.setSrc(0, 1999);   // edit util.c
    assert(bs.build() === 2, "edit util.c rebuilds util.o + app");
    assert(bs.built[1] === mainBuilt, "main.o left untouched");
}
{
    // 0 <-> 1 cycle leaves targets unordered
    const bs = new BuildSystem(2);
    bs.addDep(0, 1);
    bs.addDep(1, 0);
    assert(bs.topo() < 2, "cycle leaves targets unordered");
}

console.log("All build_systems examples passed.");
process.exit(0);
