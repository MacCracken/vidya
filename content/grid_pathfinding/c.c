// Vidya — Grid Pathfinding in C
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
// C uses flat fixed-size arrays for everything: grid + visited as
// uint8_t[64], a circular FIFO array as the BFS queue, and a
// linear-scan over an open-set array for A*'s min-f selection.
// For 64 cells the linear scan is O(N) but N is tiny — exactly the
// scaling decision the Cyrius reference makes. Manhattan is the
// heuristic. INT64_MAX sentinels mark un-relaxed g_scores.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define GW 8
#define GH 8
#define GN (GW * GH)

static int idx(int x, int y) { return y * GW + x; }

static int manhattan(int ax, int ay, int bx, int by) {
    int dx = ax - bx; if (dx < 0) dx = -dx;
    int dy = ay - by; if (dy < 0) dy = -dy;
    return dx + dy;
}

static void grid_clear(uint8_t *g) {
    for (int i = 0; i < GN; i++) g[i] = 0;
}

static void grid_block(uint8_t *g, int x, int y) { g[idx(x, y)] = 1; }

// Returns count of neighbours written into out[0..3].
static int neighbours(int curr, int out[4]) {
    int cx = curr % GW, cy = curr / GW, n = 0;
    if (cy > 0)        out[n++] = curr - GW;
    if (cy < GH - 1)   out[n++] = curr + GW;
    if (cx > 0)        out[n++] = curr - 1;
    if (cx < GW - 1)   out[n++] = curr + 1;
    return n;
}

static int64_t bfs(const uint8_t *grid, int start, int goal) {
    if (start == goal) return 0;
    uint8_t visited[GN] = {0};
    int64_t dist[GN];
    for (int i = 0; i < GN; i++) dist[i] = -1;
    int queue[GN];
    int head = 0, tail = 0;
    queue[tail++] = start;
    visited[start] = 1;
    dist[start] = 0;
    while (head < tail) {
        int curr = queue[head++];
        if (curr == goal) return dist[curr];
        int nb[4];
        int nc = neighbours(curr, nb);
        for (int i = 0; i < nc; i++) {
            int n = nb[i];
            if (!visited[n] && grid[n] == 0) {
                visited[n] = 1;
                dist[n] = dist[curr] + 1;
                queue[tail++] = n;
            }
        }
    }
    return -1;
}

static int64_t astar(const uint8_t *grid, int sx, int sy, int gx, int gy) {
    int start = idx(sx, sy), goal = idx(gx, gy);
    int64_t g_score[GN], f_score[GN];
    uint8_t closed[GN] = {0};
    for (int i = 0; i < GN; i++) {
        g_score[i] = INT64_MAX;
        f_score[i] = INT64_MAX;
    }
    g_score[start] = 0;
    f_score[start] = manhattan(sx, sy, gx, gy);

    // open-set as flat array; linear scan for min-f. For GN=64 this is
    // dirt cheap and avoids a heap dependency.
    int open_set[GN * 4];
    int open_n = 0;
    open_set[open_n++] = start;

    while (open_n > 0) {
        int best_i = 0;
        int64_t best_f = f_score[open_set[0]];
        for (int k = 1; k < open_n; k++) {
            int64_t fv = f_score[open_set[k]];
            if (fv < best_f) { best_f = fv; best_i = k; }
        }
        int curr = open_set[best_i];
        if (curr == goal) return g_score[goal];
        // swap-remove
        open_set[best_i] = open_set[--open_n];
        closed[curr] = 1;

        int64_t tg = g_score[curr] + 1;
        int nb[4];
        int nc = neighbours(curr, nb);
        for (int i = 0; i < nc; i++) {
            int n = nb[i];
            if (closed[n] || grid[n] != 0) continue;
            if (tg < g_score[n]) {
                g_score[n] = tg;
                int nx = n % GW, ny = n / GW;
                f_score[n] = tg + manhattan(nx, ny, gx, gy);
                open_set[open_n++] = n;
            }
        }
    }
    return -1;
}

static void test_manhattan(void) {
    assert(manhattan(0, 0, 0, 0) == 0);
    assert(manhattan(0, 0, 3, 4) == 7);
    assert(manhattan(7, 7, 0, 0) == 14);
    assert(manhattan(2, 5, 5, 2) == 6);
}

static void test_bfs_empty_grid(void) {
    uint8_t g[GN]; grid_clear(g);
    assert(bfs(g, idx(0, 0), idx(7, 7)) == 14);
}

static void test_bfs_same_start_end(void) {
    uint8_t g[GN]; grid_clear(g);
    assert(bfs(g, idx(3, 3), idx(3, 3)) == 0);
}

static void test_bfs_around_wall(void) {
    uint8_t g[GN]; grid_clear(g);
    for (int y = 0; y < 7; y++) grid_block(g, 4, y);
    assert(bfs(g, idx(0, 0), idx(7, 0)) == 21);
}

static void test_bfs_unreachable(void) {
    uint8_t g[GN]; grid_clear(g);
    grid_block(g, 6, 7);
    grid_block(g, 7, 6);
    assert(bfs(g, idx(0, 0), idx(7, 7)) == -1);
}

static void test_astar_empty_grid(void) {
    uint8_t g[GN]; grid_clear(g);
    assert(astar(g, 0, 0, 7, 7) == 14);
}

static void test_astar_matches_bfs_with_obstacle(void) {
    uint8_t g[GN]; grid_clear(g);
    for (int y = 0; y < 7; y++) grid_block(g, 4, y);
    int64_t b = bfs(g, idx(0, 0), idx(7, 0));
    int64_t a = astar(g, 0, 0, 7, 0);
    assert(a == b);
    assert(a == 21);
}

static void test_astar_unreachable(void) {
    uint8_t g[GN]; grid_clear(g);
    grid_block(g, 6, 7);
    grid_block(g, 7, 6);
    assert(astar(g, 0, 0, 7, 7) == -1);
}

int main(void) {
    test_manhattan();
    test_bfs_empty_grid();
    test_bfs_same_start_end();
    test_bfs_around_wall();
    test_bfs_unreachable();
    test_astar_empty_grid();
    test_astar_matches_bfs_with_obstacle();
    test_astar_unreachable();
    puts("All grid_pathfinding examples passed.");
    return 0;
}
