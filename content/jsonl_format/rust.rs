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

// Returns escaped length, or None on bounds-check failure. Worst case is
// 6x: RFC 8259 §7 requires EVERY control byte U+0000..U+001F to be escaped,
// and those without a short form become \u00XX. Leaving them raw (only
// escaping \n \t \r) emits invalid JSON.
fn json_escape(dst: &mut Vec<u8>, dst_cap: usize, src: &[u8]) -> Option<usize> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    if src.len() * 6 > dst_cap {
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
            c if c < 0x20 => {
                dst.extend_from_slice(&[b'\\', b'u', b'0', b'0', HEX[(c >> 4) as usize], HEX[(c & 0xF) as usize]]);
            }
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
                b'u' if i + 5 < src.len() => {
                    // \u00XX (control bytes)
                    let hex = std::str::from_utf8(&src[i + 2..i + 6]).ok()
                        .and_then(|h| u8::from_str_radix(h, 16).ok());
                    match hex {
                        Some(b) => { dst.push(b); i += 6; }
                        None => { dst.push(src[i]); i += 1; }
                    }
                    continue;
                }
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

    // Test 6: control bytes without a short escape (NUL, backspace, 0x1F)
    let s6: &[u8] = &[b'a', 0x00, 0x08, 0x1F];
    let mut esc6: Vec<u8> = Vec::new();
    json_escape(&mut esc6, 64, s6).expect("escape fits");
    assert_eq!(esc6, b"a\\u0000\\u0008\\u001f", "\\u00XX escapes");
    let mut un6: Vec<u8> = Vec::new();
    json_unescape(&mut un6, &esc6);
    assert_eq!(un6, s6, "\\u00XX round-trip");

    println!("jsonl_format: 10/10 ok");
}
