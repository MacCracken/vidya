// Vidya — Embeddings and Vector Search — Rust port. Q15 fixed-point.

const SCALE: i32 = 15;
const ONE: i64 = 32768;
const DIM: usize = 4;
const N_CORPUS: usize = 4;

fn q_mul(a: i64, b: i64) -> i64 {
    let p = a * b;
    if p < 0 { -((-p) >> SCALE) } else { p >> SCALE }
}

const CORPUS: [[i64; DIM]; N_CORPUS] = [
    [32767, 0, 0, 0],
    [0, 32767, 0, 0],
    [16384, 16384, 16384, 16384],
    [-32767, 0, 0, 0],
];

fn dot(a: &[i64], b: &[i64]) -> i64 {
    let mut acc: i64 = 0;
    for i in 0..a.len() {
        acc += q_mul(a[i], b[i]);
    }
    acc
}

fn corpus_sim(query: &[i64], idx: usize) -> i64 {
    dot(query, &CORPUS[idx])
}

fn nearest(query: &[i64]) -> usize {
    let mut best_idx = 0;
    let mut best_sim = corpus_sim(query, 0);
    for i in 1..N_CORPUS {
        let s = corpus_sim(query, i);
        if s > best_sim {
            best_sim = s;
            best_idx = i;
        }
    }
    best_idx
}

fn top_k_neighbors(query: &[i64], k: usize) -> Vec<usize> {
    let mut marks = [false; N_CORPUS];
    let mut out = Vec::new();
    while out.len() < k {
        let mut best_idx: i32 = -1;
        let mut best_sim: i64 = 0;
        let mut first = true;
        for j in 0..N_CORPUS {
            if !marks[j] {
                let s = corpus_sim(query, j);
                if first {
                    best_idx = j as i32;
                    best_sim = s;
                    first = false;
                } else if s > best_sim {
                    best_idx = j as i32;
                    best_sim = s;
                }
            }
        }
        if best_idx < 0 {
            return out;
        }
        marks[best_idx as usize] = true;
        out.push(best_idx as usize);
    }
    out
}

fn main() {
    for i in 0..N_CORPUS {
        let s = corpus_sim(&CORPUS[i], i);
        assert!(s >= 32760, "v{} self-sim ≈ ONE (got {})", i, s);
    }

    assert_eq!(corpus_sim(&CORPUS[0], 1), 0);
    {
        let s = corpus_sim(&CORPUS[0], 3);
        assert!(s >= -ONE && s <= -32760, "v0·v3 ≈ -ONE (got {})", s);
    }
    assert_eq!(corpus_sim(&CORPUS[2], 2), ONE);
    {
        let s = corpus_sim(&CORPUS[0], 2);
        assert!(s >= 16380 && s <= 16384, "v0·v2 ≈ 0.5 (got {})", s);
    }
    assert_eq!(dot(&CORPUS[0], &CORPUS[2]), dot(&CORPUS[2], &CORPUS[0]));

    assert_eq!(nearest(&[29490, 0, 0, 0]), 0);
    assert_eq!(nearest(&[0, 32767, 0, 0]), 1);
    assert_eq!(nearest(&[16384, 16384, 16384, 16384]), 2);
    assert_eq!(nearest(&[-29490, 0, 0, 0]), 3);

    assert_eq!(top_k_neighbors(&[32767, 0, 0, 0], 3), vec![0, 2, 1]);
    assert_eq!(top_k_neighbors(&[32767, 0, 0, 0], 10).len(), 4);

    {
        let q: [i64; 4] = [29490, 0, 0, 0];
        assert_eq!(nearest(&q), nearest(&q));
    }

    println!("embeddings: 13 tests, 16 assertions ok");
}
