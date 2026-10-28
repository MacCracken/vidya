// Vidya — Page Management in Go
//
// Fixed-size 4KB pages, single file. Header at offset 0; page 0 reserved
// as null sentinel; data pages at PAGE_SZ + num * PAGE_SZ. Free list is
// a stack with `next` pointer at byte offset 8 of each freed page.
// Mirrors the cyrius reference's test surface exactly.

package main

import (
	"encoding/binary"
	"fmt"
	"os"
)

const (
	PageSz    = 4096
	Magic     = uint32(0x50415452)
	HPgCount  = 8
	HFreeHead = 16
	FPNext    = 8
)

type Header struct {
	PageCount uint64
	FreeHead  uint64
}

func pageOffset(num uint64) int64 {
	return int64(PageSz + num*PageSz)
}

func hdrToBytes(h *Header) []byte {
	buf := make([]byte, PageSz)
	binary.LittleEndian.PutUint32(buf[0:4], Magic)
	binary.LittleEndian.PutUint64(buf[HPgCount:HPgCount+8], h.PageCount)
	binary.LittleEndian.PutUint64(buf[HFreeHead:HFreeHead+8], h.FreeHead)
	return buf
}

func hdrVerify(buf []byte) bool {
	return binary.LittleEndian.Uint32(buf[0:4]) == Magic
}

func hdrLoad(buf []byte) Header {
	return Header{
		PageCount: binary.LittleEndian.Uint64(buf[HPgCount : HPgCount+8]),
		FreeHead:  binary.LittleEndian.Uint64(buf[HFreeHead : HFreeHead+8]),
	}
}

func pageRead(f *os.File, num uint64) ([]byte, error) {
	buf := make([]byte, PageSz)
	if _, err := f.Seek(pageOffset(num), 0); err != nil {
		return nil, err
	}
	if _, err := f.Read(buf); err != nil {
		return nil, err
	}
	return buf, nil
}

func pageWrite(f *os.File, num uint64, buf []byte) error {
	if _, err := f.Seek(pageOffset(num), 0); err != nil {
		return err
	}
	_, err := f.Write(buf)
	return err
}

// hdrSync writes the header page back. PageCount and FreeHead live in the
// file, not just in memory: without this, reopening the file would lose
// every allocation and the whole free list.
func hdrSync(f *os.File, h *Header) error {
	_, err := f.WriteAt(hdrToBytes(h), 0)
	return err
}

func pageAlloc(f *os.File, h *Header) (uint64, error) {
	if h.FreeHead != 0 {
		fh := h.FreeHead
		buf, err := pageRead(f, fh)
		if err != nil {
			return 0, err
		}
		h.FreeHead = binary.LittleEndian.Uint64(buf[FPNext : FPNext+8])
		return fh, hdrSync(f, h)
	}
	num := h.PageCount
	h.PageCount++
	zero := make([]byte, PageSz)
	if err := pageWrite(f, num, zero); err != nil {
		return 0, err
	}
	return num, hdrSync(f, h)
}

func pageFree(f *os.File, h *Header, num uint64) error {
	buf := make([]byte, PageSz)
	binary.LittleEndian.PutUint64(buf[FPNext:FPNext+8], h.FreeHead)
	if err := pageWrite(f, num, buf); err != nil {
		return err
	}
	h.FreeHead = num
	return hdrSync(f, h)
}

func mustEq(got, want uint64, label string) {
	checks++
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
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
	// os.CreateTemp, not a fixed /tmp name: a fixed name collides with a
	// concurrent run and with whatever another user created there first.
	f, err := os.CreateTemp("", "vidya_page_go_*.bin")
	if err != nil {
		panic(err)
	}
	path := f.Name()

	h := Header{PageCount: 1, FreeHead: 0}
	if _, err := f.Write(hdrToBytes(&h)); err != nil {
		panic(err)
	}

	// 1-2. header
	if _, err := f.Seek(0, 0); err != nil {
		panic(err)
	}
	rh := make([]byte, PageSz)
	if _, err := f.Read(rh); err != nil {
		panic(err)
	}
	check(hdrVerify(rh), "magic ok failed")
	loaded := hdrLoad(rh)
	mustEq(loaded.PageCount, 1, "pgcount starts at 1")

	// 3-4. alloc
	p1, _ := pageAlloc(f, &h)
	mustEq(p1, 1, "first alloc = 1")
	p2, _ := pageAlloc(f, &h)
	mustEq(p2, 2, "second alloc = 2")

	// 5. roundtrip
	buf := make([]byte, PageSz)
	binary.LittleEndian.PutUint64(buf[0:8], 42)
	if err := pageWrite(f, p1, buf); err != nil {
		panic(err)
	}
	rb, _ := pageRead(f, p1)
	got := binary.LittleEndian.Uint64(rb[0:8])
	mustEq(got, 42, "read back 42")

	// 6. free + reuse
	if err := pageFree(f, &h, p2); err != nil {
		panic(err)
	}
	p3, _ := pageAlloc(f, &h)
	mustEq(p3, 2, "reused freed page")

	// 7. the header on disk tracks the allocator (what a reopen would see)
	if _, err := f.ReadAt(rh, 0); err != nil {
		panic(err)
	}
	mustEq(hdrLoad(rh).PageCount, h.PageCount, "on-disk page count persisted")
	mustEq(hdrLoad(rh).FreeHead, h.FreeHead, "on-disk free head persisted")

	f.Close()
	os.Remove(path)
	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("page_management: %d/%d ok\n", checks, checks)
}
