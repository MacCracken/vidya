# Vidya — Algorithms in Python
#
# Python's high-level data structures (list, dict, set) make
# algorithms concise. bisect provides binary search, heapq gives
# priority queues, and collections.deque is ideal for BFS.
# Python's sort is Timsort — O(n log n), stable, adaptive.

from collections import deque
from functools import lru_cache


def main():
    test_binary_search()
    test_sorting()
    test_graph_bfs()
    test_graph_dfs()
    test_dynamic_programming()
    test_two_sum_hashmap()
    test_gcd()
    test_merge_sort()

    print("All algorithms examples passed.")


# ── Binary search ──────────────────────────────────────────────────────
def binary_search(arr: list[int], target: int) -> int | None:
    lo, hi = 0, len(arr)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        if arr[mid] == target:
            return mid
        elif arr[mid] < target:
            lo = mid + 1
        else:
            hi = mid
    return None


def test_binary_search():
    arr = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
    assert binary_search(arr, 7) == 3
    assert binary_search(arr, 1) == 0
    assert binary_search(arr, 19) == 9
    assert binary_search(arr, 4) is None
    assert binary_search(arr, 20) is None
    assert binary_search([], 1) is None

    # Compare with stdlib bisect
    import bisect
    idx = bisect.bisect_left(arr, 7)
    assert idx < len(arr) and arr[idx] == 7


# ── Sorting ────────────────────────────────────────────────────────────
def insertion_sort(arr: list[int]) -> list[int]:
    result = arr.copy()
    for i in range(1, len(result)):
        key = result[i]
        j = i - 1
        while j >= 0 and result[j] > key:
            result[j + 1] = result[j]
            j -= 1
        result[j + 1] = key
    return result


def test_sorting():
    assert insertion_sort([5, 2, 8, 1, 9, 3]) == [1, 2, 3, 5, 8, 9]
    assert insertion_sort([]) == []
    assert insertion_sort([42]) == [42]
    assert insertion_sort([1, 2, 3]) == [1, 2, 3]

    # Stdlib: Timsort, stable, adaptive
    assert sorted([5, 2, 8, 1, 9, 3]) == [1, 2, 3, 5, 8, 9]


# ── Graph BFS (shortest path, unweighted) ─────────────────────────────
def bfs_shortest_path(
    adj: list[list[int]], start: int, end: int
) -> list[int] | None:
    visited = [False] * len(adj)
    parent: list[int | None] = [None] * len(adj)
    queue = deque([start])
    visited[start] = True

    while queue:
        node = queue.popleft()
        if node == end:
            path = [end]
            current = end
            while parent[current] is not None:
                path.append(parent[current])
                current = parent[current]
            return path[::-1]
        for neighbor in adj[node]:
            if not visited[neighbor]:
                visited[neighbor] = True
                parent[neighbor] = node
                queue.append(neighbor)
    return None


def test_graph_bfs():
    adj = [
        [1, 4],  # 0
        [0, 2],  # 1
        [1, 3],  # 2
        [2, 4],  # 3
        [0, 3],  # 4
    ]
    path = bfs_shortest_path(adj, 0, 3)
    assert path == [0, 4, 3], f"got {path}"

    # Disconnected
    adj2 = [[1], [0], [3], [2]]
    assert bfs_shortest_path(adj2, 0, 2) is None


# ── Graph DFS (reachability) ──────────────────────────────────────────
def dfs_reachable(adj: list[list[int]], start: int) -> list[bool]:
    visited = [False] * len(adj)
    stack = [start]
    while stack:
        node = stack.pop()
        if visited[node]:
            continue
        visited[node] = True
        for neighbor in adj[node]:
            if not visited[neighbor]:
                stack.append(neighbor)
    return visited


def test_graph_dfs():
    adj = [[1, 2], [0, 3], [0], [1], []]
    reachable = dfs_reachable(adj, 0)
    assert all(reachable[:4])
    assert not reachable[4]


# ── Dynamic programming ───────────────────────────────────────────────
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    a, b = 0, 1
    for _ in range(2, n + 1):
        a, b = b, a + b
    return b


def lcs_length(a: str, b: str) -> int:
    m, n = len(a), len(b)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if a[i - 1] == b[j - 1]:
                dp[i][j] = dp[i - 1][j - 1] + 1
            else:
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
    return dp[m][n]


def test_dynamic_programming():
    assert fibonacci(0) == 0
    assert fibonacci(1) == 1
    assert fibonacci(10) == 55
    assert fibonacci(20) == 6765

    assert lcs_length("ABCBDAB", "BDCAB") == 4
    assert lcs_length("", "ABC") == 0
    assert lcs_length("ABC", "ABC") == 3
    assert lcs_length("ABC", "DEF") == 0

    # Memoized recursion (top-down DP)
    @lru_cache(maxsize=None)
    def fib_memo(n: int) -> int:
        if n <= 1:
            return n
        return fib_memo(n - 1) + fib_memo(n - 2)

    assert fib_memo(30) == 832040


# ── Two-sum with hash map: O(n) ───────────────────────────────────────
def two_sum(nums: list[int], target: int) -> tuple[int, int] | None:
    seen: dict[int, int] = {}
    for i, num in enumerate(nums):
        complement = target - num
        if complement in seen:
            return (seen[complement], i)
        seen[num] = i
    return None


def test_two_sum_hashmap():
    assert two_sum([2, 7, 11, 15], 9) == (0, 1)
    assert two_sum([3, 2, 4], 6) == (1, 2)
    assert two_sum([1, 2, 3], 7) is None


# ── GCD (Euclidean algorithm) ─────────────────────────────────────────
def gcd(a: int, b: int) -> int:
    while b:
        a, b = b, a % b
    return a


def test_gcd():
    assert gcd(48, 18) == 6
    assert gcd(100, 75) == 25
    assert gcd(17, 13) == 1
    assert gcd(0, 5) == 5
    assert gcd(7, 0) == 7

    # Compare with stdlib
    import math
    assert math.gcd(48, 18) == 6


# ── Merge sort ─────────────────────────────────────────────────────────
def merge_sort(arr: list[int]) -> list[int]:
    if len(arr) <= 1:
        return arr
    mid = len(arr) // 2
    left = merge_sort(arr[:mid])
    right = merge_sort(arr[mid:])

    merged = []
    i = j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            merged.append(left[i])
            i += 1
        else:
            merged.append(right[j])
            j += 1
    merged.extend(left[i:])
    merged.extend(right[j:])
    return merged


def test_merge_sort():
    assert merge_sort([38, 27, 43, 3, 9, 82, 10]) == [3, 9, 10, 27, 38, 43, 82]
    assert merge_sort([]) == []
    assert merge_sort([1]) == [1]


if __name__ == "__main__":
    main()
