// Vidya — Serialization in Go
//
// Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

package main

import (
	"bytes"
	"fmt"
)

const (
	MaxVarintBytes = 10
	MaxMsgSize     = uint64(1024)
)

func encodeVarint(value uint64) []byte {
	var out []byte
	for value >= 128 {
		out = append(out, byte(value&0x7F)|0x80)
		value >>= 7
	}
	out = append(out, byte(value&0x7F))
	return out
}

func decodeVarint(buf []byte) (uint64, int, bool) {
	var value uint64
	shift := uint(0)
	for i := 0; i < MaxVarintBytes; i++ {
		if i >= len(buf) {
			return 0, 0, false
		}
		b := buf[i]
		// The 10th byte holds only bit 63: anything above 0x01 needs bits
		// 64-69, which << 63 would silently drop. Rejecting only an 11th
		// byte is not enough (encoding/binary.Uvarint does the same check).
		if i == MaxVarintBytes-1 && b > 1 {
			return 0, 0, false
		}
		value += uint64(b&0x7F) << shift
		if b&0x80 == 0 {
			return value, i + 1, true
		}
		shift += 7
	}
	return 0, 0, false
}

func encodeFrame(payload []byte) []byte {
	out := encodeVarint(uint64(len(payload)))
	return append(out, payload...)
}

func decodeFrame(buf []byte, maxMsg uint64) ([]byte, int, bool) {
	length, hdr, ok := decodeVarint(buf)
	if !ok {
		return nil, 0, false
	}
	if length > maxMsg {
		return nil, 0, false
	}
	total := hdr + int(length)
	if total > len(buf) {
		return nil, 0, false
	}
	return buf[hdr:total], total, true
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
	v := encodeVarint(0)
	check(len(v) == 1 && v[0] == 0, "v0")
	v = encodeVarint(127)
	check(len(v) == 1 && v[0] == 0x7F, "v127")
	v = encodeVarint(128)
	check(len(v) == 2 && v[0] == 0x80 && v[1] == 0x01, "v128")
	v = encodeVarint(16383)
	check(len(v) == 2, "v16383")
	v = encodeVarint(16384)
	check(len(v) == 3, "v16384")

	enc := encodeVarint(1234567890)
	dec, dn, ok := decodeVarint(enc)
	check(ok && dec == 1234567890 && dn == len(enc), "roundtrip")

	bomb := bytes.Repeat([]byte{0xFF}, 11)
	_, _, okBomb := decodeVarint(bomb)
	check(!okBomb, "overflow")
	wide := append(bytes.Repeat([]byte{0xFF}, 9), 0x7F) // 10 bytes, 70 bits
	_, _, okWide := decodeVarint(wide)
	check(!okWide, "10-byte varint wider than 64 bits accepted")
	maxU64 := encodeVarint(^uint64(0)) // 10 bytes, last byte 0x01
	got, _, okMax := decodeVarint(maxU64)
	check(okMax && got == ^uint64(0), "max uint64 roundtrip")

	payload := []byte("hello, world")
	frame := encodeFrame(payload)
	check(len(frame) == 13 && frame[0] == 12, "frame")
	dec2, c, ok := decodeFrame(frame, MaxMsgSize)
	check(ok && c == 13 && bytes.Equal(dec2, payload), "frame rt")

	var stream []byte
	stream = append(stream, encodeFrame([]byte("AAA"))...)
	stream = append(stream, encodeFrame([]byte("BBBB"))...)
	stream = append(stream, encodeFrame([]byte("CCCCC"))...)
	pos, msgs := 0, 0
	for pos < len(stream) {
		_, c, ok := decodeFrame(stream[pos:], MaxMsgSize)
		if !ok {
			break
		}
		msgs++
		pos += c
	}
	check(msgs == 3, "stream")

	trunc := []byte{100, 'B', 'C', 'D', 'E', 'F'}
	_, _, okTrunc := decodeFrame(trunc, MaxMsgSize)
	check(!okTrunc, "trunc")

	over := encodeVarint(9999)
	_, _, okOver := decodeFrame(over, MaxMsgSize)
	check(!okOver, "oversize")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("serialization: %d/%d ok\n", checks, checks)
}
