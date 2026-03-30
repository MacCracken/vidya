// Vidya — Algorithms in Zig
//
// Zig's standard library provides sort and binary search in std.sort
// and std.mem. No garbage collector means you manage allocations for
// dynamic structures. Zig's comptime can generate specialized
// algorithm variants at compile time.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    try testBinarySearch();
    try testSorting();
    try testDynamicProgramming();
    try testGCD();
    try testMergeSort();
    try testTwoSum();
    try testGraphBFS();

    std.debug.print("All algorithms examples passed.\n", .{});
}

// ── Binary search ─────────────────────────────────────────────────────
fn binarySearch(arr: []const i32, target: i32) ?usize {
    var lo: usize = 0;
    var hi: usize = arr.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (arr[mid] == target) return mid;
        if (arr[mid] < target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return null;
}

fn testBinarySearch() !void {
    const arr = [_]i32{ 1, 3, 5, 7, 9, 11, 13, 15, 17, 19 };
    try expect(binarySearch(&arr, 7).? == 3);
    try expect(binarySearch(&arr, 1).? == 0);
    try expect(binarySearch(&arr, 19).? == 9);
    try expect(binarySearch(&arr, 4) == null);
    try expect(binarySearch(&arr, 20) == null);

    const empty = [_]i32{};
    try expect(binarySearch(&empty, 1) == null);
}

// ── Sorting ───────────────────────────────────────────────────────────
fn insertionSort(arr: []i32) void {
    if (arr.len <= 1) return;
    for (1..arr.len) |i| {
        const key = arr[i];
        var j: usize = i;
        while (j > 0 and arr[j - 1] > key) {
            arr[j] = arr[j - 1];
            j -= 1;
        }
        arr[j] = key;
    }
}

fn testSorting() !void {
    var arr = [_]i32{ 5, 2, 8, 1, 9, 3 };
    insertionSort(&arr);
    try expect(mem.eql(i32, &arr, &[_]i32{ 1, 2, 3, 5, 8, 9 }));

    var one = [_]i32{42};
    insertionSort(&one);
    try expect(one[0] == 42);

    var sorted = [_]i32{ 1, 2, 3, 4, 5 };
    insertionSort(&sorted);
    try expect(mem.eql(i32, &sorted, &[_]i32{ 1, 2, 3, 4, 5 }));

    // Stdlib sort
    var arr2 = [_]i32{ 5, 2, 8, 1, 9, 3 };
    mem.sort(i32, &arr2, {}, std.sort.asc(i32));
    try expect(mem.eql(i32, &arr2, &[_]i32{ 1, 2, 3, 5, 8, 9 }));
}

// ── Dynamic programming: Fibonacci ────────────────────────────────────
fn fibonacci(n: u64) u64 {
    if (n <= 1) return n;
    var a: u64 = 0;
    var b: u64 = 1;
    for (2..n + 1) |_| {
        const next = a + b;
        a = b;
        b = next;
    }
    return b;
}

// LCS length
fn lcsLength(a: []const u8, b: []const u8) usize {
    const m = a.len;
    const n = b.len;
    // Use a flat array for the DP table
    var dp: [64 * 64]usize = undefined;
    const stride = n + 1;

    // Init first row and column to 0
    for (0..m + 1) |i| {
        dp[i * stride] = 0;
    }
    for (0..n + 1) |j| {
        dp[j] = 0;
    }

    for (1..m + 1) |i| {
        for (1..n + 1) |j| {
            if (a[i - 1] == b[j - 1]) {
                dp[i * stride + j] = dp[(i - 1) * stride + (j - 1)] + 1;
            } else {
                const up = dp[(i - 1) * stride + j];
                const left = dp[i * stride + (j - 1)];
                dp[i * stride + j] = @max(up, left);
            }
        }
    }
    return dp[m * stride + n];
}

fn testDynamicProgramming() !void {
    try expect(fibonacci(0) == 0);
    try expect(fibonacci(1) == 1);
    try expect(fibonacci(10) == 55);
    try expect(fibonacci(20) == 6765);

    try expect(lcsLength("ABCBDAB", "BDCAB") == 4);
    try expect(lcsLength("", "ABC") == 0);
    try expect(lcsLength("ABC", "ABC") == 3);
    try expect(lcsLength("ABC", "DEF") == 0);
}

// ── GCD (Euclidean) ───────────────────────────────────────────────────
fn gcd(a_in: u64, b_in: u64) u64 {
    var a = a_in;
    var b = b_in;
    while (b != 0) {
        const t = b;
        b = a % b;
        a = t;
    }
    return a;
}

fn testGCD() !void {
    try expect(gcd(48, 18) == 6);
    try expect(gcd(100, 75) == 25);
    try expect(gcd(17, 13) == 1);
    try expect(gcd(0, 5) == 5);
    try expect(gcd(7, 0) == 7);
}

// ── Merge sort ────────────────────────────────────────────────────────
fn mergeSort(arr: []i32, buf: []i32) void {
    if (arr.len <= 1) return;
    const mid = arr.len / 2;
    mergeSort(arr[0..mid], buf[0..mid]);
    mergeSort(arr[mid..], buf[mid..]);

    // Merge into buf, then copy back
    var i: usize = 0;
    var j: usize = mid;
    var k: usize = 0;
    while (i < mid and j < arr.len) {
        if (arr[i] <= arr[j]) {
            buf[k] = arr[i];
            i += 1;
        } else {
            buf[k] = arr[j];
            j += 1;
        }
        k += 1;
    }
    while (i < mid) {
        buf[k] = arr[i];
        i += 1;
        k += 1;
    }
    while (j < arr.len) {
        buf[k] = arr[j];
        j += 1;
        k += 1;
    }
    @memcpy(arr, buf[0..arr.len]);
}

fn testMergeSort() !void {
    var arr = [_]i32{ 38, 27, 43, 3, 9, 82, 10 };
    var buf: [7]i32 = undefined;
    mergeSort(&arr, &buf);
    try expect(mem.eql(i32, &arr, &[_]i32{ 3, 9, 10, 27, 38, 43, 82 }));

    var one = [_]i32{1};
    var buf1: [1]i32 = undefined;
    mergeSort(&one, &buf1);
    try expect(one[0] == 1);
}

// ── Two-sum with hash map ─────────────────────────────────────────────
fn twoSum(nums: []const i32, target: i32) ?struct { usize, usize } {
    var seen = std.AutoHashMap(i32, usize).init(std.heap.page_allocator);
    defer seen.deinit();
    for (nums, 0..) |num, i| {
        const complement = target - num;
        if (seen.get(complement)) |j| {
            return .{ j, i };
        }
        seen.put(num, i) catch return null;
    }
    return null;
}

fn testTwoSum() !void {
    const nums1 = [_]i32{ 2, 7, 11, 15 };
    const r1 = twoSum(&nums1, 9).?;
    try expect(r1[0] == 0 and r1[1] == 1);

    const nums2 = [_]i32{ 3, 2, 4 };
    const r2 = twoSum(&nums2, 6).?;
    try expect(r2[0] == 1 and r2[1] == 2);

    const nums3 = [_]i32{ 1, 2, 3 };
    try expect(twoSum(&nums3, 7) == null);
}

// ── Graph BFS (fixed-size, no allocator) ──────────────────────────────
const MAX_NODES = 16;

const Graph = struct {
    adj: [MAX_NODES][MAX_NODES]u8 = undefined,
    degree: [MAX_NODES]u8 = [_]u8{0} ** MAX_NODES,
    n: usize,

    fn addEdge(self: *Graph, u: usize, v: usize) void {
        self.adj[u][self.degree[u]] = @intCast(v);
        self.degree[u] += 1;
        self.adj[v][self.degree[v]] = @intCast(u);
        self.degree[v] += 1;
    }

    fn bfs(self: *const Graph, start: usize, end: usize) ?[MAX_NODES]u8 {
        var visited = [_]bool{false} ** MAX_NODES;
        var parent = [_]i8{-1} ** MAX_NODES;
        var queue: [MAX_NODES]u8 = undefined;
        var front: usize = 0;
        var back: usize = 0;

        visited[start] = true;
        queue[back] = @intCast(start);
        back += 1;

        while (front < back) {
            const node: usize = queue[front];
            front += 1;
            if (node == end) {
                // Reconstruct path into result
                var path: [MAX_NODES]u8 = undefined;
                var len: usize = 0;
                var cur: usize = end;
                while (true) {
                    path[len] = @intCast(cur);
                    len += 1;
                    if (parent[cur] == -1) break;
                    cur = @intCast(@as(u8, @bitCast(parent[cur])));
                }
                // Reverse in place
                var i: usize = 0;
                var j: usize = len - 1;
                while (i < j) {
                    const tmp = path[i];
                    path[i] = path[j];
                    path[j] = tmp;
                    i += 1;
                    j -= 1;
                }
                return path;
            }
            for (0..self.degree[node]) |k| {
                const nb: usize = self.adj[node][k];
                if (!visited[nb]) {
                    visited[nb] = true;
                    parent[nb] = @intCast(@as(u8, @truncate(node)));
                    queue[back] = @intCast(nb);
                    back += 1;
                }
            }
        }
        return null;
    }
};

fn testGraphBFS() !void {
    var g = Graph{ .n = 5 };
    g.addEdge(0, 1);
    g.addEdge(1, 2);
    g.addEdge(2, 3);
    g.addEdge(3, 4);
    g.addEdge(0, 4);

    const path = g.bfs(0, 3).?;
    try expect(path[0] == 0 and path[1] == 4 and path[2] == 3);
}
