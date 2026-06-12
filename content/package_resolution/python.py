#!/usr/bin/env python3
"""Vidya — Package Resolution — Python port.

Dependency-resolver core: semantic versioning, caret constraint
matching, range intersection for diamond dependencies, highest-version
selection, bounded backtracking, and dependency-cycle detection — the
heart of an npm/cargo/cyrius.cyml resolver.

A semver major.minor.patch is encoded as one integer
    enc = major*1_000_000 + minor*1_000 + patch
so version comparison IS integer comparison. A constraint is a
half-open range [lo, hi). A caret ^X.Y.Z allows everything from X.Y.Z
up to (but not including) the next major: [X.Y.Z, (X+1).0.0).
"""

VMAJ = 1_000_000
VMIN = 1_000


# --- Semver encode / inspect ---
def sv(maj, mnr, pat):
    return maj * VMAJ + mnr * VMIN + pat


def sv_major(v):
    return v // VMAJ


# --- Caret range [lo, hi): ^X.Y.Z = [X.Y.Z, (X+1).0.0) ---
def caret_lo(v):
    return v


def caret_hi(v):
    return (sv_major(v) + 1) * VMAJ


# --- Constraint satisfaction over a half-open range ---
def satisfies(v, lo, hi):
    return lo <= v < hi


# --- Range intersection: [max(lo), min(hi)); empty iff lo >= hi ---
def range_lo_max(a, b):
    return max(a, b)


def range_hi_min(a, b):
    return min(a, b)


def range_empty(lo, hi):
    return lo >= hi


# --- Highest version in `vers` that lies in [lo, hi); -1 if none ---
def best_match(vers, lo, hi):
    best = -1
    for v in vers:
        if satisfies(v, lo, hi) and v > best:
            best = v
    return best


# --- Available versions of the shared dependency C ---
C_VERS = [sv(1, 0, 0), sv(1, 5, 0), sv(2, 0, 0)]


# --- Diamond resolution: A requires C ^a_base, B requires C ^b_base.
#     Intersect the two carets and pick the highest C that fits.
#     Returns chosen C version, or -1 if the constraints conflict. ---
def resolve_shared(a_base, b_base):
    lo = range_lo_max(caret_lo(a_base), caret_lo(b_base))
    hi = range_hi_min(caret_hi(a_base), caret_hi(b_base))
    if range_empty(lo, hi):
        return -1
    return best_match(C_VERS, lo, hi)


# --- Bounded backtracking: A has candidate versions (a_vers), each of
#     which requires a different caret on C (a_creq). B requires C
#     ^b_base. The absolute-highest A may force a C constraint that
#     conflicts with B; choose the HIGHEST A for which some C still
#     satisfies both. Returns (chosen_A, chosen_C); (-1, -1) if none. ---
def resolve_backtrack(a_vers, a_creq, b_base):
    best_a, best_c = -1, -1
    for aver, creq in zip(a_vers, a_creq):
        lo = range_lo_max(caret_lo(creq), caret_lo(b_base))
        hi = range_hi_min(caret_hi(creq), caret_hi(b_base))
        if not range_empty(lo, hi):
            c = best_match(C_VERS, lo, hi)
            if c != -1 and aver > best_a:
                best_a, best_c = aver, c
    return best_a, best_c


# --- Dependency-graph cycle detection (Kahn ready-scan; a cycle leaves
#     some package permanently unplaceable). ---
def has_cycle(n, deps):
    placed = [False] * n
    count = 0
    while count < n:
        progress = False
        for p in range(n):
            if placed[p]:
                continue
            if all(placed[d] for d in deps[p]):
                placed[p] = True
                count += 1
                progress = True
        if not progress:
            return True  # stuck => cycle
    return False


# === Tests ===

def test_semver():
    assert sv(1, 2, 3) > sv(1, 2, 0), "patch ordering"
    assert sv(2, 0, 0) > sv(1, 9, 9), "major dominates minor/patch"
    assert sv_major(sv(1, 5, 2)) == 1, "extract major"


def test_caret():
    assert caret_lo(sv(1, 2, 0)) == sv(1, 2, 0), "caret lower = base"
    assert caret_hi(sv(1, 2, 0)) == sv(2, 0, 0), "caret upper = next major"
    lo, hi = caret_lo(sv(1, 2, 0)), caret_hi(sv(1, 2, 0))
    assert satisfies(sv(1, 4, 0), lo, hi), "1.4.0 in ^1.2.0"
    assert not satisfies(sv(2, 0, 0), lo, hi), "2.0.0 not in ^1.2.0"
    assert not satisfies(sv(1, 1, 0), lo, hi), "1.1.0 below ^1.2.0"


def test_intersect():
    assert range_lo_max(sv(1, 0, 0), sv(1, 3, 0)) == sv(1, 3, 0), "intersect lo = max"
    assert range_hi_min(sv(2, 0, 0), sv(3, 0, 0)) == sv(2, 0, 0), "intersect hi = min"
    lo = range_lo_max(caret_lo(sv(1, 0, 0)), caret_lo(sv(2, 0, 0)))
    hi = range_hi_min(caret_hi(sv(1, 0, 0)), caret_hi(sv(2, 0, 0)))
    assert range_empty(lo, hi), "^1.0.0 and ^2.0.0 are disjoint"


def test_best_match():
    assert best_match(C_VERS, caret_lo(sv(1, 0, 0)), caret_hi(sv(1, 0, 0))) == sv(1, 5, 0), \
        "highest C in ^1.0.0 = 1.5.0"
    assert best_match(C_VERS, caret_lo(sv(3, 0, 0)), caret_hi(sv(3, 0, 0))) == -1, \
        "no C in ^3.0.0"


def test_resolve_diamond_ok():
    assert resolve_shared(sv(1, 0, 0), sv(1, 0, 0)) == sv(1, 5, 0), \
        "A^1 ∩ B^1 picks C 1.5.0"


def test_resolve_conflict():
    assert resolve_shared(sv(1, 0, 0), sv(2, 0, 0)) == -1, \
        "A^1 vs B^2 is unresolvable"


def test_resolve_backtrack():
    # A 1.1.0 requires C ^2.0.0; A 1.0.0 requires C ^1.0.0; B requires C ^1.0.0.
    # The highest A (1.1.0) forces C ^2 which conflicts with B^1 — backtrack.
    a_vers = [sv(1, 1, 0), sv(1, 0, 0)]
    a_creq = [sv(2, 0, 0), sv(1, 0, 0)]
    chosen_a, chosen_c = resolve_backtrack(a_vers, a_creq, sv(1, 0, 0))
    assert chosen_a == sv(1, 0, 0), "backtrack picks A 1.0.0, not 1.1.0"
    assert chosen_c == sv(1, 5, 0), "and resolves C to 1.5.0"


def test_cycle():
    # A <-> B (mutual dependency) is a cycle.
    assert has_cycle(2, [[1], [0]]), "A↔B is a dependency cycle"
    # app -> A, B (diamond) is acyclic.
    assert not has_cycle(3, [[], [], [0, 1]]), "diamond graph is acyclic"


if __name__ == "__main__":
    test_semver()
    test_caret()
    test_intersect()
    test_best_match()
    test_resolve_diamond_ok()
    test_resolve_conflict()
    test_resolve_backtrack()
    test_cycle()
    print("All package_resolution examples passed.")
    raise SystemExit(0)
