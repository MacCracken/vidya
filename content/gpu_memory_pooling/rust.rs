// Vidya — GPU Memory Pooling in Rust
//
// Bump allocator over a 1024-byte pool. -1 sentinel for exhaustion;
// reset recycles the entire pool.

const POOL_SIZE: i64 = 1024;

struct Pool {
    bump: i64,
}

impl Pool {
    fn new() -> Self { Pool { bump: 0 } }
    fn reset(&mut self) { self.bump = 0; }
    fn used(&self) -> i64 { self.bump }
    fn free(&self) -> i64 { POOL_SIZE - self.bump }

    fn alloc(&mut self, size: i64) -> i64 {
        if size == 0 { return self.bump; }
        if self.bump + size > POOL_SIZE { return -1; }
        let off = self.bump;
        self.bump += size;
        off
    }

    fn alloc_aligned(&mut self, size: i64, align: i64) -> i64 {
        let mask = align - 1;
        let aligned = (self.bump + mask) & !mask;
        if aligned + size > POOL_SIZE { return -1; }
        self.bump = aligned + size;
        aligned
    }
}

fn main() {
    let mut p = Pool::new();
    assert_eq!(p.used(), 0);
    assert_eq!(p.free(), 1024);

    assert_eq!(p.alloc(100), 0);
    assert_eq!(p.used(), 100);

    assert_eq!(p.alloc(200), 100);
    assert_eq!(p.used(), 300);

    assert_eq!(p.alloc(1000), -1);
    assert_eq!(p.used(), 300);

    p.reset();
    assert_eq!(p.used(), 0);
    assert_eq!(p.free(), 1024);
    assert_eq!(p.alloc(50), 0);

    assert_eq!(p.alloc_aligned(32, 16), 64);
    assert_eq!(p.used(), 96);

    assert_eq!(p.alloc(0), 96);
    assert_eq!(p.used(), 96);

    p.reset();
    for _ in 0..10 { p.alloc(8); }
    assert_eq!(p.used(), 80);

    println!("gpu_memory_pooling: 16/16 ok");
}
