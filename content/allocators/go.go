// Vidya — Allocators in Go
//
// Three allocation strategies: bump (arena), slab (fixed-size free list),
// and bitmap (page-level bit tracking). Go manages memory with a garbage
// collector, but these patterns matter when implementing systems that
// need deterministic allocation — kernels, compilers, embedded runtimes.
//
// Here we simulate raw memory with byte slices and implement the
// algorithms directly. The allocation logic is identical to what runs
// in real kernels and runtimes.

package main

import "fmt"

// ── Bump Allocator (Arena) ────────────────────────────────────────────
//
// A pointer advances with each allocation. Individual frees are
// impossible — reset frees everything at once. O(1) alloc.
// Use for: compiler AST nodes, per-request scratch space, parsing.

type BumpAllocator struct {
	memory     []byte
	offset     int
	allocCount int
}

func NewBumpAllocator(capacity int) *BumpAllocator {
	return &BumpAllocator{
		memory: make([]byte, capacity),
	}
}

// Alloc allocates size bytes with the given alignment.
// Returns the offset into the backing memory, or -1 if out of memory.
func (b *BumpAllocator) Alloc(size, align int) int {
	// Round up to alignment boundary
	aligned := (b.offset + align - 1) &^ (align - 1)
	end := aligned + size
	if end > len(b.memory) {
		return -1
	}
	b.offset = end
	b.allocCount++
	return aligned
}

// Reset frees all allocations at once.
func (b *BumpAllocator) Reset() {
	b.offset = 0
	b.allocCount = 0
}

func (b *BumpAllocator) Used() int { return b.offset }

func (b *BumpAllocator) String() string {
	return fmt.Sprintf("Bump[%d/%d bytes, %d allocs]", b.offset, len(b.memory), b.allocCount)
}

// ── Slab Allocator ────────────────────────────────────────────────────
//
// Pre-divides memory into fixed-size slots. Free slots are tracked with
// an embedded free list (stored as indices). Alloc = pop head.
// Free = push head. Both O(1). Zero external fragmentation.
// Used by the Linux kernel for task_struct, inode, dentry.

type SlabAllocator struct {
	memory    []byte
	slotSize  int
	count     int
	freeHead  int // index of first free slot, or -1
	next      []int
	allocated int
}

func NewSlabAllocator(slotSize, count int) *SlabAllocator {
	s := &SlabAllocator{
		memory:   make([]byte, slotSize*count),
		slotSize: slotSize,
		count:    count,
		next:     make([]int, count),
		freeHead: 0,
	}
	// Chain all slots into the free list
	for i := 0; i < count-1; i++ {
		s.next[i] = i + 1
	}
	s.next[count-1] = -1
	return s
}

// Alloc returns a slot index, or -1 if full.
func (s *SlabAllocator) Alloc() int {
	if s.freeHead == -1 {
		return -1
	}
	index := s.freeHead
	s.freeHead = s.next[index]
	s.next[index] = -1
	s.allocated++
	// Zero the slot
	offset := index * s.slotSize
	for i := offset; i < offset+s.slotSize; i++ {
		s.memory[i] = 0
	}
	return index
}

// Free returns a slot to the free list.
func (s *SlabAllocator) Free(index int) {
	s.next[index] = s.freeHead
	s.freeHead = index
	s.allocated--
}

// Write copies data into a slot.
func (s *SlabAllocator) Write(index int, data []byte) {
	offset := index * s.slotSize
	n := len(data)
	if n > s.slotSize {
		n = s.slotSize
	}
	copy(s.memory[offset:offset+n], data[:n])
}

// Read returns a copy of data from a slot.
func (s *SlabAllocator) Read(index, length int) []byte {
	offset := index * s.slotSize
	if length > s.slotSize {
		length = s.slotSize
	}
	result := make([]byte, length)
	copy(result, s.memory[offset:offset+length])
	return result
}

func (s *SlabAllocator) String() string {
	return fmt.Sprintf("Slab[%d/%d slots, %d bytes/slot]", s.allocated, s.count, s.slotSize)
}

// ── Bitmap Allocator ──────────────────────────────────────────────────
//
// One bit per page. Set = allocated, clear = free. A next_free hint
// accelerates sequential allocation by skipping known-allocated pages.
// Used by physical memory managers (PMMs) in kernels.

type BitmapAllocator struct {
	bitmap    []byte
	numPages  int
	nextFree  int
	allocated int
}

func NewBitmapAllocator(numPages int) *BitmapAllocator {
	return &BitmapAllocator{
		bitmap:   make([]byte, (numPages+7)/8),
		numPages: numPages,
	}
}

func (b *BitmapAllocator) test(page int) bool {
	return (b.bitmap[page/8]>>(page%8))&1 != 0
}

func (b *BitmapAllocator) set(page int) {
	b.bitmap[page/8] |= 1 << (page % 8)
}

func (b *BitmapAllocator) clear(page int) {
	b.bitmap[page/8] &^= 1 << (page % 8)
}

// Alloc returns a page index, or -1 if full.
func (b *BitmapAllocator) Alloc() int {
	// Search from hint
	for i := b.nextFree; i < b.numPages; i++ {
		if !b.test(i) {
			b.set(i)
			b.nextFree = i + 1
			b.allocated++
			return i
		}
	}
	// Wrap around
	for i := 0; i < b.nextFree; i++ {
		if !b.test(i) {
			b.set(i)
			b.nextFree = i + 1
			b.allocated++
			return i
		}
	}
	return -1
}

// Free releases a page and retracts the hint if appropriate.
func (b *BitmapAllocator) Free(page int) {
	b.clear(page)
	b.allocated--
	if page < b.nextFree {
		b.nextFree = page
	}
}

func (b *BitmapAllocator) String() string {
	return fmt.Sprintf("Bitmap[%d/%d pages]", b.allocated, b.numPages)
}

// ── Main ──────────────────────────────────────────────────────────────

func main() {
	fmt.Println("Allocators — three strategies for different patterns:\n")

	// Bump allocator
	fmt.Println("1. Bump Allocator (arena):")
	bump := NewBumpAllocator(4096)

	offsets := make([]int, 10)
	for i := range offsets {
		offsets[i] = bump.Alloc(24, 8)
		if offsets[i] == -1 {
			panic("bump alloc failed")
		}
		if offsets[i]%8 != 0 {
			panic("misaligned bump alloc")
		}
	}
	fmt.Printf("   Allocated 10 x 24 bytes: first 3 offsets = %v\n", offsets[:3])
	fmt.Printf("   %s\n", bump)

	// Alignment after odd-size alloc
	bump.Alloc(3, 1)
	alignedOff := bump.Alloc(8, 8)
	if alignedOff%8 != 0 {
		panic("misaligned after odd alloc")
	}
	fmt.Printf("   After 3-byte + 8-byte: offset %d (aligned: %v)\n", alignedOff, alignedOff%8 == 0)

	bump.Reset()
	if bump.Used() != 0 {
		panic("bump reset failed")
	}
	fmt.Printf("   After reset: %s\n", bump)

	reuse := bump.Alloc(16, 8)
	if reuse != 0 {
		panic("expected offset 0 after reset")
	}
	fmt.Printf("   Re-allocated after reset: offset %d\n\n", reuse)

	// Slab allocator
	fmt.Println("2. Slab Allocator (fixed-size objects):")
	slab := NewSlabAllocator(64, 16)

	slots := make([]int, 5)
	for i := range slots {
		slots[i] = slab.Alloc()
		if slots[i] == -1 {
			panic("slab alloc failed")
		}
	}
	fmt.Printf("   Allocated 5 slots: %v\n", slots)
	fmt.Printf("   %s\n", slab)

	slab.Free(slots[1])
	slab.Free(slots[3])
	fmt.Printf("   Freed slots %d and %d\n", slots[1], slots[3])
	fmt.Printf("   %s\n", slab)

	reused1 := slab.Alloc()
	reused2 := slab.Alloc()
	if reused1 != slots[3] {
		panic("expected LIFO reuse of last freed slot")
	}
	if reused2 != slots[1] {
		panic("expected LIFO reuse of second freed slot")
	}
	fmt.Printf("   Reallocated: slots %d and %d (reused)\n", reused1, reused2)

	slab.Write(reused1, []byte{0xDE, 0xAD, 0xBE, 0xEF})
	data := slab.Read(reused1, 4)
	if data[0] != 0xDE || data[1] != 0xAD || data[2] != 0xBE || data[3] != 0xEF {
		panic("slab read/write mismatch")
	}
	fmt.Printf("   Write/read: %02x%02x%02x%02x\n\n", data[0], data[1], data[2], data[3])

	// Bitmap allocator
	fmt.Println("3. Bitmap Allocator (page frames):")
	bmp := NewBitmapAllocator(64)

	p0 := bmp.Alloc()
	p1 := bmp.Alloc()
	p2 := bmp.Alloc()
	if p0 != 0 || p1 != 1 || p2 != 2 {
		panic("sequential bitmap allocation failed")
	}
	fmt.Printf("   Allocated pages: %d, %d, %d\n", p0, p1, p2)
	fmt.Printf("   %s\n", bmp)

	bmp.Free(1)
	fmt.Println("   Freed page 1")
	reusedPage := bmp.Alloc()
	if reusedPage != 1 {
		panic("expected reuse of freed page 1")
	}
	fmt.Printf("   Reallocated: page %d (reused via hint retraction)\n", reusedPage)

	p3 := bmp.Alloc()
	if p3 != 3 {
		panic("expected page 3 after hint advancement")
	}
	fmt.Printf("   Next alloc: page %d\n", p3)
	fmt.Printf("   %s\n", bmp)

	// Fill all remaining
	for bmp.Alloc() != -1 {
	}
	if bmp.allocated != 64 {
		panic("expected all pages allocated")
	}
	fmt.Printf("   Filled all 64 pages, next alloc = -1: %v\n", bmp.Alloc() == -1)

	fmt.Println("\nAll tests passed.")
}
