/* Vidya — Maze Generation in C
 *
 * Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell holds
 * a bitmask of present walls (N=1, S=2, E=4, W=8). Generation carves
 * passages by clearing the wall bit on both the current and neighbour
 * cell.
 *
 * The PCG step relies on signed-integer overflow being defined as
 * mod-2^64 wrap. C technically calls signed overflow undefined, but
 * gcc/clang with default flags both lower it to the natural CPU wrap.
 * We use uint64_t for the state to keep the language-defined wrap, and
 * cast to int64_t only when we mask the top bits down to a non-negative
 * 31-bit value.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

#define GW 8
#define GH 8
#define GN (GW * GH)

#define WN 1
#define WS 2
#define WE 4
#define WW 8
#define WALLS_ALL 15

static const uint64_t PCG_MULT = 6364136223846793005ULL;
static const uint64_t PCG_INC  = 1442695040888963407ULL;

static uint64_t rng_state = 12345;

static void rng_seed(uint64_t s) { rng_state = s; }

static int64_t rng_next(void) {
    /* uint64_t multiply/add is mod-2^64 by definition. */
    rng_state = rng_state * PCG_MULT + PCG_INC;
    return (int64_t)((rng_state >> 33) & 0x7fffffffULL);
}

static int64_t rng_range(int64_t max) {
    if (max <= 0) return 0;
    return rng_next() % max;
}

static uint8_t maze_cells[GN];
static uint8_t visited[GN];

static int idx(int x, int y) { return y * GW + x; }

static int opposite_dir(int d) {
    switch (d) {
        case WN: return WS;
        case WS: return WN;
        case WE: return WW;
        case WW: return WE;
    }
    return 0;
}

static void maze_init(void) {
    memset(maze_cells, WALLS_ALL, GN);
    memset(visited, 0, GN);
}

static void carve(int x, int y, int d, int nx, int ny) {
    int ci = idx(x, y), ni = idx(nx, ny);
    int od = opposite_dir(d);
    /* Clear wall on both sides — without this the neighbour would
     * still report a wall facing us. */
    maze_cells[ci] &= (uint8_t)(~d & 0xff);
    maze_cells[ni] &= (uint8_t)(~od & 0xff);
}

typedef struct { int dir, nx, ny; } Neighbour;

static int collect_unvisited(int x, int y, Neighbour *out) {
    int n = 0;
    if (y > 0 && !visited[idx(x, y - 1)]) {
        out[n++] = (Neighbour){WN, x, y - 1};
    }
    if (y < GH - 1 && !visited[idx(x, y + 1)]) {
        out[n++] = (Neighbour){WS, x, y + 1};
    }
    if (x > 0 && !visited[idx(x - 1, y)]) {
        out[n++] = (Neighbour){WW, x - 1, y};
    }
    if (x < GW - 1 && !visited[idx(x + 1, y)]) {
        out[n++] = (Neighbour){WE, x + 1, y};
    }
    return n;
}

static void maze_generate(int sx, int sy) {
    maze_init();
    /* DFS stack as packed cell indices; up to GN entries fits easily. */
    int stack[GN];
    int sp = 0;
    stack[sp++] = idx(sx, sy);
    visited[idx(sx, sy)] = 1;

    while (sp > 0) {
        int top = stack[sp - 1];
        int tx = top % GW, ty = top / GW;
        Neighbour buf[4];
        int k = collect_unvisited(tx, ty, buf);
        if (k == 0) {
            sp--;
        } else {
            int pick = (int)rng_range((int64_t)k);
            Neighbour *p = &buf[pick];
            carve(tx, ty, p->dir, p->nx, p->ny);
            visited[idx(p->nx, p->ny)] = 1;
            stack[sp++] = idx(p->nx, p->ny);
        }
    }
}

static int count_visited(void) {
    int n = 0;
    for (int i = 0; i < GN; i++) if (visited[i]) n++;
    return n;
}

static int count_removed_walls(void) {
    int removed = 0;
    for (int y = 0; y < GH; y++) {
        for (int x = 0; x < GW; x++) {
            uint8_t w = maze_cells[idx(x, y)];
            if (y > 0 && !(w & WN)) removed++;
            if (x > 0 && !(w & WW)) removed++;
        }
    }
    return removed;
}

static bool walls_consistent(void) {
    for (int y = 0; y < GH; y++) {
        for (int x = 0; x < GW; x++) {
            uint8_t w = maze_cells[idx(x, y)];
            if (x < GW - 1) {
                uint8_t nw = maze_cells[idx(x + 1, y)];
                if (((w & WE) == 0) != ((nw & WW) == 0)) return false;
            }
            if (y < GH - 1) {
                uint8_t sw = maze_cells[idx(x, y + 1)];
                if (((w & WS) == 0) != ((sw & WN) == 0)) return false;
            }
        }
    }
    return true;
}

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); exit(1); } \
} while (0)

static void test_init_state(void) {
    maze_init();
    CHECK(maze_cells[0] == WALLS_ALL, "init: cell 0");
    CHECK(maze_cells[63] == WALLS_ALL, "init: cell 63");
    CHECK(visited[0] == 0, "init: cell 0 not visited");
}

static void test_full_coverage(void) {
    rng_seed(42);
    maze_generate(0, 0);
    CHECK(count_visited() == GN, "all 64 cells visited");
}

static void test_perfect_maze_wall_count(void) {
    rng_seed(42);
    maze_generate(0, 0);
    CHECK(count_removed_walls() == GN - 1, "perfect maze: GN-1 walls");
}

static void test_wall_consistency(void) {
    rng_seed(42);
    maze_generate(0, 0);
    CHECK(walls_consistent(), "wall pairs consistent");
}

static void test_determinism(void) {
    rng_seed(42);
    maze_generate(0, 0);
    uint8_t c0 = maze_cells[0], c27 = maze_cells[27], c63 = maze_cells[63];

    rng_seed(42);
    maze_generate(0, 0);
    CHECK(maze_cells[0] == c0,   "deterministic: cell 0");
    CHECK(maze_cells[27] == c27, "deterministic: cell 27");
    CHECK(maze_cells[63] == c63, "deterministic: cell 63");
}

static void test_different_seeds_differ(void) {
    rng_seed(1);
    maze_generate(0, 0);
    int sum1 = 0;
    for (int i = 0; i < GN; i++) sum1 += maze_cells[i];

    rng_seed(2);
    maze_generate(0, 0);
    int sum2 = 0;
    for (int i = 0; i < GN; i++) sum2 += maze_cells[i];

    CHECK(sum1 != sum2, "different seeds produce different mazes");
}

static void test_starting_cell_visited(void) {
    rng_seed(42);
    maze_generate(3, 5);
    CHECK(visited[idx(3, 5)] == 1, "start cell marked visited");
    CHECK(count_visited() == GN, "all cells reachable");
}

int main(void) {
    test_init_state();
    test_full_coverage();
    test_perfect_maze_wall_count();
    test_wall_consistency();
    test_determinism();
    test_different_seeds_differ();
    test_starting_cell_visited();

    /* Cross-language byte parity (matches cyrius reference). */
    rng_seed(42);
    maze_generate(0, 0);
    CHECK(maze_cells[0] == 13, "parity: cell 0 == 13");
    CHECK(maze_cells[27] == 12, "parity: cell 27 == 12");
    CHECK(maze_cells[63] == 6, "parity: cell 63 == 6");

    printf("All maze_generation examples passed.\n");
    return 0;
}
