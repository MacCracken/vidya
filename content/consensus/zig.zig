// Vidya — Consensus and Raft — Zig port.

const std = @import("std");

const N_NODES: usize = 3;
const MAX_LOG: usize = 8;
const QUORUM: usize = 2;

const Role = enum(u8) { follower = 0, candidate = 1, leader = 2 };

const Cluster = struct {
    role: [N_NODES]Role = [_]Role{.follower} ** N_NODES,
    term: [N_NODES]i64 = [_]i64{0} ** N_NODES,
    voted_for: [N_NODES]i32 = [_]i32{-1} ** N_NODES,
    log_count: [N_NODES]usize = [_]usize{0} ** N_NODES,
    log_terms: [N_NODES][MAX_LOG]i64 = [_][MAX_LOG]i64{[_]i64{0} ** MAX_LOG} ** N_NODES,
    log_values: [N_NODES][MAX_LOG]i64 = [_][MAX_LOG]i64{[_]i64{0} ** MAX_LOG} ** N_NODES,
    commit_idx: [N_NODES]i32 = [_]i32{-1} ** N_NODES,

    fn lastLogIndex(self: *const Cluster, n: usize) i32 {
        return @as(i32, @intCast(self.log_count[n])) - 1;
    }
    fn lastLogTerm(self: *const Cluster, n: usize) i64 {
        if (self.log_count[n] == 0) return 0;
        return self.log_terms[n][self.log_count[n] - 1];
    }
    fn logUpToDate(_: *const Cluster, c_term: i64, c_idx: i32, v_term: i64, v_idx: i32) bool {
        if (c_term > v_term) return true;
        if (c_term < v_term) return false;
        return c_idx >= v_idx;
    }
    fn startElection(self: *Cluster, node: usize) i64 {
        self.term[node] += 1;
        self.voted_for[node] = @intCast(node);
        self.role[node] = .candidate;
        return self.term[node];
    }
    fn requestVote(self: *Cluster, voter: usize, candidate: i32, c_term: i64,
                   c_last_term: i64, c_last_idx: i32) bool {
        if (c_term < self.term[voter]) return false;
        if (c_term > self.term[voter]) {
            self.term[voter] = c_term;
            self.voted_for[voter] = -1;
            self.role[voter] = .follower;
        }
        if (self.voted_for[voter] != -1 and self.voted_for[voter] != candidate) return false;
        if (!self.logUpToDate(c_last_term, c_last_idx, self.lastLogTerm(voter), self.lastLogIndex(voter))) return false;
        self.voted_for[voter] = candidate;
        return true;
    }
    fn runElection(self: *Cluster, candidate: usize) usize {
        var votes: usize = 1;
        const c_term = self.term[candidate];
        const c_last_term = self.lastLogTerm(candidate);
        const c_last_idx = self.lastLogIndex(candidate);
        var v: usize = 0;
        while (v < N_NODES) : (v += 1) {
            if (v == candidate) continue;
            if (self.requestVote(v, @intCast(candidate), c_term, c_last_term, c_last_idx)) votes += 1;
        }
        if (votes >= QUORUM) self.role[candidate] = .leader;
        return votes;
    }
    fn appendEntry(self: *Cluster, leader: usize, value: i64) i32 {
        if (self.log_count[leader] >= MAX_LOG) return -1;
        const idx = self.log_count[leader];
        self.log_terms[leader][idx] = self.term[leader];
        self.log_values[leader][idx] = value;
        self.log_count[leader] += 1;
        return @intCast(idx);
    }
    fn replicate(self: *Cluster, leader: usize, follower: usize) usize {
        const lc = self.log_count[leader];
        var i: usize = 0;
        while (i < lc) : (i += 1) {
            const lt = self.log_terms[leader][i];
            const lv = self.log_values[leader][i];
            if (i < self.log_count[follower] and self.log_terms[follower][i] != lt) {
                self.log_count[follower] = i;
            }
            if (i >= self.log_count[follower]) {
                self.log_terms[follower][i] = lt;
                self.log_values[follower][i] = lv;
                self.log_count[follower] = i + 1;
            }
        }
        return self.log_count[follower];
    }
    fn countMatching(self: *const Cluster, leader: usize, idx: usize) usize {
        const leader_term = self.log_terms[leader][idx];
        var count: usize = 0;
        var n: usize = 0;
        while (n < N_NODES) : (n += 1) {
            if (self.log_count[n] > idx and self.log_terms[n][idx] == leader_term) count += 1;
        }
        return count;
    }
    fn advanceCommit(self: *Cluster, leader: usize) i32 {
        const cur = self.term[leader];
        var idx: usize = @intCast(self.commit_idx[leader] + 1);
        while (idx < self.log_count[leader]) : (idx += 1) {
            if (self.log_terms[leader][idx] == cur and self.countMatching(leader, idx) >= QUORUM) {
                self.commit_idx[leader] = @intCast(idx);
            }
        }
        return self.commit_idx[leader];
    }
};

var pass_count: i32 = 0;
var fail_count: i32 = 0;
fn check(cond: bool, name: []const u8) void {
    if (cond) {
        pass_count += 1;
    } else {
        fail_count += 1;
        std.debug.print("  FAIL: {s}\n", .{name});
    }
}

pub fn main() !void {
    {
        const c = Cluster{};
        var n: usize = 0;
        while (n < N_NODES) : (n += 1) check(c.role[n] == .follower, "follower");
        check(c.term[0] == 0, "term=0");
        check(c.voted_for[0] == -1, "voted_for=-1");
        check(c.log_count[0] == 0, "empty log");
        check(c.commit_idx[0] == -1, "nothing committed");
    }
    {
        var c = Cluster{};
        check(c.startElection(0) == 1, "term=1");
        check(c.runElection(0) == 3, "3 votes");
        check(c.role[0] == .leader, "leader");
        check(c.term[1] == 1, "follower term updated");
        check(c.voted_for[1] == 0, "follower voted 0");
    }
    {
        var c = Cluster{};
        c.term[1] = 5;
        check(!c.requestVote(1, 0, 1, 0, -1), "stale rejected");
        check(c.term[1] == 5, "term unchanged");
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        _ = c.runElection(0);
        check(c.role[0] == .leader, "leader");
        check(c.requestVote(0, 2, 5, 0, -1), "higher-term granted");
        check(c.term[0] == 5, "term=5");
        check(c.role[0] == .follower, "stepped down");
    }
    {
        var c = Cluster{};
        check(c.requestVote(2, 0, 1, 0, -1), "first vote");
        check(!c.requestVote(2, 1, 1, 0, -1), "second denied");
        check(c.voted_for[2] == 0, "voted_for unchanged");
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        _ = c.runElection(0);
        _ = c.appendEntry(0, 100);
        _ = c.appendEntry(0, 200);
        _ = c.appendEntry(0, 300);
        check(c.replicate(0, 1) == 3, "3 replicated");
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            check(c.log_terms[0][i] == c.log_terms[1][i] and
                  c.log_values[0][i] == c.log_values[1][i], "match");
        }
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        _ = c.runElection(0);
        _ = c.appendEntry(0, 42);
        _ = c.replicate(0, 1);
        check(c.advanceCommit(0) == 0, "commit_idx → 0");
        _ = c.appendEntry(0, 99);
        check(c.advanceCommit(0) == 0, "stays at 0");
        _ = c.replicate(0, 2);
        check(c.advanceCommit(0) == 1, "commit_idx → 1");
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        _ = c.runElection(0);
        _ = c.appendEntry(0, 10);
        _ = c.appendEntry(0, 20);
        c.term[1] = 4;
        const t = c.startElection(1);
        check(!c.requestVote(0, 1, t, 0, -1), "shorter-log denied");
        check(c.term[0] == t, "term advanced");
        check(c.role[0] == .follower, "stepped down");
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        _ = c.runElection(0);
        _ = c.appendEntry(0, 100);
        _ = c.replicate(0, 1);
        _ = c.advanceCommit(0);
        check(c.commit_idx[0] == 0, "term-1 committed");
        const t2 = c.startElection(1);
        check(t2 == 2, "term=2");
        const votes = c.runElection(1);
        check(votes >= QUORUM, "node 1 wins");
        check(c.role[1] == .leader, "leader");
        _ = c.appendEntry(1, 200);
        _ = c.replicate(1, 2);
        _ = c.advanceCommit(1);
        check(c.commit_idx[1] == 1, "term-2 commits and drags term-1 forward");
        check(c.log_terms[1][0] == 1, "idx 0 term-1");
        check(c.log_terms[1][1] == 2, "idx 1 term-2");
    }
    {
        var c = Cluster{};
        _ = c.startElection(0);
        const t1 = c.term[0];
        _ = c.startElection(0);
        const t2 = c.term[0];
        check(t2 > t1, "term increases");
        check(!c.requestVote(0, 1, 1, 0, -1), "stale denied");
        check(c.term[0] == t2, "term not decremented");
    }

    std.debug.print("=== consensus ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
