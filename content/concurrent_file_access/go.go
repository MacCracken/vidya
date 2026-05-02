// Vidya — Concurrent File Access (flock) in Go
//
// Single-process exercise of the file-lock state machine via two
// distinct opens of the same path. flock is per-OPEN; the two fds
// have independent lock state and contend with each other inside one
// process. syscall.Flock returns syscall.EWOULDBLOCK on LOCK_NB
// conflict.

package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"syscall"
)

func mustEqU64(got, want uint64, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %x want %x", label, got, want))
	}
}

func mustOk(err error, label string) {
	if err != nil {
		panic(fmt.Sprintf("%s: %v", label, err))
	}
}

func main() {
	path := "/tmp/vidya_cfa_go.bin"
	os.Remove(path)

	// Test 1: exclusive write
	f1, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0644)
	mustOk(err, "open fd1")
	mustOk(syscall.Flock(int(f1.Fd()), syscall.LOCK_EX), "fd1 LOCK_EX")

	const val uint64 = 0xDEADBEEF12345678
	buf := make([]byte, 8)
	binary.LittleEndian.PutUint64(buf, val)
	f1.Seek(0, 0)
	if _, err := f1.Write(buf); err != nil {
		panic(err)
	}
	mustOk(syscall.Flock(int(f1.Fd()), syscall.LOCK_UN), "fd1 LOCK_UN")

	// Test 2: shared read with roundtrip
	mustOk(syscall.Flock(int(f1.Fd()), syscall.LOCK_SH), "fd1 LOCK_SH")
	rb := make([]byte, 8)
	f1.Seek(0, 0)
	if _, err := f1.Read(rb); err != nil {
		panic(err)
	}
	mustEqU64(binary.LittleEndian.Uint64(rb), val, "data roundtrip")
	syscall.Flock(int(f1.Fd()), syscall.LOCK_UN)

	// Test 3: exclusive contention
	f2, err := os.OpenFile(path, os.O_RDWR, 0644)
	mustOk(err, "open fd2")
	mustOk(syscall.Flock(int(f1.Fd()), syscall.LOCK_EX), "fd1 re-acquires LOCK_EX")
	nb := syscall.Flock(int(f2.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	if nb == nil {
		panic("fd2 LOCK_NB should have failed")
	}

	// Test 4: release fd1, fd2 acquires
	syscall.Flock(int(f1.Fd()), syscall.LOCK_UN)
	mustOk(syscall.Flock(int(f2.Fd()), syscall.LOCK_EX|syscall.LOCK_NB), "fd2 acquires after fd1 releases")
	syscall.Flock(int(f2.Fd()), syscall.LOCK_UN)

	// Test 5: shared locks coexist
	mustOk(syscall.Flock(int(f1.Fd()), syscall.LOCK_SH|syscall.LOCK_NB), "fd1 LOCK_SH non-blocking")
	mustOk(syscall.Flock(int(f2.Fd()), syscall.LOCK_SH|syscall.LOCK_NB), "fd2 LOCK_SH non-blocking coexists")
	syscall.Flock(int(f1.Fd()), syscall.LOCK_UN)
	syscall.Flock(int(f2.Fd()), syscall.LOCK_UN)

	f1.Close()
	f2.Close()
	os.Remove(path)
	fmt.Println("concurrent_file_access: 12/12 ok")
}
