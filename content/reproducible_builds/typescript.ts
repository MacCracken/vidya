// Vidya — Reproducible Builds — TypeScript port.
//
// A reproducible build is a pure function of its inputs: the same
// sources produce a byte-identical artifact, on any machine, at any
// time. Three classic sources of non-determinism, and their fixes:
//
//   1. Embedded wall-clock timestamps  → clamp every timestamp to
//      SOURCE_DATE_EPOCH (a fixed build time taken from the sources,
//      e.g. the last commit date) so "now" never leaks in.
//   2. Filesystem iteration order      → readdir() returns entries in
//      inode/hash order, which varies; SORT filenames before processing
//      so the output doesn't depend on directory layout.
//   3. Non-deterministic artifact names → name artifacts by the HASH of
//      their content (content-addressing), so identical inputs map to
//      identical paths — the build becomes idempotent.
//
// Verification: build twice and compare digests. A deterministic
// pipeline stays identical across runs that differ in input order AND
// wall-clock time; a naive build drifts.

const HB = 131;
const HM = 1000003;
const HSEED = 7;

function fold(h: number, v: number): number {
    return (h * HB + v) % HM;
}

// --- 1. Deterministic timestamps: clamp "now" to SOURCE_DATE_EPOCH ---
function normalizeTs(now: number, sde: number): number {
    return now > sde ? sde : now;
}

// --- 3. Content-addressed artifact path: a pure function of content ---
function casPath(content: number): number {
    return (content * HB + 7) % HM;
}

interface FileSet { name: number[]; content: number[]; }

// --- 2. Sorted iteration: stable-sort files by name key, ascending,
//     reordering content alongside so the pairing is preserved. ---
function filesSort(fs: FileSet): void {
    const n = fs.name.length;
    for (let i = 1; i < n; i++) {
        const kn = fs.name[i];
        const kc = fs.content[i];
        let j = i - 1;
        while (j >= 0 && fs.name[j] > kn) {
            fs.name[j + 1] = fs.name[j];
            fs.content[j + 1] = fs.content[j];
            j--;
        }
        fs.name[j + 1] = kn;
        fs.content[j + 1] = kc;
    }
}

// --- The build: fold the (normalized) timestamp and every file's
//     (name, content) into one artifact digest. Flags toggle the two
//     determinism fixes so we can contrast a correct vs naive pipeline. ---
function buildDigest(doSort: boolean, doNorm: boolean, fs: FileSet, now: number, sde: number): number {
    if (doSort) filesSort(fs);
    const ts = doNorm ? normalizeTs(now, sde) : now;
    let h = fold(HSEED, ts);
    for (let i = 0; i < fs.name.length; i++) {
        h = fold(h, fs.name[i]);
        h = fold(h, fs.content[i]);
    }
    return h;
}

// Same SET of three files, presented in two different input orders.
function orderA(): FileSet {
    return { name: [30, 10, 20], content: [111, 222, 333] };
}
function orderB(): FileSet {
    return { name: [20, 30, 10], content: [333, 111, 222] };
}

function assert(cond: boolean, name: string): void {
    if (!cond) throw new Error("FAIL: " + name);
}

// --- 1. Deterministic timestamps ---
assert(normalizeTs(9999, 5000) === 5000, "clamp future now to SOURCE_DATE_EPOCH");
assert(normalizeTs(3000, 5000) === 3000, "keep timestamp already <= SDE");

// --- 2. Sorted iteration: content stays paired with its name ---
{
    const fs = orderA();
    filesSort(fs);
    assert(fs.name[0] === 10 && fs.name[1] === 20 && fs.name[2] === 30, "sorted names ascending");
    assert(fs.content[0] === 222, "content followed name 10");
}

// --- 3. Content-addressed paths ---
assert(casPath(111) === casPath(111), "same content → same path");
assert(casPath(111) !== casPath(222), "different content → different path");

// --- Deterministic build: differs in input order AND clock, equal digest ---
assert(
    buildDigest(true, true, orderA(), 9999, 5000) === buildDigest(true, true, orderB(), 8888, 5000),
    "deterministic build is byte-identical across runs",
);

// --- Naive build drifts with order + timestamp ---
assert(
    buildDigest(false, false, orderA(), 9999, 5000) !== buildDigest(false, false, orderB(), 8888, 5000),
    "naive build drifts with order + timestamp",
);

// --- Normalization alone kills clock drift ---
assert(
    buildDigest(true, true, orderA(), 9999, 5000) === buildDigest(true, true, orderA(), 7777, 5000),
    "normalized timestamp removes clock dependence",
);

console.log("All reproducible_builds examples passed.");
process.exit(0);
