// Vidya — JSON Lines (JSONL) in Go
//
// In-memory JSONL primitives mirroring cyrius.cyr.

package main

import (
	"bytes"
	"fmt"
	"strconv"
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

// Returns escaped bytes, or nil on bounds-check failure. RFC 8259 §7
// requires EVERY control byte U+0000..U+001F to be escaped, not just
// \n \t \r: the rest go out as \u00XX (6 bytes, hence the 6x worst case).
func jsonEscape(src []byte, dstCap int) []byte {
	worst := len(src) * 2
	for _, c := range src {
		if c < 0x20 && c != '\n' && c != '\t' && c != '\r' {
			worst += 4 // \u00XX is 6 bytes, not 2
		}
	}
	if worst > dstCap {
		return nil
	}
	const hexDigits = "0123456789abcdef"
	out := make([]byte, 0, worst)
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
			if c < 0x20 {
				out = append(out, '\\', 'u', '0', '0', hexDigits[c>>4], hexDigits[c&0xF])
			} else {
				out = append(out, c)
			}
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
			case 'u': // \u00XX: the byte-range escapes jsonEscape emits
				if i+6 <= len(src) {
					if v, err := strconv.ParseUint(string(src[i+2:i+6]), 16, 8); err == nil {
						out = append(out, byte(v))
						i += 6
						continue
					}
				}
				out = append(out, src[i])
				i++
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

// checks counts the assertions this file runs, for the final tally.
var checks int

func check(cond bool, label string) {
	checks++
	if !cond {
		panic(label)
	}
}

func main() {
	var buf []byte

	// Test 1
	appendRecord(&buf, []byte(`{"id":1}`))
	appendRecord(&buf, []byte(`{"id":2}`))
	appendRecord(&buf, []byte(`{"id":3}`))
	offs, lens := buildIndex(buf)
	check(len(offs) == 3, "3 records indexed")
	check(lens[2] == 8, "third record length 8")
	third := buf[offs[2] : offs[2]+lens[2]]
	check(bytes.Equal(third, []byte(`{"id":3}`)), "third record bytes")

	// Test 2: no trailing newline
	buf2 := make([]byte, len(buf))
	copy(buf2, buf)
	if len(buf2) > 0 && buf2[len(buf2)-1] == '\n' {
		buf2 = buf2[:len(buf2)-1]
	}
	offs2, _ := buildIndex(buf2)
	check(len(offs2) == 3, "3 records indexed without trailing newline")

	// Test 3: escape
	s3 := []byte{'s', 'a', 'y', ' ', '"', 'h', 'i', '"', '\t', '\n', '\r', '\\'}
	esc := jsonEscape(s3, 256)
	check(len(esc) == 18, fmt.Sprintf("escape: got %d want 18", len(esc)))

	// Test 3b: other control bytes escape as \u00XX and round-trip
	ctl := jsonEscape([]byte{'a', 0x01, 0x1f}, 64)
	check(bytes.Equal(ctl, []byte(`a\u0001\u001f`)), fmt.Sprintf("control escape: got %q", ctl))
	check(bytes.Equal(jsonUnescape(ctl), []byte{'a', 0x01, 0x1f}), "control round-trip")

	// Test 4: bounds check
	s4 := []byte{'"', '"', '"', '"'}
	check(jsonEscape(s4, 4) == nil, "escape refuses tight cap")

	// Test 5: roundtrip
	un := jsonUnescape(esc)
	check(len(un) == 12, "unescape recovers 12")
	check(bytes.Equal(un, s3), "round-trip bytes")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("jsonl_format: %d/%d ok\n", checks, checks)
}
