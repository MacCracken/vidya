// Vidya — Explicit GPU Synchronization in Rust
//
// Timeline semaphores — monotonic 64-bit counters with signal/wait
// and a wait_all multi-sem barrier.

struct Timelines {
    compute: u64,
    transfer: u64,
}

impl Timelines {
    fn new() -> Self { Timelines { compute: 0, transfer: 0 } }

    /// Returns true on success, false on regression rejection.
    fn signal(&mut self, sem: u32, value: u64) -> bool {
        match sem {
            0 => { if value <= self.compute { return false; } self.compute = value; true }
            1 => { if value <= self.transfer { return false; } self.transfer = value; true }
            _ => false,
        }
    }

    fn wait_for(&self, sem: u32, target: u64) -> bool {
        match sem {
            0 => self.compute >= target,
            1 => self.transfer >= target,
            _ => false,
        }
    }

    fn wait_all(&self, c_target: u64, t_target: u64) -> bool {
        self.wait_for(0, c_target) && self.wait_for(1, t_target)
    }
}

fn main() {
    let mut t = Timelines::new();

    // 1: init
    assert_eq!(t.compute, 0);
    assert_eq!(t.transfer, 0);
    assert!(t.wait_for(0, 0));

    // 2: signal advances
    assert!(t.signal(0, 5));
    assert_eq!(t.compute, 5);

    // 3: past / current / future
    assert!(t.wait_for(0, 3));
    assert!(t.wait_for(0, 5));
    assert!(!t.wait_for(0, 10));

    // 4: regression rejected
    assert!(!t.signal(0, 3));
    assert_eq!(t.compute, 5);
    assert!(!t.signal(0, 5));

    // 5: multi-sem
    t.signal(1, 3);
    assert_eq!(t.transfer, 3);
    assert!(t.wait_all(5, 3));
    assert!(!t.wait_all(5, 4));
    assert!(!t.wait_all(6, 3));
    assert!(t.wait_all(0, 0));

    // 6: monotonic across many signals
    let mut t2 = Timelines::new();
    for i in 1..=10 { t2.signal(0, i); }
    assert_eq!(t2.compute, 10);
    assert!(t2.wait_for(0, 10));
    assert!(!t2.wait_for(0, 11));

    println!("explicit_gpu_synchronization: 19/19 ok");
}
