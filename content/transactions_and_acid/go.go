// Vidya — Transactions and ACID — Go port.
//
// OCC store with read-set version snapshots.

package main

import (
	"fmt"
	"os"
)

const (
	NAccounts = 8
	NTx       = 2
	TxCap     = 4
)

const (
	StatusFree      = 0
	StatusActive    = 1
	StatusCommitted = 2
	StatusAborted   = 3
)

type Store struct {
	accounts [NAccounts]int64
	version  [NAccounts]int64
	status   [NTx]int
	writes   [NTx]map[int]int64
	reads    [NTx]map[int]int64
}

func NewStore() *Store {
	s := &Store{}
	for i := range s.writes {
		s.writes[i] = make(map[int]int64)
		s.reads[i] = make(map[int]int64)
	}
	return s
}

func (s *Store) AccountSetRaw(k int, v int64) {
	s.accounts[k] = v
	s.version[k]++
}

func (s *Store) AccountGetRaw(k int) int64 { return s.accounts[k] }

func (s *Store) Total() int64 {
	var sum int64
	for _, v := range s.accounts {
		sum += v
	}
	return sum
}

func (s *Store) Begin() int {
	for t := 0; t < NTx; t++ {
		if s.status[t] == StatusFree {
			s.status[t] = StatusActive
			s.writes[t] = make(map[int]int64)
			s.reads[t] = make(map[int]int64)
			return t
		}
	}
	return -1
}

func (s *Store) Read(tx, k int) int64 {
	if s.status[tx] != StatusActive {
		panic("read on non-active tx")
	}
	if v, ok := s.writes[tx][k]; ok {
		return v
	}
	if _, seen := s.reads[tx][k]; !seen && len(s.reads[tx]) < TxCap {
		s.reads[tx][k] = s.version[k]
	}
	return s.accounts[k]
}

func (s *Store) Write(tx, k int, v int64) int {
	if s.status[tx] != StatusActive {
		return 0
	}
	if _, ok := s.writes[tx][k]; ok {
		s.writes[tx][k] = v
		return 1
	}
	if len(s.writes[tx]) >= TxCap {
		return 0
	}
	s.writes[tx][k] = v
	return 1
}

func (s *Store) Validate(tx int) bool {
	for k, snap := range s.reads[tx] {
		if s.version[k] != snap {
			return false
		}
	}
	return true
}

func (s *Store) Commit(tx int) int {
	if s.status[tx] != StatusActive {
		return 0
	}
	if !s.Validate(tx) {
		s.status[tx] = StatusAborted
		return 0
	}
	for k, v := range s.writes[tx] {
		s.accounts[k] = v
		s.version[k]++
	}
	s.status[tx] = StatusCommitted
	return 1
}

func (s *Store) Abort(tx int) int {
	if s.status[tx] != StatusActive {
		return 0
	}
	s.status[tx] = StatusAborted
	return 1
}

func (s *Store) CrashRecovery() {
	for t := 0; t < NTx; t++ {
		s.status[t] = StatusFree
		s.writes[t] = make(map[int]int64)
		s.reads[t] = make(map[int]int64)
	}
}

func seed() *Store {
	s := NewStore()
	s.AccountSetRaw(0, 1000)
	s.AccountSetRaw(1, 500)
	s.AccountSetRaw(2, 200)
	return s
}

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func main() {
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 9999)
		s.Write(tx, 1, 8888)
		s.Write(tx, 2, 7777)
		s.Abort(tx)
		check(s.AccountGetRaw(0) == 1000, "abort: key 0 unchanged")
		check(s.AccountGetRaw(1) == 500, "abort: key 1 unchanged")
		check(s.AccountGetRaw(2) == 200, "abort: key 2 unchanged")
		check(s.status[tx] == StatusAborted, "tx status = ABORTED")
	}
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 100)
		s.Write(tx, 1, 200)
		s.Write(tx, 2, 300)
		check(s.Commit(tx) == 1, "commit succeeded")
		check(s.AccountGetRaw(0) == 100, "commit: key 0 installed")
		check(s.AccountGetRaw(1) == 200, "commit: key 1 installed")
		check(s.AccountGetRaw(2) == 300, "commit: key 2 installed")
		check(s.status[tx] == StatusCommitted, "tx status = COMMITTED")
	}
	{
		s := seed()
		initial := s.Total()
		tx := s.Begin()
		src := s.Read(tx, 0)
		dst := s.Read(tx, 1)
		s.Write(tx, 0, src-100)
		s.Write(tx, 1, dst+100)
		s.Commit(tx)
		check(s.AccountGetRaw(0) == 900, "src debited")
		check(s.AccountGetRaw(1) == 600, "dst credited")
		check(s.Total() == initial, "total preserved")
	}
	{
		s := seed()
		tx1 := s.Begin()
		tx2 := s.Begin()
		s.Write(tx1, 0, 9999)
		check(s.Read(tx2, 0) == 1000, "tx2 sees committed, not pending")
	}
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 4242)
		check(s.Read(tx, 0) == 4242, "tx sees own write")
		check(s.AccountGetRaw(0) == 1000, "durable unchanged before commit")
	}
	{
		s := seed()
		tx1 := s.Begin()
		tx2 := s.Begin()
		v1 := s.Read(tx1, 0)
		s.Write(tx1, 0, v1+50)
		v2 := s.Read(tx2, 0)
		s.Write(tx2, 0, v2+100)
		ok1 := s.Commit(tx1)
		ok2 := s.Commit(tx2)
		check(ok1 == 1, "tx1 commits")
		check(ok2 == 0, "tx2 conflicts and aborts")
		check(s.status[tx2] == StatusAborted, "tx2 status = ABORTED")
		check(s.AccountGetRaw(0) == 1050, "tx1 durable; tx2 lost")
	}
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 12345)
		s.Commit(tx)
		s.CrashRecovery()
		check(s.AccountGetRaw(0) == 12345, "committed survives crash")
	}
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 7)
		ok1 := s.Commit(tx)
		ok2 := s.Commit(tx)
		check(ok1 == 1, "first commit ok")
		check(ok2 == 0, "second commit rejected")
	}
	{
		s := seed()
		tx := s.Begin()
		s.Write(tx, 0, 1)
		s.Write(tx, 1, 2)
		s.Write(tx, 2, 3)
		s.Write(tx, 3, 4)
		fifth := s.Write(tx, 4, 5)
		check(fifth == 0, "5th write rejected (cap=4)")
	}

	fmt.Println("=== transactions_and_acid ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
