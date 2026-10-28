#!/usr/bin/env python3
"""Vidya — Reproducible Builds — Python port.

A reproducible build is a pure function of its inputs: the same sources
produce a byte-identical artifact, on any machine, at any time. Three
classic sources of non-determinism, and their fixes:

  1. Embedded wall-clock timestamps  -> the build stamps
     SOURCE_DATE_EPOCH (a fixed build time taken from the sources, e.g.
     the last commit date) instead of "now", so the clock never reaches
     the output, fast or slow. Clamping (min(t, SDE)) is for FILE mtimes:
     a fresh checkout's newer mtimes are pinned down to SDE. Clamping the
     clock itself would still leak any clock that runs behind SDE.
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


# --- 1. Deterministic timestamps: the mtime clamp (tar --clamp-mtime).
#     A file mtime newer than SOURCE_DATE_EPOCH is pinned down to it; an
#     older one is kept. The build time itself is SDE, not this. ---
def normalize_ts(mtime, sde):
    return sde if mtime > sde else mtime


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
    ts = sde if do_norm else now  # build time comes from the sources
    h = fold(HSEED, ts)
    for name, content in files:
        h = fold(h, name)
        h = fold(h, content)
    return h


# Same SET of three files, presented in two different input orders.
order_a = [(30, 111), (10, 222), (20, 333)]
order_b = [(20, 333), (30, 111), (10, 222)]


if __name__ == "__main__":
    # 1. The mtime clamp.
    assert normalize_ts(9999, 5000) == 5000, "newer mtime clamped to SOURCE_DATE_EPOCH"
    assert normalize_ts(3000, 5000) == 3000, "older mtime kept"

    # 2. Sorted iteration keeps content paired with its name.
    s = files_sort(order_a)
    assert [nc[0] for nc in s] == [10, 20, 30], "names sorted ascending"
    assert s[0][1] == 222, "content followed name 10"

    # 3. Content addressing is a pure function of content, so equal content
    #    maps to an equal path by construction (asserting
    #    cas_path(x) == cas_path(x) could never fail). What can fail is
    #    distinct content colliding on one path:
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
    # both stamped with SDE -> identical digest.
    assert build_digest(True, True, order_a, 9999, 5000) == \
        build_digest(True, True, order_a, 7777, 5000), \
        "normalized timestamp removes clock dependence"
    # ...including a clock that runs BEHIND the epoch: min(now, sde) would
    # stamp 3000 here and 5000 above, and the digests would differ.
    assert build_digest(True, True, order_a, 3000, 5000) == \
        build_digest(True, True, order_a, 9999, 5000), \
        "a slow clock does not leak into the build either"

    print("All reproducible_builds examples passed.")
    raise SystemExit(0)
