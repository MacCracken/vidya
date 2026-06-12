// Vidya — Package Resolution — Rust port.
//
// Semantic versioning, caret constraint matching, range intersection
// for diamond dependencies, highest-version selection, bounded
// backtracking, and dependency-cycle detection — the core of a
// dependency resolver (npm, cargo, cyrius.cyml's own resolver).
//
// A semver major.minor.patch is encoded as one i64
//   enc = major*1_000_000 + minor*1_000 + patch
// so version comparison IS integer comparison. A constraint is a
// half-open range [lo, hi). A caret ^X.Y.Z allows everything from
// X.Y.Z up to (but not including) the next major: [X.Y.Z, (X+1).0.0).

const VMAJ: i64 = 1_000_000;
const VMIN: i64 = 1_000;

// --- Semver encode / inspect ---
fn sv(maj: i64, min: i64, pat: i64) -> i64 { maj * VMAJ + min * VMIN + pat }
fn sv_major(v: i64) -> i64 { v / VMAJ }

// --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---
fn caret_lo(v: i64) -> i64 { v }
fn caret_hi(v: i64) -> i64 { (sv_major(v) + 1) * VMAJ }

// --- Constraint satisfaction over a half-open range ---
fn satisfies(v: i64, lo: i64, hi: i64) -> bool { lo <= v && v < hi }

// --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---
fn range_lo_max(a: i64, b: i64) -> i64 { if a > b { a } else { b } }
fn range_hi_min(a: i64, b: i64) -> i64 { if a < b { a } else { b } }
fn range_empty(lo: i64, hi: i64) -> bool { lo >= hi }

// --- Highest version in vers that lies in [lo, hi); -1 if none ---
fn best_match(vers: &[i64], lo: i64, hi: i64) -> i64 {
    let mut best = -1;
    for &v in vers {
        if satisfies(v, lo, hi) && v > best {
            best = v;
        }
    }
    best
}

// --- Available versions of the shared dependency C ---
fn c_versions() -> [i64; 3] {
    [sv(1, 0, 0), sv(1, 5, 0), sv(2, 0, 0)]
}

// --- Diamond resolution: A requires C ^a_base, B requires C ^b_base.
//     Intersect the two carets and pick the highest C that fits.
//     Returns chosen C version, or -1 if the constraints conflict. ---
fn resolve_shared(c_vers: &[i64], a_base: i64, b_base: i64) -> i64 {
    let lo = range_lo_max(caret_lo(a_base), caret_lo(b_base));
    let hi = range_hi_min(caret_hi(a_base), caret_hi(b_base));
    if range_empty(lo, hi) { return -1; }
    best_match(c_vers, lo, hi)
}

// --- Bounded backtracking: A has candidate versions (a_vers), each of
//     which requires a different caret on C (a_creq). B requires C
//     ^b_base. The absolute-highest A may force a C constraint that
//     conflicts with B; choose the HIGHEST A for which some C still
//     satisfies both. Returns (chosen A, chosen C); (-1, -1) if none. ---
fn resolve_backtrack(c_vers: &[i64], a_vers: &[i64], a_creq: &[i64], b_base: i64) -> (i64, i64) {
    let mut best_a = -1;
    let mut best_c = -1;
    for i in 0..a_vers.len() {
        let aver = a_vers[i];
        let creq = a_creq[i];
        let lo = range_lo_max(caret_lo(creq), caret_lo(b_base));
        let hi = range_hi_min(caret_hi(creq), caret_hi(b_base));
        if !range_empty(lo, hi) {
            let c = best_match(c_vers, lo, hi);
            if c != -1 && aver > best_a {
                best_a = aver;
                best_c = c;
            }
        }
    }
    (best_a, best_c)
}

// --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
//     some package permanently unplaceable). ---
struct PkgGraph {
    deps: Vec<Vec<usize>>,
}

impl PkgGraph {
    fn new(n: usize) -> Self {
        PkgGraph { deps: vec![Vec::new(); n] }
    }
    fn add_dep(&mut self, p: usize, d: usize) {
        self.deps[p].push(d);
    }
    fn has_cycle(&self) -> bool {
        let n = self.deps.len();
        let mut placed = vec![false; n];
        let mut count = 0;
        while count < n {
            let mut progress = false;
            for p in 0..n {
                if placed[p] { continue; }
                let ready = self.deps[p].iter().all(|&d| placed[d]);
                if ready {
                    placed[p] = true;
                    count += 1;
                    progress = true;
                }
            }
            if !progress { return true; } // stuck => cycle
        }
        false
    }
}

fn main() {
    // --- semver ---
    assert!(sv(1, 2, 3) > sv(1, 2, 0), "patch ordering");
    assert!(sv(2, 0, 0) > sv(1, 9, 9), "major dominates minor/patch");
    assert_eq!(sv_major(sv(1, 5, 2)), 1, "extract major");

    // --- caret ---
    assert_eq!(caret_lo(sv(1, 2, 0)), sv(1, 2, 0), "caret lower = base");
    assert_eq!(caret_hi(sv(1, 2, 0)), sv(2, 0, 0), "caret upper = next major");
    assert!(satisfies(sv(1, 4, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))), "1.4.0 in ^1.2.0");
    assert!(!satisfies(sv(2, 0, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))), "2.0.0 not in ^1.2.0");
    assert!(!satisfies(sv(1, 1, 0), caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))), "1.1.0 below ^1.2.0");

    // --- intersect ---
    assert_eq!(range_lo_max(sv(1, 0, 0), sv(1, 3, 0)), sv(1, 3, 0), "intersect lo = max");
    assert_eq!(range_hi_min(sv(2, 0, 0), sv(3, 0, 0)), sv(2, 0, 0), "intersect hi = min");
    {
        let lo = range_lo_max(caret_lo(sv(1, 0, 0)), caret_lo(sv(2, 0, 0)));
        let hi = range_hi_min(caret_hi(sv(1, 0, 0)), caret_hi(sv(2, 0, 0)));
        assert!(range_empty(lo, hi), "^1.0.0 and ^2.0.0 are disjoint");
    }

    let c_vers = c_versions();

    // --- best_match ---
    assert_eq!(best_match(&c_vers, caret_lo(sv(1, 0, 0)), caret_hi(sv(1, 0, 0))), sv(1, 5, 0), "highest C in ^1.0.0 = 1.5.0");
    assert_eq!(best_match(&c_vers, caret_lo(sv(3, 0, 0)), caret_hi(sv(3, 0, 0))), -1, "no C in ^3.0.0");

    // --- diamond resolution ---
    assert_eq!(resolve_shared(&c_vers, sv(1, 0, 0), sv(1, 0, 0)), sv(1, 5, 0), "A^1 n B^1 picks C 1.5.0");
    assert_eq!(resolve_shared(&c_vers, sv(1, 0, 0), sv(2, 0, 0)), -1, "A^1 vs B^2 is unresolvable");

    // --- bounded backtracking ---
    // A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
    // The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
    {
        let a_vers = [sv(1, 1, 0), sv(1, 0, 0)];
        let a_creq = [sv(2, 0, 0), sv(1, 0, 0)];
        let (chosen_a, chosen_c) = resolve_backtrack(&c_vers, &a_vers, &a_creq, sv(1, 0, 0));
        assert_eq!(chosen_a, sv(1, 0, 0), "backtrack picks A 1.0.0, not 1.1.0");
        assert_eq!(chosen_c, sv(1, 5, 0), "and resolves C to 1.5.0");
    }

    // --- cycle detection ---
    {
        let mut g = PkgGraph::new(2);
        g.add_dep(0, 1);
        g.add_dep(1, 0);
        assert!(g.has_cycle(), "A<->B is a dependency cycle");
    }
    {
        let mut g = PkgGraph::new(3);
        g.add_dep(2, 0);
        g.add_dep(2, 1); // app -> A, B (diamond, acyclic)
        assert!(!g.has_cycle(), "diamond graph is acyclic");
    }

    println!("All package_resolution examples passed.");
}
