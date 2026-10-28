// Vidya — Direct DRM GPU Compute in Rust
//
// In-memory simulation of GEM BO + VA-map + submit + syncobj-wait
// flow. No real ioctls; tests the state-machine that AMDGPU compute
// MVPs target.

const BO_CAP: usize = 32;
const VA_CAP: usize = 32;

struct Device {
    fd: i64,
    bo_size: [u64; BO_CAP],
    next_bo: u32,
    va_addr: [u64; VA_CAP],
    va_bo: [u32; VA_CAP],
    va_count: usize,
    next_seq: u64,
    completed_seq: u64,
}

impl Device {
    fn new() -> Self {
        Device {
            fd: 0,
            bo_size: [0; BO_CAP],
            next_bo: 1,
            va_addr: [0; VA_CAP],
            va_bo: [0; VA_CAP],
            va_count: 0,
            next_seq: 1,
            completed_seq: 0,
        }
    }

    fn open_render_node(&mut self) -> i64 { self.fd = 42; self.fd }

    fn gem_create(&mut self, size: u64) -> u32 {
        if (self.next_bo as usize) >= BO_CAP { return 0; }
        let h = self.next_bo;
        self.next_bo += 1;
        self.bo_size[h as usize] = size;
        h
    }

    fn gem_destroy(&mut self, handle: u32) -> bool {
        if handle == 0 || (handle as usize) >= BO_CAP { return false; }
        if self.bo_size[handle as usize] == 0 { return false; }
        self.bo_size[handle as usize] = 0;
        for i in 0..self.va_count {
            if self.va_bo[i] == handle { self.va_bo[i] = 0; }
        }
        true
    }

    fn gem_va_map(&mut self, handle: u32, va: u64) -> bool {
        if handle == 0 || (handle as usize) >= BO_CAP { return false; }
        if self.bo_size[handle as usize] == 0 { return false; }
        if self.va_count >= VA_CAP { return false; }
        self.va_addr[self.va_count] = va;
        self.va_bo[self.va_count] = handle;
        self.va_count += 1;
        true
    }

    fn va_lookup(&self, va: u64) -> u32 {
        for i in 0..self.va_count {
            if self.va_addr[i] == va && self.va_bo[i] != 0 {
                return self.va_bo[i];
            }
        }
        0
    }

    fn submit(&mut self, handle: u32) -> u64 {
        if handle == 0 || (handle as usize) >= BO_CAP { return 0; }
        if self.bo_size[handle as usize] == 0 { return 0; }
        let seq = self.next_seq;
        self.next_seq += 1;
        self.completed_seq = seq;
        seq
    }

    fn syncobj_wait(&self, seq: u64) -> bool {
        self.completed_seq >= seq
    }
}

fn main() {
    let mut d = Device::new();

    assert_ne!(d.open_render_node(), 0, "fd != 0");

    let b1 = d.gem_create(4096);
    let b2 = d.gem_create(8192);
    let b3 = d.gem_create(16384);
    assert_eq!(b1, 1);
    assert_eq!(b2, 2);
    assert_eq!(b3, 3);

    assert!(d.gem_va_map(b1, 0x1000));
    assert!(d.gem_va_map(b2, 0x2000));

    assert_eq!(d.va_lookup(0x1000), b1);
    assert_eq!(d.va_lookup(0x2000), b2);
    assert_eq!(d.va_lookup(0x9000), 0);

    assert!(!d.gem_va_map(99, 0x3000));
    assert!(!d.gem_va_map(0, 0x3000));

    assert_eq!(d.submit(b1), 1);
    assert_eq!(d.submit(b2), 2);
    assert_eq!(d.submit(b3), 3);

    assert!(d.syncobj_wait(1));
    assert!(d.syncobj_wait(3));
    assert!(!d.syncobj_wait(99));

    d.gem_destroy(b1);
    assert_eq!(d.va_lookup(0x1000), 0);

    assert_eq!(d.submit(b1), 0);
    assert_eq!(d.submit(b2), 4);

    println!("direct_drm_gpu_compute: 20/20 ok");
}
