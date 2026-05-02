// Vidya — Maze Generation in Rust
//
// Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell stores
// a bitmask of present walls (N=1, S=2, E=4, W=8). Generation carves
// passages by clearing the corresponding bit on the current and
// neighbour cell. Rust's `wrapping_mul` / `wrapping_add` give us the
// modular-2^64 arithmetic the PCG state needs — overflow is defined,
// we just have to ask for it. The PRNG step matches cyrius byte-for-
// byte: same constants, same mask, same shift.

#![allow(dead_code, unused_assignments)]

const GW: usize = 8;
const GH: usize = 8;
const GN: usize = GW * GH;

const WN: u8 = 1;
const WS: u8 = 2;
const WE: u8 = 4;
const WW: u8 = 8;
const WALLS_ALL: u8 = 15;

const PCG_MULT: u64 = 6364136223846793005;
const PCG_INC: u64 = 1442695040888963407;

struct Rng {
    state: u64,
}

impl Rng {
    fn new(seed: u64) -> Self {
        Rng { state: seed }
    }

    fn seed(&mut self, s: u64) {
        self.state = s;
    }

    fn next(&mut self) -> i64 {
        // PCG step: u64 wraparound is the natural mod-2^64 arithmetic.
        self.state = self.state.wrapping_mul(PCG_MULT).wrapping_add(PCG_INC);
        // Top bits give better distribution. Mask to 31 bits so the
        // result is non-negative and the modulo below is well-defined.
        ((self.state >> 33) & 0x7fff_ffff) as i64
    }

    fn range(&mut self, max: i64) -> i64 {
        if max <= 0 {
            return 0;
        }
        // After the mask above, `next()` is non-negative, so this is
        // exactly the (positive) modulo cyrius computes.
        self.next() % max
    }
}

struct Maze {
    cells: [u8; GN],
    visited: [bool; GN],
}

impl Maze {
    fn new() -> Self {
        Maze {
            cells: [WALLS_ALL; GN],
            visited: [false; GN],
        }
    }

    fn idx(x: usize, y: usize) -> usize {
        y * GW + x
    }

    fn opposite(d: u8) -> u8 {
        match d {
            WN => WS,
            WS => WN,
            WE => WW,
            WW => WE,
            _ => 0,
        }
    }

    fn carve(&mut self, x: usize, y: usize, dir: u8, nx: usize, ny: usize) {
        let ci = Self::idx(x, y);
        let ni = Self::idx(nx, ny);
        let od = Self::opposite(dir);
        // Clear the wall on the current cell, and the matching wall on
        // the neighbour. Without both edits the maze would look like a
        // half-removed wall on one side and a full wall on the other.
        self.cells[ci] &= !dir;
        self.cells[ni] &= !od;
    }

    fn collect_unvisited(&self, x: usize, y: usize) -> Vec<(u8, usize, usize)> {
        let mut out = Vec::with_capacity(4);
        if y > 0 && !self.visited[Self::idx(x, y - 1)] {
            out.push((WN, x, y - 1));
        }
        if y + 1 < GH && !self.visited[Self::idx(x, y + 1)] {
            out.push((WS, x, y + 1));
        }
        if x > 0 && !self.visited[Self::idx(x - 1, y)] {
            out.push((WW, x - 1, y));
        }
        if x + 1 < GW && !self.visited[Self::idx(x + 1, y)] {
            out.push((WE, x + 1, y));
        }
        out
    }

    fn generate(&mut self, rng: &mut Rng, sx: usize, sy: usize) {
        // Reset state — this matches cyrius's maze_init+visited reset.
        self.cells = [WALLS_ALL; GN];
        self.visited = [false; GN];
        let mut stack: Vec<(usize, usize)> = Vec::with_capacity(GN);
        stack.push((sx, sy));
        self.visited[Self::idx(sx, sy)] = true;
        while let Some(&(tx, ty)) = stack.last() {
            let nbrs = self.collect_unvisited(tx, ty);
            if nbrs.is_empty() {
                stack.pop();
            } else {
                let pick = rng.range(nbrs.len() as i64) as usize;
                let (d, nx, ny) = nbrs[pick];
                self.carve(tx, ty, d, nx, ny);
                self.visited[Self::idx(nx, ny)] = true;
                stack.push((nx, ny));
            }
        }
    }

    fn count_visited(&self) -> usize {
        self.visited.iter().filter(|v| **v).count()
    }

    fn count_removed_walls(&self) -> usize {
        let mut removed = 0;
        for y in 0..GH {
            for x in 0..GW {
                let w = self.cells[Self::idx(x, y)];
                if y > 0 && (w & WN) == 0 {
                    removed += 1;
                }
                if x > 0 && (w & WW) == 0 {
                    removed += 1;
                }
            }
        }
        removed
    }

    fn walls_consistent(&self) -> bool {
        for y in 0..GH {
            for x in 0..GW {
                let w = self.cells[Self::idx(x, y)];
                if x + 1 < GW {
                    let nw = self.cells[Self::idx(x + 1, y)];
                    if (w & WE == 0) != (nw & WW == 0) {
                        return false;
                    }
                }
                if y + 1 < GH {
                    let sw = self.cells[Self::idx(x, y + 1)];
                    if (w & WS == 0) != (sw & WN == 0) {
                        return false;
                    }
                }
            }
        }
        true
    }
}

fn test_init_state() {
    let m = Maze::new();
    assert_eq!(m.cells[0], WALLS_ALL, "init: cell 0 has all walls");
    assert_eq!(m.cells[63], WALLS_ALL, "init: cell 63 has all walls");
    assert!(!m.visited[0], "init: cell 0 not visited");
}

fn test_full_coverage() {
    let mut rng = Rng::new(42);
    let mut m = Maze::new();
    m.generate(&mut rng, 0, 0);
    assert_eq!(m.count_visited(), GN, "all 64 cells visited");
}

fn test_perfect_maze_wall_count() {
    let mut rng = Rng::new(42);
    let mut m = Maze::new();
    m.generate(&mut rng, 0, 0);
    assert_eq!(m.count_removed_walls(), GN - 1, "perfect maze: GN-1 walls");
}

fn test_wall_consistency() {
    let mut rng = Rng::new(42);
    let mut m = Maze::new();
    m.generate(&mut rng, 0, 0);
    assert!(m.walls_consistent(), "wall pairs are consistent");
}

fn test_determinism() {
    let mut rng = Rng::new(42);
    let mut a = Maze::new();
    a.generate(&mut rng, 0, 0);
    let (c0, c27, c63) = (a.cells[0], a.cells[27], a.cells[63]);

    rng.seed(42);
    let mut b = Maze::new();
    b.generate(&mut rng, 0, 0);
    assert_eq!(b.cells[0], c0, "deterministic: cell 0");
    assert_eq!(b.cells[27], c27, "deterministic: cell 27");
    assert_eq!(b.cells[63], c63, "deterministic: cell 63");
}

fn test_different_seeds_differ() {
    let mut rng = Rng::new(1);
    let mut a = Maze::new();
    a.generate(&mut rng, 0, 0);
    let sum1: u64 = a.cells.iter().map(|&v| v as u64).sum();

    rng.seed(2);
    let mut b = Maze::new();
    b.generate(&mut rng, 0, 0);
    let sum2: u64 = b.cells.iter().map(|&v| v as u64).sum();

    assert!(sum1 != sum2, "different seeds produce different mazes");
}

fn test_starting_cell_visited() {
    let mut rng = Rng::new(42);
    let mut m = Maze::new();
    m.generate(&mut rng, 3, 5);
    assert!(m.visited[Maze::idx(3, 5)], "start cell marked visited");
    assert_eq!(m.count_visited(), GN, "all cells reachable");
}

fn main() {
    test_init_state();
    test_full_coverage();
    test_perfect_maze_wall_count();
    test_wall_consistency();
    test_determinism();
    test_different_seeds_differ();
    test_starting_cell_visited();

    // Cross-language byte parity sanity (matches cyrius reference): for
    // seed=42 the per-cell wall bytes at indices 0/27/63 are 13/12/6.
    let mut rng = Rng::new(42);
    let mut m = Maze::new();
    m.generate(&mut rng, 0, 0);
    assert_eq!(m.cells[0], 13, "parity: cell 0 == 13");
    assert_eq!(m.cells[27], 12, "parity: cell 27 == 12");
    assert_eq!(m.cells[63], 6, "parity: cell 63 == 6");

    println!("All maze_generation examples passed.");
}
