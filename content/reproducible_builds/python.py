#!/usr/bin/env python3
"""Vidya — Reproducible Builds — Python port.

A reproducible build is a pure function of its inputs: the same sources
produce a byte-identical artifact, on any machine, at any time. Three
classic sources of non-determinism, and their fixes:

  1. Embedded wall-clock timestamps  -> clamp every timestamp to
     SOURCE_DATE_EPOCH (a fixed build time taken from the sources, e.g.
     the last commit date) so "now" never leaks in.
  2. Filesystem iteration order      -> readdir() returns entries in
     inode/hash order, which varies; SORT filenames before processing
     so the output doesn't depend on directory layout.
  3. Non-deterministic artifact names -> name artifacts by the HASH of
     their content (content-addressing), so identical inputs map to
     identical paths -- the build becomes idempotent.

The verification is simple: build twice and compare digests. This models
that pipeline over an in-memory set of files (name key + content
signature) and shows a deterministic build staying identical across runs
that differ in input order AND wall-clock time, while a naive build drifts.

Mirrors the Cyrius reference: same constants, same functions, same tests.
"""

HB = 131
HM = 1000003
HSEED = 7


def fold(h, v):
    return (h * HB + v) % HM


# --- 1. Deterministic timestamps: clamp "now" to SOURCE_DATE_EPOCH ---
def normalize_ts(now, sde):
    return sde if now > sde else now


# --- 3. Content-addressed artifact path: a pure function of content ---
def cas_path(content):
    return (content * HB + 7) % HM


# --- 2. Sorted iteration: stable sort files by name key ascending,
#     keeping content paired with its name. ---
def files_sort(files):
    # Python's sort is stable; sorting by name preserves the pairing.
    return sorted(files, key=lambda nc: nc[0])


# --- The build: fold the (normalized) timestamp and every file's
#     (name, content) into one artifact digest. Flags toggle the two
#     determinism fixes so we can contrast a correct vs naive pipeline. ---
def build_digest(do_sort, do_norm, files, now, sde):
    if do_sort:
        files = files_sort(files)
    ts = normalize_ts(now, sde) if do_norm else now
    h = fold(HSEED, ts)
    for name, content in files:
        h = fold(h, name)
        h = fold(h, content)
    return h


# Same SET of three files, presented in two different input orders.
order_a = [(30, 111), (10, 222), (20, 333)]
order_b = [(20, 333), (30, 111), (10, 222)]


if __name__ == "__main__":
    # 1. Timestamp clamping.
    assert normalize_ts(9999, 5000) == 5000, "clamp future now to SOURCE_DATE_EPOCH"
    assert normalize_ts(3000, 5000) == 3000, "keep timestamp already <= SDE"

    # 2. Sorted iteration keeps content paired with its name.
    s = files_sort(order_a)
    assert [nc[0] for nc in s] == [10, 20, 30], "names sorted ascending"
    assert s[0][1] == 222, "content followed name 10"

    # 3. Content addressing is a pure function of content.
    assert cas_path(111) == cas_path(111), "same content -> same path"
    assert cas_path(111) != cas_path(222), "different content -> different path"

    # Deterministic pipeline (sort + normalize): two builds that differ in
    # BOTH input order and wall-clock "now" must produce equal digests.
    assert build_digest(True, True, order_a, 9999, 5000) == \
        build_digest(True, True, order_b, 8888, 5000), \
        "deterministic build is byte-identical across runs"

    # Naive pipeline (no sort, raw now): same source set drifts when order
    # or clock differ -- the bug reproducible builds eliminate.
    assert build_digest(False, False, order_a, 9999, 5000) != \
        build_digest(False, False, order_b, 8888, 5000), \
        "naive build drifts with order + timestamp"

    # Normalization alone kills clock drift: same order, differing clock,
    # both clamped to SDE -> identical digest.
    assert build_digest(True, True, order_a, 9999, 5000) == \
        build_digest(True, True, order_a, 7777, 5000), \
        "normalized timestamp removes clock dependence"

    print("All reproducible_builds examples passed.")
    raise SystemExit(0)
