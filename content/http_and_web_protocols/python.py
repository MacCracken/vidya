# Vidya — HTTP and Web Protocols in Python
#
# HTTP/1.1 request parser, sequential parse pattern + case-insensitive
# header lookup.


class Request:
    def __init__(self):
        self.method = b""
        self.path = b""
        self.version = b""
        self.headers = []
        self.body = b""


def find_crlf(buf, start):
    return buf.find(b"\r\n", start)


def parse_request(buf):
    rl_end = find_crlf(buf, 0)
    if rl_end < 0:
        return None
    line = buf[:rl_end]
    sp1 = line.find(b" ")
    sp2 = line.find(b" ", sp1 + 1)
    if sp1 < 0 or sp2 < 0:
        return None
    req = Request()
    req.method = bytes(line[:sp1])
    req.path = bytes(line[sp1 + 1:sp2])
    req.version = bytes(line[sp2 + 1:])
    pos = rl_end + 2
    while True:
        if pos + 1 >= len(buf):
            return None
        if buf[pos:pos + 2] == b"\r\n":
            pos += 2
            req.body = bytes(buf[pos:])
            return req
        line_end = find_crlf(buf, pos)
        if line_end < 0:
            return None
        line = buf[pos:line_end]
        colon = line.find(b":")
        if colon < 0:
            return None
        name = bytes(line[:colon]).lower()
        vstart = colon + 1
        while vstart < len(line) and line[vstart:vstart + 1] == b" ":
            vstart += 1
        value = bytes(line[vstart:])
        req.headers.append((name, value))
        pos = line_end + 2


def header_lookup(req, name):
    n = name.lower()
    for hn, hv in req.headers:
        if hn == n:
            return hv
    return None


def main():
    req1 = b"GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"
    r1 = parse_request(req1)
    assert r1 is not None
    assert r1.method == b"GET"
    assert r1.path == b"/index.html"
    assert r1.version == b"HTTP/1.1"
    assert len(r1.headers) == 1

    assert header_lookup(r1, b"host") == b"example.com"
    assert header_lookup(r1, b"HOST") == b"example.com"
    assert header_lookup(r1, b"Host") == b"example.com"

    req3 = b"GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n"
    r3 = parse_request(req3)
    assert len(r3.headers) == 3
    assert header_lookup(r3, b"user-agent") == b"test/1.0"

    req4 = b"POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world"
    r4 = parse_request(req4)
    assert r4.method == b"POST"
    assert r4.body == b"hello world"

    req5 = b"POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!"
    r5 = parse_request(req5)
    assert len(r5.body) == 13
    assert r5.body == b"line1\r\nline2!"

    req6 = b"GET / HTTP/1.1\r\nHost: x\r\n"
    assert parse_request(req6) is None

    assert header_lookup(r1, b"authorization") is None

    print("http_and_web_protocols: 24/24 ok")


main()
