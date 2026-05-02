// Vidya — B+ Tree Indexing in Go
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the layout declared by cyrius.cyr. Go uses slices for keys/vals and a
// `[]*node` for children; an `isLeaf` bool tags the discriminator. The
// slice-based design lets append+sort logic stay branch-free; we
// allocate a fresh leaf on split rather than mutating in place. Lookup
// of a missing key returns -1 (matches bt_search).

package main

import "fmt"

const btMax = 7

type node struct {
	isLeaf   bool
	keys     []int64
	vals     []int64 // used when isLeaf
	children []*node // used when !isLeaf
}

func newLeaf() *node {
	return &node{isLeaf: true, keys: nil, vals: nil}
}

// leafInsert keeps keys sorted (precondition: caller will split if oversize).
func leafInsert(leaf *node, key, val int64) {
	pos := len(leaf.keys)
	for i, k := range leaf.keys {
		if key <= k {
			pos = i
			break
		}
	}
	leaf.keys = append(leaf.keys, 0)
	leaf.vals = append(leaf.vals, 0)
	copy(leaf.keys[pos+1:], leaf.keys[pos:])
	copy(leaf.vals[pos+1:], leaf.vals[pos:])
	leaf.keys[pos] = key
	leaf.vals[pos] = val
}

// findLeaf walks down to the leaf that should contain `key`.
func findLeaf(root *node, key int64) *node {
	n := root
	for !n.isLeaf {
		ci := len(n.keys)
		for i, k := range n.keys {
			if key < k {
				ci = i
				break
			}
		}
		n = n.children[ci]
	}
	return n
}

func btSearch(root *node, key int64) int64 {
	leaf := findLeaf(root, key)
	for i, k := range leaf.keys {
		if k == key {
			return leaf.vals[i]
		}
	}
	return -1
}

func splitRootLeaf(old *node) *node {
	nk := len(old.keys)
	mid := nk / 2
	median := old.keys[mid]

	left := newLeaf()
	left.keys = append(left.keys, old.keys[:mid]...)
	left.vals = append(left.vals, old.vals[:mid]...)

	right := newLeaf()
	right.keys = append(right.keys, old.keys[mid:]...)
	right.vals = append(right.vals, old.vals[mid:]...)

	return &node{
		isLeaf:   false,
		keys:     []int64{median},
		children: []*node{left, right},
	}
}

func btInsert(root *node, key, val int64) *node {
	if root.isLeaf {
		leafInsert(root, key, val)
		if len(root.keys) > btMax {
			return splitRootLeaf(root)
		}
		return root
	}

	// Internal root → descend. The cyrius test set only forces one split.
	ci := len(root.keys)
	for i, k := range root.keys {
		if key < k {
			ci = i
			break
		}
	}
	leaf := root.children[ci]
	if !leaf.isLeaf {
		panic("multi-level split not implemented")
	}
	leafInsert(leaf, key, val)
	if len(leaf.keys) > btMax {
		panic("multi-level split not implemented")
	}
	return root
}

// --- Tests ---

func mustEq(got, want int64, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %d, want %d", msg, got, want))
	}
}

func mustTrue(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func testBasicInsertAndSearch() {
	t := newLeaf()
	for _, kv := range [][2]int64{{10, 100}, {5, 50}, {20, 200}, {15, 150}, {3, 30}} {
		t = btInsert(t, kv[0], kv[1])
	}
	mustEq(btSearch(t, 10), 100, "find 10")
	mustEq(btSearch(t, 5), 50, "find 5")
	mustEq(btSearch(t, 3), 30, "find 3")
	mustEq(btSearch(t, 99), -1, "miss 99")
}

func testKeysSortedInLeaf() {
	t := newLeaf()
	for _, kv := range [][2]int64{{10, 100}, {5, 50}, {20, 200}, {15, 150}, {3, 30}} {
		t = btInsert(t, kv[0], kv[1])
	}
	mustTrue(t.isLeaf, "single leaf")
	mustEq(int64(len(t.keys)), 5, "5 keys")
	mustEq(t.keys[0], 3, "first=3")
	mustEq(t.keys[4], 20, "last=20")
}

func testSplitOnOverflow() {
	t := newLeaf()
	for i := int64(0); i <= btMax; i++ {
		t = btInsert(t, i, i*10)
	}
	mustTrue(!t.isLeaf, "root became internal after split")
	for i := int64(0); i <= btMax; i++ {
		mustEq(btSearch(t, i), i*10, fmt.Sprintf("find %d", i))
	}
	mustEq(btSearch(t, 999), -1, "miss 999")
}

func testDescendingInsertsAreSorted() {
	t := newLeaf()
	keys := []int64{50, 40, 30, 20, 10}
	for _, k := range keys {
		t = btInsert(t, k, k*2)
	}
	mustTrue(t.isLeaf, "single leaf")
	mustEq(int64(len(t.keys)), 5, "5 keys")
	mustEq(t.keys[0], 10, "first=10")
	mustEq(t.keys[4], 50, "last=50")
	for _, k := range keys {
		mustEq(btSearch(t, k), k*2, fmt.Sprintf("find %d", k))
	}
}

func main() {
	testBasicInsertAndSearch()
	testKeysSortedInLeaf()
	testSplitOnOverflow()
	testDescendingInsertsAreSorted()
	fmt.Println("All btree_indexing examples passed.")
}
