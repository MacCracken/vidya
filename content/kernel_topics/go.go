// Vidya — Kernel Topics in Go
//
// Go isn't used for kernel code (it needs a runtime), but it's
// excellent for kernel tooling, testing, and simulation. These
// examples model kernel data structures — page tables, interrupt
// descriptors, MMIO registers, and ABIs — in Go's type system.

package main

import (
	"fmt"
)

func main() {
	testPageTableEntry()
	testVirtualAddressDecompose()
	testMmioRegister()
	testInterruptDescriptorTable()
	testAbiCallingConvention()
	testGdtEntry()

	fmt.Println("All kernel topics examples passed.")
}

// ── Page Table Entry ──────────────────────────────────────────────────
const (
	PTE_PRESENT    uint64 = 1 << 0
	PTE_WRITABLE   uint64 = 1 << 1
	PTE_USER       uint64 = 1 << 2
	PTE_HUGE_PAGE  uint64 = 1 << 7
	PTE_NO_EXECUTE uint64 = 1 << 63
	PTE_ADDR_MASK  uint64 = 0x000F_FFFF_FFFF_F000
)

type PageTableEntry uint64

func NewPTE(physAddr, flags uint64) PageTableEntry {
	if physAddr & ^PTE_ADDR_MASK != 0 {
		panic("address not 4KB aligned")
	}
	return PageTableEntry((physAddr & PTE_ADDR_MASK) | flags)
}

func (p PageTableEntry) Present() bool    { return uint64(p)&PTE_PRESENT != 0 }
func (p PageTableEntry) Writable() bool   { return uint64(p)&PTE_WRITABLE != 0 }
func (p PageTableEntry) User() bool       { return uint64(p)&PTE_USER != 0 }
func (p PageTableEntry) NoExecute() bool  { return uint64(p)&PTE_NO_EXECUTE != 0 }
func (p PageTableEntry) PhysAddr() uint64 { return uint64(p) & PTE_ADDR_MASK }

func testPageTableEntry() {
	code := NewPTE(0x1000, PTE_PRESENT)
	assert(code.Present(), "code present")
	assert(!code.Writable(), "code not writable")
	assert(code.PhysAddr() == 0x1000, "code addr")

	data := NewPTE(0x200_000, PTE_PRESENT|PTE_WRITABLE|PTE_USER|PTE_NO_EXECUTE)
	assert(data.Writable() && data.User() && data.NoExecute(), "data flags")

	unmapped := PageTableEntry(0)
	assert(!unmapped.Present(), "unmapped")
}

// ── Virtual Address Decomposition ─────────────────────────────────────
type VAddrParts struct {
	PML4, PDPT, PD, PT uint16
	Offset              uint16
}

func DecomposeVAddr(vaddr uint64) VAddrParts {
	return VAddrParts{
		PML4:   uint16((vaddr >> 39) & 0x1FF),
		PDPT:   uint16((vaddr >> 30) & 0x1FF),
		PD:     uint16((vaddr >> 21) & 0x1FF),
		PT:     uint16((vaddr >> 12) & 0x1FF),
		Offset: uint16(vaddr & 0xFFF),
	}
}

func testVirtualAddressDecompose() {
	parts := DecomposeVAddr(0x0000_7FFF_FFFF_F000)
	assert(parts.PML4 == 0xFF, "pml4")
	assert(parts.PDPT == 0x1FF, "pdpt")
	assert(parts.PD == 0x1FF, "pd")
	assert(parts.PT == 0x1FF, "pt")
	assert(parts.Offset == 0, "offset")

	kernel := DecomposeVAddr(0xFFFF_8000_0000_0000)
	assert(kernel.PML4 == 256, "kernel pml4")
}

// ── MMIO Register ─────────────────────────────────────────────────────
type MmioRegister struct {
	Name  string
	value uint32
}

func (r *MmioRegister) Read() uint32       { return r.value }
func (r *MmioRegister) Write(val uint32)   { r.value = val }
func (r *MmioRegister) SetBits(mask uint32)   { r.Write(r.Read() | mask) }
func (r *MmioRegister) ClearBits(mask uint32) { r.Write(r.Read() & ^mask) }

func testMmioRegister() {
	ctrl := &MmioRegister{Name: "UART_CTRL"}
	ctrl.SetBits(0b11)
	assert(ctrl.Read() == 0b11, "set TX+RX")

	ctrl.ClearBits(0b10)
	assert(ctrl.Read() == 0b01, "clear RX")
}

// ── Interrupt Descriptor Table ────────────────────────────────────────
type InterruptHandler func(vector uint8) string

type IdtEntry struct {
	Vector  uint8
	Name    string
	Handler InterruptHandler
	IST     uint8
}

type IDT struct {
	entries map[uint8]IdtEntry
}

func NewIDT() *IDT {
	return &IDT{entries: make(map[uint8]IdtEntry)}
}

func (idt *IDT) Register(vector uint8, name string, ist uint8, handler InterruptHandler) {
	idt.entries[vector] = IdtEntry{vector, name, handler, ist}
}

func (idt *IDT) Dispatch(vector uint8) (string, bool) {
	entry, ok := idt.entries[vector]
	if !ok {
		return "", false
	}
	return entry.Handler(entry.Vector), true
}

func testInterruptDescriptorTable() {
	idt := NewIDT()
	idt.Register(0, "Divide Error", 0, func(v uint8) string { return "handled: #DE" })
	idt.Register(8, "Double Fault", 1, func(v uint8) string { return "handled: #DF" })
	idt.Register(14, "Page Fault", 0, func(v uint8) string { return "handled: #PF" })
	idt.Register(32, "Timer", 0, func(v uint8) string { return "handled: timer" })

	r, ok := idt.Dispatch(0)
	assert(ok && r == "handled: #DE", "dispatch #DE")

	r, ok = idt.Dispatch(14)
	assert(ok && r == "handled: #PF", "dispatch #PF")

	_, ok = idt.Dispatch(255)
	assert(!ok, "unregistered")

	assert(idt.entries[8].IST > 0, "double fault IST")
}

// ── ABI / Calling Convention ──────────────────────────────────────────
func testAbiCallingConvention() {
	sysvRegs := []string{"rdi", "rsi", "rdx", "rcx", "r8", "r9"}
	assert(sysvRegs[0] == "rdi", "sysv arg0")
	assert(sysvRegs[5] == "r9", "sysv arg5")
	assert(len(sysvRegs) == 6, "sysv count")

	// Linux syscall: rax=number, args in rdi/rsi/rdx/r10/r8/r9
	syscallRegs := []string{"rax", "rdi", "rsi", "rdx", "r10", "r8", "r9"}
	assert(syscallRegs[0] == "rax", "syscall number reg")
	assert(syscallRegs[4] == "r10", "r10 not rcx")
}

// ── GDT Entry ─────────────────────────────────────────────────────────
type GdtEntry uint64

func (g GdtEntry) Present() bool  { return (uint64(g)>>47)&1 == 1 }
func (g GdtEntry) DPL() uint8     { return uint8((uint64(g) >> 45) & 0x3) }
func (g GdtEntry) LongMode() bool { return (uint64(g)>>53)&1 == 1 }

func testGdtEntry() {
	null := GdtEntry(0)
	assert(!null.Present(), "null not present")

	kernelCode := GdtEntry(0x00AF_9A00_0000_FFFF)
	assert(kernelCode.Present(), "code present")
	assert(kernelCode.DPL() == 0, "code ring 0")
	assert(kernelCode.LongMode(), "code long mode")

	kernelData := GdtEntry(0x00CF_9200_0000_FFFF)
	assert(kernelData.Present(), "data present")
	assert(kernelData.DPL() == 0, "data ring 0")
}

// ── Helpers ───────────────────────────────────────────────────────────
func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
