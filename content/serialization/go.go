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

func main() {
	v := encodeVarint(0)
	if len(v) != 1 || v[0] != 0 { panic("v0") }
	v = encodeVarint(127)
	if len(v) != 1 || v[0] != 0x7F { panic("v127") }
	v = encodeVarint(128)
	if len(v) != 2 || v[0] != 0x80 || v[1] != 0x01 { panic("v128") }
	v = encodeVarint(16383)
	if len(v) != 2 { panic("v16383") }
	v = encodeVarint(16384)
	if len(v) != 3 { panic("v16384") }

	enc := encodeVarint(1234567890)
	dec, dn, ok := decodeVarint(enc)
	if !ok || dec != 1234567890 || dn != len(enc) { panic("roundtrip") }

	bomb := bytes.Repeat([]byte{0xFF}, 11)
	if _, _, ok := decodeVarint(bomb); ok { panic("overflow") }

	payload := []byte("hello, world")
	frame := encodeFrame(payload)
	if len(frame) != 13 || frame[0] != 12 { panic("frame") }
	dec2, c, ok := decodeFrame(frame, MaxMsgSize)
	if !ok || c != 13 || !bytes.Equal(dec2, payload) { panic("frame rt") }

	var stream []byte
	stream = append(stream, encodeFrame([]byte("AAA"))...)
	stream = append(stream, encodeFrame([]byte("BBBB"))...)
	stream = append(stream, encodeFrame([]byte("CCCCC"))...)
	pos, msgs := 0, 0
	for pos < len(stream) {
		_, c, ok := decodeFrame(stream[pos:], MaxMsgSize)
		if !ok { break }
		msgs++
		pos += c
	}
	if msgs != 3 { panic("stream") }

	trunc := []byte{100, 'B', 'C', 'D', 'E', 'F'}
	if _, _, ok := decodeFrame(trunc, MaxMsgSize); ok { panic("trunc") }

	over := encodeVarint(9999)
	if _, _, ok := decodeFrame(over, MaxMsgSize); ok { panic("oversize") }

	fmt.Println("serialization: 19/19 ok")
}
