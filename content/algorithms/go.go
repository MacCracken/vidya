// Vidya — Algorithms in Go
//
// Go has sort.Slice/sort.Search in the standard library but no
// generics-based data structures (pre-1.21). Algorithms are typically
// written with slices and maps. Go's map gives O(1) average lookup,
// and slices are the standard container for sorting/searching.

package main

import (
	"fmt"
	"sort"
)

func main() {
	testBinarySearch()
	testSorting()
	testGraphBFS()
	testGraphDFS()
	testDynamicProgramming()
	testTwoSumHashmap()
	testGCD()
	testMergeSort()

	fmt.Println("All algorithms examples passed.")
}

// ── Binary search ─────────────────────────────────────────────────────
func binarySearch(arr []int, target int) int {
	lo, hi := 0, len(arr)
	for lo < hi {
		mid := lo + (hi-lo)/2
		if arr[mid] == target {
			return mid
		} else if arr[mid] < target {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return -1
}

func testBinarySearch() {
	arr := []int{1, 3, 5, 7, 9, 11, 13, 15, 17, 19}
	assert(binarySearch(arr, 7) == 3, "find 7")
	assert(binarySearch(arr, 1) == 0, "find 1")
	assert(binarySearch(arr, 19) == 9, "find 19")
	assert(binarySearch(arr, 4) == -1, "miss 4")
	assert(binarySearch(arr, 20) == -1, "miss 20")
	assert(binarySearch([]int{}, 1) == -1, "empty")

	// Stdlib: sort.SearchInts
	idx := sort.SearchInts(arr, 7)
	assert(idx < len(arr) && arr[idx] == 7, "stdlib search")
}

// ── Sorting ───────────────────────────────────────────────────────────
func insertionSort(arr []int) {
	for i := 1; i < len(arr); i++ {
		key := arr[i]
		j := i
		for j > 0 && arr[j-1] > key {
			arr[j] = arr[j-1]
			j--
		}
		arr[j] = key
	}
}

func testSorting() {
	arr := []int{5, 2, 8, 1, 9, 3}
	insertionSort(arr)
	assertSliceEq(arr, []int{1, 2, 3, 5, 8, 9}, "insertion sort")

	// Stdlib: pdqsort (Go 1.19+)
	arr2 := []int{5, 2, 8, 1, 9, 3}
	sort.Ints(arr2)
	assertSliceEq(arr2, []int{1, 2, 3, 5, 8, 9}, "stdlib sort")
}

// ── Graph BFS ─────────────────────────────────────────────────────────
func bfsShortestPath(adj [][]int, start, end int) []int {
	n := len(adj)
	visited := make([]bool, n)
	parent := make([]int, n)
	for i := range parent {
		parent[i] = -1
	}
	queue := []int{start}
	visited[start] = true

	for len(queue) > 0 {
		node := queue[0]
		queue = queue[1:]
		if node == end {
			path := []int{end}
			for cur := end; parent[cur] != -1; cur = parent[cur] {
				path = append(path, parent[cur])
			}
			// Reverse
			for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
				path[i], path[j] = path[j], path[i]
			}
			return path
		}
		for _, nb := range adj[node] {
			if !visited[nb] {
				visited[nb] = true
				parent[nb] = node
				queue = append(queue, nb)
			}
		}
	}
	return nil
}

func testGraphBFS() {
	adj := [][]int{
		{1, 4}, // 0
		{0, 2}, // 1
		{1, 3}, // 2
		{2, 4}, // 3
		{0, 3}, // 4
	}
	path := bfsShortestPath(adj, 0, 3)
	assertSliceEq(path, []int{0, 4, 3}, "bfs shortest path")

	disconnected := [][]int{{1}, {0}, {3}, {2}}
	assert(bfsShortestPath(disconnected, 0, 2) == nil, "disconnected")
}

// ── Graph DFS ─────────────────────────────────────────────────────────
func dfsReachable(adj [][]int, start int) []bool {
	visited := make([]bool, len(adj))
	stack := []int{start}
	for len(stack) > 0 {
		node := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		if visited[node] {
			continue
		}
		visited[node] = true
		for _, nb := range adj[node] {
			if !visited[nb] {
				stack = append(stack, nb)
			}
		}
	}
	return visited
}

func testGraphDFS() {
	adj := [][]int{{1, 2}, {0, 3}, {0}, {1}, {}}
	reachable := dfsReachable(adj, 0)
	assert(reachable[0] && reachable[1] && reachable[2] && reachable[3], "connected nodes")
	assert(!reachable[4], "isolated node")
}

// ── Dynamic programming ──────────────────────────────────────────────
func fibonacci(n int) uint64 {
	if n <= 1 {
		return uint64(n)
	}
	a, b := uint64(0), uint64(1)
	for i := 2; i <= n; i++ {
		a, b = b, a+b
	}
	return b
}

func lcsLength(a, b string) int {
	m, n := len(a), len(b)
	dp := make([][]int, m+1)
	for i := range dp {
		dp[i] = make([]int, n+1)
	}
	for i := 1; i <= m; i++ {
		for j := 1; j <= n; j++ {
			if a[i-1] == b[j-1] {
				dp[i][j] = dp[i-1][j-1] + 1
			} else {
				dp[i][j] = max(dp[i-1][j], dp[i][j-1])
			}
		}
	}
	return dp[m][n]
}

func testDynamicProgramming() {
	assert(fibonacci(0) == 0, "fib(0)")
	assert(fibonacci(1) == 1, "fib(1)")
	assert(fibonacci(10) == 55, "fib(10)")
	assert(fibonacci(20) == 6765, "fib(20)")

	assert(lcsLength("ABCBDAB", "BDCAB") == 4, "lcs")
	assert(lcsLength("", "ABC") == 0, "lcs empty")
	assert(lcsLength("ABC", "ABC") == 3, "lcs same")
	assert(lcsLength("ABC", "DEF") == 0, "lcs none")
}

// ── Two-sum with hash map ─────────────────────────────────────────────
func twoSum(nums []int, target int) (int, int, bool) {
	seen := make(map[int]int)
	for i, num := range nums {
		complement := target - num
		if j, ok := seen[complement]; ok {
			return j, i, true
		}
		seen[num] = i
	}
	return 0, 0, false
}

func testTwoSumHashmap() {
	i, j, ok := twoSum([]int{2, 7, 11, 15}, 9)
	assert(ok && i == 0 && j == 1, "two sum basic")

	i, j, ok = twoSum([]int{3, 2, 4}, 6)
	assert(ok && i == 1 && j == 2, "two sum mid")

	_, _, ok = twoSum([]int{1, 2, 3}, 7)
	assert(!ok, "two sum no match")
}

// ── GCD ───────────────────────────────────────────────────────────────
func gcd(a, b uint64) uint64 {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

func testGCD() {
	assert(gcd(48, 18) == 6, "gcd 48,18")
	assert(gcd(100, 75) == 25, "gcd 100,75")
	assert(gcd(17, 13) == 1, "gcd coprime")
	assert(gcd(0, 5) == 5, "gcd 0,5")
	assert(gcd(7, 0) == 7, "gcd 7,0")
}

// ── Merge sort ────────────────────────────────────────────────────────
func mergeSort(arr []int) []int {
	if len(arr) <= 1 {
		return arr
	}
	mid := len(arr) / 2
	left := mergeSort(arr[:mid])
	right := mergeSort(arr[mid:])

	merged := make([]int, 0, len(arr))
	i, j := 0, 0
	for i < len(left) && j < len(right) {
		if left[i] <= right[j] {
			merged = append(merged, left[i])
			i++
		} else {
			merged = append(merged, right[j])
			j++
		}
	}
	merged = append(merged, left[i:]...)
	merged = append(merged, right[j:]...)
	return merged
}

func testMergeSort() {
	result := mergeSort([]int{38, 27, 43, 3, 9, 82, 10})
	assertSliceEq(result, []int{3, 9, 10, 27, 38, 43, 82}, "merge sort")
	assertSliceEq(mergeSort([]int{}), []int{}, "merge sort empty")
	assertSliceEq(mergeSort([]int{1}), []int{1}, "merge sort single")
}

// ── Helpers ───────────────────────────────────────────────────────────
func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func assertSliceEq(a, b []int, msg string) {
	if len(a) != len(b) {
		panic(fmt.Sprintf("FAIL: %s: len %d != %d", msg, len(a), len(b)))
	}
	for i := range a {
		if a[i] != b[i] {
			panic(fmt.Sprintf("FAIL: %s: index %d: %d != %d", msg, i, a[i], b[i]))
		}
	}
}
