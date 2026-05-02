// Vidya — B+ Tree Indexing in TypeScript
//
// Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly
// the layout declared by cyrius.cyr. TS uses a discriminated-union
// `Node = Leaf | Internal` with `kind: "leaf" | "internal"` for type
// narrowing; each node carries `keys: number[]` plus either `vals` or
// `children`. Lookup of a missing key returns -1 (matches bt_search).

const BT_MAX = 7;

interface Leaf {
    kind: "leaf";
    keys: number[];
    vals: number[];
}

interface Internal {
    kind: "internal";
    keys: number[];
    children: Node[];
}

type Node = Leaf | Internal;

function newLeaf(): Leaf {
    return { kind: "leaf", keys: [], vals: [] };
}

// leafInsert — keep keys sorted (caller splits if oversize after insert).
function leafInsert(leaf: Leaf, key: number, val: number): void {
    let pos = leaf.keys.length;
    for (let i = 0; i < leaf.keys.length; i++) {
        if (key <= leaf.keys[i]) { pos = i; break; }
    }
    leaf.keys.splice(pos, 0, key);
    leaf.vals.splice(pos, 0, val);
}

function findLeaf(root: Node, key: number): Leaf {
    let n: Node = root;
    while (n.kind === "internal") {
        let ci = n.keys.length;
        for (let i = 0; i < n.keys.length; i++) {
            if (key < n.keys[i]) { ci = i; break; }
        }
        n = n.children[ci];
    }
    return n;
}

function btSearch(root: Node, key: number): number {
    const leaf = findLeaf(root, key);
    for (let i = 0; i < leaf.keys.length; i++) {
        if (leaf.keys[i] === key) return leaf.vals[i];
    }
    return -1;
}

function splitRootLeaf(old: Leaf): Internal {
    const nk = old.keys.length;
    const mid = nk >> 1;
    const median = old.keys[mid];
    const left: Leaf = {
        kind: "leaf",
        keys: old.keys.slice(0, mid),
        vals: old.vals.slice(0, mid),
    };
    const right: Leaf = {
        kind: "leaf",
        keys: old.keys.slice(mid),
        vals: old.vals.slice(mid),
    };
    return { kind: "internal", keys: [median], children: [left, right] };
}

function btInsert(root: Node, key: number, val: number): Node {
    if (root.kind === "leaf") {
        leafInsert(root, key, val);
        if (root.keys.length > BT_MAX) return splitRootLeaf(root);
        return root;
    }
    let ci = root.keys.length;
    for (let i = 0; i < root.keys.length; i++) {
        if (key < root.keys[i]) { ci = i; break; }
    }
    const child = root.children[ci];
    if (child.kind !== "leaf") {
        throw new Error("multi-level split not implemented");
    }
    leafInsert(child, key, val);
    if (child.keys.length > BT_MAX) {
        throw new Error("multi-level split not implemented");
    }
    return root;
}

// --- Tests ---

function mustEq(got: number, want: number, msg: string): void {
    if (got !== want) throw new Error(`FAIL: ${msg}: got ${got}, want ${want}`);
}

function mustTrue(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

function testBasicInsertAndSearch(): void {
    let t: Node = newLeaf();
    for (const [k, v] of [[10, 100], [5, 50], [20, 200], [15, 150], [3, 30]]) {
        t = btInsert(t, k, v);
    }
    mustEq(btSearch(t, 10), 100, "find 10");
    mustEq(btSearch(t, 5), 50, "find 5");
    mustEq(btSearch(t, 3), 30, "find 3");
    mustEq(btSearch(t, 99), -1, "miss 99");
}

function testKeysSortedInLeaf(): void {
    let t: Node = newLeaf();
    for (const [k, v] of [[10, 100], [5, 50], [20, 200], [15, 150], [3, 30]]) {
        t = btInsert(t, k, v);
    }
    mustTrue(t.kind === "leaf", "single leaf");
    if (t.kind !== "leaf") return;
    mustEq(t.keys.length, 5, "5 keys");
    mustEq(t.keys[0], 3, "first=3");
    mustEq(t.keys[4], 20, "last=20");
}

function testSplitOnOverflow(): void {
    let t: Node = newLeaf();
    for (let i = 0; i <= BT_MAX; i++) {
        t = btInsert(t, i, i * 10);
    }
    mustTrue(t.kind === "internal", "root became internal after split");
    for (let i = 0; i <= BT_MAX; i++) {
        mustEq(btSearch(t, i), i * 10, `find ${i}`);
    }
    mustEq(btSearch(t, 999), -1, "miss 999");
}

function testDescendingInsertsAreSorted(): void {
    let t: Node = newLeaf();
    const keys = [50, 40, 30, 20, 10];
    for (const k of keys) {
        t = btInsert(t, k, k * 2);
    }
    mustTrue(t.kind === "leaf", "single leaf");
    if (t.kind !== "leaf") return;
    mustEq(t.keys.length, 5, "5 keys");
    mustEq(t.keys[0], 10, "first=10");
    mustEq(t.keys[4], 50, "last=50");
    for (const k of keys) {
        mustEq(btSearch(t, k), k * 2, `find ${k}`);
    }
}

function main(): void {
    testBasicInsertAndSearch();
    testKeysSortedInLeaf();
    testSplitOnOverflow();
    testDescendingInsertsAreSorted();
    console.log("All btree_indexing examples passed.");
}

main();
