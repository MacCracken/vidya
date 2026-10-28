// Vidya — Bindless Resources in Go
//
// In-memory descriptor table — "one global table per frame" pattern.

package main

import "fmt"

const TableCap = 64

// A handle is (generation << 8) | slot. Free bumps the slot's generation,
// so a handle kept after Free no longer matches and reads as invalid
// instead of silently resolving to whatever descriptor reused the slot —
// the concept's "generation counter in the handle" best practice. It also
// makes a double free detectable instead of corrupting the free list.
const slotBits = 8

type Table struct {
	slots     [TableCap]uint64
	freeLinks [TableCap]uint32
	gens      [TableCap]uint32
	live      [TableCap]bool
	nextID    uint32
	freeHead  uint32
}

func newTable() *Table { return &Table{nextID: 1} }

func handle(slot, gen uint32) uint32 { return gen<<slotBits | slot }

// liveSlot returns the slot a handle names, if the handle is still current.
func (t *Table) liveSlot(h uint32) (uint32, bool) {
	slot := h & (1<<slotBits - 1)
	if slot == 0 || slot >= TableCap || !t.live[slot] || t.gens[slot] != h>>slotBits {
		return 0, false
	}
	return slot, true
}

func (t *Table) Alloc(desc uint64) uint32 {
	var id uint32
	if t.freeHead != 0 {
		id = t.freeHead
		t.freeHead = t.freeLinks[id]
	} else {
		if t.nextID >= TableCap {
			return 0
		}
		id = t.nextID
		t.nextID++
	}
	t.slots[id] = desc
	t.live[id] = true
	return handle(id, t.gens[id])
}

func (t *Table) Lookup(h uint32) uint64 {
	slot, ok := t.liveSlot(h)
	if !ok {
		return 0
	}
	return t.slots[slot]
}

func (t *Table) Update(h uint32, desc uint64) bool {
	slot, ok := t.liveSlot(h)
	if !ok {
		return false
	}
	t.slots[slot] = desc
	return true
}

func (t *Table) Free(h uint32) bool {
	slot, ok := t.liveSlot(h)
	if !ok {
		return false // stale handle or double free
	}
	t.live[slot] = false
	t.gens[slot]++
	t.freeLinks[slot] = t.freeHead
	t.freeHead = slot
	t.slots[slot] = 0
	return true
}

func eq[T comparable](got, want T, label string) {
	checks++
	if got != want {
		panic(fmt.Sprintf("%s: got %v want %v", label, got, want))
	}
}

func tru(b bool, label string) {
	checks++
	if !b {
		panic(label)
	}
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
	t := newTable()

	id1 := t.Alloc(0x1111111111111111)
	id2 := t.Alloc(0x2222222222222222)
	id3 := t.Alloc(0x3333333333333333)
	eq(id1, uint32(1), "id1")
	eq(id2, uint32(2), "id2")
	eq(id3, uint32(3), "id3")

	eq(t.Lookup(0), uint64(0), "slot 0")

	eq(t.Lookup(id1), uint64(0x1111111111111111), "lookup1")
	eq(t.Lookup(id2), uint64(0x2222222222222222), "lookup2")
	eq(t.Lookup(id3), uint64(0x3333333333333333), "lookup3")

	check(t.Update(id2, 0xAAAAAAAAAAAAAAAA), "update")
	eq(t.Lookup(id2), uint64(0xAAAAAAAAAAAAAAAA), "id2 new")
	eq(t.Lookup(id1), uint64(0x1111111111111111), "id1 unchanged")
	eq(t.Lookup(id3), uint64(0x3333333333333333), "id3 unchanged")

	t.Free(id2)
	eq(t.Lookup(id2), uint64(0), "freed reads 0")
	id4 := t.Alloc(0x4444444444444444)
	eq(id4&(1<<slotBits-1), id2, "reused slot")
	tru(id4 != id2, "reused slot gets a new generation")
	eq(t.Lookup(id4), uint64(0x4444444444444444), "reused slot desc")
	eq(t.Lookup(id2), uint64(0), "stale handle does not see the new descriptor")
	tru(!t.Free(id2), "double free rejected")

	t2 := newTable()
	for i := uint64(1); i < TableCap; i++ {
		t2.Alloc(i)
	}
	eq(t2.Alloc(0xDEADBEEF), uint32(0), "exhausted")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("bindless_resources: %d/%d ok\n", checks, checks)
}
