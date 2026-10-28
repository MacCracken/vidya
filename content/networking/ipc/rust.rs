// Vidya — IPC in Rust
//
// In-memory simulation of three IPC primitives: shared memory,
// bounded pipe, named-endpoint message channel.

const SHM_REGION_CAP: usize = 4;
const SHM_BYTES: usize = 64;
const PIPE_CAP: usize = 8;
const CHAN_CAP: usize = 4;
const CHAN_QUEUE_CAP: usize = 8;

struct Ipc {
    shm: [[u8; SHM_BYTES]; SHM_REGION_CAP],
    pipe: [u8; PIPE_CAP],
    pipe_head: usize,
    pipe_count: usize,
    chan_open: [bool; CHAN_CAP],
    chan_queue: [[u64; CHAN_QUEUE_CAP]; CHAN_CAP],
    chan_count: [usize; CHAN_CAP],
}

impl Ipc {
    fn new() -> Self {
        Ipc {
            shm: [[0; SHM_BYTES]; SHM_REGION_CAP],
            pipe: [0; PIPE_CAP],
            pipe_head: 0,
            pipe_count: 0,
            chan_open: [false; CHAN_CAP],
            chan_queue: [[0; CHAN_QUEUE_CAP]; CHAN_CAP],
            chan_count: [0; CHAN_CAP],
        }
    }

    fn shm_write(&mut self, region: usize, offset: usize, byte: u8) -> bool {
        if region >= SHM_REGION_CAP || offset >= SHM_BYTES { return false; }
        self.shm[region][offset] = byte;
        true
    }

    fn shm_read(&self, region: usize, offset: usize) -> i32 {
        if region >= SHM_REGION_CAP || offset >= SHM_BYTES { return -1; }
        self.shm[region][offset] as i32
    }

    fn pipe_write(&mut self, byte: u8) -> bool {
        if self.pipe_count >= PIPE_CAP { return false; }
        let tail = (self.pipe_head + self.pipe_count) % PIPE_CAP;
        self.pipe[tail] = byte;
        self.pipe_count += 1;
        true
    }

    fn pipe_read(&mut self) -> i32 {
        if self.pipe_count == 0 { return -1; }
        let b = self.pipe[self.pipe_head];
        self.pipe_head = (self.pipe_head + 1) % PIPE_CAP;
        self.pipe_count -= 1;
        b as i32
    }

    fn chan_listen(&mut self, endpoint: usize) -> bool {
        if endpoint >= CHAN_CAP { return false; }
        self.chan_open[endpoint] = true;
        true
    }

    fn chan_send(&mut self, dst: usize, msg: u64) -> bool {
        if dst >= CHAN_CAP || !self.chan_open[dst] { return false; }
        if self.chan_count[dst] >= CHAN_QUEUE_CAP { return false; }
        self.chan_queue[dst][self.chan_count[dst]] = msg;
        self.chan_count[dst] += 1;
        true
    }

    fn chan_recv(&mut self, endpoint: usize) -> i64 {
        if endpoint >= CHAN_CAP || !self.chan_open[endpoint] { return -1; }
        if self.chan_count[endpoint] == 0 { return -1; }
        let msg = self.chan_queue[endpoint][0];
        for i in 0..self.chan_count[endpoint] - 1 {
            self.chan_queue[endpoint][i] = self.chan_queue[endpoint][i + 1];
        }
        self.chan_count[endpoint] -= 1;
        msg as i64
    }
}

fn main() {
    let mut ipc = Ipc::new();

    // Shared memory
    assert!(ipc.shm_write(1, 5, 0xA1));
    assert_eq!(ipc.shm_read(1, 5), 0xA1);
    assert_eq!(ipc.shm_read(2, 5), 0);
    assert!(!ipc.shm_write(1, 99, 0xFF));
    assert_eq!(ipc.shm_read(1, 99), -1);

    // Pipe FIFO
    ipc.pipe_write(65);
    ipc.pipe_write(66);
    ipc.pipe_write(67);
    assert_eq!(ipc.pipe_read(), 65);
    assert_eq!(ipc.pipe_read(), 66);
    assert_eq!(ipc.pipe_read(), 67);
    assert_eq!(ipc.pipe_read(), -1);

    // Pipe full → write rejected
    let mut ipc2 = Ipc::new();
    for i in 0..PIPE_CAP { ipc2.pipe_write((i + 100) as u8); }
    assert!(!ipc2.pipe_write(99));
    ipc2.pipe_read();
    assert!(ipc2.pipe_write(99));

    // Channel
    let mut ipc3 = Ipc::new();
    assert!(!ipc3.chan_send(1, 0xDEADBEEF));
    ipc3.chan_listen(1);
    assert!(ipc3.chan_send(1, 0xCAFE));
    assert!(ipc3.chan_send(1, 0xBABE));
    assert_eq!(ipc3.chan_recv(1), 0xCAFE);
    assert_eq!(ipc3.chan_recv(1), 0xBABE);
    assert_eq!(ipc3.chan_recv(1), -1);
    assert_eq!(ipc3.chan_recv(2), -1);

    println!("ipc: 18/18 ok");
}
