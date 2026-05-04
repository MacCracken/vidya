#!/usr/bin/env python3
"""Vidya — Embeddings and Vector Search — Python port. Q15 fixed-point.

Cosine similarity (= dot product on pre-normalized vectors) +
brute-force nearest-neighbour + top-k. Small fixed corpus.
"""

SCALE = 15
ONE = 32768
DIM = 4
N_CORPUS = 4


def q_mul(a, b):
    p = a * b
    return -((-p) >> SCALE) if p < 0 else (p >> SCALE)


# Pre-normalized 4-D unit vectors.
CORPUS = [
    [32767, 0, 0, 0],            # v0: x-axis
    [0, 32767, 0, 0],            # v1: y-axis
    [16384, 16384, 16384, 16384],# v2: diagonal (sum-of-squares = 4*0.25 = 1.0)
    [-32767, 0, 0, 0],           # v3: -x-axis (opposite of v0)
]


def dot(a, b):
    acc = 0
    for i in range(len(a)):
        acc += q_mul(a[i], b[i])
    return acc


def corpus_sim(query, idx):
    return dot(query, CORPUS[idx])


def nearest(query):
    best_idx = 0
    best_sim = corpus_sim(query, 0)
    for i in range(1, N_CORPUS):
        sim = corpus_sim(query, i)
        if sim > best_sim:
            best_sim = sim
            best_idx = i
    return best_idx


def top_k_neighbors(query, k):
    marks = [False] * N_CORPUS
    out = []
    while len(out) < k:
        best_idx = -1
        best_sim = 0
        first = True
        for j in range(N_CORPUS):
            if not marks[j]:
                sim = corpus_sim(query, j)
                if first:
                    best_idx, best_sim, first = j, sim, False
                elif sim > best_sim:
                    best_idx, best_sim = j, sim
        if best_idx < 0:
            return out
        marks[best_idx] = True
        out.append(best_idx)
    return out


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_self_similarity_is_one():
    for i in range(N_CORPUS):
        s = corpus_sim(CORPUS[i], i)
        check(s >= 32760, f"v{i} self-sim ≈ ONE (got {s})")


def test_orthogonal_is_zero():
    check(corpus_sim(CORPUS[0], 1) == 0, "v0·v1 = 0")


def test_opposite_is_negative_one():
    s = corpus_sim(CORPUS[0], 3)
    check(-ONE <= s <= -32760, f"v0·v3 ≈ -ONE (got {s})")


def test_diagonal_self_sim():
    check(corpus_sim(CORPUS[2], 2) == ONE, "v2 self-sim = ONE")


def test_diagonal_with_axis():
    s = corpus_sim(CORPUS[0], 2)
    check(16380 <= s <= 16384, f"v0·v2 ≈ 0.5 (got {s})")


def test_dot_symmetric():
    check(dot(CORPUS[0], CORPUS[2]) == dot(CORPUS[2], CORPUS[0]), "dot symmetric")


def test_nearest_axis_query():
    check(nearest([29490, 0, 0, 0]) == 0, "near-x → v0")


def test_nearest_y_axis_query():
    check(nearest([0, 32767, 0, 0]) == 1, "y-axis → v1")


def test_nearest_diagonal_query():
    check(nearest([16384, 16384, 16384, 16384]) == 2, "diagonal → v2")


def test_nearest_picks_opposite_for_negative():
    check(nearest([-29490, 0, 0, 0]) == 3, "negative-x → v3")


def test_top_k_axis_query():
    out = top_k_neighbors([32767, 0, 0, 0], 3)
    check(out == [0, 2, 1], f"top-3 ranked v0,v2,v1 (got {out})")


def test_top_k_returns_all_when_k_exceeds_corpus():
    out = top_k_neighbors([32767, 0, 0, 0], 10)
    check(len(out) == 4, f"top_k caps at corpus size (got len {len(out)})")


def test_nearest_deterministic():
    q = [29490, 0, 0, 0]
    check(nearest(q) == nearest(q), "deterministic")


if __name__ == "__main__":
    test_self_similarity_is_one()
    test_orthogonal_is_zero()
    test_opposite_is_negative_one()
    test_diagonal_self_sim()
    test_diagonal_with_axis()
    test_dot_symmetric()
    test_nearest_axis_query()
    test_nearest_y_axis_query()
    test_nearest_diagonal_query()
    test_nearest_picks_opposite_for_negative()
    test_top_k_axis_query()
    test_top_k_returns_all_when_k_exceeds_corpus()
    test_nearest_deterministic()
    print("=== embeddings ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
