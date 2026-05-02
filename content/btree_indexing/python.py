#!/usr/bin/env python3
"""Vidya — B+ Tree Indexing in Python.

Simplified in-memory B+ tree (order 8, max 7 keys per node) — exactly the
shape declared by cyrius.cyr. Python uses two small classes (``Leaf`` and
``Internal``) instead of a tagged union: each leaf holds parallel ``keys``
and ``vals`` lists, each internal holds ``keys`` plus a ``children`` list.
Tests cover insert + sorted-order, hit/miss search, split when a leaf
exceeds MAX entries, and descending-input inserts (which exercise the
shift-right loop most heavily).
"""

from __future__ import annotations

from typing import List, Union

MAX = 7


class Leaf:
    __slots__ = ("keys", "vals")

    def __init__(self) -> None:
        self.keys: List[int] = []
        self.vals: List[int] = []


class Internal:
    __slots__ = ("keys", "children")

    def __init__(self) -> None:
        self.keys: List[int] = []
        self.children: List[Union["Leaf", "Internal"]] = []


Node = Union[Leaf, Internal]


def _leaf_insert(leaf: Leaf, key: int, val: int) -> None:
    """Insert (key, val) into ``leaf`` keeping ``keys`` sorted."""
    pos = len(leaf.keys)
    for i, k in enumerate(leaf.keys):
        if key <= k:
            pos = i
            break
    leaf.keys.insert(pos, key)
    leaf.vals.insert(pos, val)


def _find_leaf(root: Node, key: int) -> Leaf:
    node: Node = root
    while isinstance(node, Internal):
        ci = len(node.keys)
        for i, k in enumerate(node.keys):
            if key < k:
                ci = i
                break
        node = node.children[ci]
    return node


class BTree:
    def __init__(self) -> None:
        self.root: Node = Leaf()

    def search(self, key: int) -> int:
        leaf = _find_leaf(self.root, key)
        for i, k in enumerate(leaf.keys):
            if k == key:
                return leaf.vals[i]
        return -1

    def insert(self, key: int, val: int) -> None:
        if isinstance(self.root, Leaf):
            _leaf_insert(self.root, key, val)
            if len(self.root.keys) > MAX:
                self._split_root_leaf()
            return

        # Internal root — descend to the right leaf and insert.
        nk = len(self.root.keys)
        ci = nk
        for i, k in enumerate(self.root.keys):
            if key < k:
                ci = i
                break
        leaf = self.root.children[ci]
        if not isinstance(leaf, Leaf):
            raise RuntimeError("multi-level split not implemented for this reference")
        _leaf_insert(leaf, key, val)
        if len(leaf.keys) > MAX:
            raise RuntimeError("multi-level split not implemented for this reference")

    def _split_root_leaf(self) -> None:
        assert isinstance(self.root, Leaf)
        old = self.root
        nk = len(old.keys)
        mid = nk // 2
        median = old.keys[mid]

        left = Leaf()
        left.keys = old.keys[:mid]
        left.vals = old.vals[:mid]

        right = Leaf()
        right.keys = old.keys[mid:]
        right.vals = old.vals[mid:]

        new_root = Internal()
        new_root.keys = [median]
        new_root.children = [left, right]
        self.root = new_root


# ── Tests ─────────────────────────────────────────────────────────────────


def test_basic_insert_and_search() -> None:
    t = BTree()
    for k, v in ((10, 100), (5, 50), (20, 200), (15, 150), (3, 30)):
        t.insert(k, v)
    assert t.search(10) == 100
    assert t.search(5) == 50
    assert t.search(3) == 30
    assert t.search(99) == -1


def test_keys_sorted_in_leaf() -> None:
    t = BTree()
    for k, v in ((10, 100), (5, 50), (20, 200), (15, 150), (3, 30)):
        t.insert(k, v)
    leaf = _find_leaf(t.root, 0)
    assert leaf.keys == [3, 5, 10, 15, 20]
    assert leaf.vals == [30, 50, 100, 150, 200]


def test_split_on_overflow() -> None:
    t = BTree()
    for i in range(MAX + 1):
        t.insert(i, i * 10)
    assert isinstance(t.root, Internal)
    for i in range(MAX + 1):
        assert t.search(i) == i * 10
    assert t.search(999) == -1


def test_descending_inserts_are_sorted() -> None:
    t = BTree()
    keys = [50, 40, 30, 20, 10]
    for k in keys:
        t.insert(k, k * 2)
    leaf = _find_leaf(t.root, 0)
    assert leaf.keys == [10, 20, 30, 40, 50]
    for k in keys:
        assert t.search(k) == k * 2


def main() -> None:
    test_basic_insert_and_search()
    test_keys_sorted_in_leaf()
    test_split_on_overflow()
    test_descending_inserts_are_sorted()
    print("All btree_indexing examples passed.")


if __name__ == "__main__":
    main()
