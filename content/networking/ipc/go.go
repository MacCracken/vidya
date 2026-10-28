// Vidya — IPC in Go
//
// In-memory simulation: shared memory, pipe, named channel.

package main

import "fmt"

const (
	ShmRegionCap = 4
	ShmBytes     = 64
	PipeCap      = 8
	ChanCap      = 4
	ChanQueueCap = 8
)

type Ipc struct {
	Shm       [ShmRegionCap][ShmBytes]byte
	PipeBuf   [PipeCap]byte
	PipeHead  int
	PipeCount int
	ChanOpen  [ChanCap]bool
	ChanQueue [ChanCap][ChanQueueCap]uint64
	ChanCount [ChanCap]int
}

func (i *Ipc) ShmWrite(region, offset int, b byte) bool {
	if region < 0 || region >= ShmRegionCap || offset < 0 || offset >= ShmBytes {
		return false
	}
	i.Shm[region][offset] = b
	return true
}

func (i *Ipc) ShmRead(region, offset int) int {
	if region < 0 || region >= ShmRegionCap || offset < 0 || offset >= ShmBytes {
		return -1
	}
	return int(i.Shm[region][offset])
}

func (i *Ipc) PipeWrite(b byte) bool {
	if i.PipeCount >= PipeCap {
		return false
	}
	tail := (i.PipeHead + i.PipeCount) % PipeCap
	i.PipeBuf[tail] = b
	i.PipeCount++
	return true
}

func (i *Ipc) PipeRead() int {
	if i.PipeCount == 0 {
		return -1
	}
	b := i.PipeBuf[i.PipeHead]
	i.PipeHead = (i.PipeHead + 1) % PipeCap
	i.PipeCount--
	return int(b)
}

func (i *Ipc) ChanListen(endpoint int) bool {
	if endpoint < 0 || endpoint >= ChanCap {
		return false
	}
	i.ChanOpen[endpoint] = true
	return true
}

func (i *Ipc) ChanSend(dst int, msg uint64) bool {
	if dst < 0 || dst >= ChanCap || !i.ChanOpen[dst] {
		return false
	}
	if i.ChanCount[dst] >= ChanQueueCap {
		return false
	}
	i.ChanQueue[dst][i.ChanCount[dst]] = msg
	i.ChanCount[dst]++
	return true
}

func (i *Ipc) ChanRecv(endpoint int) int64 {
	if endpoint < 0 || endpoint >= ChanCap || !i.ChanOpen[endpoint] {
		return -1
	}
	if i.ChanCount[endpoint] == 0 {
		return -1
	}
	msg := i.ChanQueue[endpoint][0]
	for k := 0; k < i.ChanCount[endpoint]-1; k++ {
		i.ChanQueue[endpoint][k] = i.ChanQueue[endpoint][k+1]
	}
	i.ChanCount[endpoint]--
	return int64(msg)
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
	var ipc Ipc

	check(ipc.ShmWrite(1, 5, 0xA1), "shm_write")
	check(ipc.ShmRead(1, 5) == 0xA1, "shm_read")
	check(ipc.ShmRead(2, 5) == 0, "other region")
	check(!ipc.ShmWrite(1, 99, 0xFF), "oob write")
	check(ipc.ShmRead(1, 99) == -1, "oob read")

	ipc.PipeWrite(65)
	ipc.PipeWrite(66)
	ipc.PipeWrite(67)
	check(ipc.PipeRead() == 65, "pipe1")
	check(ipc.PipeRead() == 66, "pipe2")
	check(ipc.PipeRead() == 67, "pipe3")
	check(ipc.PipeRead() == -1, "pipe empty")

	var ipc2 Ipc
	for k := 0; k < PipeCap; k++ {
		ipc2.PipeWrite(byte(k + 100))
	}
	check(!ipc2.PipeWrite(99), "pipe full not rejected")
	ipc2.PipeRead()
	check(ipc2.PipeWrite(99), "post-drain failed")

	var ipc3 Ipc
	check(!ipc3.ChanSend(1, 0xDEADBEEF), "send to closed accepted")
	ipc3.ChanListen(1)
	check(ipc3.ChanSend(1, 0xCAFE), "send 1")
	check(ipc3.ChanSend(1, 0xBABE), "send 2")
	check(ipc3.ChanRecv(1) == 0xCAFE, "recv 1")
	check(ipc3.ChanRecv(1) == 0xBABE, "recv 2")
	check(ipc3.ChanRecv(1) == -1, "recv empty")
	check(ipc3.ChanRecv(2) == -1, "recv unopened")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("ipc: %d/%d ok\n", checks, checks)
}
