// Vidya — Algorithms in Rust
//
// Rust's standard library provides sort, binary_search, and iterators
// that cover many algorithmic needs. For graphs and DP, Rust's
// ownership model encourages index-based approaches over pointer
// graphs. HashMap and BTreeMap cover most lookup patterns.

use std::collections::{HashMap, VecDeque};

fn main() {
    test_binary_search();
    test_sorting();
    test_graph_bfs();
    test_graph_dfs();
    test_dynamic_programming();
    test_two_sum_hashmap();
    test_gcd();
    test_merge_sort();

    println!("All algorithms examples passed.");
}

// ── Binary search ───────────────────────────────────���─────────────────
// O(log n) — requires sorted input. Returns index of target.
fn binary_search(arr: &[i32], target: i32) -> Option<usize> {
    let mut lo: usize = 0;
    let mut hi: usize = arr.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2; // safe midpoint (no overflow)
        match arr[mid].cmp(&target) {
            std::cmp::Ordering::Equal => return Some(mid),
            std::cmp::Ordering::Less => lo = mid + 1,
            std::cmp::Ordering::Greater => hi = mid,
        }
    }
    None
}

fn test_binary_search() {
    let arr = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19];
    assert_eq!(binary_search(&arr, 7), Some(3));
    assert_eq!(binary_search(&arr, 1), Some(0));
    assert_eq!(binary_search(&arr, 19), Some(9));
    assert_eq!(binary_search(&arr, 4), None);
    assert_eq!(binary_search(&arr, 20), None);
    assert_eq!(binary_search(&[], 1), None);

    // Compare with stdlib
    assert_eq!(arr.binary_search(&7), Ok(3));
}

// ── Sorting ──────────────────────────────────────────��────────────────
// Insertion sort: O(n^2) but fast for small/nearly-sorted data
fn insertion_sort(arr: &mut [i32]) {
    for i in 1..arr.len() {
        let key = arr[i];
        let mut j = i;
        while j > 0 && arr[j - 1] > key {
            arr[j] = arr[j - 1];
            j -= 1;
        }
        arr[j] = key;
    }
}

fn test_sorting() {
    let mut arr = [5, 2, 8, 1, 9, 3];
    insertion_sort(&mut arr);
    assert_eq!(arr, [1, 2, 3, 5, 8, 9]);

    // Empty and single-element
    let mut empty: [i32; 0] = [];
    insertion_sort(&mut empty);
    let mut one = [42];
    insertion_sort(&mut one);
    assert_eq!(one, [42]);

    // Already sorted
    let mut sorted = [1, 2, 3, 4, 5];
    insertion_sort(&mut sorted);
    assert_eq!(sorted, [1, 2, 3, 4, 5]);

    // Stdlib sort (pdqsort — pattern-defeating quicksort)
    let mut v = vec![5, 2, 8, 1, 9, 3];
    v.sort_unstable();
    assert_eq!(v, [1, 2, 3, 5, 8, 9]);
}

// ── Graph BFS (shortest path in unweighted graph) ─────────────────────
// Adjacency list represented as Vec<Vec<usize>>
fn bfs_shortest_path(adj: &[Vec<usize>], start: usize, end: usize) -> Option<Vec<usize>> {
    let n = adj.len();
    let mut visited = vec![false; n];
    let mut parent = vec![None; n];
    let mut queue = VecDeque::new();

    visited[start] = true;
    queue.push_back(start);

    while let Some(node) = queue.pop_front() {
        if node == end {
            // Reconstruct path
            let mut path = vec![end];
            let mut current = end;
            while let Some(p) = parent[current] {
                path.push(p);
                current = p;
            }
            path.reverse();
            return Some(path);
        }
        for &neighbor in &adj[node] {
            if !visited[neighbor] {
                visited[neighbor] = true;
                parent[neighbor] = Some(node);
                queue.push_back(neighbor);
            }
        }
    }
    None
}

fn test_graph_bfs() {
    // Graph: 0-1-2-3, 0-4-3 (shorter path 0→4→3)
    let adj = vec![
        vec![1, 4],    // 0 → 1, 4
        vec![0, 2],    // 1 → 0, 2
        vec![1, 3],    // 2 → 1, 3
        vec![2, 4],    // 3 → 2, 4
        vec![0, 3],    // 4 → 0, 3
    ];

    let path = bfs_shortest_path(&adj, 0, 3).unwrap();
    assert_eq!(path, vec![0, 4, 3]); // shortest: 0→4→3 (length 2)
    assert_eq!(path.len(), 3);       // 3 nodes = 2 edges

    // No path in disconnected graph
    let disconnected = vec![vec![1], vec![0], vec![3], vec![2]];
    assert!(bfs_shortest_path(&disconnected, 0, 2).is_none());
}

// ── Graph DFS (exhaustive reachability) ───────────────────────────────
fn dfs_reachable(adj: &[Vec<usize>], start: usize) -> Vec<bool> {
    let mut visited = vec![false; adj.len()];
    let mut stack = vec![start];

    while let Some(node) = stack.pop() {
        if visited[node] {
            continue;
        }
        visited[node] = true;
        for &neighbor in &adj[node] {
            if !visited[neighbor] {
                stack.push(neighbor);
            }
        }
    }
    visited
}

fn test_graph_dfs() {
    let adj = vec![
        vec![1, 2],    // 0
        vec![0, 3],    // 1
        vec![0],       // 2
        vec![1],       // 3
        vec![],        // 4 (isolated)
    ];

    let reachable = dfs_reachable(&adj, 0);
    assert!(reachable[0] && reachable[1] && reachable[2] && reachable[3]);
    assert!(!reachable[4]); // isolated node
}

// ── Dynamic programming: Fibonacci ────────────────────────────────────
// Bottom-up tabulation: O(n) time, O(1) space
fn fibonacci(n: u64) -> u64 {
    if n <= 1 {
        return n;
    }
    let (mut a, mut b) = (0u64, 1u64);
    for _ in 2..=n {
        let next = a + b;
        a = b;
        b = next;
    }
    b
}

// Longest common subsequence: O(m*n) time
fn lcs_length(a: &[u8], b: &[u8]) -> usize {
    let (m, n) = (a.len(), b.len());
    let mut dp = vec![vec![0usize; n + 1]; m + 1];
    for i in 1..=m {
        for j in 1..=n {
            dp[i][j] = if a[i - 1] == b[j - 1] {
                dp[i - 1][j - 1] + 1
            } else {
                dp[i - 1][j].max(dp[i][j - 1])
            };
        }
    }
    dp[m][n]
}

fn test_dynamic_programming() {
    // Fibonacci
    assert_eq!(fibonacci(0), 0);
    assert_eq!(fibonacci(1), 1);
    assert_eq!(fibonacci(10), 55);
    assert_eq!(fibonacci(20), 6765);

    // LCS
    assert_eq!(lcs_length(b"ABCBDAB", b"BDCAB"), 4); // "BCAB"
    assert_eq!(lcs_length(b"", b"ABC"), 0);
    assert_eq!(lcs_length(b"ABC", b"ABC"), 3);
    assert_eq!(lcs_length(b"ABC", b"DEF"), 0);
}

// ── Two-sum with hash map: O(n) ──────────────────────────────────────
fn two_sum(nums: &[i32], target: i32) -> Option<(usize, usize)> {
    let mut seen: HashMap<i32, usize> = HashMap::new();
    for (i, &num) in nums.iter().enumerate() {
        let complement = target - num;
        if let Some(&j) = seen.get(&complement) {
            return Some((j, i));
        }
        seen.insert(num, i);
    }
    None
}

fn test_two_sum_hashmap() {
    assert_eq!(two_sum(&[2, 7, 11, 15], 9), Some((0, 1)));
    assert_eq!(two_sum(&[3, 2, 4], 6), Some((1, 2)));
    assert_eq!(two_sum(&[1, 2, 3], 7), None);
}

// ── GCD (Euclidean algorithm): O(log(min(a,b))) ──��───────────────────
fn gcd(mut a: u64, mut b: u64) -> u64 {
    while b != 0 {
        let t = b;
        b = a % b;
        a = t;
    }
    a
}

fn test_gcd() {
    assert_eq!(gcd(48, 18), 6);
    assert_eq!(gcd(100, 75), 25);
    assert_eq!(gcd(17, 13), 1); // coprime
    assert_eq!(gcd(0, 5), 5);
    assert_eq!(gcd(7, 0), 7);
}

// ── Merge sort: O(n log n), stable ────────────────────────────────────
fn merge_sort(arr: &mut [i32]) {
    let len = arr.len();
    if len <= 1 {
        return;
    }
    let mid = len / 2;
    merge_sort(&mut arr[..mid]);
    merge_sort(&mut arr[mid..]);

    // Merge into temp buffer, then copy back
    let left = arr[..mid].to_vec();
    let right = arr[mid..].to_vec();
    let (mut i, mut j, mut k) = (0, 0, 0);
    while i < left.len() && j < right.len() {
        if left[i] <= right[j] {
            arr[k] = left[i];
            i += 1;
        } else {
            arr[k] = right[j];
            j += 1;
        }
        k += 1;
    }
    while i < left.len() {
        arr[k] = left[i];
        i += 1;
        k += 1;
    }
    while j < right.len() {
        arr[k] = right[j];
        j += 1;
        k += 1;
    }
}

fn test_merge_sort() {
    let mut arr = [38, 27, 43, 3, 9, 82, 10];
    merge_sort(&mut arr);
    assert_eq!(arr, [3, 9, 10, 27, 38, 43, 82]);

    let mut empty: [i32; 0] = [];
    merge_sort(&mut empty);

    let mut one = [1];
    merge_sort(&mut one);
    assert_eq!(one, [1]);

    // Stability not testable with i32, but merge sort preserves order
    // of equal elements by design (left[i] <= right[j] uses <=)
}
