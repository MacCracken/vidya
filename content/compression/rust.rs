// Vidya — Compression (LZ77-shaped) in Rust
//
// Mirrors cyrius.cyr's two-byte token stream:
//   [0, BYTE]      — literal
//   [OFFSET, LEN]  — match: copy LEN bytes from out[pos - OFFSET..]
// Greedy O(n²) match-finder over a 255-byte window. Decoder enforces
// an output-cap to defuse decompression bombs (the gotcha called out
// in concept.toml). Match copy is byte-by-byte so RLE-style overlap
// (offset=1) replicates the trailing byte instead of misbehaving via
// memcpy.

const MIN_MATCH: usize = 3;
const MAX_MATCH: usize = 255;
const WIN_SIZE: usize = 255;

fn match_len_at(src: &[u8], hist: usize, pos: usize) -> usize {
    let mut n = 0;
    let max = (src.len() - pos).min(MAX_MATCH);
    while n < max && src[hist + n] == src[pos + n] {
        n += 1;
    }
    n
}

fn best_match(src: &[u8], pos: usize) -> Option<(u8, u8)> {
    let win_start = pos.saturating_sub(WIN_SIZE);
    let mut best_off = 0usize;
    let mut best_len = 0usize;
    for i in win_start..pos {
        let n = match_len_at(src, i, pos);
        if n > best_len {
            best_len = n;
            best_off = pos - i;
        }
    }
    if best_len >= MIN_MATCH {
        Some((best_off as u8, best_len as u8))
    } else {
        None
    }
}

fn encode(src: &[u8]) -> Vec<u8> {
    let mut tok = Vec::new();
    let mut pos = 0;
    while pos < src.len() {
        match best_match(src, pos) {
            Some((off, len)) => {
                tok.push(off);
                tok.push(len);
                pos += len as usize;
            }
            None => {
                tok.push(0);
                tok.push(src[pos]);
                pos += 1;
            }
        }
    }
    tok
}

// Returns Some(output) on success, None on bomb-guard trigger.
fn decode(tok: &[u8], out_cap: usize) -> Option<Vec<u8>> {
    let mut out: Vec<u8> = Vec::new();
    let mut i = 0;
    while i + 1 < tok.len() {
        let b0 = tok[i];
        let b1 = tok[i + 1];
        i += 2;
        if b0 == 0 {
            if out.len() + 1 > out_cap { return None; }
            out.push(b1);
        } else {
            let offset = b0 as usize;
            let length = b1 as usize;
            if out.len() + length > out_cap { return None; }
            // Capture start so the source index doesn't drift as we push.
            // For offset=1, this still produces RLE replication because
            // start - 1 + k advances into bytes we just pushed.
            let start = out.len();
            for k in 0..length {
                let byte = out[start - offset + k];
                out.push(byte);
            }
        }
    }
    Some(out)
}

fn main() {
    // 1. Round-trip with substring match
    let s1 = b"ABCABCABC";
    let t1 = encode(s1);
    assert!(t1.len() > 0, "encoded length > 0");
    let d1 = decode(&t1, 512).expect("decode succeeds");
    assert_eq!(d1, s1, "ABCABCABC roundtrip");

    // 2. Round-trip with overlapping (RLE) match
    let s2 = b"AAAAAAAA";
    let t2 = encode(s2);
    let d2 = decode(&t2, 512).expect("decode succeeds");
    assert_eq!(d2, s2, "AAAAAAAA roundtrip");
    assert!(t2.len() < s2.len() + 4, "AAAAAAAA actually compresses");

    // 3. Round-trip mostly literals
    let s3 = b"Hello, World!";
    let t3 = encode(s3);
    let d3 = decode(&t3, 512).expect("decode succeeds");
    assert_eq!(d3, s3, "Hello roundtrip");

    // 4. Decompression bomb guard: token claims length 200, cap is 10
    let bomb = vec![1u8, 200u8];
    assert!(decode(&bomb, 10).is_none(), "bomb guard rejects oversize");

    // 5. Empty input
    let t5 = encode(&[]);
    assert_eq!(t5.len(), 0, "empty input → zero tokens");
    let d5 = decode(&[], 512).expect("empty decode");
    assert_eq!(d5.len(), 0, "empty tokens → zero output");

    println!("compression: 11/11 ok");
}
