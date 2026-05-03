// Vidya — Consensus and Raft — Rust port.

const N_NODES: usize = 3;
const MAX_LOG: usize = 8;
const QUORUM: usize = 2;

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum Role {
    Follower,
    Candidate,
    Leader,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
struct Entry {
    term: i64,
    value: i64,
}

struct Cluster {
    role: [Role; N_NODES],
    term: [i64; N_NODES],
    voted_for: [i32; N_NODES],
    log: [Vec<Entry>; N_NODES],
    commit_idx: [i32; N_NODES],
}

impl Cluster {
    fn new() -> Self {
        Cluster {
            role: [Role::Follower; N_NODES],
            term: [0; N_NODES],
            voted_for: [-1; N_NODES],
            log: [Vec::new(), Vec::new(), Vec::new()],
            commit_idx: [-1; N_NODES],
        }
    }

    fn last_log_index(&self, n: usize) -> i32 { self.log[n].len() as i32 - 1 }
    fn last_log_term(&self, n: usize) -> i64 {
        self.log[n].last().map_or(0, |e| e.term)
    }

    fn log_up_to_date(&self, c_term: i64, c_idx: i32, v_term: i64, v_idx: i32) -> bool {
        if c_term > v_term { return true; }
        if c_term < v_term { return false; }
        c_idx >= v_idx
    }

    fn start_election(&mut self, node: usize) -> i64 {
        self.term[node] += 1;
        self.voted_for[node] = node as i32;
        self.role[node] = Role::Candidate;
        self.term[node]
    }

    fn request_vote(&mut self, voter: usize, candidate: i32, c_term: i64,
                    c_last_term: i64, c_last_idx: i32) -> bool {
        if c_term < self.term[voter] { return false; }
        if c_term > self.term[voter] {
            self.term[voter] = c_term;
            self.voted_for[voter] = -1;
            self.role[voter] = Role::Follower;
        }
        if self.voted_for[voter] != -1 && self.voted_for[voter] != candidate {
            return false;
        }
        if !self.log_up_to_date(c_last_term, c_last_idx,
                                self.last_log_term(voter),
                                self.last_log_index(voter)) {
            return false;
        }
        self.voted_for[voter] = candidate;
        true
    }

    fn run_election(&mut self, candidate: usize) -> usize {
        let mut votes = 1;
        let c_term = self.term[candidate];
        let c_last_term = self.last_log_term(candidate);
        let c_last_idx = self.last_log_index(candidate);
        for v in 0..N_NODES {
            if v == candidate { continue; }
            if self.request_vote(v, candidate as i32, c_term, c_last_term, c_last_idx) {
                votes += 1;
            }
        }
        if votes >= QUORUM {
            self.role[candidate] = Role::Leader;
        }
        votes
    }

    fn append_entry(&mut self, leader: usize, value: i64) -> i32 {
        if self.log[leader].len() >= MAX_LOG { return -1; }
        let idx = self.log[leader].len() as i32;
        let t = self.term[leader];
        self.log[leader].push(Entry { term: t, value });
        idx
    }

    fn replicate(&mut self, leader: usize, follower: usize) -> usize {
        let leader_log = self.log[leader].clone();
        for i in 0..leader_log.len() {
            let le = leader_log[i];
            if i < self.log[follower].len() && self.log[follower][i].term != le.term {
                self.log[follower].truncate(i);
            }
            if i >= self.log[follower].len() {
                self.log[follower].push(le);
            }
        }
        self.log[follower].len()
    }

    fn count_matching(&self, leader: usize, idx: usize) -> usize {
        let leader_term = self.log[leader][idx].term;
        let mut count = 0;
        for n in 0..N_NODES {
            if self.log[n].len() > idx && self.log[n][idx].term == leader_term {
                count += 1;
            }
        }
        count
    }

    fn advance_commit(&mut self, leader: usize) -> i32 {
        let cur = self.term[leader];
        let leader_count = self.log[leader].len();
        let mut idx = (self.commit_idx[leader] + 1) as usize;
        while idx < leader_count {
            if self.log[leader][idx].term == cur && self.count_matching(leader, idx) >= QUORUM {
                self.commit_idx[leader] = idx as i32;
            }
            idx += 1;
        }
        self.commit_idx[leader]
    }
}

fn main() {
    {
        let c = Cluster::new();
        for n in 0..N_NODES {
            assert_eq!(c.role[n], Role::Follower);
        }
        assert_eq!(c.term[0], 0);
        assert_eq!(c.voted_for[0], -1);
        assert_eq!(c.log[0].len(), 0);
        assert_eq!(c.commit_idx[0], -1);
    }
    {
        let mut c = Cluster::new();
        let t = c.start_election(0);
        assert_eq!(t, 1);
        let votes = c.run_election(0);
        assert_eq!(votes, 3);
        assert_eq!(c.role[0], Role::Leader);
        assert_eq!(c.term[1], 1);
        assert_eq!(c.voted_for[1], 0);
    }
    {
        let mut c = Cluster::new();
        c.term[1] = 5;
        assert!(!c.request_vote(1, 0, 1, 0, -1));
        assert_eq!(c.term[1], 5);
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        c.run_election(0);
        assert_eq!(c.role[0], Role::Leader);
        assert!(c.request_vote(0, 2, 5, 0, -1));
        assert_eq!(c.term[0], 5);
        assert_eq!(c.role[0], Role::Follower);
    }
    {
        let mut c = Cluster::new();
        assert!(c.request_vote(2, 0, 1, 0, -1));
        assert!(!c.request_vote(2, 1, 1, 0, -1));
        assert_eq!(c.voted_for[2], 0);
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        c.run_election(0);
        c.append_entry(0, 100);
        c.append_entry(0, 200);
        c.append_entry(0, 300);
        let n = c.replicate(0, 1);
        assert_eq!(n, 3);
        for i in 0..3 {
            assert_eq!(c.log[0][i], c.log[1][i]);
        }
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        c.run_election(0);
        c.append_entry(0, 42);
        c.replicate(0, 1);
        assert_eq!(c.advance_commit(0), 0);
        c.append_entry(0, 99);
        assert_eq!(c.advance_commit(0), 0);
        c.replicate(0, 2);
        assert_eq!(c.advance_commit(0), 1);
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        c.run_election(0);
        c.append_entry(0, 10);
        c.append_entry(0, 20);
        c.term[1] = 4;
        let t = c.start_election(1);
        assert!(!c.request_vote(0, 1, t, 0, -1));
        assert_eq!(c.term[0], t);
        assert_eq!(c.role[0], Role::Follower);
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        c.run_election(0);
        c.append_entry(0, 100);
        c.replicate(0, 1);
        c.advance_commit(0);
        assert_eq!(c.commit_idx[0], 0);
        let t2 = c.start_election(1);
        assert_eq!(t2, 2);
        let votes = c.run_election(1);
        assert!(votes >= QUORUM);
        assert_eq!(c.role[1], Role::Leader);
        c.append_entry(1, 200);
        c.replicate(1, 2);
        c.advance_commit(1);
        assert_eq!(c.commit_idx[1], 1);
        assert_eq!(c.log[1][0].term, 1);
        assert_eq!(c.log[1][1].term, 2);
    }
    {
        let mut c = Cluster::new();
        c.start_election(0);
        let t1 = c.term[0];
        c.start_election(0);
        let t2 = c.term[0];
        assert!(t2 > t1);
        assert!(!c.request_vote(0, 1, 1, 0, -1));
        assert_eq!(c.term[0], t2);
    }

    println!("consensus: 10 tests, 41 assertions ok");
}
