// Vidya — Serialization in Rust
//
// Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

const MAX_VARINT_BYTES: usize = 10;
const MAX_MSG_SIZE: u64 = 1024;

fn encode_varint(mut value: u64, out: &mut Vec<u8>) -> usize {
    let start = out.len();
    while value >= 128 {
        out.push((value as u8 & 0x7F) | 0x80);
        value >>= 7;
    }
    out.push(value as u8 & 0x7F);
    out.len() - start
}

fn decode_varint(buf: &[u8]) -> Option<(u64, usize)> {
    let mut value: u64 = 0;
    let mut shift = 0;
    for i in 0..MAX_VARINT_BYTES {
        if i >= buf.len() { return None; }
        let b = buf[i];
        value += ((b & 0x7F) as u64) << shift;
        if b & 0x80 == 0 { return Some((value, i + 1)); }
        shift += 7;
    }
    None
}

fn encode_frame(payload: &[u8], out: &mut Vec<u8>) -> usize {
    let n = encode_varint(payload.len() as u64, out);
    out.extend_from_slice(payload);
    n + payload.len()
}

fn decode_frame(buf: &[u8], max_msg: u64) -> Option<(Vec<u8>, usize)> {
    let (len, hdr) = decode_varint(buf)?;
    if len > max_msg { return None; }
    let total = hdr + len as usize;
    if total > buf.len() { return None; }
    Some((buf[hdr..total].to_vec(), total))
}

fn main() {
    // Varint sizes
    let mut buf = Vec::new();
    assert_eq!(encode_varint(0, &mut buf), 1);
    assert_eq!(buf, vec![0]);
    buf.clear();

    assert_eq!(encode_varint(127, &mut buf), 1);
    assert_eq!(buf, vec![0x7F]);
    buf.clear();

    assert_eq!(encode_varint(128, &mut buf), 2);
    assert_eq!(buf, vec![0x80, 0x01]);
    buf.clear();

    assert_eq!(encode_varint(16383, &mut buf), 2);
    buf.clear();
    assert_eq!(encode_varint(16384, &mut buf), 3);
    buf.clear();

    // Round-trip
    let sample = 1234567890u64;
    let n = encode_varint(sample, &mut buf);
    let (dec, dn) = decode_varint(&buf).unwrap();
    assert_eq!(dec, sample);
    assert_eq!(dn, n);
    buf.clear();

    // Overflow guard: 11 bytes all-continuation
    let bomb = vec![0xFFu8; 11];
    assert!(decode_varint(&bomb).is_none());

    // Frame round-trip
    let payload = b"hello, world";
    let n = encode_frame(payload, &mut buf);
    assert_eq!(n, 13);
    assert_eq!(buf[0], 12);
    let (decoded, consumed) = decode_frame(&buf, MAX_MSG_SIZE).unwrap();
    assert_eq!(consumed, 13);
    assert_eq!(decoded.as_slice(), payload);
    buf.clear();

    // Stream of 3 frames
    encode_frame(b"AAA", &mut buf);
    encode_frame(b"BBBB", &mut buf);
    encode_frame(b"CCCCC", &mut buf);
    let mut pos = 0;
    let mut msg_count = 0;
    while pos < buf.len() {
        match decode_frame(&buf[pos..], MAX_MSG_SIZE) {
            Some((_, c)) => { msg_count += 1; pos += c; }
            None => break,
        }
    }
    assert_eq!(msg_count, 3);

    // Truncated frame
    let trunc = vec![100u8, b'B', b'C', b'D', b'E', b'F'];
    assert!(decode_frame(&trunc, MAX_MSG_SIZE).is_none());

    // Oversize length rejected
    let mut over = Vec::new();
    encode_varint(9999, &mut over);
    assert!(decode_frame(&over, MAX_MSG_SIZE).is_none());

    println!("serialization: 19/19 ok");
}
