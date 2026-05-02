// Vidya — Write-Ahead Logging in Go
//
// In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
// mutating the data store, then replay the durable prefix on recovery.
// Go's `[]byte` is the natural cousin of cyrius's flat buffer; the
// `encoding/binary` package gives us LittleEndian.PutUint64 /
// Uint64 for the load64/store64 primitives — we reinterpret as int64
// at the boundary. The 256-record cap and the OP_INVALID/SET/DEL
// constants match the cyrius reference. No real fsync — `logCommitted`
// snapshots the durable prefix.

package main

import (
	"encoding/binary"
	"fmt"
	"os"
)

const (
	recSZ        = 24
	logCapBytes  = 6144
	opInvalid    = int64(0)
	opSet        = int64(1)
	opDel        = int64(2)
	storeKeys    = 16
)

type Wal struct {
	logBuf       []byte
	logOffset    int64
	logCommitted int64
	dataVals     [storeKeys]int64
	dataPresent  [storeKeys]uint8
}

func newWal() *Wal {
	return &Wal{logBuf: make([]byte, logCapBytes)}
}

func (w *Wal) logReset() {
	w.logOffset = 0
	w.logCommitted = 0
}

func (w *Wal) storeClear() {
	for i := 0; i < storeKeys; i++ {
		w.dataVals[i] = 0
		w.dataPresent[i] = 0
	}
}

func (w *Wal) resetAll() {
	w.logReset()
	w.storeClear()
	// Wipe the buffer so leftover bytes from a prior test don't ghost
	// into a fresh replay.
	for i := range w.logBuf {
		w.logBuf[i] = 0
	}
}

func (w *Wal) store64(off int64, v int64) {
	binary.LittleEndian.PutUint64(w.logBuf[off:off+8], uint64(v))
}

func (w *Wal) load64(off int64) int64 {
	return int64(binary.LittleEndian.Uint64(w.logBuf[off : off+8]))
}

// logAppend returns 1 on success, 0 if the buffer is full — matches cyrius.
func (w *Wal) logAppend(op, key, val int64) int64 {
	if w.logOffset+recSZ > logCapBytes {
		return 0
	}
	off := w.logOffset
	w.store64(off+0, op)
	w.store64(off+8, key)
	w.store64(off+16, val)
	w.logOffset += recSZ
	return 1
}

func (w *Wal) logCommit() int64 {
	// Real implementations call fsync(walFd); we model durability with
	// an offset snapshot.
	w.logCommitted = w.logOffset
	return w.logCommitted
}

func (w *Wal) storeSet(key, val int64) int64 {
	if key < 0 || key >= storeKeys {
		return 0
	}
	// WAL rule: log BEFORE data.
	if w.logAppend(opSet, key, val) == 0 {
		return 0
	}
	w.dataVals[key] = val
	w.dataPresent[key] = 1
	return 1
}

func (w *Wal) storeDel(key int64) int64 {
	if key < 0 || key >= storeKeys {
		return 0
	}
	if w.logAppend(opDel, key, 0) == 0 {
		return 0
	}
	w.dataVals[key] = 0
	w.dataPresent[key] = 0
	return 1
}

func (w *Wal) storeGet(key int64) int64 {
	if key < 0 || key >= storeKeys {
		return -1
	}
	if w.dataPresent[key] == 0 {
		return -1
	}
	return w.dataVals[key]
}

func (w *Wal) replay() int64 {
	w.storeClear()
	var pos, applied int64
	for pos < w.logCommitted {
		op := w.load64(pos + 0)
		key := w.load64(pos + 8)
		val := w.load64(pos + 16)
		if op == opSet {
			w.dataVals[key] = val
			w.dataPresent[key] = 1
			applied++
		} else if op == opDel {
			w.dataVals[key] = 0
			w.dataPresent[key] = 0
			applied++
		}
		pos += recSZ
	}
	return applied
}

func check(cond bool, msg string) {
	if !cond {
		fmt.Fprintln(os.Stderr, "FAIL:", msg)
		os.Exit(1)
	}
}

func testAppendAndReplay() {
	w := newWal()
	w.resetAll()
	w.storeSet(0, 100)
	w.storeSet(1, 200)
	w.storeSet(2, 300)
	w.logCommit()
	w.storeClear()
	n := w.replay()
	check(n == 3, "replayed 3 records")
	check(w.storeGet(0) == 100, "key 0 = 100")
	check(w.storeGet(1) == 200, "key 1 = 200")
	check(w.storeGet(2) == 300, "key 2 = 300")
}

func testLogBeforeDataInvariant() {
	w := newWal()
	w.resetAll()
	ok := w.storeSet(5, 42)
	check(ok == 1, "first set succeeds")
	check(w.load64(0) == opSet, "log[0].op = SET")
	check(w.load64(8) == 5, "log[0].key = 5")
	check(w.load64(16) == 42, "log[0].val = 42")
	check(w.storeGet(5) == 42, "data has key 5 = 42")
}

func testUncommittedWritesLostOnCrash() {
	w := newWal()
	w.resetAll()
	w.storeSet(0, 1)
	w.storeSet(1, 2)
	w.logCommit()
	w.storeSet(2, 3)
	w.storeSet(3, 4)
	w.storeClear()
	n := w.replay()
	check(n == 2, "only 2 committed records replayed")
	check(w.storeGet(0) == 1, "committed key 0 survived")
	check(w.storeGet(1) == 2, "committed key 1 survived")
	check(w.storeGet(2) == -1, "uncommitted key 2 lost")
	check(w.storeGet(3) == -1, "uncommitted key 3 lost")
}

func testDeleteReplaysCorrectly() {
	w := newWal()
	w.resetAll()
	w.storeSet(0, 100)
	w.storeSet(1, 200)
	w.storeDel(0)
	w.logCommit()
	w.storeClear()
	w.replay()
	check(w.storeGet(0) == -1, "key 0 deleted")
	check(w.storeGet(1) == 200, "key 1 = 200")
}

func testOverwriteUsesLastRecord() {
	w := newWal()
	w.resetAll()
	w.storeSet(7, 100)
	w.storeSet(7, 200)
	w.storeSet(7, 300)
	w.logCommit()
	w.storeClear()
	w.replay()
	check(w.storeGet(7) == 300, "last write wins on replay")
}

func testSequentialOffsetsMonotonic() {
	w := newWal()
	w.resetAll()
	prev := w.logOffset
	for i := int64(0); i < 5; i++ {
		w.storeSet(i, i*10)
		now := w.logOffset
		check(now > prev, "log offset advances monotonically")
		prev = now
	}
}

func testLogCapacityLimit() {
	w := newWal()
	w.resetAll()
	failures := 0
	for i := int64(0); i < 300; i++ {
		ok := w.storeSet(0, i)
		if ok == 0 {
			failures++
		}
	}
	check(failures > 0, "log capacity is bounded")
}

func main() {
	_ = opInvalid // referenced by spec
	testAppendAndReplay()
	testLogBeforeDataInvariant()
	testUncommittedWritesLostOnCrash()
	testDeleteReplaysCorrectly()
	testOverwriteUsesLastRecord()
	testSequentialOffsetsMonotonic()
	testLogCapacityLimit()
	fmt.Println("All write_ahead_logging examples passed.")
}
