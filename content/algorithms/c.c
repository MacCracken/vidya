#define _GNU_SOURCE
// Vidya — Algorithms in C
//
// C gives you full control over memory and data layout — crucial for
// cache-friendly algorithms. No built-in dynamic arrays or hash maps;
// you build (or use) your own. qsort and bsearch are in stdlib.h.

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Binary search ─────────────────────────────────────────────────────
// Returns index of target, or -1 if not found.
static int binary_search(const int *arr, int len, int target) {
    int lo = 0, hi = len;
    while (lo < hi) {
        int mid = lo + (hi - lo) / 2;  // safe midpoint
        if (arr[mid] == target) return mid;
        else if (arr[mid] < target) lo = mid + 1;
        else hi = mid;
    }
    return -1;
}

static void test_binary_search(void) {
    int arr[] = {1, 3, 5, 7, 9, 11, 13, 15, 17, 19};
    int len = sizeof(arr) / sizeof(arr[0]);

    assert(binary_search(arr, len, 7) == 3);
    assert(binary_search(arr, len, 1) == 0);
    assert(binary_search(arr, len, 19) == 9);
    assert(binary_search(arr, len, 4) == -1);
    assert(binary_search(arr, len, 20) == -1);
    assert(binary_search(arr, 0, 1) == -1);
}

static int compare_int(const void *a, const void *b) {
    return *(const int *)a - *(const int *)b;
}

// ── Insertion sort ────────────────────────────────────────────────────
static void insertion_sort(int *arr, int len) {
    for (int i = 1; i < len; i++) {
        int key = arr[i];
        int j = i - 1;
        while (j >= 0 && arr[j] > key) {
            arr[j + 1] = arr[j];
            j--;
        }
        arr[j + 1] = key;
    }
}

static void test_sorting(void) {
    int arr[] = {5, 2, 8, 1, 9, 3};
    insertion_sort(arr, 6);
    int expected[] = {1, 2, 3, 5, 8, 9};
    assert(memcmp(arr, expected, sizeof(expected)) == 0);

    // Empty and single
    insertion_sort(NULL, 0);  // should not crash
    int one[] = {42};
    insertion_sort(one, 1);
    assert(one[0] == 42);

    // Stdlib qsort for comparison
    int arr2[] = {5, 2, 8, 1, 9, 3};
    qsort(arr2, 6, sizeof(int), compare_int);
    assert(memcmp(arr2, expected, sizeof(expected)) == 0);
}

// ── Graph BFS (adjacency matrix, small graphs) ───────────────────────
#define MAX_NODES 16

typedef struct {
    int adj[MAX_NODES][MAX_NODES];
    int degree[MAX_NODES];
    int n;
} Graph;

static void graph_init(Graph *g, int n) {
    memset(g, 0, sizeof(*g));
    g->n = n;
}

static void graph_add_edge(Graph *g, int u, int v) {
    g->adj[u][g->degree[u]++] = v;
    g->adj[v][g->degree[v]++] = u;
}

static int bfs_shortest_path(const Graph *g, int start, int end, int *path) {
    bool visited[MAX_NODES] = {false};
    int parent[MAX_NODES];
    memset(parent, -1, sizeof(parent));

    int queue[MAX_NODES];
    int front = 0, back = 0;
    queue[back++] = start;
    visited[start] = true;

    while (front < back) {
        int node = queue[front++];
        if (node == end) {
            // Reconstruct path
            int len = 0;
            for (int cur = end; cur != -1; cur = parent[cur]) {
                path[len++] = cur;
            }
            // Reverse
            for (int i = 0; i < len / 2; i++) {
                int tmp = path[i];
                path[i] = path[len - 1 - i];
                path[len - 1 - i] = tmp;
            }
            return len;
        }
        for (int i = 0; i < g->degree[node]; i++) {
            int nb = g->adj[node][i];
            if (!visited[nb]) {
                visited[nb] = true;
                parent[nb] = node;
                queue[back++] = nb;
            }
        }
    }
    return 0;  // no path
}

static void test_graph_bfs(void) {
    Graph g;
    graph_init(&g, 5);
    graph_add_edge(&g, 0, 1);
    graph_add_edge(&g, 1, 2);
    graph_add_edge(&g, 2, 3);
    graph_add_edge(&g, 3, 4);
    graph_add_edge(&g, 0, 4);

    int path[MAX_NODES];
    int len = bfs_shortest_path(&g, 0, 3, path);
    assert(len == 3);  // 0→4→3
    assert(path[0] == 0 && path[1] == 4 && path[2] == 3);
}

// ── Graph DFS (iterative with stack) ──────────────────────────────────
static void dfs_reachable(const Graph *g, int start, bool *visited) {
    memset(visited, false, sizeof(bool) * (size_t)g->n);
    int stack[MAX_NODES];
    int top = 0;
    stack[top++] = start;

    while (top > 0) {
        int node = stack[--top];
        if (visited[node]) continue;
        visited[node] = true;
        for (int i = 0; i < g->degree[node]; i++) {
            int nb = g->adj[node][i];
            if (!visited[nb]) {
                stack[top++] = nb;
            }
        }
    }
}

static void test_graph_dfs(void) {
    Graph g;
    graph_init(&g, 5);
    graph_add_edge(&g, 0, 1);
    graph_add_edge(&g, 0, 2);
    graph_add_edge(&g, 1, 3);
    // Node 4 is isolated

    bool visited[MAX_NODES];
    dfs_reachable(&g, 0, visited);
    assert(visited[0] && visited[1] && visited[2] && visited[3]);
    assert(!visited[4]);
}

// ── Dynamic programming: Fibonacci ────────────────────────────────────
static uint64_t fibonacci(int n) {
    if (n <= 1) return (uint64_t)n;
    uint64_t a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
        uint64_t next = a + b;
        a = b;
        b = next;
    }
    return b;
}

// LCS length
static int lcs_length(const char *a, const char *b) {
    int m = (int)strlen(a), n = (int)strlen(b);
    // Use VLA for small inputs (stack-allocated DP table)
    int dp[m + 1][n + 1];
    memset(dp, 0, sizeof(dp));
    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (a[i - 1] == b[j - 1]) {
                dp[i][j] = dp[i - 1][j - 1] + 1;
            } else {
                dp[i][j] = dp[i - 1][j] > dp[i][j - 1]
                          ? dp[i - 1][j] : dp[i][j - 1];
            }
        }
    }
    return dp[m][n];
}

static void test_dynamic_programming(void) {
    assert(fibonacci(0) == 0);
    assert(fibonacci(1) == 1);
    assert(fibonacci(10) == 55);
    assert(fibonacci(20) == 6765);

    assert(lcs_length("ABCBDAB", "BDCAB") == 4);
    assert(lcs_length("", "ABC") == 0);
    assert(lcs_length("ABC", "ABC") == 3);
    assert(lcs_length("ABC", "DEF") == 0);
}

// ── GCD (Euclidean) ───────────────────────────────────────────────────
static uint64_t gcd(uint64_t a, uint64_t b) {
    while (b != 0) {
        uint64_t t = b;
        b = a % b;
        a = t;
    }
    return a;
}

static void test_gcd(void) {
    assert(gcd(48, 18) == 6);
    assert(gcd(100, 75) == 25);
    assert(gcd(17, 13) == 1);
    assert(gcd(0, 5) == 5);
    assert(gcd(7, 0) == 7);
}

// ── Merge sort ────────────────────────────────────────────────────────
static void merge_sort(int *arr, int len) {
    if (len <= 1) return;
    int mid = len / 2;
    merge_sort(arr, mid);
    merge_sort(arr + mid, len - mid);

    int *tmp = malloc(sizeof(int) * (size_t)len);
    assert(tmp != NULL);
    int i = 0, j = mid, k = 0;
    while (i < mid && j < len) {
        if (arr[i] <= arr[j]) tmp[k++] = arr[i++];
        else tmp[k++] = arr[j++];
    }
    while (i < mid) tmp[k++] = arr[i++];
    while (j < len) tmp[k++] = arr[j++];
    memcpy(arr, tmp, sizeof(int) * (size_t)len);
    free(tmp);
}

static void test_merge_sort(void) {
    int arr[] = {38, 27, 43, 3, 9, 82, 10};
    merge_sort(arr, 7);
    int expected[] = {3, 9, 10, 27, 38, 43, 82};
    assert(memcmp(arr, expected, sizeof(expected)) == 0);

    merge_sort(NULL, 0);  // empty
    int one[] = {1};
    merge_sort(one, 1);
    assert(one[0] == 1);
}

int main(void) {
    test_binary_search();
    test_sorting();
    test_graph_bfs();
    test_graph_dfs();
    test_dynamic_programming();
    test_gcd();
    test_merge_sort();

    printf("All algorithms examples passed.\n");
    return 0;
}
