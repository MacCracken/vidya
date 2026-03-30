// Vidya — Algorithms in TypeScript
//
// TypeScript adds type safety to JavaScript's flexible arrays and
// objects. Array.sort() is in-place and defaults to lexicographic
// order (gotcha!). Map gives O(1) lookup. No built-in binary search
// or graph structures — you build your own.

function main(): void {
    testBinarySearch();
    testSorting();
    testGraphBFS();
    testGraphDFS();
    testDynamicProgramming();
    testTwoSumHashmap();
    testGCD();
    testMergeSort();

    console.log("All algorithms examples passed.");
}

// ── Binary search ─────────────────────────────────────────────────────
function binarySearch(arr: number[], target: number): number {
    let lo = 0, hi = arr.length;
    while (lo < hi) {
        const mid = lo + Math.floor((hi - lo) / 2);
        if (arr[mid] === target) return mid;
        else if (arr[mid] < target) lo = mid + 1;
        else hi = mid;
    }
    return -1;
}

function testBinarySearch(): void {
    const arr = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19];
    assert(binarySearch(arr, 7) === 3, "find 7");
    assert(binarySearch(arr, 1) === 0, "find 1");
    assert(binarySearch(arr, 19) === 9, "find 19");
    assert(binarySearch(arr, 4) === -1, "miss 4");
    assert(binarySearch(arr, 20) === -1, "miss 20");
    assert(binarySearch([], 1) === -1, "empty");
}

// ── Sorting ───────────────────────────────────────────────────────────
function insertionSort(arr: number[]): number[] {
    const result = [...arr];
    for (let i = 1; i < result.length; i++) {
        const key = result[i];
        let j = i - 1;
        while (j >= 0 && result[j] > key) {
            result[j + 1] = result[j];
            j--;
        }
        result[j + 1] = key;
    }
    return result;
}

function testSorting(): void {
    assertArrayEq(insertionSort([5, 2, 8, 1, 9, 3]), [1, 2, 3, 5, 8, 9], "insertion sort");
    assertArrayEq(insertionSort([]), [], "empty");
    assertArrayEq(insertionSort([42]), [42], "single");

    // GOTCHA: Array.sort() is lexicographic by default!
    // [10, 9, 2].sort() gives [10, 2, 9] — wrong for numbers
    const bad = [10, 9, 2].sort();
    assert(bad[0] === 10, "lexicographic gotcha");  // "10" < "2" < "9"

    // GOOD: provide numeric comparator
    const good = [10, 9, 2].sort((a, b) => a - b);
    assertArrayEq(good, [2, 9, 10], "numeric sort");
}

// ── Graph BFS ─────────────────────────────────────────────────────────
function bfsShortestPath(adj: number[][], start: number, end: number): number[] | null {
    const n = adj.length;
    const visited = new Array<boolean>(n).fill(false);
    const parent = new Array<number>(n).fill(-1);
    const queue: number[] = [start];
    visited[start] = true;

    while (queue.length > 0) {
        const node = queue.shift()!;
        if (node === end) {
            const path: number[] = [end];
            let cur = end;
            while (parent[cur] !== -1) {
                path.push(parent[cur]);
                cur = parent[cur];
            }
            return path.reverse();
        }
        for (const nb of adj[node]) {
            if (!visited[nb]) {
                visited[nb] = true;
                parent[nb] = node;
                queue.push(nb);
            }
        }
    }
    return null;
}

function testGraphBFS(): void {
    const adj = [
        [1, 4], // 0
        [0, 2], // 1
        [1, 3], // 2
        [2, 4], // 3
        [0, 3], // 4
    ];
    assertArrayEq(bfsShortestPath(adj, 0, 3)!, [0, 4, 3], "bfs shortest");

    const disconnected = [[1], [0], [3], [2]];
    assert(bfsShortestPath(disconnected, 0, 2) === null, "disconnected");
}

// ── Graph DFS ─────────────────────────────────────────────────────────
function dfsReachable(adj: number[][], start: number): boolean[] {
    const visited = new Array<boolean>(adj.length).fill(false);
    const stack = [start];
    while (stack.length > 0) {
        const node = stack.pop()!;
        if (visited[node]) continue;
        visited[node] = true;
        for (const nb of adj[node]) {
            if (!visited[nb]) stack.push(nb);
        }
    }
    return visited;
}

function testGraphDFS(): void {
    const adj = [[1, 2], [0, 3], [0], [1], []];
    const reachable = dfsReachable(adj, 0);
    assert(reachable[0] && reachable[1] && reachable[2] && reachable[3], "connected");
    assert(!reachable[4], "isolated");
}

// ── Dynamic programming ──────────────────────────────────────────────
function fibonacci(n: number): number {
    if (n <= 1) return n;
    let a = 0, b = 1;
    for (let i = 2; i <= n; i++) {
        [a, b] = [b, a + b];
    }
    return b;
}

function lcsLength(a: string, b: string): number {
    const m = a.length, n = b.length;
    const dp: number[][] = Array.from({ length: m + 1 }, () => new Array(n + 1).fill(0));
    for (let i = 1; i <= m; i++) {
        for (let j = 1; j <= n; j++) {
            if (a[i - 1] === b[j - 1]) {
                dp[i][j] = dp[i - 1][j - 1] + 1;
            } else {
                dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
            }
        }
    }
    return dp[m][n];
}

function testDynamicProgramming(): void {
    assert(fibonacci(0) === 0, "fib(0)");
    assert(fibonacci(1) === 1, "fib(1)");
    assert(fibonacci(10) === 55, "fib(10)");
    assert(fibonacci(20) === 6765, "fib(20)");

    assert(lcsLength("ABCBDAB", "BDCAB") === 4, "lcs");
    assert(lcsLength("", "ABC") === 0, "lcs empty");
    assert(lcsLength("ABC", "ABC") === 3, "lcs same");
    assert(lcsLength("ABC", "DEF") === 0, "lcs none");
}

// ── Two-sum with Map ──────────────────────────────────────────────────
function twoSum(nums: number[], target: number): [number, number] | null {
    const seen = new Map<number, number>();
    for (let i = 0; i < nums.length; i++) {
        const complement = target - nums[i];
        if (seen.has(complement)) {
            return [seen.get(complement)!, i];
        }
        seen.set(nums[i], i);
    }
    return null;
}

function testTwoSumHashmap(): void {
    assertArrayEq(twoSum([2, 7, 11, 15], 9)!, [0, 1], "two sum");
    assertArrayEq(twoSum([3, 2, 4], 6)!, [1, 2], "two sum mid");
    assert(twoSum([1, 2, 3], 7) === null, "two sum none");
}

// ── GCD ───────────────────────────────────────────────────────────────
function gcd(a: number, b: number): number {
    while (b !== 0) {
        [a, b] = [b, a % b];
    }
    return a;
}

function testGCD(): void {
    assert(gcd(48, 18) === 6, "gcd 48,18");
    assert(gcd(100, 75) === 25, "gcd 100,75");
    assert(gcd(17, 13) === 1, "gcd coprime");
    assert(gcd(0, 5) === 5, "gcd 0,5");
    assert(gcd(7, 0) === 7, "gcd 7,0");
}

// ── Merge sort ────────────────────────────────────────────────────────
function mergeSort(arr: number[]): number[] {
    if (arr.length <= 1) return arr;
    const mid = Math.floor(arr.length / 2);
    const left = mergeSort(arr.slice(0, mid));
    const right = mergeSort(arr.slice(mid));

    const merged: number[] = [];
    let i = 0, j = 0;
    while (i < left.length && j < right.length) {
        if (left[i] <= right[j]) merged.push(left[i++]);
        else merged.push(right[j++]);
    }
    merged.push(...left.slice(i), ...right.slice(j));
    return merged;
}

function testMergeSort(): void {
    assertArrayEq(mergeSort([38, 27, 43, 3, 9, 82, 10]), [3, 9, 10, 27, 38, 43, 82], "merge sort");
    assertArrayEq(mergeSort([]), [], "empty");
    assertArrayEq(mergeSort([1]), [1], "single");
}

// ── Helpers ───────────────────────────────────────────────────────────
function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

function assertArrayEq(a: number[], b: number[], msg: string): void {
    if (a.length !== b.length || a.some((v, i) => v !== b[i])) {
        throw new Error(`FAIL: ${msg}: [${a}] !== [${b}]`);
    }
}

main();
