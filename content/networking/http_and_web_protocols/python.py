# Vidya — HTTP and Web Protocols in Python
#
# HTTP/1.1 request parser, sequential parse pattern + case-insensitive
# header lookup.
#
# The body is framed by Content-Length (RFC 9112 §6.3), never "whatever
# follows the headers": on a keep-alive connection the rest of the buffer
# is the next pipelined request, and treating it as body is the root of
# request smuggling. Chunked Transfer-Encoding is out of scope.

BODY_CAP = 1 << 20  # 413 Content Too Large above this


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
            # No Content-Length means no body.
            cl = header_lookup(req, b"content-length")
            body_len = 0
            if cl is not None:
                # Digits only: int() would also take " 5", "+5" and "5_0".
                if not cl.isdigit():
                    return None  # 400 Bad Request
                body_len = int(cl)
                if body_len > BODY_CAP:
                    return None  # 413
            if body_len > len(buf) - pos:
                return None  # body not fully received
            req.body = bytes(buf[pos:pos + body_len])
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
    assert r1.body == b""  # no Content-Length, no body

    # Content-Length frames the body: trailing bytes are the next request
    r7 = parse_request(
        b"POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n\r\n")
    assert r7 is not None and r7.body == b"hello"
    # A short body is incomplete, not accepted
    assert parse_request(b"POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort") is None
    # Non-numeric Content-Length is rejected (int() would accept "5_0")
    assert parse_request(b"POST /x HTTP/1.1\r\nContent-Length: 5x\r\n\r\nhello") is None
    assert parse_request(b"POST /x HTTP/1.1\r\nContent-Length: 0_5\r\n\r\nhello") is None

    print("http_and_web_protocols: 21/21 ok")


main()
