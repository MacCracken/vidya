// Vidya — JSON Lines (JSONL) in Go
//
// In-memory JSONL primitives mirroring cyrius.cyr.

package main

import (
	"bytes"
	"fmt"
)

func appendRecord(buf *[]byte, rec []byte) {
	*buf = append(*buf, rec...)
	*buf = append(*buf, '\n')
}

func buildIndex(buf []byte) (offsets, lengths []int) {
	start := 0
	for i, b := range buf {
		if b == '\n' {
			offsets = append(offsets, start)
			lengths = append(lengths, i-start)
			start = i + 1
		}
	}
	if start < len(buf) {
		offsets = append(offsets, start)
		lengths = append(lengths, len(buf)-start)
	}
	return
}

// Returns escaped bytes, or nil on bounds-check failure.
func jsonEscape(src []byte, dstCap int) []byte {
	if len(src)*2 > dstCap {
		return nil
	}
	out := make([]byte, 0, len(src)*2)
	for _, c := range src {
		switch c {
		case '"':
			out = append(out, '\\', '"')
		case '\\':
			out = append(out, '\\', '\\')
		case '\n':
			out = append(out, '\\', 'n')
		case '\t':
			out = append(out, '\\', 't')
		case '\r':
			out = append(out, '\\', 'r')
		default:
			out = append(out, c)
		}
	}
	return out
}

func jsonUnescape(src []byte) []byte {
	out := make([]byte, 0, len(src))
	for i := 0; i < len(src); {
		if src[i] == '\\' && i+1 < len(src) {
			switch src[i+1] {
			case '"':
				out = append(out, '"')
				i += 2
			case '\\':
				out = append(out, '\\')
				i += 2
			case 'n':
				out = append(out, '\n')
				i += 2
			case 't':
				out = append(out, '\t')
				i += 2
			case 'r':
				out = append(out, '\r')
				i += 2
			default:
				out = append(out, src[i])
				i++
			}
		} else {
			out = append(out, src[i])
			i++
		}
	}
	return out
}

func main() {
	var buf []byte

	// Test 1
	appendRecord(&buf, []byte(`{"id":1}`))
	appendRecord(&buf, []byte(`{"id":2}`))
	appendRecord(&buf, []byte(`{"id":3}`))
	offs, lens := buildIndex(buf)
	if len(offs) != 3 {
		panic("3 records indexed")
	}
	if lens[2] != 8 {
		panic("third record length 8")
	}
	third := buf[offs[2] : offs[2]+lens[2]]
	if !bytes.Equal(third, []byte(`{"id":3}`)) {
		panic("third record bytes")
	}

	// Test 2: no trailing newline
	buf2 := make([]byte, len(buf))
	copy(buf2, buf)
	if len(buf2) > 0 && buf2[len(buf2)-1] == '\n' {
		buf2 = buf2[:len(buf2)-1]
	}
	offs2, _ := buildIndex(buf2)
	if len(offs2) != 3 {
		panic("3 records indexed without trailing newline")
	}

	// Test 3: escape
	s3 := []byte{'s', 'a', 'y', ' ', '"', 'h', 'i', '"', '\t', '\n', '\r', '\\'}
	esc := jsonEscape(s3, 256)
	if len(esc) != 18 {
		panic(fmt.Sprintf("escape: got %d want 18", len(esc)))
	}

	// Test 4: bounds check
	s4 := []byte{'"', '"', '"', '"'}
	if jsonEscape(s4, 4) != nil {
		panic("escape refuses tight cap")
	}

	// Test 5: roundtrip
	un := jsonUnescape(esc)
	if len(un) != 12 {
		panic("unescape recovers 12")
	}
	if !bytes.Equal(un, s3) {
		panic("round-trip bytes")
	}

	fmt.Println("jsonl_format: 8/8 ok")
}
