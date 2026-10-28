// Vidya — HTTP and Web Protocols in Go
//
// HTTP/1.1 request parser, sequential.

package main

import (
	"bytes"
	"fmt"
	"strconv"
)

type Request struct {
	Method, Path, Version []byte
	Headers               [][2][]byte
	Body                  []byte
}

func findCRLF(buf []byte, start int) int {
	idx := bytes.Index(buf[start:], []byte("\r\n"))
	if idx < 0 {
		return -1
	}
	return start + idx
}

func parseRequest(buf []byte) *Request {
	rlEnd := findCRLF(buf, 0)
	if rlEnd < 0 {
		return nil
	}
	line := buf[:rlEnd]
	sp1 := bytes.IndexByte(line, ' ')
	if sp1 < 0 {
		return nil
	}
	sp2 := bytes.IndexByte(line[sp1+1:], ' ')
	if sp2 < 0 {
		return nil
	}
	sp2 += sp1 + 1

	req := &Request{
		Method:  append([]byte{}, line[:sp1]...),
		Path:    append([]byte{}, line[sp1+1:sp2]...),
		Version: append([]byte{}, line[sp2+1:]...),
	}

	pos := rlEnd + 2
	for {
		if pos+1 >= len(buf) {
			return nil
		}
		if buf[pos] == '\r' && buf[pos+1] == '\n' {
			pos += 2
			// The body is exactly Content-Length bytes (RFC 9112 §6.3);
			// bytes after it belong to the next pipelined request. A
			// request with no Content-Length (and no chunked coding, which
			// this parser does not handle) has no body at all.
			n := 0
			if cl := headerLookup(req, "content-length"); cl != nil {
				v, err := strconv.Atoi(string(cl))
				if err != nil || v < 0 || pos+v > len(buf) {
					return nil // malformed length, or body not fully received
				}
				n = v
			}
			req.Body = append([]byte{}, buf[pos:pos+n]...)
			return req
		}
		lineEnd := findCRLF(buf, pos)
		if lineEnd < 0 {
			return nil
		}
		l := buf[pos:lineEnd]
		colon := bytes.IndexByte(l, ':')
		if colon < 0 {
			return nil
		}
		name := bytes.ToLower(l[:colon])
		vstart := colon + 1
		for vstart < len(l) && l[vstart] == ' ' {
			vstart++
		}
		value := l[vstart:]
		req.Headers = append(req.Headers, [2][]byte{
			append([]byte{}, name...),
			append([]byte{}, value...),
		})
		pos = lineEnd + 2
	}
}

func headerLookup(req *Request, name string) []byte {
	n := bytes.ToLower([]byte(name))
	for _, h := range req.Headers {
		if bytes.Equal(h[0], n) {
			return h[1]
		}
	}
	return nil
}

// checks counts the assertions this file runs, for the final tally.
var checks int

func check(cond bool, label string) {
	checks++
	if !cond {
		panic(label)
	}
}

func main() {
	req1 := []byte("GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n")
	r1 := parseRequest(req1)
	check(r1 != nil, "req1")
	check(bytes.Equal(r1.Method, []byte("GET")), "method")
	check(bytes.Equal(r1.Path, []byte("/index.html")), "path")
	check(bytes.Equal(r1.Version, []byte("HTTP/1.1")), "version")
	check(len(r1.Headers) == 1, "hdr count")

	for _, n := range []string{"host", "HOST", "Host"} {
		check(bytes.Equal(headerLookup(r1, n), []byte("example.com")), fmt.Sprintf("case %s", n))
	}

	req3 := []byte("GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n")
	r3 := parseRequest(req3)
	check(len(r3.Headers) == 3, "hdr3")
	check(bytes.Equal(headerLookup(r3, "user-agent"), []byte("test/1.0")), "ua")

	req4 := []byte("POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world")
	r4 := parseRequest(req4)
	check(bytes.Equal(r4.Method, []byte("POST")), "post")
	check(bytes.Equal(r4.Body, []byte("hello world")), "body")

	req5 := []byte("POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!")
	r5 := parseRequest(req5)
	check(len(r5.Body) == 13, "body5 len")
	check(bytes.Equal(r5.Body, []byte("line1\r\nline2!")), "body5")

	// Content-Length frames the body: trailing bytes are not body.
	req7 := []byte("POST /a HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n")
	r7 := parseRequest(req7)
	check(r7 != nil && bytes.Equal(r7.Body, []byte("hello")), "body must stop at Content-Length")

	req6 := []byte("GET / HTTP/1.1\r\nHost: x\r\n")
	check(parseRequest(req6) == nil, "malformed accepted")

	check(headerLookup(r1, "authorization") == nil, "absent")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("http_and_web_protocols: %d/%d ok\n", checks, checks)
}
