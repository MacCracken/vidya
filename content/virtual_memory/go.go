// Vidya — Virtual Memory in Go
//
// Simulates x86_64 virtual memory management:
//   1. Page table entry (PTE) encoding with bit manipulation
//   2. 4-level page walk: PML4 -> PDPT -> PD -> PT -> frame
//   3. Virtual address decomposition into index fields
//   4. TLB cache with hit/miss tracking
//   5. Demand paging — page fault on unmapped access
//   6. Page permission checking (read/write/execute/user)
//
// In hardware, the MMU walks page tables and the TLB caches results.
// Here we simulate the entire translation pipeline in software.

package main

import "fmt"

func main() {
	testPTEEncoding()
	testAddressDecomposition()
	testPageTableWalk()
	testTLBCache()
	testDemandPaging()
	testPermissionChecks()

	fmt.Println("All virtual memory examples passed.")
}

// ── Constants ────────────────────────────────────────────────────────

const (
	PageSize       = 4096
	PageShift      = 12
	EntriesPerTable = 512 // 2^9 entries per level

	// PTE flag bits — matches x86_64 hardware
	PTE_PRESENT    uint64 = 1 << 0
	PTE_WRITABLE   uint64 = 1 << 1
	PTE_USER       uint64 = 1 << 2
	PTE_ACCESSED   uint64 = 1 << 5
	PTE_DIRTY      uint64 = 1 << 6
	PTE_HUGE_PAGE  uint64 = 1 << 7
	PTE_NO_EXECUTE uint64 = 1 << 63
	PTE_ADDR_MASK  uint64 = 0x000F_FFFF_FFFF_F000 // bits 12-51
)

// ── Page Table Entry ─────────────────────────────────────────────────
// A PTE is a 64-bit value encoding a physical frame address and flags.
// Bits 12-51 hold the physical address (40 bits = 1 TB addressable).
// Bits 0-11 and 63 hold permission/status flags.

type PTE uint64

func NewPTE(physAddr, flags uint64) PTE {
	if physAddr&^PTE_ADDR_MASK != 0 {
		panic("address not 4KB aligned or out of range")
	}
	return PTE((physAddr & PTE_ADDR_MASK) | flags)
}

func (p PTE) Present() bool    { return uint64(p)&PTE_PRESENT != 0 }
func (p PTE) Writable() bool   { return uint64(p)&PTE_WRITABLE != 0 }
func (p PTE) User() bool       { return uint64(p)&PTE_USER != 0 }
func (p PTE) Accessed() bool   { return uint64(p)&PTE_ACCESSED != 0 }
func (p PTE) Dirty() bool      { return uint64(p)&PTE_DIRTY != 0 }
func (p PTE) NoExecute() bool  { return uint64(p)&PTE_NO_EXECUTE != 0 }
func (p PTE) PhysAddr() uint64 { return uint64(p) & PTE_ADDR_MASK }
func (p PTE) Flags() uint64    { return uint64(p) & ^PTE_ADDR_MASK }

func testPTEEncoding() {
	fmt.Println("1. Page table entry encoding:")

	// Code page: present, not writable, executable
	code := NewPTE(0x1000, PTE_PRESENT)
	assert(code.Present(), "code present")
	assert(!code.Writable(), "code read-only")
	assert(!code.NoExecute(), "code executable")
	assert(code.PhysAddr() == 0x1000, "code phys addr")

	// Data page: present, writable, no-execute
	data := NewPTE(0x200_000, PTE_PRESENT|PTE_WRITABLE|PTE_USER|PTE_NO_EXECUTE)
	assert(data.Writable(), "data writable")
	assert(data.User(), "data user-accessible")
	assert(data.NoExecute(), "data no-execute")
	assert(data.PhysAddr() == 0x200_000, "data phys addr")

	// Unmapped page: no flags set
	unmapped := PTE(0)
	assert(!unmapped.Present(), "unmapped not present")

	// Dirty/accessed bits — set by hardware on access
	dirty := NewPTE(0x3000, PTE_PRESENT|PTE_WRITABLE|PTE_ACCESSED|PTE_DIRTY)
	assert(dirty.Accessed(), "accessed set")
	assert(dirty.Dirty(), "dirty set")

	fmt.Printf("   Code PTE:     0x%016X (P=%v W=%v NX=%v)\n",
		uint64(code), code.Present(), code.Writable(), code.NoExecute())
	fmt.Printf("   Data PTE:     0x%016X (P=%v W=%v NX=%v)\n",
		uint64(data), data.Present(), data.Writable(), data.NoExecute())
	fmt.Printf("   Unmapped PTE: 0x%016X (P=%v)\n", uint64(unmapped), unmapped.Present())
}

// ── Virtual Address Decomposition ────────────────────────────────────
// x86_64 uses 48-bit virtual addresses (bits 0-47), with bits 48-63
// being a sign extension of bit 47. The 48 bits are split:
//   [47:39] PML4 index   (9 bits, 512 entries)
//   [38:30] PDPT index   (9 bits, 512 entries)
//   [29:21] PD index     (9 bits, 512 entries)
//   [20:12] PT index     (9 bits, 512 entries)
//   [11:0]  Page offset  (12 bits, 4096 bytes)

type VAddrParts struct {
	PML4   uint16
	PDPT   uint16
	PD     uint16
	PT     uint16
	Offset uint16
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

// RecomposeVAddr reconstructs a virtual address from its parts.
// If PML4 index >= 256, sign-extends to canonical form (kernel space).
func RecomposeVAddr(p VAddrParts) uint64 {
	addr := uint64(p.PML4)<<39 |
		uint64(p.PDPT)<<30 |
		uint64(p.PD)<<21 |
		uint64(p.PT)<<12 |
		uint64(p.Offset)
	// Sign-extend bit 47 to bits 48-63 for canonical form
	if addr&(1<<47) != 0 {
		addr |= 0xFFFF_0000_0000_0000
	}
	return addr
}

func testAddressDecomposition() {
	fmt.Println("\n2. Virtual address decomposition:")

	// User-space address near end of user range
	p := DecomposeVAddr(0x0000_7FFF_FFFF_F000)
	assert(p.PML4 == 0xFF, "pml4=0xFF")
	assert(p.PDPT == 0x1FF, "pdpt=0x1FF")
	assert(p.PD == 0x1FF, "pd=0x1FF")
	assert(p.PT == 0x1FF, "pt=0x1FF")
	assert(p.Offset == 0, "offset=0")

	// Kernel-space address (canonical high half)
	k := DecomposeVAddr(0xFFFF_8000_0000_0000)
	assert(k.PML4 == 256, "kernel pml4=256")
	assert(k.PDPT == 0, "kernel pdpt=0")

	// Typical code address
	c := DecomposeVAddr(0x0000_0000_0040_0078)
	assert(c.PML4 == 0, "code pml4=0")
	assert(c.PD == 2, "code pd=2")
	assert(c.Offset == 0x78, "code offset=0x78")

	// Roundtrip: decompose and recompose must match
	testAddr := uint64(0x0000_7FFF_DEAD_B000)
	rt := RecomposeVAddr(DecomposeVAddr(testAddr))
	assert(rt == testAddr, "roundtrip user address")

	kernelAddr := uint64(0xFFFF_8000_0010_0000)
	rtk := RecomposeVAddr(DecomposeVAddr(kernelAddr))
	assert(rtk == kernelAddr, "roundtrip kernel address")

	fmt.Printf("   0x%016X -> PML4[%3d] PDPT[%3d] PD[%3d] PT[%3d] +0x%03X\n",
		uint64(0x0000_7FFF_FFFF_F000), p.PML4, p.PDPT, p.PD, p.PT, p.Offset)
	fmt.Printf("   0x%016X -> PML4[%3d] PDPT[%3d] PD[%3d] PT[%3d] +0x%03X\n",
		uint64(0xFFFF_8000_0000_0000), k.PML4, k.PDPT, k.PD, k.PT, k.Offset)
	fmt.Printf("   0x%016X -> PML4[%3d] PDPT[%3d] PD[%3d] PT[%3d] +0x%03X\n",
		uint64(0x0000_0000_0040_0078), c.PML4, c.PDPT, c.PD, c.PT, c.Offset)
}

// ── Page Table (one level) ───────────────────────────────────────────

type PageTable struct {
	entries [EntriesPerTable]PTE
}

// ── TLB Cache ────────────────────────────────────────────────────────
// The Translation Lookaside Buffer caches recent virtual-to-physical
// mappings. On a real CPU, TLB misses trigger hardware page walks.
// We simulate direct-mapped TLB with a configurable size.

const TLBCapacity = 64

type TLBEntry struct {
	vpage  uint64 // virtual page (vaddr with offset zeroed)
	pframe uint64 // physical frame address
	valid  bool
}

type TLB struct {
	entries [TLBCapacity]TLBEntry
	hits    int
	misses  int
}

func (t *TLB) Lookup(vpage uint64) (uint64, bool) {
	// Direct-mapped: index by low bits of vpage
	idx := (vpage >> PageShift) % TLBCapacity
	e := &t.entries[idx]
	if e.valid && e.vpage == vpage {
		t.hits++
		return e.pframe, true
	}
	t.misses++
	return 0, false
}

func (t *TLB) Insert(vpage, pframe uint64) {
	idx := (vpage >> PageShift) % TLBCapacity
	t.entries[idx] = TLBEntry{vpage, pframe, true}
}

func (t *TLB) Invalidate(vpage uint64) {
	idx := (vpage >> PageShift) % TLBCapacity
	if t.entries[idx].vpage == vpage {
		t.entries[idx].valid = false
	}
}

func (t *TLB) Flush() {
	for i := range t.entries {
		t.entries[i].valid = false
	}
}

func (t *TLB) HitRate() float64 {
	total := t.hits + t.misses
	if total == 0 {
		return 0
	}
	return float64(t.hits) / float64(total) * 100
}

// ── MMU Simulation ───────────────────────────────────────────────────

type MMU struct {
	tables     map[uint64]*PageTable // "physical address" -> table
	cr3        uint64                // PML4 physical address
	nextFrame  uint64                // bump allocator
	tlb        TLB
	pageFaults int
}

func NewMMU() *MMU {
	mmu := &MMU{
		tables:    make(map[uint64]*PageTable),
		nextFrame: 0x1000, // skip null page
	}
	mmu.cr3 = mmu.allocTable()
	return mmu
}

func (m *MMU) allocTable() uint64 {
	addr := m.nextFrame
	m.nextFrame += PageSize
	m.tables[addr] = &PageTable{}
	return addr
}

// ensureEntry ensures an intermediate page table entry exists at the
// given index. Returns the physical address of the next-level table.
func (m *MMU) ensureEntry(tableAddr uint64, index int, flags uint64) uint64 {
	t := m.tables[tableAddr]
	if t.entries[index].Present() {
		return t.entries[index].PhysAddr()
	}
	newAddr := m.allocTable()
	t.entries[index] = NewPTE(newAddr, flags|PTE_PRESENT)
	return newAddr
}

func (m *MMU) MapPage(vaddr, physFrame, flags uint64) {
	p := DecomposeVAddr(vaddr)

	pdptAddr := m.ensureEntry(m.cr3, int(p.PML4), flags)
	pdAddr := m.ensureEntry(pdptAddr, int(p.PDPT), flags)
	ptAddr := m.ensureEntry(pdAddr, int(p.PD), flags)

	pt := m.tables[ptAddr]
	pt.entries[p.PT] = NewPTE(physFrame, flags|PTE_PRESENT)

	// Invalidate TLB for this page — the mapping changed
	m.tlb.Invalidate(vaddr & ^uint64(0xFFF))
}

// Translate performs a full virtual-to-physical translation.
// Returns (physAddr, true) on success, (0, false) on page fault.
func (m *MMU) Translate(vaddr uint64) (uint64, bool) {
	vpage := vaddr & ^uint64(0xFFF)
	offset := vaddr & 0xFFF

	// TLB fast path
	if pframe, ok := m.tlb.Lookup(vpage); ok {
		return pframe | offset, true
	}

	// Page table walk — 4 levels
	p := DecomposeVAddr(vaddr)
	indices := [4]int{int(p.PML4), int(p.PDPT), int(p.PD), int(p.PT)}

	current := m.cr3
	for level := 0; level < 4; level++ {
		t, ok := m.tables[current]
		if !ok || !t.entries[indices[level]].Present() {
			m.pageFaults++
			return 0, false
		}
		current = t.entries[indices[level]].PhysAddr()
	}

	// Walk succeeded — cache in TLB
	m.tlb.Insert(vpage, current)
	return current | offset, true
}

func testPageTableWalk() {
	fmt.Println("\n3. 4-level page table walk:")

	mmu := NewMMU()
	flags := PTE_PRESENT | PTE_WRITABLE | PTE_USER

	// Map several pages
	type mapping struct {
		vaddr, paddr uint64
		label        string
	}
	mappings := []mapping{
		{0x00400000, 0x00200000, "code"},
		{0x00401000, 0x00201000, "code page 2"},
		{0x00600000, 0x00300000, "data"},
		{0x7FFFF000, 0x00100000, "stack top"},
	}
	for _, m := range mappings {
		mmu.MapPage(m.vaddr, m.paddr, flags)
		fmt.Printf("   mapped 0x%08X -> 0x%08X (%s)\n", m.vaddr, m.paddr, m.label)
	}

	// Translate with offsets
	phys, ok := mmu.Translate(0x00400078)
	assert(ok && phys == 0x00200078, "code+offset translation")

	phys, ok = mmu.Translate(0x00600100)
	assert(ok && phys == 0x00300100, "data translation")

	phys, ok = mmu.Translate(0x7FFFF800)
	assert(ok && phys == 0x00100800, "stack translation")

	// Unmapped address -> page fault
	_, ok = mmu.Translate(0x00500000)
	assert(!ok, "unmapped -> page fault")
	assert(mmu.pageFaults >= 1, "page fault counted")

	fmt.Printf("   0x00400078 -> 0x%08X (code + 0x78 offset)\n", uint64(0x00200078))
	fmt.Printf("   0x00500000 -> PAGE FAULT (unmapped)\n")
	fmt.Printf("   Page tables allocated: %d\n", len(mmu.tables))
}

func testTLBCache() {
	fmt.Println("\n4. TLB cache simulation:")

	mmu := NewMMU()
	flags := PTE_PRESENT | PTE_WRITABLE | PTE_USER
	mmu.MapPage(0x1000, 0xA000, flags)
	mmu.MapPage(0x2000, 0xB000, flags)

	// First access — TLB miss, page walk
	mmu.Translate(0x1000)
	assert(mmu.tlb.misses == 1, "first access is miss")
	assert(mmu.tlb.hits == 0, "no hits yet")

	// Second access — TLB hit
	mmu.Translate(0x1234)
	assert(mmu.tlb.hits == 1, "second access hits TLB")

	// Different page — miss
	mmu.Translate(0x2000)
	assert(mmu.tlb.misses == 2, "different page is miss")

	// Same page again — hit
	mmu.Translate(0x2FFF)
	assert(mmu.tlb.hits == 2, "same page is hit")

	// Flush TLB (like writing CR3 or INVLPG)
	mmu.tlb.Flush()
	mmu.Translate(0x1000)
	assert(mmu.tlb.misses == 3, "after flush is miss")

	fmt.Printf("   Hits: %d, Misses: %d, Hit rate: %.0f%%\n",
		mmu.tlb.hits, mmu.tlb.misses, mmu.tlb.HitRate())
	fmt.Println("   TLB avoids expensive 4-level page walks on repeated access")
}

func testDemandPaging() {
	fmt.Println("\n5. Demand paging simulation:")

	mmu := NewMMU()
	flags := PTE_PRESENT | PTE_WRITABLE | PTE_USER

	// Access before mapping — page fault
	_, ok := mmu.Translate(0x10000)
	assert(!ok, "demand: unmapped -> fault")
	faultsBefore := mmu.pageFaults

	// Simulate demand paging: fault handler maps the page
	mmu.MapPage(0x10000, 0x50000, flags)

	// Now access succeeds
	phys, ok := mmu.Translate(0x10000)
	assert(ok && phys == 0x50000, "demand: mapped after fault")
	assert(mmu.pageFaults == faultsBefore, "no new fault after mapping")

	fmt.Println("   Access 0x10000 -> PAGE FAULT (not mapped)")
	fmt.Println("   Handler maps 0x10000 -> 0x50000")
	fmt.Println("   Retry 0x10000 -> 0x50000 (success)")
}

func testPermissionChecks() {
	fmt.Println("\n6. Page permission encoding:")

	// Kernel code: present, not writable, executable, not user
	kernelCode := NewPTE(0x100000, PTE_PRESENT)
	assert(kernelCode.Present(), "kernel code present")
	assert(!kernelCode.Writable(), "kernel code read-only")
	assert(!kernelCode.User(), "kernel code ring 0 only")
	assert(!kernelCode.NoExecute(), "kernel code executable")

	// User data: present, writable, user, no-execute (W^X)
	userData := NewPTE(0x200000, PTE_PRESENT|PTE_WRITABLE|PTE_USER|PTE_NO_EXECUTE)
	assert(userData.Writable(), "user data writable")
	assert(userData.User(), "user data accessible")
	assert(userData.NoExecute(), "user data NX (W^X policy)")

	// Guard page: not present (any access faults)
	guard := PTE(0)
	assert(!guard.Present(), "guard page not present")

	fmt.Printf("   Kernel code: P=%v W=%v U=%v NX=%v\n",
		kernelCode.Present(), kernelCode.Writable(), kernelCode.User(), kernelCode.NoExecute())
	fmt.Printf("   User data:   P=%v W=%v U=%v NX=%v\n",
		userData.Present(), userData.Writable(), userData.User(), userData.NoExecute())
	fmt.Printf("   Guard page:  P=%v (any access -> #PF)\n", guard.Present())
	fmt.Println("   W^X: pages are either writable OR executable, never both")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
