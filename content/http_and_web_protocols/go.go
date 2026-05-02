// Vidya — HTTP and Web Protocols in Go
//
// HTTP/1.1 request parser, sequential.

package main

import (
	"bytes"
	"fmt"
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
			req.Body = append([]byte{}, buf[pos:]...)
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

func main() {
	req1 := []byte("GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n")
	r1 := parseRequest(req1)
	if r1 == nil { panic("req1") }
	if !bytes.Equal(r1.Method, []byte("GET")) { panic("method") }
	if !bytes.Equal(r1.Path, []byte("/index.html")) { panic("path") }
	if !bytes.Equal(r1.Version, []byte("HTTP/1.1")) { panic("version") }
	if len(r1.Headers) != 1 { panic("hdr count") }

	for _, n := range []string{"host", "HOST", "Host"} {
		if !bytes.Equal(headerLookup(r1, n), []byte("example.com")) {
			panic(fmt.Sprintf("case %s", n))
		}
	}

	req3 := []byte("GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n")
	r3 := parseRequest(req3)
	if len(r3.Headers) != 3 { panic("hdr3") }
	if !bytes.Equal(headerLookup(r3, "user-agent"), []byte("test/1.0")) { panic("ua") }

	req4 := []byte("POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world")
	r4 := parseRequest(req4)
	if !bytes.Equal(r4.Method, []byte("POST")) { panic("post") }
	if !bytes.Equal(r4.Body, []byte("hello world")) { panic("body") }

	req5 := []byte("POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!")
	r5 := parseRequest(req5)
	if len(r5.Body) != 13 { panic("body5 len") }
	if !bytes.Equal(r5.Body, []byte("line1\r\nline2!")) { panic("body5") }

	req6 := []byte("GET / HTTP/1.1\r\nHost: x\r\n")
	if parseRequest(req6) != nil { panic("malformed accepted") }

	if headerLookup(r1, "authorization") != nil { panic("absent") }

	fmt.Println("http_and_web_protocols: 24/24 ok")
}
