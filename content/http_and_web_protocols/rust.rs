// Vidya — HTTP and Web Protocols in Rust
//
// HTTP/1.1 request parser. Sequential parsing per concept.toml's first
// best practice: request line → headers → optional body. Header names
// are normalized to lowercase for case-insensitive lookup.

#[derive(Default)]
struct Request {
    method: Vec<u8>,
    path: Vec<u8>,
    version: Vec<u8>,
    headers: Vec<(Vec<u8>, Vec<u8>)>,
    body: Vec<u8>,
}

fn find_crlf(buf: &[u8], start: usize) -> Option<usize> {
    let mut i = start;
    while i + 1 < buf.len() {
        if buf[i] == b'\r' && buf[i + 1] == b'\n' { return Some(i); }
        i += 1;
    }
    None
}

fn parse_request(buf: &[u8]) -> Option<Request> {
    let rl_end = find_crlf(buf, 0)?;
    let sp1 = buf[..rl_end].iter().position(|&b| b == b' ')?;
    let sp2 = (sp1 + 1..rl_end).find(|&i| buf[i] == b' ')?;

    let mut req = Request {
        method: buf[..sp1].to_vec(),
        path: buf[sp1 + 1..sp2].to_vec(),
        version: buf[sp2 + 1..rl_end].to_vec(),
        ..Default::default()
    };

    let mut pos = rl_end + 2;
    loop {
        if pos + 1 >= buf.len() { return None; }
        if buf[pos] == b'\r' && buf[pos + 1] == b'\n' {
            pos += 2;
            req.body = buf[pos..].to_vec();
            return Some(req);
        }
        let line_end = find_crlf(buf, pos)?;
        let colon = (pos..line_end).find(|&i| buf[i] == b':')?;
        let name: Vec<u8> = buf[pos..colon].iter().map(|b| b.to_ascii_lowercase()).collect();
        let mut vstart = colon + 1;
        while vstart < line_end && buf[vstart] == b' ' { vstart += 1; }
        let value = buf[vstart..line_end].to_vec();
        req.headers.push((name, value));
        pos = line_end + 2;
    }
}

fn header_lookup<'a>(req: &'a Request, name: &[u8]) -> Option<&'a [u8]> {
    let lower: Vec<u8> = name.iter().map(|b| b.to_ascii_lowercase()).collect();
    req.headers.iter().find(|(n, _)| n == &lower).map(|(_, v)| v.as_slice())
}

fn main() {
    // 1. Simple GET
    let req1 = b"GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n";
    let r1 = parse_request(req1).expect("parse req1");
    assert_eq!(r1.method, b"GET");
    assert_eq!(r1.path, b"/index.html");
    assert_eq!(r1.version, b"HTTP/1.1");
    assert_eq!(r1.headers.len(), 1);

    // 2. Case-insensitive
    assert_eq!(header_lookup(&r1, b"host"), Some(&b"example.com"[..]));
    assert_eq!(header_lookup(&r1, b"HOST"), Some(&b"example.com"[..]));
    assert_eq!(header_lookup(&r1, b"Host"), Some(&b"example.com"[..]));

    // 3. Multiple headers
    let req3 = b"GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n";
    let r3 = parse_request(req3).expect("parse req3");
    assert_eq!(r3.headers.len(), 3);
    assert_eq!(header_lookup(&r3, b"user-agent"), Some(&b"test/1.0"[..]));

    // 4. POST with body
    let req4 = b"POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world";
    let r4 = parse_request(req4).expect("parse req4");
    assert_eq!(r4.method, b"POST");
    assert_eq!(r4.body, b"hello world");

    // 5. Body containing CRLF preserved
    let req5 = b"POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!";
    let r5 = parse_request(req5).expect("parse req5");
    assert_eq!(r5.body.len(), 13);
    assert_eq!(r5.body, b"line1\r\nline2!");

    // 6. Malformed (no \r\n\r\n)
    let req6 = b"GET / HTTP/1.1\r\nHost: x\r\n";
    assert!(parse_request(req6).is_none());

    // 7. Absent header
    assert_eq!(header_lookup(&r1, b"authorization"), None);

    println!("http_and_web_protocols: 24/24 ok");
}
