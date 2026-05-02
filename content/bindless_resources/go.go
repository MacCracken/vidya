// Vidya — Bindless Resources in Go
//
// In-memory descriptor table — "one global table per frame" pattern.

package main

import "fmt"

const TableCap = 64

type Table struct {
	slots     [TableCap]uint64
	freeLinks [TableCap]uint32
	nextID    uint32
	freeHead  uint32
}

func newTable() *Table { return &Table{nextID: 1} }

func (t *Table) Alloc(desc uint64) uint32 {
	if t.freeHead != 0 {
		id := t.freeHead
		t.freeHead = t.freeLinks[id]
		t.slots[id] = desc
		return id
	}
	if t.nextID >= TableCap {
		return 0
	}
	id := t.nextID
	t.nextID++
	t.slots[id] = desc
	return id
}

func (t *Table) Lookup(id uint32) uint64 {
	if id == 0 || id >= TableCap {
		return 0
	}
	return t.slots[id]
}

func (t *Table) Update(id uint32, desc uint64) bool {
	if id == 0 || id >= TableCap {
		return false
	}
	t.slots[id] = desc
	return true
}

func (t *Table) Free(id uint32) bool {
	if id == 0 || id >= TableCap {
		return false
	}
	t.freeLinks[id] = t.freeHead
	t.freeHead = id
	t.slots[id] = 0
	return true
}

func eq[T comparable](got, want T, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %v want %v", label, got, want))
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

	if !t.Update(id2, 0xAAAAAAAAAAAAAAAA) {
		panic("update")
	}
	eq(t.Lookup(id2), uint64(0xAAAAAAAAAAAAAAAA), "id2 new")
	eq(t.Lookup(id1), uint64(0x1111111111111111), "id1 unchanged")
	eq(t.Lookup(id3), uint64(0x3333333333333333), "id3 unchanged")

	t.Free(id2)
	eq(t.Lookup(id2), uint64(0), "freed reads 0")
	id4 := t.Alloc(0x4444444444444444)
	eq(id4, id2, "reused slot id")
	eq(t.Lookup(id4), uint64(0x4444444444444444), "reused slot desc")

	t2 := newTable()
	for i := uint64(1); i < TableCap; i++ {
		t2.Alloc(i)
	}
	eq(t2.Alloc(0xDEADBEEF), uint32(0), "exhausted")

	fmt.Println("bindless_resources: 15/15 ok")
}
