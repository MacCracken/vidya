#!/usr/bin/env python3
"""Vidya — Build Systems — Python port.

A minimal build-system core: a DAG of targets, topological build order,
content-signature dirty-tracking, and ninja-style incremental rebuild
(only dirty targets run), plus cycle detection. Mirrors the Cyrius
reference: same data model, same algorithms, same tests.

No real files or compilers: each target carries a source "content
signature" (an integer). A target's INPUT signature mixes its own source
with the OUTPUT signatures of its dependencies; if that differs from the
signature it was last built against, the target is dirty and rebuilds.
Editing a source changes its signature, which transitively re-dirties
everything downstream — exactly how mtime/hash-based tools (make, ninja,
bazel) decide what to redo.
"""

HB = 131        # signature polynomial base
HM = 1000003    # signature modulus (prime; keeps values < 2^53)


class BuildSystem:
    def __init__(self, n):
        # Parallel lists over n targets.
        self.src = [0] * n          # source content signature
        self.deps = [[] for _ in range(n)]  # dependency lists
        self.built = [-1] * n       # signature last built against (-1 = never)
        self.out = [0] * n          # current output signature
        self.order = []             # topological order (target ids)

    @property
    def n(self):
        return len(self.src)

    def set_src(self, t, sig):
        self.src[t] = sig

    def add_dep(self, t, d):
        self.deps[t].append(d)

    def topo(self):
        """Kahn-style ready-scan. Places any target whose deps are all
        placed; a full pass that places nothing (with targets left) is a
        cycle. Returns how many were ordered (< n ⇒ cycle)."""
        placed = [False] * self.n
        self.order = []
        while len(self.order) < self.n:
            progress = False
            for t in range(self.n):
                if placed[t]:
                    continue
                if all(placed[d] for d in self.deps[t]):
                    self.order.append(t)
                    placed[t] = True
                    progress = True
            if not progress:
                return len(self.order)  # stuck ⇒ cycle
        return len(self.order)

    def sig(self, t):
        """Input signature: mix this target's source with deps' outputs."""
        s = self.src[t] % HM
        for d in self.deps[t]:
            s = (s * HB + self.out[d]) % HM
        return s

    def build(self):
        """Walk topo order, rebuild only dirty targets. Output is
        content-addressed (out == input signature), so a target whose
        inputs are unchanged keeps its output and its dependents stay
        clean. Returns the number of targets rebuilt."""
        self.topo()
        rebuilt = 0
        for t in self.order:
            s = self.sig(t)
            if s != self.built[t]:
                self.out[t] = s     # produce output
                self.built[t] = s   # remember what we built
                rebuilt += 1
        return rebuilt

    def order_pos(self, target):
        return self.order.index(target) if target in self.order else -1


# Classic C build graph:  app(2) <- util.o(0), main.o(1)
def build_graph():
    bs = BuildSystem(3)
    bs.set_src(0, 1001)  # util.c
    bs.set_src(1, 2002)  # main.c
    bs.set_src(2, 3003)  # link recipe
    bs.add_dep(2, 0)
    bs.add_dep(2, 1)
    return bs


def test_topo_order():
    bs = build_graph()
    assert bs.topo() == 3, "topo orders all 3 targets"
    assert bs.order_pos(2) > bs.order_pos(0), "app built after util.o"
    assert bs.order_pos(2) > bs.order_pos(1), "app built after main.o"


def test_cold_build_rebuilds_all():
    bs = build_graph()
    assert bs.build() == 3, "cold build rebuilds all 3"


def test_noop_build_rebuilds_none():
    bs = build_graph()
    bs.build()  # cold
    assert bs.build() == 0, "second build (no edits) rebuilds nothing"


def test_edit_leaf_rebuilds_transitively():
    bs = build_graph()
    bs.build()  # cold: all up to date
    bs.set_src(1, 2999)  # edit main.c
    assert bs.build() == 2, "edit main.c rebuilds main.o + app"


def test_edit_other_leaf_skips_sibling():
    bs = build_graph()
    bs.build()
    main_built = bs.built[1]
    bs.set_src(0, 1999)  # edit util.c
    assert bs.build() == 2, "edit util.c rebuilds util.o + app"
    assert bs.built[1] == main_built, "main.o left untouched"


def test_cycle_detected():
    bs = BuildSystem(2)
    bs.add_dep(0, 1)
    bs.add_dep(1, 0)  # 0 <-> 1 cycle
    assert bs.topo() < 2, "cycle leaves targets unordered"


if __name__ == "__main__":
    test_topo_order()
    test_cold_build_rebuilds_all()
    test_noop_build_rebuilds_none()
    test_edit_leaf_rebuilds_transitively()
    test_edit_other_leaf_skips_sibling()
    test_cycle_detected()
    print("All build_systems examples passed.")
    raise SystemExit(0)
