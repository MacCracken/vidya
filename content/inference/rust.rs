// Vidya — LLM Inference (Decoding) — Rust port.

const VOCAB_SIZE: usize = 8;
const TOK_EOS: usize = 1;

fn init_bigram() -> [[i64; VOCAB_SIZE]; VOCAB_SIZE] {
    let mut b = [[0i64; VOCAB_SIZE]; VOCAB_SIZE];
    b[2][3] = 1000;
    b[2][4] = 100;
    b[3][6] = 800;
    b[3][5] = 200;
    b[4][5] = 700;
    b[5][1] = 600;
    b[6][7] = 900;
    b[6][3] = 100;
    b[7][1] = 950;
    b
}

fn argmax_logits(logits: &[i64]) -> usize {
    let mut best_idx = 0;
    let mut best_val = logits[0];
    for i in 1..logits.len() {
        if logits[i] > best_val {
            best_val = logits[i];
            best_idx = i;
        }
    }
    best_idx
}

fn topk_filter(logits: &mut [i64], k: usize) -> usize {
    let mut marks = vec![false; logits.len()];
    let mut picked = 0;
    while picked < k {
        let mut best_idx: i32 = -1;
        let mut best_val: i64 = 0;
        let mut first = true;
        for j in 0..logits.len() {
            if !marks[j] {
                if first {
                    best_idx = j as i32;
                    best_val = logits[j];
                    first = false;
                } else if logits[j] > best_val {
                    best_idx = j as i32;
                    best_val = logits[j];
                }
            }
        }
        if best_idx < 0 {
            return picked;
        }
        marks[best_idx as usize] = true;
        picked += 1;
    }
    // Mask with the integer stand-in for -inf, not 0: logits can be negative,
    // so a 0 would rank a filtered token ABOVE the survivors (and softmax
    // would still give it weight e^0 = 1).
    for m in 0..logits.len() {
        if !marks[m] {
            logits[m] = i64::MIN;
        }
    }
    picked
}

fn bigram_logits(bigram: &[[i64; VOCAB_SIZE]; VOCAB_SIZE], prev: usize) -> [i64; VOCAB_SIZE] {
    bigram[prev]
}

fn decode_sequence(
    bigram: &[[i64; VOCAB_SIZE]; VOCAB_SIZE],
    start: usize,
    max_len: usize,
) -> Vec<usize> {
    let mut output = Vec::new();
    let mut current = start;
    while output.len() < max_len {
        let next = argmax_logits(&bigram_logits(bigram, current));
        output.push(next);
        if next == TOK_EOS {
            return output;
        }
        current = next;
    }
    output
}

fn main() {
    let bigram = init_bigram();

    assert_eq!(argmax_logits(&[100, 500, 200, 300]), 1);
    assert_eq!(argmax_logits(&[100, 500, 500]), 1);
    assert_eq!(argmax_logits(&[-100, -50, -200]), 1);

    {
        let mut l: Vec<i64> = vec![10, 50, 30, 20, 40, 5, 60, 25];
        assert_eq!(topk_filter(&mut l, 3), 3);
        assert_eq!(l[6], 60);
        assert_eq!(l[1], 50);
        assert_eq!(l[4], 40);
        for &i in &[0, 2, 3, 5, 7] {
            assert_eq!(l[i], i64::MIN, "idx {} masked", i);
        }
    }
    {
        // Negative logits: the survivor must still win after filtering.
        let mut l: Vec<i64> = vec![-5, -1, -3];
        topk_filter(&mut l, 1);
        assert_eq!(argmax_logits(&l), 1);
    }
    {
        let mut l: Vec<i64> = vec![1, 2, 3];
        assert_eq!(topk_filter(&mut l, 3), 3);
        assert_eq!(l, vec![1, 2, 3]);
    }

    assert_eq!(argmax_logits(&bigram_logits(&bigram, 2)), 3);

    assert_eq!(decode_sequence(&bigram, 2, 10), vec![3, 6, 7, 1]);
    assert_eq!(decode_sequence(&bigram, 5, 10), vec![1]);
    assert_eq!(decode_sequence(&bigram, 2, 2), vec![3, 6]);
    // Greedy decoding is deterministic because argmax has a fixed tie-break
    // (first index wins), not because two calls of a pure function agree.
    // Token 0's row is all zeros, so every step ties and picks 0 again:
    // greedy decoding stuck repeating until the length cap.
    assert_eq!(decode_sequence(&bigram, 0, 3), vec![0, 0, 0]);

    println!("inference: 10 tests, 17 assertions ok");
}
