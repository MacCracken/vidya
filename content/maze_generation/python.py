#!/usr/bin/env python3
"""Vidya — Maze Generation in Python

Recursive backtracker (iterative DFS) on an 8x8 grid. Walls per cell
are stored as a bitmask (N=1, S=2, E=4, W=8). Generation carves
passages by clearing the wall bit on both the current and neighbour
cell.

Python's `int` is arbitrary precision, which means the PCG step would
not wrap on its own. We mask explicitly to 64 bits, then convert to
signed if needed so the `>>` and modulo behave like cyrius's signed-i64
arithmetic. Top-bit masking after the shift keeps the result
non-negative regardless of platform shift semantics.
"""

GW = 8
GH = 8
GN = GW * GH

WN, WS, WE, WW = 1, 2, 4, 8
WALLS_ALL = 15

PCG_MULT = 6364136223846793005
PCG_INC = 1442695040888963407
U64_MASK = (1 << 64) - 1


class Rng:
    def __init__(self, seed: int = 12345) -> None:
        self.state = seed & U64_MASK

    def seed(self, s: int) -> None:
        self.state = s & U64_MASK

    def next(self) -> int:
        # PCG step: explicit mask provides the wrap that other languages
        # get from native i64 overflow.
        self.state = (self.state * PCG_MULT + PCG_INC) & U64_MASK
        # Top bits, then mask to 31 — non-negative, so range modulo is
        # well-defined and matches cyrius byte-for-byte.
        return (self.state >> 33) & 0x7FFFFFFF

    def range(self, max_val: int) -> int:
        if max_val <= 0:
            return 0
        return self.next() % max_val


def idx(x: int, y: int) -> int:
    return y * GW + x


def opposite(d: int) -> int:
    return {WN: WS, WS: WN, WE: WW, WW: WE}.get(d, 0)


class Maze:
    def __init__(self) -> None:
        self.cells = [WALLS_ALL] * GN
        self.visited = [False] * GN

    def reset(self) -> None:
        for i in range(GN):
            self.cells[i] = WALLS_ALL
            self.visited[i] = False

    def carve(self, x: int, y: int, d: int, nx: int, ny: int) -> None:
        ci, ni = idx(x, y), idx(nx, ny)
        # Clear the wall on both sides so the maze is symmetric.
        self.cells[ci] &= ~d & 0xFF
        self.cells[ni] &= ~opposite(d) & 0xFF

    def collect_unvisited(self, x: int, y: int):
        out = []
        if y > 0 and not self.visited[idx(x, y - 1)]:
            out.append((WN, x, y - 1))
        if y < GH - 1 and not self.visited[idx(x, y + 1)]:
            out.append((WS, x, y + 1))
        if x > 0 and not self.visited[idx(x - 1, y)]:
            out.append((WW, x - 1, y))
        if x < GW - 1 and not self.visited[idx(x + 1, y)]:
            out.append((WE, x + 1, y))
        return out

    def generate(self, rng: Rng, sx: int, sy: int) -> None:
        self.reset()
        stack = [(sx, sy)]
        self.visited[idx(sx, sy)] = True
        while stack:
            tx, ty = stack[-1]
            nbrs = self.collect_unvisited(tx, ty)
            if not nbrs:
                stack.pop()
            else:
                pick = rng.range(len(nbrs))
                d, nx, ny = nbrs[pick]
                self.carve(tx, ty, d, nx, ny)
                self.visited[idx(nx, ny)] = True
                stack.append((nx, ny))

    def count_visited(self) -> int:
        return sum(1 for v in self.visited if v)

    def count_removed_walls(self) -> int:
        removed = 0
        for y in range(GH):
            for x in range(GW):
                w = self.cells[idx(x, y)]
                if y > 0 and (w & WN) == 0:
                    removed += 1
                if x > 0 and (w & WW) == 0:
                    removed += 1
        return removed

    def walls_consistent(self) -> bool:
        for y in range(GH):
            for x in range(GW):
                w = self.cells[idx(x, y)]
                if x < GW - 1:
                    nw = self.cells[idx(x + 1, y)]
                    if ((w & WE) == 0) != ((nw & WW) == 0):
                        return False
                if y < GH - 1:
                    sw = self.cells[idx(x, y + 1)]
                    if ((w & WS) == 0) != ((sw & WN) == 0):
                        return False
        return True


def test_init_state():
    m = Maze()
    assert m.cells[0] == WALLS_ALL, "init: cell 0 has all walls"
    assert m.cells[63] == WALLS_ALL, "init: cell 63 has all walls"
    assert not m.visited[0], "init: cell 0 not visited"


def test_full_coverage():
    rng = Rng(42)
    m = Maze()
    m.generate(rng, 0, 0)
    assert m.count_visited() == GN, "all 64 cells visited"


def test_perfect_maze_wall_count():
    rng = Rng(42)
    m = Maze()
    m.generate(rng, 0, 0)
    assert m.count_removed_walls() == GN - 1, "perfect maze: GN-1 walls"


def test_wall_consistency():
    rng = Rng(42)
    m = Maze()
    m.generate(rng, 0, 0)
    assert m.walls_consistent(), "wall pairs are consistent"


def test_determinism():
    rng = Rng(42)
    a = Maze()
    a.generate(rng, 0, 0)
    snap = (a.cells[0], a.cells[27], a.cells[63])

    rng.seed(42)
    b = Maze()
    b.generate(rng, 0, 0)
    assert (b.cells[0], b.cells[27], b.cells[63]) == snap, "deterministic"


def test_different_seeds_differ():
    rng = Rng(1)
    a = Maze()
    a.generate(rng, 0, 0)
    sum1 = sum(a.cells)

    rng.seed(2)
    b = Maze()
    b.generate(rng, 0, 0)
    sum2 = sum(b.cells)
    assert sum1 != sum2, "different seeds produce different mazes"


def test_starting_cell_visited():
    rng = Rng(42)
    m = Maze()
    m.generate(rng, 3, 5)
    assert m.visited[idx(3, 5)], "start cell marked visited"
    assert m.count_visited() == GN, "all cells reachable from non-corner"


def main() -> None:
    test_init_state()
    test_full_coverage()
    test_perfect_maze_wall_count()
    test_wall_consistency()
    test_determinism()
    test_different_seeds_differ()
    test_starting_cell_visited()

    # Cross-language byte parity check (matches cyrius reference).
    rng = Rng(42)
    m = Maze()
    m.generate(rng, 0, 0)
    assert m.cells[0] == 13, "parity: cell 0 == 13"
    assert m.cells[27] == 12, "parity: cell 27 == 12"
    assert m.cells[63] == 6, "parity: cell 63 == 6"

    print("All maze_generation examples passed.")


if __name__ == "__main__":
    main()
