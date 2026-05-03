// Vidya — Consensus and Raft — TypeScript port.

const N_NODES = 3;
const MAX_LOG = 8;
const QUORUM = 2;

const enum Role { Follower = 0, Candidate = 1, Leader = 2 }

interface Entry { term: number; value: number; }

class Cluster {
    role: Role[] = new Array(N_NODES).fill(Role.Follower);
    term: number[] = new Array(N_NODES).fill(0);
    votedFor: number[] = new Array(N_NODES).fill(-1);
    log: Entry[][] = [[], [], []];
    commitIdx: number[] = new Array(N_NODES).fill(-1);

    lastLogIndex(n: number): number { return this.log[n].length - 1; }
    lastLogTerm(n: number): number {
        const l = this.log[n];
        return l.length === 0 ? 0 : l[l.length - 1].term;
    }
    logUpToDate(cT: number, cI: number, vT: number, vI: number): boolean {
        if (cT > vT) return true;
        if (cT < vT) return false;
        return cI >= vI;
    }
    startElection(node: number): number {
        this.term[node] += 1;
        this.votedFor[node] = node;
        this.role[node] = Role.Candidate;
        return this.term[node];
    }
    requestVote(voter: number, candidate: number, cT: number, cLT: number, cLI: number): boolean {
        if (cT < this.term[voter]) return false;
        if (cT > this.term[voter]) {
            this.term[voter] = cT;
            this.votedFor[voter] = -1;
            this.role[voter] = Role.Follower;
        }
        if (this.votedFor[voter] !== -1 && this.votedFor[voter] !== candidate) return false;
        if (!this.logUpToDate(cLT, cLI, this.lastLogTerm(voter), this.lastLogIndex(voter))) return false;
        this.votedFor[voter] = candidate;
        return true;
    }
    runElection(candidate: number): number {
        let votes = 1;
        const cT = this.term[candidate];
        const cLT = this.lastLogTerm(candidate);
        const cLI = this.lastLogIndex(candidate);
        for (let v = 0; v < N_NODES; v++) {
            if (v === candidate) continue;
            if (this.requestVote(v, candidate, cT, cLT, cLI)) votes++;
        }
        if (votes >= QUORUM) this.role[candidate] = Role.Leader;
        return votes;
    }
    appendEntry(leader: number, value: number): number {
        if (this.log[leader].length >= MAX_LOG) return -1;
        const idx = this.log[leader].length;
        this.log[leader].push({ term: this.term[leader], value });
        return idx;
    }
    replicate(leader: number, follower: number): number {
        for (let i = 0; i < this.log[leader].length; i++) {
            const le = this.log[leader][i];
            if (i < this.log[follower].length && this.log[follower][i].term !== le.term) {
                this.log[follower].length = i;
            }
            if (i >= this.log[follower].length) {
                this.log[follower].push(le);
            }
        }
        return this.log[follower].length;
    }
    countMatching(leader: number, idx: number): number {
        const lt = this.log[leader][idx].term;
        let count = 0;
        for (let n = 0; n < N_NODES; n++) {
            if (this.log[n].length > idx && this.log[n][idx].term === lt) count++;
        }
        return count;
    }
    advanceCommit(leader: number): number {
        const cur = this.term[leader];
        for (let idx = this.commitIdx[leader] + 1; idx < this.log[leader].length; idx++) {
            if (this.log[leader][idx].term === cur && this.countMatching(leader, idx) >= QUORUM) {
                this.commitIdx[leader] = idx;
            }
        }
        return this.commitIdx[leader];
    }
}

let passCount = 0, failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

{
    const c = new Cluster();
    for (let n = 0; n < N_NODES; n++) check(c.role[n] === Role.Follower, "follower");
    check(c.term[0] === 0, "term=0");
    check(c.votedFor[0] === -1, "voted_for=-1");
    check(c.log[0].length === 0, "empty log");
    check(c.commitIdx[0] === -1, "nothing committed");
}
{
    const c = new Cluster();
    check(c.startElection(0) === 1, "term=1");
    check(c.runElection(0) === 3, "3 votes");
    check(c.role[0] === Role.Leader, "leader");
    check(c.term[1] === 1, "follower term updated");
    check(c.votedFor[1] === 0, "follower voted 0");
}
{
    const c = new Cluster();
    c.term[1] = 5;
    check(!c.requestVote(1, 0, 1, 0, -1), "stale rejected");
    check(c.term[1] === 5, "term unchanged");
}
{
    const c = new Cluster();
    c.startElection(0); c.runElection(0);
    check(c.role[0] === Role.Leader, "leader");
    check(c.requestVote(0, 2, 5, 0, -1), "higher-term granted");
    check(c.term[0] === 5, "term=5");
    check(c.role[0] === Role.Follower, "stepped down");
}
{
    const c = new Cluster();
    check(c.requestVote(2, 0, 1, 0, -1), "first vote");
    check(!c.requestVote(2, 1, 1, 0, -1), "second denied");
    check(c.votedFor[2] === 0, "voted_for unchanged");
}
{
    const c = new Cluster();
    c.startElection(0); c.runElection(0);
    c.appendEntry(0, 100);
    c.appendEntry(0, 200);
    c.appendEntry(0, 300);
    check(c.replicate(0, 1) === 3, "3 replicated");
    for (let i = 0; i < 3; i++) {
        check(c.log[0][i].term === c.log[1][i].term &&
              c.log[0][i].value === c.log[1][i].value, "match");
    }
}
{
    const c = new Cluster();
    c.startElection(0); c.runElection(0);
    c.appendEntry(0, 42);
    c.replicate(0, 1);
    check(c.advanceCommit(0) === 0, "commit_idx → 0");
    c.appendEntry(0, 99);
    check(c.advanceCommit(0) === 0, "stays at 0");
    c.replicate(0, 2);
    check(c.advanceCommit(0) === 1, "commit_idx → 1");
}
{
    const c = new Cluster();
    c.startElection(0); c.runElection(0);
    c.appendEntry(0, 10);
    c.appendEntry(0, 20);
    c.term[1] = 4;
    const t = c.startElection(1);
    check(!c.requestVote(0, 1, t, 0, -1), "shorter-log denied");
    check(c.term[0] === t, "term advanced");
    check(c.role[0] === Role.Follower, "stepped down");
}
{
    const c = new Cluster();
    c.startElection(0); c.runElection(0);
    c.appendEntry(0, 100);
    c.replicate(0, 1);
    c.advanceCommit(0);
    check(c.commitIdx[0] === 0, "term-1 committed");
    const t2 = c.startElection(1);
    check(t2 === 2, "term=2");
    const votes = c.runElection(1);
    check(votes >= QUORUM, "node 1 wins");
    check(c.role[1] === Role.Leader, "leader");
    c.appendEntry(1, 200);
    c.replicate(1, 2);
    c.advanceCommit(1);
    check(c.commitIdx[1] === 1, "term-2 commits and drags term-1 forward");
    check(c.log[1][0].term === 1, "idx 0 term-1");
    check(c.log[1][1].term === 2, "idx 1 term-2");
}
{
    const c = new Cluster();
    c.startElection(0);
    const t1 = c.term[0];
    c.startElection(0);
    const t2 = c.term[0];
    check(t2 > t1, "term increases");
    check(!c.requestVote(0, 1, 1, 0, -1), "stale denied");
    check(c.term[0] === t2, "term not decremented");
}

console.log("=== consensus ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
