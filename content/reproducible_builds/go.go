// Vidya — Reproducible Builds — Go port.
//
// A reproducible build is a pure function of its inputs: the same sources
// produce a byte-identical artifact, on any machine, at any time. Three
// classic sources of non-determinism, and their fixes:
//
//  1. Embedded wall-clock timestamps  → clamp every timestamp to
//     SOURCE_DATE_EPOCH so "now" never leaks in.
//  2. Filesystem iteration order      → sort filenames before processing,
//     so output doesn't depend on directory layout.
//  3. Non-deterministic artifact names → name artifacts by the HASH of
//     their content (content-addressing), so identical inputs map to
//     identical paths and the build becomes idempotent.
//
// Verification is simple: build twice and compare digests.

package main

import (
	"fmt"
	"os"
)

const (
	HB    int64 = 131
	HM    int64 = 1000003
	HSEED int64 = 7
)

func fold(h, v int64) int64 { return (h*HB + v) % HM }

// 1. Deterministic timestamps: clamp "now" to SOURCE_DATE_EPOCH.
func normalizeTS(now, sde int64) int64 {
	if now > sde {
		return sde
	}
	return now
}

// 3. Content-addressed artifact path: a pure function of content.
func casPath(content int64) int64 { return (content*HB + 7) % HM }

// File set: parallel slices (name sort-key, content signature).
type Files struct {
	name    []int64
	content []int64
}

// 2. Sorted iteration: insertion-sort files by name key, ascending,
// reordering content alongside so the pairing is preserved.
func (f *Files) sort() {
	for i := 1; i < len(f.name); i++ {
		kn := f.name[i]
		kc := f.content[i]
		j := i - 1
		for j >= 0 && f.name[j] > kn {
			f.name[j+1] = f.name[j]
			f.content[j+1] = f.content[j]
			j--
		}
		f.name[j+1] = kn
		f.content[j+1] = kc
	}
}

// The build: fold the (normalized) timestamp and every file's
// (name, content) into one artifact digest. Flags toggle the two
// determinism fixes so we can contrast a correct vs naive pipeline.
func (f *Files) buildDigest(doSort, doNorm bool, now, sde int64) int64 {
	if doSort {
		f.sort()
	}
	ts := now
	if doNorm {
		ts = normalizeTS(now, sde)
	}
	h := fold(HSEED, ts)
	for i := range f.name {
		h = fold(h, f.name[i])
		h = fold(h, f.content[i])
	}
	return h
}

// Same SET of three files, presented in two different input orders.
func orderA() *Files {
	return &Files{name: []int64{30, 10, 20}, content: []int64{111, 222, 333}}
}
func orderB() *Files {
	return &Files{name: []int64{20, 30, 10}, content: []int64{333, 111, 222}}
}

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func main() {
	// 1. Deterministic timestamps.
	check(normalizeTS(9999, 5000) == 5000, "clamp future now to SOURCE_DATE_EPOCH")
	check(normalizeTS(3000, 5000) == 3000, "keep timestamp already <= SDE")

	// 2. Sorted iteration keeps content paired with its name.
	{
		f := orderA()
		f.sort()
		check(f.name[0] == 10, "sorted name[0] = 10")
		check(f.name[1] == 20, "sorted name[1] = 20")
		check(f.name[2] == 30, "sorted name[2] = 30")
		check(f.content[0] == 222, "content followed name 10")
	}

	// 3. Content-addressed paths.
	check(casPath(111) == casPath(111), "same content → same path")
	check(casPath(111) != casPath(222), "different content → different path")

	// Deterministic pipeline: two builds differing in BOTH input order and
	// wall-clock "now" must produce equal digests.
	{
		d1 := orderA().buildDigest(true, true, 9999, 5000)
		d2 := orderB().buildDigest(true, true, 8888, 5000)
		check(d1 == d2, "deterministic build is byte-identical across runs")
	}

	// Naive pipeline (no sort, raw now): drifts with order + timestamp.
	{
		d1 := orderA().buildDigest(false, false, 9999, 5000)
		d2 := orderB().buildDigest(false, false, 8888, 5000)
		check(d1 != d2, "naive build drifts with order + timestamp")
	}

	// Normalization alone kills clock drift (sort on, only clock differs).
	{
		n1 := orderA().buildDigest(true, true, 9999, 5000) // clamps 9999 → 5000
		n2 := orderA().buildDigest(true, true, 7777, 5000) // clamps 7777 → 5000
		check(n1 == n2, "normalized timestamp removes clock dependence")
	}

	fmt.Println("=== reproducible_builds ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
	fmt.Println("All reproducible_builds examples passed.")
}
