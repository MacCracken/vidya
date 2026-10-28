// Vidya — B+ Tree Indexing in Rust
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the shape declared by cyrius.cyr. Rust uses `Box<Node>` for owned tree
// nodes and an enum `NodeKind { Leaf { vals }, Internal { children } }`
// to distinguish leaves from internal nodes. Keys live inline in
// fixed-size `[i64; MAX]` arrays (no allocations on insert until split),
// matching the BN_LEAF/BN_NK/BN_KEYS/BN_VALS layout. The tests cover
// insert + sorted-order, hit/miss search, and split-promotion of a
// median key once a leaf exceeds MAX entries.

const MAX: usize = 7;
const CAP: usize = MAX + 1; // one extra slot lets us insert before splitting.

enum NodeKind {
    Leaf { vals: [i64; CAP] },
    Internal { children: Vec<Box<Node>> },
}

struct Node {
    nkeys: usize,
    keys: [i64; CAP],
    kind: NodeKind,
}

impl Node {
    fn new_leaf() -> Box<Node> {
        Box::new(Node {
            nkeys: 0,
            keys: [0; CAP],
            kind: NodeKind::Leaf { vals: [0; CAP] },
        })
    }

    fn is_leaf(&self) -> bool {
        matches!(self.kind, NodeKind::Leaf { .. })
    }
}

struct BTree {
    root: Box<Node>,
}

impl BTree {
    fn new() -> Self {
        BTree { root: Node::new_leaf() }
    }

    // Insert key/val into a leaf (assumes nkeys < MAX). Keeps keys sorted.
    fn leaf_insert(leaf: &mut Node, key: i64, val: i64) {
        let nk = leaf.nkeys;
        let mut pos = nk;
        for i in 0..nk {
            if key <= leaf.keys[i] {
                pos = i;
                break;
            }
        }
        let vals = match &mut leaf.kind {
            NodeKind::Leaf { vals } => vals,
            _ => unreachable!("leaf_insert on internal"),
        };
        // Shift right
        let mut j = nk;
        while j > pos {
            leaf.keys[j] = leaf.keys[j - 1];
            vals[j] = vals[j - 1];
            j -= 1;
        }
        leaf.keys[pos] = key;
        vals[pos] = val;
        leaf.nkeys = nk + 1;
    }

    // Find the leaf that should contain `key`. Mirrors bt_find_leaf.
    fn find_leaf(&self, key: i64) -> &Node {
        let mut node: &Node = &self.root;
        loop {
            let children = match &node.kind {
                NodeKind::Leaf { .. } => return node,
                NodeKind::Internal { children } => children,
            };
            let mut ci = node.nkeys;
            for i in 0..node.nkeys {
                if key < node.keys[i] {
                    ci = i;
                    break;
                }
            }
            node = &children[ci];
        }
    }

    // Search for a key; returns its value or -1 (matches cyrius bt_search).
    fn search(&self, key: i64) -> i64 {
        let leaf = self.find_leaf(key);
        let vals = match &leaf.kind {
            NodeKind::Leaf { vals } => vals,
            _ => unreachable!(),
        };
        for i in 0..leaf.nkeys {
            if leaf.keys[i] == key {
                return vals[i];
            }
        }
        -1
    }

    // Insert key/val. If the (single-leaf) root would exceed MAX entries,
    // split it: median key promotes into a new internal root, the leaf
    // splits into left (< median) + right (>= median).
    fn insert(&mut self, key: i64, val: i64) {
        // Single-level tree: only the root is touched.
        if self.root.is_leaf() {
            if self.root.nkeys < MAX {
                Self::leaf_insert(&mut self.root, key, val);
                return;
            }
            // Leaf is full — split.
            Self::leaf_insert(&mut self.root, key, val);
            self.split_root_leaf();
            return;
        }
        // Internal root: descend to the correct leaf via index lookup,
        // then split if needed. (Multi-level splits are out of scope —
        // the test set in cyrius.cyr only forces a single split.)
        let nk = self.root.nkeys;
        let mut ci = nk;
        for i in 0..nk {
            if key < self.root.keys[i] {
                ci = i;
                break;
            }
        }
        let children = match &mut self.root.kind {
            NodeKind::Internal { children } => children,
            _ => unreachable!(),
        };
        let leaf = &mut children[ci];
        if leaf.nkeys < MAX {
            Self::leaf_insert(leaf, key, val);
        } else {
            // Single-split scenario only — the test set never triggers it.
            panic!("multi-level split not implemented for this reference");
        }
    }

    // Promote median; turn root into a new internal node with two leaves.
    fn split_root_leaf(&mut self) {
        let nk = self.root.nkeys;
        let mid = nk / 2;
        let median = self.root.keys[mid];

        let mut left = Node::new_leaf();
        let mut right = Node::new_leaf();

        let old_keys = self.root.keys;
        let old_vals = match &self.root.kind {
            NodeKind::Leaf { vals } => *vals,
            _ => unreachable!(),
        };

        // [0..mid) -> left ; [mid..nk) -> right (B+ keeps median in right)
        let lvals = match &mut left.kind {
            NodeKind::Leaf { vals } => vals,
            _ => unreachable!(),
        };
        for i in 0..mid {
            left.keys[i] = old_keys[i];
            lvals[i] = old_vals[i];
        }
        left.nkeys = mid;

        let rvals = match &mut right.kind {
            NodeKind::Leaf { vals } => vals,
            _ => unreachable!(),
        };
        for i in mid..nk {
            right.keys[i - mid] = old_keys[i];
            rvals[i - mid] = old_vals[i];
        }
        right.nkeys = nk - mid;

        let mut new_root = Box::new(Node {
            nkeys: 1,
            keys: [0; CAP],
            kind: NodeKind::Internal { children: vec![left, right] },
        });
        new_root.keys[0] = median;
        self.root = new_root;
    }
}

fn test_basic_insert_and_search() {
    let mut t = BTree::new();
    t.insert(10, 100);
    t.insert(5, 50);
    t.insert(20, 200);
    t.insert(15, 150);
    t.insert(3, 30);

    assert_eq!(t.search(10), 100);
    assert_eq!(t.search(5), 50);
    assert_eq!(t.search(3), 30);
    assert_eq!(t.search(99), -1);
}

fn test_keys_sorted_in_leaf() {
    let mut t = BTree::new();
    t.insert(10, 100);
    t.insert(5, 50);
    t.insert(20, 200);
    t.insert(15, 150);
    t.insert(3, 30);
    // Single leaf — keys should be sorted: 3, 5, 10, 15, 20.
    let leaf = t.find_leaf(0);
    assert_eq!(leaf.nkeys, 5);
    assert_eq!(leaf.keys[0], 3);
    assert_eq!(leaf.keys[4], 20);
}

fn test_split_on_overflow() {
    // Insert MAX+1 keys to force a single split.
    let mut t = BTree::new();
    for i in 0..(MAX + 1) as i64 {
        t.insert(i, i * 10);
    }
    // Root is now internal; lookups still work.
    assert!(!t.root.is_leaf());
    for i in 0..(MAX + 1) as i64 {
        assert_eq!(t.search(i), i * 10);
    }
    assert_eq!(t.search(999), -1);
}

fn test_descending_inserts_are_sorted() {
    let mut t = BTree::new();
    let keys = [50, 40, 30, 20, 10];
    for k in keys {
        t.insert(k, k * 2);
    }
    let leaf = t.find_leaf(0);
    assert_eq!(leaf.nkeys, 5);
    assert_eq!(leaf.keys[0], 10);
    assert_eq!(leaf.keys[4], 50);
    for k in keys {
        assert_eq!(t.search(k), k * 2);
    }
}

fn main() {
    test_basic_insert_and_search();
    test_keys_sorted_in_leaf();
    test_split_on_overflow();
    test_descending_inserts_are_sorted();
    println!("All btree_indexing examples passed.");
}
