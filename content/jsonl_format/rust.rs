// Vidya — JSON Lines (JSONL) in Rust
//
// In-memory JSONL primitives mirroring cyrius.cyr:
//   - append records into a flat byte buffer with \n separators
//   - build a per-line index, handling the no-trailing-newline edge
//   - extract a record by index
//   - JSON string escape with bounds check
//   - escape <-> unescape roundtrip

fn append_record(buf: &mut Vec<u8>, rec: &[u8]) {
    buf.extend_from_slice(rec);
    buf.push(b'\n');
}

#[derive(Debug)]
struct LineIndex {
    offsets: Vec<usize>,
    lengths: Vec<usize>,
}

fn build_index(buf: &[u8]) -> LineIndex {
    let mut idx = LineIndex { offsets: Vec::new(), lengths: Vec::new() };
    let mut start = 0;
    for (i, &b) in buf.iter().enumerate() {
        if b == b'\n' {
            idx.offsets.push(start);
            idx.lengths.push(i - start);
            start = i + 1;
        }
    }
    if start < buf.len() {
        idx.offsets.push(start);
        idx.lengths.push(buf.len() - start);
    }
    idx
}

// Returns escaped length, or None on bounds-check failure.
fn json_escape(dst: &mut Vec<u8>, dst_cap: usize, src: &[u8]) -> Option<usize> {
    if src.len() * 2 > dst_cap {
        return None;
    }
    dst.clear();
    for &c in src {
        match c {
            b'"' => { dst.push(b'\\'); dst.push(b'"'); }
            b'\\' => { dst.push(b'\\'); dst.push(b'\\'); }
            b'\n' => { dst.push(b'\\'); dst.push(b'n'); }
            b'\t' => { dst.push(b'\\'); dst.push(b't'); }
            b'\r' => { dst.push(b'\\'); dst.push(b'r'); }
            _ => dst.push(c),
        }
    }
    Some(dst.len())
}

fn json_unescape(dst: &mut Vec<u8>, src: &[u8]) -> usize {
    dst.clear();
    let mut i = 0;
    while i < src.len() {
        if src[i] == b'\\' && i + 1 < src.len() {
            let n = src[i + 1];
            match n {
                b'"' => dst.push(b'"'),
                b'\\' => dst.push(b'\\'),
                b'n' => dst.push(b'\n'),
                b't' => dst.push(b'\t'),
                b'r' => dst.push(b'\r'),
                _ => { dst.push(src[i]); i += 1; continue; }
            }
            i += 2;
        } else {
            dst.push(src[i]);
            i += 1;
        }
    }
    dst.len()
}

fn main() {
    // Test 1: build, index, extract
    let mut buf: Vec<u8> = Vec::new();
    append_record(&mut buf, b"{\"id\":1}");
    append_record(&mut buf, b"{\"id\":2}");
    append_record(&mut buf, b"{\"id\":3}");
    let idx = build_index(&buf);
    assert_eq!(idx.offsets.len(), 3, "3 records indexed");
    assert_eq!(idx.lengths[2], 8, "third record length 8");
    let third = &buf[idx.offsets[2]..idx.offsets[2] + idx.lengths[2]];
    assert_eq!(third, b"{\"id\":3}", "third record bytes");

    // Test 2: no-trailing-newline edge case
    let mut buf2 = buf.clone();
    if buf2.last() == Some(&b'\n') { buf2.pop(); }
    let idx2 = build_index(&buf2);
    assert_eq!(idx2.offsets.len(), 3, "3 records indexed without trailing newline");

    // Test 3: escape
    let s3: &[u8] = &[b's', b'a', b'y', b' ', b'"', b'h', b'i', b'"', b'\t', b'\n', b'\r', b'\\'];
    let mut esc: Vec<u8> = Vec::new();
    let en = json_escape(&mut esc, 256, s3).expect("escape fits");
    assert_eq!(en, 18, "escape produces 18 bytes from 12");

    // Test 4: bounds check
    let s4: &[u8] = &[b'"', b'"', b'"', b'"'];
    let mut esc4: Vec<u8> = Vec::new();
    assert!(json_escape(&mut esc4, 4, s4).is_none(), "escape refuses tight cap");

    // Test 5: roundtrip
    let mut un: Vec<u8> = Vec::new();
    let unl = json_unescape(&mut un, &esc);
    assert_eq!(unl, 12, "unescape recovers 12 bytes");
    assert_eq!(un, s3, "round-trip bytes match");

    println!("jsonl_format: 8/8 ok");
}
