#!/usr/bin/env python3
"""Vidya — Grid Pathfinding in Python.

BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
Python uses a list-of-int as the flat grid, ``collections.deque`` as
the BFS frontier (O(1) popleft), and ``heapq`` as A*'s open set —
a binary min-heap over (f_score, counter, cell_index). The counter
breaks ties stably to avoid comparing un-orderable payloads.
Manhattan distance is the heuristic.
"""

from __future__ import annotations

import heapq
from collections import deque
from itertools import count

GW = 8
GH = 8
GN = GW * GH


def idx(x: int, y: int) -> int:
    return y * GW + x


def manhattan(ax: int, ay: int, bx: int, by: int) -> int:
    return abs(ax - bx) + abs(ay - by)


def neighbors(curr: int):
    cx = curr % GW
    cy = curr // GW
    if cy > 0:
        yield curr - GW
    if cy < GH - 1:
        yield curr + GW
    if cx > 0:
        yield curr - 1
    if cx < GW - 1:
        yield curr + 1


def grid_clear() -> list[int]:
    return [0] * GN


def grid_block(g: list[int], x: int, y: int) -> None:
    g[idx(x, y)] = 1


def bfs(grid: list[int], start: int, goal: int) -> int:
    if start == goal:
        return 0
    visited = [False] * GN
    dist = [-1] * GN
    q: deque[int] = deque([start])
    visited[start] = True
    dist[start] = 0
    while q:
        curr = q.popleft()
        if curr == goal:
            return dist[curr]
        for n in neighbors(curr):
            if not visited[n] and grid[n] == 0:
                visited[n] = True
                dist[n] = dist[curr] + 1
                q.append(n)
    return -1


def astar(grid: list[int], sx: int, sy: int, gx: int, gy: int) -> int:
    start = idx(sx, sy)
    goal = idx(gx, gy)
    g_score = [10**18] * GN
    closed = [False] * GN
    g_score[start] = 0
    tie = count()
    open_heap: list[tuple[int, int, int]] = [
        (manhattan(sx, sy, gx, gy), next(tie), start)
    ]
    while open_heap:
        _f, _c, curr = heapq.heappop(open_heap)
        if curr == goal:
            return g_score[goal]
        if closed[curr]:
            continue
        closed[curr] = True
        tg = g_score[curr] + 1
        for n in neighbors(curr):
            if grid[n] != 0 or closed[n]:
                continue
            if tg < g_score[n]:
                g_score[n] = tg
                nx, ny = n % GW, n // GW
                f = tg + manhattan(nx, ny, gx, gy)
                heapq.heappush(open_heap, (f, next(tie), n))
    return -1


def test_manhattan() -> None:
    assert manhattan(0, 0, 0, 0) == 0
    assert manhattan(0, 0, 3, 4) == 7
    assert manhattan(7, 7, 0, 0) == 14
    assert manhattan(2, 5, 5, 2) == 6


def test_bfs_empty_grid() -> None:
    g = grid_clear()
    assert bfs(g, idx(0, 0), idx(7, 7)) == 14


def test_bfs_same_start_end() -> None:
    g = grid_clear()
    assert bfs(g, idx(3, 3), idx(3, 3)) == 0


def test_bfs_around_wall() -> None:
    g = grid_clear()
    for y in range(7):
        grid_block(g, 4, y)
    assert bfs(g, idx(0, 0), idx(7, 0)) == 21


def test_bfs_unreachable() -> None:
    g = grid_clear()
    grid_block(g, 6, 7)
    grid_block(g, 7, 6)
    assert bfs(g, idx(0, 0), idx(7, 7)) == -1


def test_astar_empty_grid() -> None:
    g = grid_clear()
    assert astar(g, 0, 0, 7, 7) == 14


def test_astar_matches_bfs_with_obstacle() -> None:
    g = grid_clear()
    for y in range(7):
        grid_block(g, 4, y)
    bfs_len = bfs(g, idx(0, 0), idx(7, 0))
    astar_len = astar(g, 0, 0, 7, 0)
    assert bfs_len == astar_len == 21


def test_astar_unreachable() -> None:
    g = grid_clear()
    grid_block(g, 6, 7)
    grid_block(g, 7, 6)
    assert astar(g, 0, 0, 7, 7) == -1


def main() -> None:
    test_manhattan()
    test_bfs_empty_grid()
    test_bfs_same_start_end()
    test_bfs_around_wall()
    test_bfs_unreachable()
    test_astar_empty_grid()
    test_astar_matches_bfs_with_obstacle()
    test_astar_unreachable()
    print("All grid_pathfinding examples passed.")


if __name__ == "__main__":
    main()
