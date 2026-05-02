// Vidya — Grid Pathfinding in Rust
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
// Rust uses `Vec<u8>` for grid + visited (cache-locality wins per
// concept.toml's perf note), `VecDeque<usize>` for the BFS frontier,
// and `BinaryHeap<Reverse<(f, idx)>>` for A*'s open set — a min-heap
// over (f_score, cell_index). Manhattan distance is the heuristic.
// All coordinates round-trip through `idx = y * GW + x` so the
// algorithms work on flat arrays just like the Cyrius reference.

use std::cmp::Reverse;
use std::collections::{BinaryHeap, VecDeque};

const GW: usize = 8;
const GH: usize = 8;
const GN: usize = GW * GH;

#[inline]
fn idx(x: usize, y: usize) -> usize { y * GW + x }

#[inline]
fn manhattan(ax: i64, ay: i64, bx: i64, by: i64) -> i64 {
    (ax - bx).abs() + (ay - by).abs()
}

fn neighbors(curr: usize, out: &mut [usize; 4]) -> usize {
    let cx = curr % GW;
    let cy = curr / GW;
    let mut n = 0;
    if cy > 0       { out[n] = curr - GW; n += 1; }
    if cy < GH - 1  { out[n] = curr + GW; n += 1; }
    if cx > 0       { out[n] = curr - 1;  n += 1; }
    if cx < GW - 1  { out[n] = curr + 1;  n += 1; }
    n
}

fn bfs(grid: &[u8; GN], start: usize, goal: usize) -> i64 {
    if start == goal { return 0; }
    let mut visited = [0u8; GN];
    let mut dist = [-1i64; GN];
    let mut q: VecDeque<usize> = VecDeque::with_capacity(GN);
    q.push_back(start);
    visited[start] = 1;
    dist[start] = 0;
    let mut nbuf = [0usize; 4];
    while let Some(curr) = q.pop_front() {
        if curr == goal { return dist[curr]; }
        let count = neighbors(curr, &mut nbuf);
        for &n in &nbuf[..count] {
            if visited[n] == 0 && grid[n] == 0 {
                visited[n] = 1;
                dist[n] = dist[curr] + 1;
                q.push_back(n);
            }
        }
    }
    -1
}

fn astar(grid: &[u8; GN], sx: usize, sy: usize, gx: usize, gy: usize) -> i64 {
    let start = idx(sx, sy);
    let goal = idx(gx, gy);
    let mut g_score = [i64::MAX; GN];
    let mut closed = [0u8; GN];
    g_score[start] = 0;
    let h0 = manhattan(sx as i64, sy as i64, gx as i64, gy as i64);
    // BinaryHeap is a max-heap; Reverse turns it into a min-heap on f.
    let mut open: BinaryHeap<Reverse<(i64, usize)>> = BinaryHeap::new();
    open.push(Reverse((h0, start)));
    let mut nbuf = [0usize; 4];
    while let Some(Reverse((_f, curr))) = open.pop() {
        if curr == goal { return g_score[goal]; }
        if closed[curr] == 1 { continue; }
        closed[curr] = 1;
        let tg = g_score[curr] + 1;
        let count = neighbors(curr, &mut nbuf);
        for &n in &nbuf[..count] {
            if grid[n] != 0 || closed[n] == 1 { continue; }
            if tg < g_score[n] {
                g_score[n] = tg;
                let nx = (n % GW) as i64;
                let ny = (n / GW) as i64;
                let f = tg + manhattan(nx, ny, gx as i64, gy as i64);
                open.push(Reverse((f, n)));
            }
        }
    }
    -1
}

fn grid_clear() -> [u8; GN] { [0u8; GN] }

fn grid_block(grid: &mut [u8; GN], x: usize, y: usize) { grid[idx(x, y)] = 1; }

fn test_manhattan() {
    assert_eq!(manhattan(0, 0, 0, 0), 0);
    assert_eq!(manhattan(0, 0, 3, 4), 7);
    assert_eq!(manhattan(7, 7, 0, 0), 14);
    assert_eq!(manhattan(2, 5, 5, 2), 6);
}

fn test_bfs_empty_grid() {
    let g = grid_clear();
    assert_eq!(bfs(&g, idx(0, 0), idx(7, 7)), 14);
}

fn test_bfs_same_start_end() {
    let g = grid_clear();
    assert_eq!(bfs(&g, idx(3, 3), idx(3, 3)), 0);
}

fn test_bfs_around_wall() {
    let mut g = grid_clear();
    for y in 0..7 { grid_block(&mut g, 4, y); }
    assert_eq!(bfs(&g, idx(0, 0), idx(7, 0)), 21);
}

fn test_bfs_unreachable() {
    let mut g = grid_clear();
    grid_block(&mut g, 6, 7);
    grid_block(&mut g, 7, 6);
    assert_eq!(bfs(&g, idx(0, 0), idx(7, 7)), -1);
}

fn test_astar_empty_grid() {
    let g = grid_clear();
    assert_eq!(astar(&g, 0, 0, 7, 7), 14);
}

fn test_astar_matches_bfs_with_obstacle() {
    let mut g = grid_clear();
    for y in 0..7 { grid_block(&mut g, 4, y); }
    let bfs_len = bfs(&g, idx(0, 0), idx(7, 0));
    let astar_len = astar(&g, 0, 0, 7, 0);
    assert_eq!(bfs_len, astar_len);
    assert_eq!(astar_len, 21);
}

fn test_astar_unreachable() {
    let mut g = grid_clear();
    grid_block(&mut g, 6, 7);
    grid_block(&mut g, 7, 6);
    assert_eq!(astar(&g, 0, 0, 7, 7), -1);
}

fn main() {
    test_manhattan();
    test_bfs_empty_grid();
    test_bfs_same_start_end();
    test_bfs_around_wall();
    test_bfs_unreachable();
    test_astar_empty_grid();
    test_astar_matches_bfs_with_obstacle();
    test_astar_unreachable();
    println!("All grid_pathfinding examples passed.");
}
