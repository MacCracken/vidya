// Vidya — Consensus and Raft — Go port.

package main

import (
	"fmt"
	"os"
)

const (
	NNodes  = 3
	MaxLog  = 8
	Quorum  = 2
)

const (
	RoleFollower  = 0
	RoleCandidate = 1
	RoleLeader    = 2
)

type Entry struct {
	Term  int
	Value int
}

type Cluster struct {
	role      [NNodes]int
	term      [NNodes]int
	votedFor  [NNodes]int
	log       [NNodes][]Entry
	commitIdx [NNodes]int
}

func NewCluster() *Cluster {
	c := &Cluster{}
	for i := 0; i < NNodes; i++ {
		c.role[i] = RoleFollower
		c.votedFor[i] = -1
		c.log[i] = nil
		c.commitIdx[i] = -1
	}
	return c
}

func (c *Cluster) lastLogIndex(n int) int { return len(c.log[n]) - 1 }
func (c *Cluster) lastLogTerm(n int) int {
	if len(c.log[n]) == 0 {
		return 0
	}
	return c.log[n][len(c.log[n])-1].Term
}

func (c *Cluster) logUpToDate(cTerm, cIdx, vTerm, vIdx int) bool {
	if cTerm > vTerm {
		return true
	}
	if cTerm < vTerm {
		return false
	}
	return cIdx >= vIdx
}

func (c *Cluster) startElection(node int) int {
	c.term[node]++
	c.votedFor[node] = node
	c.role[node] = RoleCandidate
	return c.term[node]
}

func (c *Cluster) requestVote(voter, candidate, cTerm, cLastTerm, cLastIdx int) bool {
	if cTerm < c.term[voter] {
		return false
	}
	if cTerm > c.term[voter] {
		c.term[voter] = cTerm
		c.votedFor[voter] = -1
		c.role[voter] = RoleFollower
	}
	if c.votedFor[voter] != -1 && c.votedFor[voter] != candidate {
		return false
	}
	if !c.logUpToDate(cLastTerm, cLastIdx, c.lastLogTerm(voter), c.lastLogIndex(voter)) {
		return false
	}
	c.votedFor[voter] = candidate
	return true
}

func (c *Cluster) runElection(candidate int) int {
	votes := 1
	cTerm := c.term[candidate]
	cLastTerm := c.lastLogTerm(candidate)
	cLastIdx := c.lastLogIndex(candidate)
	for v := 0; v < NNodes; v++ {
		if v == candidate {
			continue
		}
		if c.requestVote(v, candidate, cTerm, cLastTerm, cLastIdx) {
			votes++
		}
	}
	if votes >= Quorum {
		c.role[candidate] = RoleLeader
	}
	return votes
}

func (c *Cluster) appendEntry(leader, value int) int {
	if len(c.log[leader]) >= MaxLog {
		return -1
	}
	idx := len(c.log[leader])
	c.log[leader] = append(c.log[leader], Entry{c.term[leader], value})
	return idx
}

func (c *Cluster) replicate(leader, follower int) int {
	for i := 0; i < len(c.log[leader]); i++ {
		le := c.log[leader][i]
		if i < len(c.log[follower]) && c.log[follower][i].Term != le.Term {
			c.log[follower] = c.log[follower][:i]
		}
		if i >= len(c.log[follower]) {
			c.log[follower] = append(c.log[follower], le)
		}
	}
	return len(c.log[follower])
}

func (c *Cluster) countMatching(leader, idx int) int {
	leaderTerm := c.log[leader][idx].Term
	count := 0
	for n := 0; n < NNodes; n++ {
		if len(c.log[n]) > idx && c.log[n][idx].Term == leaderTerm {
			count++
		}
	}
	return count
}

func (c *Cluster) advanceCommit(leader int) int {
	cur := c.term[leader]
	for idx := c.commitIdx[leader] + 1; idx < len(c.log[leader]); idx++ {
		if c.log[leader][idx].Term == cur {
			if c.countMatching(leader, idx) >= Quorum {
				c.commitIdx[leader] = idx
			}
		}
	}
	return c.commitIdx[leader]
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
		c := NewCluster()
		for n := 0; n < NNodes; n++ {
			check(c.role[n] == RoleFollower, "follower")
		}
		check(c.term[0] == 0, "term=0")
		check(c.votedFor[0] == -1, "voted_for=-1")
		check(len(c.log[0]) == 0, "empty log")
		check(c.commitIdx[0] == -1, "nothing committed")
	}
	{
		c := NewCluster()
		t := c.startElection(0)
		check(t == 1, "term bumps to 1")
		votes := c.runElection(0)
		check(votes == 3, "3 votes")
		check(c.role[0] == RoleLeader, "node 0 LEADER")
		check(c.term[1] == 1, "follower 1 term updated")
		check(c.votedFor[1] == 0, "follower 1 voted 0")
	}
	{
		c := NewCluster()
		c.term[1] = 5
		ok := c.requestVote(1, 0, 1, 0, -1)
		check(!ok, "stale-term rejected")
		check(c.term[1] == 5, "voter term unchanged")
	}
	{
		c := NewCluster()
		c.startElection(0)
		c.runElection(0)
		check(c.role[0] == RoleLeader, "leader")
		ok := c.requestVote(0, 2, 5, 0, -1)
		check(ok, "higher-term granted")
		check(c.term[0] == 5, "term=5")
		check(c.role[0] == RoleFollower, "stepped down")
	}
	{
		c := NewCluster()
		check(c.requestVote(2, 0, 1, 0, -1), "first vote")
		check(!c.requestVote(2, 1, 1, 0, -1), "second denied")
		check(c.votedFor[2] == 0, "voted_for unchanged")
	}
	{
		c := NewCluster()
		c.startElection(0)
		c.runElection(0)
		c.appendEntry(0, 100)
		c.appendEntry(0, 200)
		c.appendEntry(0, 300)
		n := c.replicate(0, 1)
		check(n == 3, "3 entries replicated")
		for i := 0; i < 3; i++ {
			check(c.log[0][i] == c.log[1][i], "match")
		}
	}
	{
		c := NewCluster()
		c.startElection(0)
		c.runElection(0)
		c.appendEntry(0, 42)
		c.replicate(0, 1)
		check(c.advanceCommit(0) == 0, "commit_idx → 0")
		c.appendEntry(0, 99)
		check(c.advanceCommit(0) == 0, "stays at 0")
		c.replicate(0, 2)
		check(c.advanceCommit(0) == 1, "commit_idx → 1")
	}
	{
		c := NewCluster()
		c.startElection(0)
		c.runElection(0)
		c.appendEntry(0, 10)
		c.appendEntry(0, 20)
		c.term[1] = 4
		t := c.startElection(1)
		ok := c.requestVote(0, 1, t, 0, -1)
		check(!ok, "shorter-log candidate denied")
		check(c.term[0] == t, "term advanced")
		check(c.role[0] == RoleFollower, "stepped down")
	}
	{
		c := NewCluster()
		c.startElection(0)
		c.runElection(0)
		c.appendEntry(0, 100)
		c.replicate(0, 1)
		c.advanceCommit(0)
		check(c.commitIdx[0] == 0, "term-1 committed")
		t2 := c.startElection(1)
		check(t2 == 2, "term=2")
		votes := c.runElection(1)
		check(votes >= Quorum, "node 1 wins")
		check(c.role[1] == RoleLeader, "leader")
		c.appendEntry(1, 200)
		c.replicate(1, 2)
		c.advanceCommit(1)
		check(c.commitIdx[1] == 1, "term-2 commit drags term-1 forward")
		check(c.log[1][0].Term == 1, "idx 0 term-1")
		check(c.log[1][1].Term == 2, "idx 1 term-2")
	}
	{
		c := NewCluster()
		c.startElection(0)
		t1 := c.term[0]
		c.startElection(0)
		t2 := c.term[0]
		check(t2 > t1, "term increases")
		ok := c.requestVote(0, 1, 1, 0, -1)
		check(!ok, "stale denied")
		check(c.term[0] == t2, "term not decremented")
	}

	fmt.Println("=== consensus ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
