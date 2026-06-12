// Vidya — Build Systems — Rust port.
//
// A minimal build-system core: a DAG of targets, topological build
// order, content-signature dirty-tracking, and ninja-style incremental
// rebuild (only dirty targets run), plus cycle detection.
//
// No real files or compilers: each target carries a source "content
// signature" (an integer). A target's INPUT signature mixes its own
// source with the OUTPUT signatures of its dependencies; if that differs
// from the signature it was last built against, the target is dirty and
// rebuilds. Editing a source changes its signature, which transitively
// re-dirties everything downstream — exactly how mtime/hash-based tools
// (make, ninja, bazel) decide what to redo.

const HB: i64 = 131; // signature polynomial base
const HM: i64 = 1000003; // signature modulus (prime; keeps values < 2^53)

struct BuildSystem {
    src: Vec<i64>,       // source content signature
    deps: Vec<Vec<usize>>, // dependency lists
    built: Vec<i64>,     // signature last built against (-1 = never)
    out: Vec<i64>,       // current output signature
}

impl BuildSystem {
    fn new(n: usize) -> Self {
        BuildSystem {
            src: vec![0; n],
            deps: vec![Vec::new(); n],
            built: vec![-1; n], // never built
            out: vec![0; n],
        }
    }

    fn n_targets(&self) -> usize { self.src.len() }

    fn set_src(&mut self, t: usize, sig: i64) { self.src[t] = sig; }

    fn add_dep(&mut self, t: usize, d: usize) { self.deps[t].push(d); }

    // --- Topological sort (Kahn-style ready-scan). Writes target ids into
    //     `order` and returns how many were ordered; < n_targets ⇒ a cycle
    //     left some targets unreachable. ---
    fn topo(&self, order: &mut Vec<usize>) -> usize {
        let n = self.n_targets();
        order.clear();
        let mut placed_flag = vec![false; n];
        let mut placed = 0;
        while placed < n {
            let mut progress = false;
            for t in 0..n {
                if !placed_flag[t] {
                    // ready iff every dependency is already placed
                    let ready = self.deps[t].iter().all(|&d| placed_flag[d]);
                    if ready {
                        order.push(t);
                        placed_flag[t] = true;
                        placed += 1;
                        progress = true;
                    }
                }
            }
            if !progress { return placed; } // stuck ⇒ cycle
        }
        placed
    }

    // --- Input signature: mix this target's source with deps' outputs. ---
    fn sig(&self, t: usize) -> i64 {
        let mut sig = self.src[t] % HM;
        for &d in &self.deps[t] {
            sig = (sig * HB + self.out[d]) % HM;
        }
        sig
    }

    // --- Incremental build: walk topo order, rebuild only dirty targets.
    //     Output is content-addressed (out == input signature), so a target
    //     whose inputs are unchanged keeps its output and its dependents
    //     stay clean. Returns the number of targets rebuilt. ---
    fn build(&mut self) -> usize {
        let mut order = Vec::new();
        let ordered = self.topo(&mut order);
        let mut rebuilt = 0;
        for i in 0..ordered {
            let t = order[i];
            let sig = self.sig(t);
            if sig != self.built[t] {
                self.out[t] = sig; // produce output
                self.built[t] = sig; // remember what we built
                rebuilt += 1;
            }
        }
        rebuilt
    }
}

// Classic C build graph:  app(2) <- util.o(0), main.o(1)
fn build_graph() -> BuildSystem {
    let mut bs = BuildSystem::new(3);
    bs.set_src(0, 1001); // util.c
    bs.set_src(1, 2002); // main.c
    bs.set_src(2, 3003); // link recipe
    bs.add_dep(2, 0);
    bs.add_dep(2, 1);
    bs
}

fn order_pos(order: &[usize], target: usize) -> i32 {
    order.iter().position(|&t| t == target).map_or(-1, |p| p as i32)
}

fn main() {
    // --- topological order ---
    {
        let bs = build_graph();
        let mut order = Vec::new();
        assert_eq!(bs.topo(&mut order), 3, "topo orders all 3 targets");
        assert!(order_pos(&order, 2) > order_pos(&order, 0), "app built after util.o");
        assert!(order_pos(&order, 2) > order_pos(&order, 1), "app built after main.o");
    }

    // --- cold build rebuilds all ---
    {
        let mut bs = build_graph();
        assert_eq!(bs.build(), 3, "cold build rebuilds all 3");
    }

    // --- no-op build rebuilds none ---
    {
        let mut bs = build_graph();
        bs.build(); // cold
        assert_eq!(bs.build(), 0, "second build (no edits) rebuilds nothing");
    }

    // --- edit leaf rebuilds transitively ---
    {
        let mut bs = build_graph();
        bs.build(); // cold: all up to date
        bs.set_src(1, 2999); // edit main.c
        assert_eq!(bs.build(), 2, "edit main.c rebuilds main.o + app");
    }

    // --- edit other leaf skips sibling ---
    {
        let mut bs = build_graph();
        bs.build();
        let main_built = bs.built[1];
        bs.set_src(0, 1999); // edit util.c
        assert_eq!(bs.build(), 2, "edit util.c rebuilds util.o + app");
        assert_eq!(bs.built[1], main_built, "main.o left untouched");
    }

    // --- cycle detected ---
    {
        let mut bs = BuildSystem::new(2);
        bs.add_dep(0, 1);
        bs.add_dep(1, 0); // 0 <-> 1 cycle
        let mut order = Vec::new();
        assert!(bs.topo(&mut order) < 2, "cycle leaves targets unordered");
    }

    println!("All build_systems examples passed.");
}
