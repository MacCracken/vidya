// Vidya — Reproducible Builds — Rust port.
//
// A reproducible build is a pure function of its inputs: the same sources
// produce a byte-identical artifact, on any machine, at any time. Three
// classic sources of non-determinism, and their fixes:
//
//   1. Embedded wall-clock timestamps  → the build stamps
//      SOURCE_DATE_EPOCH (a fixed build time from the sources) instead of
//      "now", so the clock never reaches the output, fast or slow.
//      Clamping (min(t, SDE)) is for FILE mtimes: a fresh checkout's newer
//      mtimes are pinned down to SDE. Clamping the clock itself would still
//      leak any clock that runs behind SDE.
//   2. Filesystem iteration order      → readdir() order varies; SORT
//      filenames before processing so output ignores directory layout.
//   3. Non-deterministic artifact names → name artifacts by the HASH of
//      their content (content-addressing) so the build is idempotent.
//
// Verification: build twice and compare digests. A deterministic build
// stays identical across runs that differ in input order AND wall-clock
// time, while a naive build drifts.

const HB: i64 = 131;
const HM: i64 = 1000003;
const HSEED: i64 = 7;

fn fold(h: i64, v: i64) -> i64 {
    (h * HB + v) % HM
}

// --- 1. Deterministic timestamps: the mtime clamp (tar --clamp-mtime).
//     A file mtime newer than SOURCE_DATE_EPOCH is pinned down to it; an
//     older one is kept. The build time itself is SDE, not this. ---
fn normalize_ts(mtime: i64, sde: i64) -> i64 {
    if mtime > sde { sde } else { mtime }
}

// --- 3. Content-addressed artifact path: a pure function of content ---
fn cas_path(content: i64) -> i64 {
    (content * HB + 7) % HM
}

// --- File set: parallel arrays of (name sort-key, content signature) ---
struct FileSet {
    name: Vec<i64>,
    content: Vec<i64>,
}

impl FileSet {
    fn new(files: &[(i64, i64)]) -> Self {
        FileSet {
            name: files.iter().map(|&(n, _)| n).collect(),
            content: files.iter().map(|&(_, c)| c).collect(),
        }
    }

    // --- 2. Sorted iteration: insertion-sort by name key, ascending,
    //     reordering content alongside so the pairing is preserved. ---
    fn sort(&mut self) {
        for i in 1..self.name.len() {
            let kn = self.name[i];
            let kc = self.content[i];
            let mut j = i;
            while j > 0 && self.name[j - 1] > kn {
                self.name[j] = self.name[j - 1];
                self.content[j] = self.content[j - 1];
                j -= 1;
            }
            self.name[j] = kn;
            self.content[j] = kc;
        }
    }

    // --- The build: fold the (normalized) timestamp and every file's
    //     (name, content) into one artifact digest. Flags toggle the two
    //     determinism fixes so we can contrast a correct vs naive pipeline.
    fn build_digest(&mut self, do_sort: bool, do_norm: bool, now: i64, sde: i64) -> i64 {
        if do_sort {
            self.sort();
        }
        let ts = if do_norm { sde } else { now }; // build time comes from the sources
        let mut h = fold(HSEED, ts);
        for i in 0..self.name.len() {
            h = fold(h, self.name[i]);
            h = fold(h, self.content[i]);
        }
        h
    }
}

fn main() {
    // Same SET of three files, presented in two different input orders.
    let order_a: [(i64, i64); 3] = [(30, 111), (10, 222), (20, 333)];
    let order_b: [(i64, i64); 3] = [(20, 333), (30, 111), (10, 222)];

    // normalize_ts: clamp a newer mtime to SDE; keep an older one.
    assert_eq!(normalize_ts(9999, 5000), 5000);
    assert_eq!(normalize_ts(3000, 5000), 3000);

    // Sorted iteration: names ascending, content stays paired with its name.
    {
        let mut fs = FileSet::new(&order_a);
        fs.sort();
        assert_eq!(fs.name, vec![10, 20, 30]);
        assert_eq!(fs.content[0], 222); // content followed name 10
    }

    // Content-addressed paths: cas_path takes nothing but the content, so
    // same content → same path by construction (asserting
    // cas_path(x) == cas_path(x) could never fail); different → different.
    assert_ne!(cas_path(111), cas_path(222));

    // REPRODUCIBLE: sort + normalize make both input order and the wall
    // clock irrelevant — two builds differing in BOTH produce equal digests.
    {
        let d1 = FileSet::new(&order_a).build_digest(true, true, 9999, 5000);
        let d2 = FileSet::new(&order_b).build_digest(true, true, 8888, 5000);
        assert_eq!(d1, d2);
    }

    // NON-DETERMINISTIC: the naive build drifts with order + timestamp.
    {
        let d1 = FileSet::new(&order_a).build_digest(false, false, 9999, 5000);
        let d2 = FileSet::new(&order_b).build_digest(false, false, 8888, 5000);
        assert_ne!(d1, d2);
    }

    // Normalization alone kills clock drift: both stamp 5000 (sorting
    // off, same input order, so only the timestamp fix is in play).
    {
        let d1 = FileSet::new(&order_a).build_digest(false, true, 9999, 5000);
        let d2 = FileSet::new(&order_a).build_digest(false, true, 7777, 5000);
        assert_eq!(d1, d2);
        let d3 = FileSet::new(&order_a).build_digest(false, false, 7777, 5000);
        assert_ne!(d1, d3); // ...and without it the clock leaks in
        // ...including a clock that runs BEHIND the epoch: min(now, sde)
        // would stamp 3000 here and 5000 above, and the digests would differ.
        let slow = FileSet::new(&order_a).build_digest(false, true, 3000, 5000);
        assert_eq!(slow, d1);
    }

    println!("All reproducible_builds examples passed.");
}
