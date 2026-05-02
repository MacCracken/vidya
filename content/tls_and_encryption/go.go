// Vidya — TLS and Encryption in Go
//
// Simulation of TLS 1.3 handshake state machine + cipher negotiation
// + cert chain verification + AEAD seal/open.

package main

import (
	"bytes"
	"fmt"
)

const (
	StInit = iota
	StHelloSent
	StServerHello
	StCertVerified
	StEstablished
	StFailed
)

const (
	TLS_AES_128_GCM_SHA256       uint16 = 0x1301
	TLS_AES_256_GCM_SHA384       uint16 = 0x1302
	TLS_CHACHA20_POLY1305_SHA256 uint16 = 0x1303
	TLS_RSA_AES_128_CBC_SHA      uint16 = 0x002F
)

type Cert struct{ Subject, Issuer uint64 }

func isTls13Cipher(c uint16) bool {
	return c == TLS_AES_128_GCM_SHA256 || c == TLS_AES_256_GCM_SHA384 || c == TLS_CHACHA20_POLY1305_SHA256
}

func pickCipher(srv, cli []uint16) uint16 {
	for _, s := range srv {
		if !isTls13Cipher(s) {
			continue
		}
		for _, c := range cli {
			if s == c {
				return s
			}
		}
	}
	return 0
}

func verifyChain(chain, trust []Cert) bool {
	if len(chain) == 0 {
		return false
	}
	for i := 0; i < len(chain)-1; i++ {
		if chain[i].Issuer != chain[i+1].Subject {
			return false
		}
	}
	last := chain[len(chain)-1].Subject
	for _, t := range trust {
		if t.Subject == last {
			return true
		}
	}
	return false
}

func certMatchesHostname(c Cert, h uint64) bool { return c.Subject == h }

func xorStream(src []byte, key byte) []byte {
	out := make([]byte, len(src))
	for i, b := range src {
		out[i] = b ^ key
	}
	return out
}

func computeTag(buf []byte, key, nonce uint64) uint64 {
	var sum uint64
	for _, b := range buf {
		sum += uint64(b)
	}
	return (sum ^ key) ^ nonce
}

func aeadSeal(pt []byte, key byte, nonce uint64) ([]byte, uint64) {
	return xorStream(pt, key), computeTag(pt, uint64(key), nonce)
}

func aeadOpen(ct []byte, key byte, nonce, tag uint64) []byte {
	pt := xorStream(ct, key)
	if computeTag(pt, uint64(key), nonce) != tag {
		return nil
	}
	return pt
}

type Handshake struct {
	State      int
	Negotiated uint16
}

func (h *Handshake) Advance(srv, cli []uint16, chain, trust []Cert, hostname uint64) {
	switch h.State {
	case StInit:
		h.State = StHelloSent
	case StHelloSent:
		c := pickCipher(srv, cli)
		if c == 0 {
			h.State = StFailed
			return
		}
		h.Negotiated = c
		h.State = StServerHello
	case StServerHello:
		if !verifyChain(chain, trust) {
			h.State = StFailed
			return
		}
		if !certMatchesHostname(chain[0], hostname) {
			h.State = StFailed
			return
		}
		h.State = StCertVerified
	case StCertVerified:
		h.State = StEstablished
	}
}

func main() {
	srv := []uint16{TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384}
	cli := []uint16{TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256}
	if pickCipher(srv, cli) != TLS_AES_128_GCM_SHA256 { panic("pick") }
	if pickCipher([]uint16{TLS_RSA_AES_128_CBC_SHA}, cli) != 0 { panic("legacy") }

	leaf := Cert{100, 200}
	inter := Cert{200, 300}
	root := Cert{300, 300}
	chain := []Cert{leaf, inter, root}
	trust := []Cert{root}
	if !verifyChain(chain, trust) { panic("chain") }
	if verifyChain(chain, []Cert{{999, 999}}) { panic("bad trust") }
	if verifyChain([]Cert{{100, 100}}, trust) { panic("ss leaf") }

	pt := []byte("secret message")
	ct, tag := aeadSeal(pt, 42, 7)
	dec := aeadOpen(ct, 42, 7, tag)
	if !bytes.Equal(dec, pt) { panic("roundtrip") }
	tampered := append([]byte{}, ct...)
	tampered[5] ^= 1
	if aeadOpen(tampered, 42, 7, tag) != nil { panic("tampered") }
	if aeadOpen(ct, 42, 7, tag^1) != nil { panic("wrong tag") }

	hs := Handshake{State: StInit}
	if hs.State != StInit { panic("init") }
	hs.Advance(srv, cli, chain, trust, 100)
	if hs.State != StHelloSent { panic("hello sent") }
	hs.Advance(srv, cli, chain, trust, 100)
	if hs.State != StServerHello { panic("server hello") }
	if hs.Negotiated != TLS_AES_128_GCM_SHA256 { panic("negotiated") }
	hs.Advance(srv, cli, chain, trust, 100)
	if hs.State != StCertVerified { panic("cert verified") }
	hs.Advance(srv, cli, chain, trust, 100)
	if hs.State != StEstablished { panic("established") }

	hs2 := Handshake{State: StInit}
	hs2.Advance(srv, cli, chain, trust, 100)
	hs2.Advance(srv, cli, chain, trust, 100)
	hs2.Advance(srv, cli, chain, trust, 999)
	if hs2.State != StFailed { panic("hostname mismatch") }

	fmt.Println("tls_and_encryption: 16/16 ok")
}
