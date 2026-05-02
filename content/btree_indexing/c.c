// Vidya — B+ Tree Indexing in C
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the layout declared by cyrius.cyr. C uses malloc'd nodes plus flat
// fixed-size arrays inside each node: `keys[CAP]` (= MAX+1 to allow a
// transient overflow before split), `vals[CAP]`, and a `children[CAP+1]`
// pointer array for internal nodes. A `is_leaf` byte distinguishes the
// two — matching cyrius's BN_LEAF/BN_NK/BN_KEYS/BN_VALS struct-by-offset
// pattern. Lookup of a missing key returns -1 (matches bt_search).

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX 7
#define CAP 8 /* MAX + 1 — temporary overflow slot for pre-split insert */

typedef struct Node {
    uint8_t is_leaf;
    int     nkeys;
    int64_t keys[CAP];
    int64_t vals[CAP];                   /* used only when is_leaf */
    struct Node *children[CAP + 1];      /* used only when !is_leaf */
} Node;

static Node *node_new(int is_leaf) {
    Node *n = (Node *)calloc(1, sizeof(Node));
    if (!n) { fprintf(stderr, "out of memory\n"); exit(1); }
    n->is_leaf = (uint8_t)is_leaf;
    return n;
}

static void node_free(Node *n) {
    if (!n) return;
    if (!n->is_leaf) {
        for (int i = 0; i <= n->nkeys; i++) {
            node_free(n->children[i]);
        }
    }
    free(n);
}

/* leaf_insert: keep keys sorted (precondition: nkeys < CAP). */
static void leaf_insert(Node *leaf, int64_t key, int64_t val) {
    int nk = leaf->nkeys;
    int pos = nk;
    for (int i = 0; i < nk; i++) {
        if (key <= leaf->keys[i]) { pos = i; break; }
    }
    for (int j = nk; j > pos; j--) {
        leaf->keys[j] = leaf->keys[j - 1];
        leaf->vals[j] = leaf->vals[j - 1];
    }
    leaf->keys[pos] = key;
    leaf->vals[pos] = val;
    leaf->nkeys = nk + 1;
}

/* find_leaf: walk down to the leaf that should contain `key`. */
static Node *find_leaf(Node *root, int64_t key) {
    Node *node = root;
    while (!node->is_leaf) {
        int ci = node->nkeys;
        for (int i = 0; i < node->nkeys; i++) {
            if (key < node->keys[i]) { ci = i; break; }
        }
        node = node->children[ci];
    }
    return node;
}

static int64_t bt_search(Node *root, int64_t key) {
    Node *leaf = find_leaf(root, key);
    for (int i = 0; i < leaf->nkeys; i++) {
        if (leaf->keys[i] == key) return leaf->vals[i];
    }
    return -1;
}

/* split_root_leaf: leaf root has nkeys == CAP; split into two leaves and
 * promote the median key into a new internal root. */
static Node *split_root_leaf(Node *old) {
    int nk = old->nkeys;
    int mid = nk / 2;
    int64_t median = old->keys[mid];

    Node *left = node_new(1);
    Node *right = node_new(1);

    for (int i = 0; i < mid; i++) {
        left->keys[i] = old->keys[i];
        left->vals[i] = old->vals[i];
    }
    left->nkeys = mid;
    for (int i = mid; i < nk; i++) {
        right->keys[i - mid] = old->keys[i];
        right->vals[i - mid] = old->vals[i];
    }
    right->nkeys = nk - mid;

    Node *new_root = node_new(0);
    new_root->keys[0] = median;
    new_root->children[0] = left;
    new_root->children[1] = right;
    new_root->nkeys = 1;

    free(old);
    return new_root;
}

static Node *bt_insert(Node *root, int64_t key, int64_t val) {
    if (root->is_leaf) {
        leaf_insert(root, key, val);
        if (root->nkeys > MAX) return split_root_leaf(root);
        return root;
    }

    /* Internal root → descend to correct leaf. The cyrius test set only
     * triggers a single split, so we don't propagate splits upward. */
    int ci = root->nkeys;
    for (int i = 0; i < root->nkeys; i++) {
        if (key < root->keys[i]) { ci = i; break; }
    }
    Node *leaf = root->children[ci];
    if (!leaf->is_leaf) {
        fprintf(stderr, "multi-level split not implemented\n"); exit(1);
    }
    leaf_insert(leaf, key, val);
    if (leaf->nkeys > MAX) {
        fprintf(stderr, "multi-level split not implemented\n"); exit(1);
    }
    return root;
}

/* ── Tests ──────────────────────────────────────────────────────────── */

static void test_basic_insert_and_search(void) {
    Node *t = node_new(1);
    t = bt_insert(t, 10, 100);
    t = bt_insert(t, 5, 50);
    t = bt_insert(t, 20, 200);
    t = bt_insert(t, 15, 150);
    t = bt_insert(t, 3, 30);

    assert(bt_search(t, 10) == 100);
    assert(bt_search(t, 5) == 50);
    assert(bt_search(t, 3) == 30);
    assert(bt_search(t, 99) == -1);

    node_free(t);
}

static void test_keys_sorted_in_leaf(void) {
    Node *t = node_new(1);
    t = bt_insert(t, 10, 100);
    t = bt_insert(t, 5, 50);
    t = bt_insert(t, 20, 200);
    t = bt_insert(t, 15, 150);
    t = bt_insert(t, 3, 30);

    /* Single leaf — keys should be sorted. */
    assert(t->is_leaf);
    assert(t->nkeys == 5);
    assert(t->keys[0] == 3);
    assert(t->keys[4] == 20);

    node_free(t);
}

static void test_split_on_overflow(void) {
    Node *t = node_new(1);
    for (int64_t i = 0; i <= MAX; i++) {
        t = bt_insert(t, i, i * 10);
    }
    /* After MAX+1 inserts, the leaf overflowed and split into an internal root. */
    assert(!t->is_leaf);
    for (int64_t i = 0; i <= MAX; i++) {
        assert(bt_search(t, i) == i * 10);
    }
    assert(bt_search(t, 999) == -1);
    node_free(t);
}

static void test_descending_inserts_are_sorted(void) {
    Node *t = node_new(1);
    int64_t keys[] = {50, 40, 30, 20, 10};
    int n = (int)(sizeof(keys) / sizeof(keys[0]));
    for (int i = 0; i < n; i++) {
        t = bt_insert(t, keys[i], keys[i] * 2);
    }
    assert(t->is_leaf);
    assert(t->nkeys == 5);
    assert(t->keys[0] == 10);
    assert(t->keys[4] == 50);
    for (int i = 0; i < n; i++) {
        assert(bt_search(t, keys[i]) == keys[i] * 2);
    }
    node_free(t);
}

int main(void) {
    test_basic_insert_and_search();
    test_keys_sorted_in_leaf();
    test_split_on_overflow();
    test_descending_inserts_are_sorted();
    puts("All btree_indexing examples passed.");
    return 0;
}
