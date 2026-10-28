// Vidya — HTTP and Web Protocols in TypeScript
//
// HTTP/1.1 request parser, sequential.
//
// The body is framed by Content-Length (RFC 9112 §6.3), never "whatever
// follows the headers": on a keep-alive connection the rest of the buffer
// is the next pipelined request, and treating it as body is the root of
// request smuggling. Chunked Transfer-Encoding is out of scope.

const BODY_CAP = 1 << 20; // 413 Content Too Large above this

interface Request {
  method: string;
  path: string;
  version: string;
  headers: Array<[string, string]>;
  body: Buffer;
}

function findCRLF(buf: Buffer, start: number): number {
  return buf.indexOf("\r\n", start);
}

function parseRequest(buf: Buffer): Request | null {
  const rlEnd = findCRLF(buf, 0);
  if (rlEnd < 0) return null;
  const line = buf.subarray(0, rlEnd).toString("utf8");
  const sp1 = line.indexOf(" ");
  const sp2 = line.indexOf(" ", sp1 + 1);
  if (sp1 < 0 || sp2 < 0) return null;

  const req: Request = {
    method: line.slice(0, sp1),
    path: line.slice(sp1 + 1, sp2),
    version: line.slice(sp2 + 1),
    headers: [],
    body: Buffer.alloc(0),
  };

  let pos = rlEnd + 2;
  while (true) {
    if (pos + 1 >= buf.length) return null;
    if (buf[pos] === 0x0D && buf[pos + 1] === 0x0A) {
      pos += 2;
      // No Content-Length means no body.
      const cl = headerLookup(req, "content-length");
      let bodyLen = 0;
      if (cl !== null) {
        if (!/^[0-9]+$/.test(cl)) return null;      // 400 Bad Request
        bodyLen = Number(cl);
        if (bodyLen > BODY_CAP) return null;        // 413
      }
      if (bodyLen > buf.length - pos) return null;  // body not fully received
      req.body = buf.subarray(pos, pos + bodyLen);
      return req;
    }
    const lineEnd = findCRLF(buf, pos);
    if (lineEnd < 0) return null;
    const lstr = buf.subarray(pos, lineEnd).toString("utf8");
    const colon = lstr.indexOf(":");
    if (colon < 0) return null;
    const name = lstr.slice(0, colon).toLowerCase();
    let vstart = colon + 1;
    while (vstart < lstr.length && lstr[vstart] === " ") vstart++;
    const value = lstr.slice(vstart);
    req.headers.push([name, value]);
    pos = lineEnd + 2;
  }
}

function headerLookup(req: Request, name: string): string | null {
  const n = name.toLowerCase();
  for (const [hn, hv] of req.headers) {
    if (hn === n) return hv;
  }
  return null;
}

function main(): void {
  const req1 = Buffer.from("GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n");
  const r1 = parseRequest(req1);
  if (!r1) throw new Error("req1");
  if (r1.method !== "GET") throw new Error("method");
  if (r1.path !== "/index.html") throw new Error("path");
  if (r1.version !== "HTTP/1.1") throw new Error("version");
  if (r1.headers.length !== 1) throw new Error("hdr count");

  for (const n of ["host", "HOST", "Host"]) {
    if (headerLookup(r1, n) !== "example.com") throw new Error(`case ${n}`);
  }

  const req3 = Buffer.from("GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n");
  const r3 = parseRequest(req3)!;
  if (r3.headers.length !== 3) throw new Error("hdr3");
  if (headerLookup(r3, "user-agent") !== "test/1.0") throw new Error("ua");

  const req4 = Buffer.from("POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world");
  const r4 = parseRequest(req4)!;
  if (r4.method !== "POST") throw new Error("post");
  if (r4.body.toString("utf8") !== "hello world") throw new Error("body");

  const req5 = Buffer.from("POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!");
  const r5 = parseRequest(req5)!;
  if (r5.body.length !== 13) throw new Error("body5 len");
  if (r5.body.toString("utf8") !== "line1\r\nline2!") throw new Error("body5");

  const req6 = Buffer.from("GET / HTTP/1.1\r\nHost: x\r\n");
  if (parseRequest(req6) !== null) throw new Error("malformed accepted");

  if (headerLookup(r1, "authorization") !== null) throw new Error("absent");
  if (r1.body.length !== 0) throw new Error("no Content-Length, no body");

  // Content-Length frames the body: trailing bytes are the next request
  const r7 = parseRequest(Buffer.from("POST /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n\r\n"));
  if (!r7 || r7.body.toString("utf8") !== "hello") throw new Error("body stops at Content-Length");
  if (parseRequest(Buffer.from("POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort")) !== null) {
    throw new Error("short body is incomplete, not accepted");
  }
  if (parseRequest(Buffer.from("POST /x HTTP/1.1\r\nContent-Length: 5x\r\n\r\nhello")) !== null) {
    throw new Error("non-numeric Content-Length rejected");
  }

  console.log("http_and_web_protocols: 20/20 ok");
}

main();
