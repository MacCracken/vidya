// Vidya — Distributed Systems Foundations — Rust port.

const N_NODES: usize = 3;
const W: usize = 2;
const R: usize = 2;

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum VCOrder {
    Less,
    Equal,
    Greater,
    Concurrent,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
struct VClock([i64; N_NODES]);

impl VClock {
    fn new() -> Self { VClock([0; N_NODES]) }
    fn tick(&mut self, node: usize) { self.0[node] += 1; }
    fn merge(&mut self, from: &VClock) {
        for i in 0..N_NODES {
            if from.0[i] > self.0[i] {
                self.0[i] = from.0[i];
            }
        }
    }
    fn compare(&self, other: &VClock) -> VCOrder {
        let mut any_lt = false;
        let mut any_gt = false;
        for i in 0..N_NODES {
            if self.0[i] < other.0[i] { any_lt = true; }
            if self.0[i] > other.0[i] { any_gt = true; }
        }
        match (any_lt, any_gt) {
            (false, false) => VCOrder::Equal,
            (false, true)  => VCOrder::Greater,
            (true, false)  => VCOrder::Less,
            (true, true)   => VCOrder::Concurrent,
        }
    }
}

struct QCluster {
    accounts: [i64; N_NODES],
    write_seq: [i64; N_NODES],
    alive: [bool; N_NODES],
    global_seq: i64,
}

impl QCluster {
    fn new() -> Self {
        QCluster {
            accounts: [0; N_NODES],
            write_seq: [0; N_NODES],
            alive: [true; N_NODES],
            global_seq: 0,
        }
    }
    fn partition(&mut self, n: usize) { self.alive[n] = false; }
    fn heal(&mut self, n: usize) { self.alive[n] = true; }
    fn alive_count(&self) -> usize { self.alive.iter().filter(|&&a| a).count() }

    fn write(&mut self, value: i64) -> bool {
        if self.alive_count() < W { return false; }
        self.global_seq += 1;
        for i in 0..N_NODES {
            if self.alive[i] {
                self.accounts[i] = value;
                self.write_seq[i] = self.global_seq;
            }
        }
        true
    }

    fn read(&self) -> Option<i64> {
        if self.alive_count() < R { return None; }
        let mut best_seq = 0i64;
        let mut best_value = 0i64;
        for i in 0..N_NODES {
            if self.alive[i] && self.write_seq[i] > best_seq {
                best_seq = self.write_seq[i];
                best_value = self.accounts[i];
            }
        }
        Some(best_value)
    }
}

fn main() {
    {
        let v = VClock::new();
        assert_eq!(v.0, [0, 0, 0]);
    }
    {
        let mut v = VClock::new();
        v.tick(1); v.tick(1); v.tick(2);
        assert_eq!(v.0, [0, 2, 1]);
    }
    {
        let mut a = VClock::new();
        let mut b = VClock::new();
        a.tick(0); a.tick(0);
        b.tick(1); b.tick(2);
        a.merge(&b);
        assert_eq!(a.0, [2, 1, 1]);
    }
    {
        let a = VClock::new();
        let mut b = VClock::new();
        b.tick(0);
        assert_eq!(a.compare(&b), VCOrder::Less);
    }
    {
        let mut a = VClock::new();
        let mut b = VClock::new();
        a.tick(0); a.tick(0); b.tick(0);
        assert_eq!(a.compare(&b), VCOrder::Greater);
    }
    {
        let mut a = VClock::new();
        let mut b = VClock::new();
        a.tick(1); b.tick(1);
        assert_eq!(a.compare(&b), VCOrder::Equal);
    }
    {
        let mut a = VClock::new();
        let mut b = VClock::new();
        a.tick(0); b.tick(1);
        assert_eq!(a.compare(&b), VCOrder::Concurrent);
        assert_eq!(b.compare(&a), VCOrder::Concurrent);
    }
    {
        let mut c = QCluster::new();
        assert!(c.write(100));
        assert_eq!(c.accounts, [100, 100, 100]);
    }
    {
        let mut c = QCluster::new();
        c.partition(2);
        assert!(c.write(200));
        assert_eq!(c.accounts[0], 200);
        assert_eq!(c.accounts[1], 200);
        assert_eq!(c.accounts[2], 0);
    }
    {
        let mut c = QCluster::new();
        c.partition(1);
        c.partition(2);
        assert!(!c.write(300));
        assert_eq!(c.accounts[0], 0);
    }
    {
        let mut c = QCluster::new();
        c.partition(2); c.write(500); c.heal(2);
        c.partition(0);
        assert_eq!(c.read(), Some(500));
    }
    {
        let mut c = QCluster::new();
        c.write(700);
        c.partition(0); c.partition(1);
        assert_eq!(c.read(), None);
    }

    println!("distributed_systems: 12 tests, 17 assertions ok");
}
