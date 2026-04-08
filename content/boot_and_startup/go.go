// Vidya — Boot and Startup in Go
//
// Go can't run as a bootloader (it needs a runtime and OS), but it's
// excellent for modeling boot data structures and verifying their
// layout. This file encodes GDT/IDT entries as byte arrays, builds
// multiboot headers with checksums, and models the CR0/CR4 bit
// transitions required for the 32-bit → 64-bit long mode switch.

package main

import (
	"encoding/binary"
	"fmt"
)

func main() {
	testGdtEntryEncoding()
	testIdtEntryEncoding()
	testMultibootHeader()
	testCr0Cr4LongModeTransition()
	testSegmentSelectors()
	testGdtTable()

	fmt.Println("All boot and startup examples passed.")
}

// ── GDT Entry Encoding ──────────────────────────────────────────────
// A GDT entry is 8 bytes. In long mode, most fields are legacy but
// the access byte and flags still matter. We encode to [8]byte and
// verify the exact layout.

type GdtEntry struct {
	LimitLow   uint16
	BaseLow    uint16
	BaseMid    uint8
	Access     uint8 // P(1) DPL(2) S(1) Type(4)
	FlagsLimit uint8 // G(1) D/B(1) L(1) AVL(1) Limit[19:16](4)
	BaseHigh   uint8
}

func (g GdtEntry) Encode() [8]byte {
	var buf [8]byte
	binary.LittleEndian.PutUint16(buf[0:2], g.LimitLow)
	binary.LittleEndian.PutUint16(buf[2:4], g.BaseLow)
	buf[4] = g.BaseMid
	buf[5] = g.Access
	buf[6] = g.FlagsLimit
	buf[7] = g.BaseHigh
	return buf
}

func (g GdtEntry) Present() bool  { return g.Access&0x80 != 0 }
func (g GdtEntry) DPL() uint8     { return (g.Access >> 5) & 0x3 }
func (g GdtEntry) IsCode() bool   { return g.Access&0x08 != 0 }
func (g GdtEntry) LongMode() bool { return g.FlagsLimit&0x20 != 0 }

// Null descriptor: 8 zero bytes
func gdtNull() GdtEntry { return GdtEntry{} }

// 64-bit kernel code: P=1, DPL=0, S=1, Type=0xA (exec+read), L=1, G=1
func gdtKernelCode64() GdtEntry {
	return GdtEntry{
		LimitLow:   0xFFFF,
		Access:     0x9A, // P=1, DPL=0, S=1, E=1, R=1
		FlagsLimit: 0xAF, // G=1, L=1, Limit[19:16]=0xF
	}
}

// 64-bit kernel data: P=1, DPL=0, S=1, Type=0x2 (read+write)
func gdtKernelData64() GdtEntry {
	return GdtEntry{
		LimitLow:   0xFFFF,
		Access:     0x92, // P=1, DPL=0, S=1, W=1
		FlagsLimit: 0xCF, // G=1, D/B=1, Limit[19:16]=0xF
	}
}

// User code ring 3
func gdtUserCode64() GdtEntry {
	return GdtEntry{
		LimitLow:   0xFFFF,
		Access:     0xFA, // P=1, DPL=3, S=1, E=1, R=1
		FlagsLimit: 0xAF,
	}
}

func testGdtEntryEncoding() {
	// Null entry must be all zeros
	null := gdtNull()
	encoded := null.Encode()
	for i, b := range encoded {
		assert(b == 0, fmt.Sprintf("null byte %d", i))
	}
	assert(!null.Present(), "null not present")

	// Kernel code segment
	kcode := gdtKernelCode64()
	assert(kcode.Present(), "kcode present")
	assert(kcode.DPL() == 0, "kcode ring 0")
	assert(kcode.IsCode(), "kcode is code")
	assert(kcode.LongMode(), "kcode long mode")

	kb := kcode.Encode()
	// Verify exact encoding: 0x00AF9A000000FFFF in little-endian bytes
	assert(kb[0] == 0xFF && kb[1] == 0xFF, "kcode limit low")
	assert(kb[5] == 0x9A, "kcode access byte")
	assert(kb[6] == 0xAF, "kcode flags+limit high")

	// User code segment
	ucode := gdtUserCode64()
	assert(ucode.DPL() == 3, "ucode ring 3")
	assert(ucode.LongMode(), "ucode long mode")
}

// ── IDT Entry Encoding ──────────────────────────────────────────────
// An IDT entry (interrupt gate) in 64-bit mode is 16 bytes.
// It holds the handler address split across three fields.

type IdtGate struct {
	OffsetLow  uint16
	Selector   uint16
	IST        uint8  // bits [2:0] = IST index (0 = no IST)
	TypeAttrs  uint8  // P(1) DPL(2) 0(1) Type(4)
	OffsetMid  uint16
	OffsetHigh uint32
	Reserved   uint32
}

func NewIdtGate(handler uint64, selector uint16, ist uint8, dpl uint8) IdtGate {
	return IdtGate{
		OffsetLow:  uint16(handler & 0xFFFF),
		Selector:   selector,
		IST:        ist & 0x7,
		TypeAttrs:  0x80 | (dpl&0x3)<<5 | 0x0E, // P=1, DPL, Type=0xE (interrupt gate)
		OffsetMid:  uint16((handler >> 16) & 0xFFFF),
		OffsetHigh: uint32(handler >> 32),
	}
}

func (g IdtGate) Handler() uint64 {
	return uint64(g.OffsetLow) | uint64(g.OffsetMid)<<16 | uint64(g.OffsetHigh)<<32
}

func (g IdtGate) Encode() [16]byte {
	var buf [16]byte
	binary.LittleEndian.PutUint16(buf[0:2], g.OffsetLow)
	binary.LittleEndian.PutUint16(buf[2:4], g.Selector)
	buf[4] = g.IST
	buf[5] = g.TypeAttrs
	binary.LittleEndian.PutUint16(buf[6:8], g.OffsetMid)
	binary.LittleEndian.PutUint32(buf[8:12], g.OffsetHigh)
	binary.LittleEndian.PutUint32(buf[12:16], 0) // reserved
	return buf
}

func testIdtEntryEncoding() {
	// Handler at a typical kernel address
	handler := uint64(0xFFFF_8000_0010_0042)
	gate := NewIdtGate(handler, 0x08, 0, 0)

	assert(gate.Handler() == handler, "handler roundtrip")
	assert(gate.OffsetLow == 0x0042, "offset low")
	assert(gate.OffsetMid == 0x0010, "offset mid")
	assert(gate.OffsetHigh == 0xFFFF_8000, "offset high")
	assert(gate.TypeAttrs&0x80 != 0, "gate present")
	assert(gate.TypeAttrs&0x0F == 0x0E, "interrupt gate type")

	// Double fault with IST=1
	df := NewIdtGate(handler, 0x08, 1, 0)
	assert(df.IST == 1, "double fault IST")

	// Verify encoded size
	encoded := gate.Encode()
	assert(len(encoded) == 16, "IDT gate is 16 bytes")
}

// ── Multiboot Header ────────────────────────────────────────────────
// Multiboot1 header: magic + flags + checksum must sum to zero (uint32).

const (
	MultibootMagic = uint32(0x1BADB002)
	// Flags: bit 0 = align modules, bit 1 = provide memory map
	MultibootFlags = uint32(0x00000003)
)

type MultibootHeader struct {
	Magic    uint32
	Flags    uint32
	Checksum uint32
}

func NewMultibootHeader() MultibootHeader {
	// Checksum: magic + flags + checksum must equal 0 (mod 2^32)
	// Use ^(x-1) trick to avoid constant overflow in Go compiler
	checksum := ^(MultibootMagic + MultibootFlags) + 1
	return MultibootHeader{
		Magic:    MultibootMagic,
		Flags:    MultibootFlags,
		Checksum: checksum,
	}
}

func (h MultibootHeader) Valid() bool {
	return h.Magic+h.Flags+h.Checksum == 0
}

func (h MultibootHeader) Encode() [12]byte {
	var buf [12]byte
	binary.LittleEndian.PutUint32(buf[0:4], h.Magic)
	binary.LittleEndian.PutUint32(buf[4:8], h.Flags)
	binary.LittleEndian.PutUint32(buf[8:12], h.Checksum)
	return buf
}

func testMultibootHeader() {
	hdr := NewMultibootHeader()

	// Checksum validation: magic + flags + checksum == 0
	assert(hdr.Valid(), "multiboot checksum valid")
	sum := hdr.Magic + hdr.Flags + hdr.Checksum
	assert(sum == 0, "sum is zero")

	// Verify magic bytes in encoded form
	encoded := hdr.Encode()
	magic := binary.LittleEndian.Uint32(encoded[0:4])
	assert(magic == 0x1BADB002, "magic in encoded bytes")

	// Corrupted header fails validation
	bad := hdr
	bad.Checksum = 0
	assert(!bad.Valid(), "corrupted checksum detected")
}

// ── CR0/CR4 Bits for Long Mode Transition ───────────────────────────
// Transitioning from 32-bit protected mode to 64-bit long mode
// requires setting specific bits in CR0, CR4, and EFER MSR.

const (
	// CR0 bits
	CR0_PE uint64 = 1 << 0  // Protected mode enable
	CR0_MP uint64 = 1 << 1  // Monitor coprocessor
	CR0_ET uint64 = 1 << 4  // Extension type (always 1 on modern CPUs)
	CR0_NE uint64 = 1 << 5  // Numeric error (native FPU errors)
	CR0_WP uint64 = 1 << 16 // Write protect (kernel can't write read-only pages)
	CR0_AM uint64 = 1 << 18 // Alignment mask
	CR0_PG uint64 = 1 << 31 // Paging enable

	// CR4 bits
	CR4_PAE        uint64 = 1 << 5  // Physical address extension (REQUIRED for long mode)
	CR4_PGE        uint64 = 1 << 7  // Page global enable
	CR4_OSFXSR     uint64 = 1 << 9  // SSE support
	CR4_OSXMMEXCPT uint64 = 1 << 10 // SSE exceptions
	CR4_FSGSBASE   uint64 = 1 << 16 // FSGSBASE instructions
	CR4_OSXSAVE    uint64 = 1 << 18 // XSAVE/XRSTOR

	// EFER MSR (0xC0000080)
	EFER_SCE uint64 = 1 << 0  // SYSCALL enable
	EFER_LME uint64 = 1 << 8  // Long mode enable
	EFER_LMA uint64 = 1 << 10 // Long mode active (set by CPU)
	EFER_NXE uint64 = 1 << 11 // No-execute enable
)

func testCr0Cr4LongModeTransition() {
	// ── Start: 32-bit protected mode ──
	cr0 := CR0_PE | CR0_ET // protected mode, extension type
	cr4 := uint64(0)
	efer := uint64(0)

	// Step 1: Enable PAE in CR4 (required before long mode)
	cr4 |= CR4_PAE
	assert(cr4&CR4_PAE != 0, "PAE enabled")

	// Step 2: Load PML4 into CR3 (modeled as just recording it)
	cr3 := uint64(0x1000) // PML4 physical address
	assert(cr3&0xFFF == 0, "PML4 page-aligned")

	// Step 3: Set LME in EFER MSR
	efer |= EFER_LME
	assert(efer&EFER_LME != 0, "EFER.LME set")

	// Step 4: Enable paging in CR0 — this activates long mode
	cr0 |= CR0_PG | CR0_WP | CR0_NE | CR0_MP
	assert(cr0&CR0_PG != 0, "paging enabled")

	// CPU sets EFER.LMA automatically when paging + LME are both set
	efer |= EFER_LMA
	assert(efer&EFER_LMA != 0, "long mode active")

	// Step 5: Enable NX bit for security
	efer |= EFER_NXE | EFER_SCE
	assert(efer&EFER_NXE != 0, "NX enabled")

	// Final CR0 state check
	requiredCr0 := CR0_PE | CR0_PG | CR0_WP | CR0_NE
	assert(cr0&requiredCr0 == requiredCr0, "all required CR0 bits set")

	// Enable SSE support in CR4
	cr4 |= CR4_OSFXSR | CR4_OSXMMEXCPT | CR4_PGE
	assert(cr4&CR4_OSFXSR != 0, "SSE enabled")
}

// ── Segment Selectors ───────────────────────────────────────────────
// A segment selector is a 16-bit value: index(13) | TI(1) | RPL(2)

type SegmentSelector uint16

func NewSelector(index uint16, ti bool, rpl uint8) SegmentSelector {
	var tiBit uint16
	if ti {
		tiBit = 1 << 2
	}
	return SegmentSelector((index << 3) | tiBit | uint16(rpl&0x3))
}

func (s SegmentSelector) Index() uint16 { return uint16(s) >> 3 }
func (s SegmentSelector) TI() bool      { return uint16(s)&(1<<2) != 0 }
func (s SegmentSelector) RPL() uint8    { return uint8(uint16(s) & 0x3) }

func testSegmentSelectors() {
	// Kernel code: GDT index 1, TI=0 (GDT), RPL=0
	kcs := NewSelector(1, false, 0)
	assert(uint16(kcs) == 0x08, "kernel CS = 0x08")
	assert(kcs.Index() == 1, "kcs index")
	assert(!kcs.TI(), "kcs in GDT")
	assert(kcs.RPL() == 0, "kcs ring 0")

	// Kernel data: GDT index 2
	kds := NewSelector(2, false, 0)
	assert(uint16(kds) == 0x10, "kernel DS = 0x10")

	// User code: GDT index 3, RPL=3
	ucs := NewSelector(3, false, 3)
	assert(uint16(ucs) == 0x1B, "user CS = 0x1B")
	assert(ucs.RPL() == 3, "ucs ring 3")
}

// ── GDT Table Builder ───────────────────────────────────────────────

type GdtTable struct {
	entries []GdtEntry
}

func NewGdtTable() *GdtTable {
	return &GdtTable{entries: []GdtEntry{gdtNull()}} // index 0 = null
}

func (t *GdtTable) Add(e GdtEntry) SegmentSelector {
	idx := len(t.entries)
	t.entries = append(t.entries, e)
	return NewSelector(uint16(idx), false, e.DPL())
}

func (t *GdtTable) SizeBytes() int { return len(t.entries) * 8 }

func testGdtTable() {
	gdt := NewGdtTable()
	kcs := gdt.Add(gdtKernelCode64())
	kds := gdt.Add(gdtKernelData64())
	ucs := gdt.Add(gdtUserCode64())

	assert(uint16(kcs) == 0x08, "table kcs")
	assert(uint16(kds) == 0x10, "table kds")
	assert(ucs.RPL() == 3, "table ucs ring 3")
	assert(gdt.SizeBytes() == 32, "4 entries * 8 bytes")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
