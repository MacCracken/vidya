// Vidya — Compression (LZ77-shaped) in Go
//
// Two-byte token stream matching cyrius.cyr:
//   {0, BYTE}      literal
//   {OFFSET, LEN}  match: copy LEN bytes from out[pos - OFFSET..]
// Greedy O(n^2) match-finder, 255-byte window. Decoder enforces an
// output-cap. Match copy byte-by-byte so offset=1 acts as RLE.

package main

import (
	"bytes"
	"fmt"
)

const (
	MinMatch = 3
	MaxMatch = 255
	WinSize  = 255
)

func matchLenAt(src []byte, hist, pos int) int {
	n := 0
	max := len(src) - pos
	if max > MaxMatch {
		max = MaxMatch
	}
	for n < max && src[hist+n] == src[pos+n] {
		n++
	}
	return n
}

func bestMatch(src []byte, pos int) (off, length int, ok bool) {
	winStart := pos - WinSize
	if winStart < 0 {
		winStart = 0
	}
	bestOff := 0
	bestLen := 0
	for i := winStart; i < pos; i++ {
		n := matchLenAt(src, i, pos)
		if n > bestLen {
			bestLen = n
			bestOff = pos - i
		}
	}
	if bestLen >= MinMatch {
		return bestOff, bestLen, true
	}
	return 0, 0, false
}

func encode(src []byte) []byte {
	var tok []byte
	pos := 0
	for pos < len(src) {
		if off, length, ok := bestMatch(src, pos); ok {
			tok = append(tok, byte(off), byte(length))
			pos += length
		} else {
			tok = append(tok, 0, src[pos])
			pos++
		}
	}
	return tok
}

// Returns nil on bomb-guard trigger, else the decoded output.
func decode(tok []byte, outCap int) []byte {
	out := make([]byte, 0, outCap)
	for i := 0; i+1 < len(tok); i += 2 {
		b0 := tok[i]
		b1 := tok[i+1]
		if b0 == 0 {
			if len(out)+1 > outCap {
				return nil
			}
			out = append(out, b1)
		} else {
			off := int(b0)
			length := int(b1)
			if len(out)+length > outCap {
				return nil
			}
			for k := 0; k < length; k++ {
				out = append(out, out[len(out)-off])
			}
		}
	}
	return out
}

func mustEq(got, want []byte, label string) {
	if !bytes.Equal(got, want) {
		panic(fmt.Sprintf("%s: got %q want %q", label, got, want))
	}
}

func main() {
	// 1. Round-trip with substring match
	s1 := []byte("ABCABCABC")
	t1 := encode(s1)
	if len(t1) == 0 {
		panic("encoded length > 0")
	}
	mustEq(decode(t1, 512), s1, "ABCABCABC roundtrip")

	// 2. Overlapping (RLE)
	s2 := []byte("AAAAAAAA")
	t2 := encode(s2)
	mustEq(decode(t2, 512), s2, "AAAAAAAA roundtrip")
	if len(t2) >= len(s2)+4 {
		panic("AAAAAAAA actually compresses")
	}

	// 3. Mostly literals
	s3 := []byte("Hello, World!")
	t3 := encode(s3)
	mustEq(decode(t3, 512), s3, "Hello roundtrip")

	// 4. Bomb guard
	bomb := []byte{1, 200}
	if decode(bomb, 10) != nil {
		panic("bomb guard rejects oversize")
	}

	// 5. Empty input
	t5 := encode(nil)
	if len(t5) != 0 {
		panic("empty input → zero tokens")
	}
	d5 := decode(nil, 512)
	if len(d5) != 0 {
		panic("empty tokens → zero output")
	}

	fmt.Println("compression: 11/11 ok")
}
