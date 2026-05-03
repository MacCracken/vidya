// Vidya — Neural Network Forward Pass — Rust port. Q15 fixed-point.

const SCALE: i32 = 15;
const ONE: i64 = 32768;
const N_IN: usize = 2;
const N_HIDDEN: usize = 3;
const N_OUT: usize = 2;

fn q_mul(a: i64, b: i64) -> i64 {
    let p = a * b;
    if p < 0 { -((-p) >> SCALE) } else { p >> SCALE }
}

const W_HIDDEN: [i64; 6] = [16384, -16384, -16384, 16384, 16384, 16384];
const B_HIDDEN: [i64; 3] = [0, 0, 0];
const W_OUTPUT: [i64; 6] = [16384, 0, 0, 0, 16384, 0];
const B_OUTPUT: [i64; 2] = [0, 0];

fn dense(w: &[i64], b: &[i64], x: &[i64], n_in: usize, n_out: usize) -> Vec<i64> {
    let mut out = vec![0i64; n_out];
    for j in 0..n_out {
        let mut acc = b[j];
        for i in 0..n_in {
            acc += q_mul(w[j * n_in + i], x[i]);
        }
        out[j] = acc;
    }
    out
}

fn relu(x: &[i64]) -> Vec<i64> {
    x.iter().map(|&v| if v > 0 { v } else { 0 }).collect()
}

fn argmax(x: &[i64]) -> usize {
    let mut best_idx = 0;
    let mut best_val = x[0];
    for i in 1..x.len() {
        if x[i] > best_val {
            best_val = x[i];
            best_idx = i;
        }
    }
    best_idx
}

fn forward(input: &[i64]) -> (usize, Vec<i64>, Vec<i64>) {
    let hidden = relu(&dense(&W_HIDDEN, &B_HIDDEN, input, N_IN, N_HIDDEN));
    let output = dense(&W_OUTPUT, &B_OUTPUT, &hidden, N_HIDDEN, N_OUT);
    (argmax(&output), hidden, output)
}

fn main() {
    assert_eq!(q_mul(ONE, 100), 100);
    assert_eq!(q_mul(16384, 16384), 8192);
    assert_eq!(q_mul(-16384, 16384), -8192);

    {
        let w = [16384i64, 16384, 8192, 24576];
        let b = [0i64, 0];
        let x = [32767i64, 32767];
        let y = dense(&w, &b, &x, 2, 2);
        assert!(y[0] >= 32765 && y[0] <= 32769, "y[0]={}", y[0]);
        assert!(y[1] >= 32765 && y[1] <= 32769, "y[1]={}", y[1]);
    }
    {
        let w = [0i64, 0];
        let b = [12345i64];
        let x = [32767i64, 32767];
        let y = dense(&w, &b, &x, 2, 1);
        assert_eq!(y[0], 12345);
    }
    assert_eq!(relu(&[-100, 200, -300, 400]), vec![0, 200, 0, 400]);
    assert_eq!(relu(&[0]), vec![0]);
    assert_eq!(argmax(&[100, 500, 200, 300]), 1);
    assert_eq!(argmax(&[100, 500, 500]), 1);

    assert_eq!(forward(&[26214, 6553]).0, 0);
    assert_eq!(forward(&[6553, 26214]).0, 1);
    assert_eq!(forward(&[32767, 0]).0, 0);
    assert_eq!(forward(&[0, 32767]).0, 1);
    {
        let (_, hidden, _) = forward(&[32767, 0]);
        assert_eq!(hidden[1], 0);
        assert!(hidden[0] > 0);
    }

    println!("neural_networks: 12 tests, 16 assertions ok");
}
